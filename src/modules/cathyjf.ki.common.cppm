// SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
// SPDX-License-Identifier: GPL-3.0-or-later

module;
#include <filesystem>
#include <string_view>
#include <type_traits>

#include <CF++.hpp>
#include <Security/Security.h>

using namespace std::string_view_literals;

export module cathyjf.ki.common;

export [[nodiscard]] auto managed_popen(const auto, const auto);

namespace {

struct managed_file;
struct file_closer {
    typedef std::invoke_result_t<decltype(popen), const char *, const char *> pointer;
    auto operator()(pointer);
private:
    managed_file *_file = nullptr;
    friend struct managed_file;
};

typedef std::unique_ptr<file_closer::pointer, file_closer> managed_file_base;
struct managed_file : managed_file_base {
    [[nodiscard]] auto get_exit_status() const {
        return _exit_status;
    }
private:
    managed_file(file_closer::pointer file): managed_file_base{ file } {
        managed_file_base::get_deleter()._file = this;
    }
    std::optional<std::invoke_result_t<decltype(pclose), file_closer::pointer>> _exit_status;

    friend auto ::managed_popen(const auto, const auto);
    friend auto file_closer::operator()(file_closer::pointer);

    managed_file(const managed_file &) = delete;
    managed_file &operator=(const managed_file &) = delete;
};

auto file_closer::operator()(file_closer::pointer p) {
    const auto status = pclose(p);
    if ((status != -1) && (_file != nullptr)) {
        _file->_exit_status = status;
    }
}

} // anonymous namespace

export [[nodiscard]] auto managed_popen(const auto command, const auto mode) {
    return managed_file{ popen(command, mode) };
}

export constexpr auto KEYCHAIN_SERVICE_NAME = "GPG Private Key"sv;

export [[nodiscard]] auto get_keychain_query_for_keygrip(const std::optional<std::string> keygrip) {
    auto query = CF::Dictionary{};
    query << CF::Pair{ kSecClass, kSecClassGenericPassword };
    query << CF::Pair{ kSecAttrService,
        std::string{ KEYCHAIN_SERVICE_NAME.data(), KEYCHAIN_SERVICE_NAME.length() }};
    if (keygrip) {
        query << CF::Pair{ kSecAttrAccount, *keygrip };
    }
    return query;
}

export [[nodiscard]] auto fgetln_string(FILE *file) -> std::optional<std::string> {
    auto length = size_t{};
    const auto begin = fgetln(file, &length);
    if ((begin == nullptr) || (length == 0)) {
        return std::nullopt;
    }
    const auto end = ([&begin, &length]() {
        const auto end = begin + length;
        return (*(end - 1) != '\n') ? end : (end - 1);
    })();
    return std::string{ begin, end };
}

namespace {

[[nodiscard]] auto get_gnupg_home_from_gpgconf() -> std::optional<std::filesystem::path> {
    auto file = managed_popen("gpgconf --list-dirs homedir", "r");
    if (!file) {
        return std::nullopt;
    }
    const auto data = fgetln_string(file.get());
    if (!data.has_value()) {
        return std::nullopt;
    } else if (feof(file.get()) || ((file.reset(), file.get_exit_status()).value_or(1) != 0)) {
        return std::nullopt;
    }
    return *data;
}

} // anonymous namespace

export [[nodiscard]] auto get_private_key_path() {
    static auto gpg_private_key_path = ([]() -> std::filesystem::path {
        auto gnupghome = std::filesystem::path{};
        if (const auto gpgconf_home = get_gnupg_home_from_gpgconf()) {
            gnupghome = *gpgconf_home;
        } else if (const auto env_p = std::getenv("GNUPGHOME")) {
            gnupghome = std::filesystem::path{ env_p };
        } else if (const auto env_home = std::getenv("HOME")) {
            gnupghome = std::filesystem::path{ env_home } / ".gnupg";
        } else {
            return {};
        }
        return gnupghome / "private-keys-v1.d";
    })();
    return gpg_private_key_path;
}

export struct keychain_entry {
    template <class T> struct cf_ref_releaser {
        typedef T pointer;
        void operator()(T cf_ref) {
            CFRelease(cf_ref);
        }
    };
    template <class T> using managed_cf_ref = std::unique_ptr<T, cf_ref_releaser<T>>;
    typedef managed_cf_ref<CFDataRef> managed_data_ref;
    keychain_entry(const auto keygrip, const auto ref):
        keygrip{ keygrip },
        data_ref{ static_cast<CFDataRef>(ref) },
        password{ CFDataGetBytePtr(data_ref.get()) },
        password_length{ CFDataGetLength(data_ref.get()) } {}
    const std::string keygrip{};
    const managed_data_ref data_ref{};
    const uint8_t *password{};
    const CFIndex password_length{};
    keychain_entry(const auto &) = delete;
    auto &operator=(const auto &) = delete;
};

export template <class T> requires std::is_base_of_v<keychain_entry, T>
[[nodiscard]] std::unique_ptr<T> get_key_from_keychain(const std::string keygrip) {
    auto query = get_keychain_query_for_keygrip(keygrip);
    query << CF::Pair{ kSecReturnData, CF::Boolean{ true } };
    auto data = CFTypeRef{};
    if (SecItemCopyMatching(query, &data) != errSecSuccess) {
        return {};
    }
    return std::make_unique<T>(keygrip, data);
}