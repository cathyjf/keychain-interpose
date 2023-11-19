// SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
// SPDX-License-Identifier: GPL-3.0-or-later

module;
#include <filesystem>
#include <string_view>

#include <CF++.hpp>
#include <Security/Security.h>

using namespace std::string_view_literals;

export module cathyjf.ki.common;

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

export [[nodiscard]] std::filesystem::path get_private_key_path() {
    static auto gpg_private_key_path = ([]() -> std::filesystem::path {
        auto gnupghome = std::filesystem::path{};
        if (const auto env_p = std::getenv("GNUPGHOME")) {
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