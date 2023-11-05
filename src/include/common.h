#ifndef _KEYCHAIN_INTERPOSE_COMMON_H_
#define _KEYCHAIN_INTERPOSE_COMMON_H_

#include <filesystem>
#include <string_view>

using namespace std::string_view_literals;

constexpr auto KEYCHAIN_SERVICE_NAME = "GPG Private Key"sv;

std::filesystem::path get_private_key_path();

#endif