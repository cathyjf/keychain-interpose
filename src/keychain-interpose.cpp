#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <memory>
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
    managed_password password{};
    std::uint32_t passwordLength{};
};

std::unique_ptr<my_gpgrt_stream> get_key_from_keychain(const std::string keygrip) {
    auto stream = std::make_unique<my_gpgrt_stream>();
    char *password{};
    const auto status = SecKeychainFindGenericPassword(
        nullptr,                        // keychainOrArray
        KEYCHAIN_SERVICE_NAME.length(), // serviceNameLength
        KEYCHAIN_SERVICE_NAME.data(),   // serviceName
        keygrip.length(),
        keygrip.c_str(),
        &stream->passwordLength,
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

void *my_gpgrt_fopen(const char *_GPGRT__RESTRICT strPath, const char *_GPGRT__RESTRICT mode) {
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
        return nullptr;
    }
    write_log_message("Found private key in keychain: " + keygrip.string());
    return stream.release();
}

DYLD_INTERPOSE(my_gpgrt_fopen, gpgrt_fopen)

__attribute__((constructor))
void initialize(int argc, const char **argv) {
    write_log_message("Initialized keychain interposition library.");
}

} //anomymous namespace