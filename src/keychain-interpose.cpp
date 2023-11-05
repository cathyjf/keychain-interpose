#include <array>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <memory>
#include <set>
#include <gpg-error.h>
#include <Security/Security.h>

#include "include/dyld-interposing.h"
#include "include/log.h"

using namespace std::string_view_literals;

namespace {

constexpr std::string_view KEYCHAIN_SERVICE_NAME { "GPG Private Key"sv };

#pragma clang diagnostic push
// SecKeychainFindGenericPassword and SecKeychainItemFreeContent are deprecated.
// Ignore these warnings for now.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

struct my_gpgrt_stream {
    struct password_closer {
        typedef char *pointer;
        void operator()(char *pointer) {
            SecKeychainItemFreeContent(nullptr, pointer);
        }
    };
    typedef std::unique_ptr<char *, password_closer> managed_password;
    constexpr static auto magic_length = 12;
    my_gpgrt_stream(const auto keygrip): keygrip{
        "..." + keygrip.substr(keygrip.length() - magic_length, magic_length)
    } {};
    std::string keygrip{};
    managed_password password{};
    std::uint32_t password_length{};
    std::ptrdiff_t index{};
};

std::unique_ptr<my_gpgrt_stream> get_key_from_keychain(const std::string keygrip) {
    auto stream = std::make_unique<my_gpgrt_stream>(keygrip);
    char *password{};
    const auto status = SecKeychainFindGenericPassword(
        nullptr,                        // keychainOrArray
        KEYCHAIN_SERVICE_NAME.length(), // serviceNameLength
        KEYCHAIN_SERVICE_NAME.data(),   // serviceName
        keygrip.length(),
        keygrip.c_str(),
        &stream->password_length,
        reinterpret_cast<void **>(&password),
        nullptr  // itemRef
    );
    stream->password = my_gpgrt_stream::managed_password{ password };
    if (status != errSecSuccess) {
        return {};
    }
    return stream;
}

#pragma clang diagnostic pop

auto my_streams = std::set<void *>{};

gpgrt_stream_t my_gpgrt_fopen(const char *_GPGRT__RESTRICT strPath, const char *_GPGRT__RESTRICT mode) {
    const auto path = std::filesystem::path{ strPath };
    write_log_message("In my_gpgrt_fopen, path = " + std::string{ strPath } + ", mode = " + mode);

    static auto gpgPrivateKeyPath = ([]() -> std::filesystem::path {
        const auto env_p = std::getenv("GNUPGHOME");
        if (env_p == nullptr) {
            return {};
        }
        const auto path = std::filesystem::path{ env_p } / "private-keys-v1.d";
        write_log_message("Determined private key path: " + path.string());
        return path;
    })();
    if (gpgPrivateKeyPath.empty()) {
        write_log_message("Unable to determine private key path. Set the GNUPGHOME environment variable.");
        return gpgrt_fopen(strPath, mode);
    } else if (!std::filesystem::equivalent(gpgPrivateKeyPath, path.parent_path())) {
        write_log_message("This isn't a private key. Falling back to normal gpgrt_fopen behavior.");
        return gpgrt_fopen(strPath, mode);
    } else if (std::strcmp(mode, "rb") != 0) {
        write_log_message("Attempting to write to the key, but we don't currently support this.");
        write_log_message("The key will be written normally to the filesystem for now.");
        return gpgrt_fopen(strPath, mode);
    }

    const auto keygrip = path.filename();
    write_log_message("Detected read request for private key: " + keygrip.string());

    auto stream = get_key_from_keychain(keygrip.string());
    if (!stream) {
        write_log_message("Failed to find or access private key in keychain: " + keygrip.string());
        write_log_message("Falling back to reading from the filesystem.");
        return gpgrt_fopen(strPath, mode);
    }
    write_log_message("Found private key in keychain: " + keygrip.string());
    my_streams.insert(stream.get());
    return reinterpret_cast<gpgrt_stream_t>(stream.release());
}

int my_gpgrt_fseek(gpgrt_stream_t any_stream, long int offset, int whence) {
    if (!my_streams.contains(any_stream)) {
        return gpgrt_fseek(any_stream, offset, whence);
    }

    const auto stream = reinterpret_cast<my_gpgrt_stream *>(any_stream);
    write_log_message("Seeking within stream: " + stream->keygrip);
    switch (whence) {
        case SEEK_SET:
            stream->index = std::max(0L, offset);
            return 0;
        case SEEK_CUR:
            stream->index = std::max(0L, stream->index + offset);
            return 0;
        case SEEK_END:
            stream->index = std::max(0L, stream->password_length - offset);
            return 0;
        default:
            return 1;
    }
}

size_t my_gpgrt_fread(void *_GPGRT__RESTRICT ptr, size_t size, size_t nitems, gpgrt_stream_t _GPGRT__RESTRICT any_stream) {
    if (!my_streams.contains(any_stream)) {
        return gpgrt_fread(ptr, size, nitems, any_stream);
    }

    const auto stream = reinterpret_cast<my_gpgrt_stream *>(any_stream);
    write_log_message("Reading data from stream: " + stream->keygrip);

    const auto remaining_bytes = stream->password_length - stream->index;
    if (remaining_bytes <= 0) {
        return 0;
    }
    const auto items = std::min(remaining_bytes / size, nitems);
    const auto bytes = items * size;
    std::memcpy(ptr, stream->password.get() + stream->index, bytes);
    stream->index += bytes;
    return items;
}

ssize_t my_gpgrt_read_line(gpgrt_stream_t any_stream, char **pbuffer, size_t *buffer_length, size_t *max_length) {
    if (!my_streams.contains(any_stream)) {
        return gpgrt_read_line(any_stream, pbuffer, buffer_length, max_length);
    }

    const auto stream = reinterpret_cast<my_gpgrt_stream *>(any_stream);
    constexpr static auto magic_minimum_length = 3;
    constexpr static auto magic_maximum_length = 256;
    if ((pbuffer == nullptr) || (buffer_length == nullptr)) {
        return -1;
    } else if (max_length != nullptr) {
        write_log_message("Error: gpgrt_read_line called with non-null max_length pointer. "
            "We don't currently support this feature.");
        return -1;
    } else if (*pbuffer == nullptr) {
        // The caller requests that we allocate a buffer.
        //
        // This magic value should be big enough for any line from a private key file.
        // The real gpgrt_read_line function can reallocate the buffer if needed,
        // but that shouldn't be needed for our purposes, so we won't implement that
        // feature right now.
        *buffer_length = magic_maximum_length;
        if ((*pbuffer = reinterpret_cast<char *>(gpgrt_malloc(*buffer_length))) == nullptr) {
            *buffer_length = 0;
            return -1;
        }
    } else if (*buffer_length < magic_minimum_length) {
        return -1;
    }
    const auto usable_length = std::min({
        *buffer_length - magic_minimum_length,
        size_t{ INT_MAX } - magic_minimum_length,
        static_cast<size_t>(stream->password_length - stream->index)
    });
    auto i = std::ptrdiff_t{};
    for (; i < usable_length; ++i) {
        const auto character = (*pbuffer)[i] = stream->password.get()[stream->index++];
        if (character == '\n') {
            break;
        }
    }
    if (i == usable_length) {
        (*pbuffer)[i] = '\n';
    }
    (*pbuffer)[i + 1] = '\0';
    auto carray = std::array<char, 70>{};
    const auto clength = std::snprintf(carray.begin(), carray.size(),
        "Read a line of %td characters from stream: %s", i, stream->keygrip.c_str());
    if (clength > 0) {
        write_log_message(carray.begin());
    }
    return i;
}

int my_gpgrt_fclose(gpgrt_stream_t any_stream) {
    if (!my_streams.contains(any_stream)) {
        return gpgrt_fclose(any_stream);
    }
    const auto stream = reinterpret_cast<my_gpgrt_stream *>(any_stream);
    write_log_message("Freeing stream: " + stream->keygrip);
    // The following line causes the stream object to be properly freed, because
    // the object will be deconstructed when the unique_ptr goes out of scope
    // (which it will do immediately because it is not stored in a variable).
    std::unique_ptr<my_gpgrt_stream>{ stream };
    my_streams.erase(stream);
    return 0;
}

DYLD_INTERPOSE(my_gpgrt_fopen, gpgrt_fopen);
DYLD_INTERPOSE(my_gpgrt_fseek, gpgrt_fseek);
DYLD_INTERPOSE(my_gpgrt_fread, gpgrt_fread);
DYLD_INTERPOSE(my_gpgrt_read_line, gpgrt_read_line);
DYLD_INTERPOSE(my_gpgrt_fclose, gpgrt_fclose);

__attribute__((constructor))
void initialize(int argc, const char **argv) {
    // If we ever need to do any initialization, we can do it here.
    // However, don't write to our log file here, or the log file won't work
    // correctly when other functions call it later.
}

} // anomymous namespace