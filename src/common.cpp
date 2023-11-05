#include <filesystem>

#include "include/common.h"

std::filesystem::path get_private_key_path() {
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