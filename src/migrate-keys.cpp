#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>

#include <CF++.hpp>
#include <Security/Security.h>

import cathyjf.ki.common;

namespace {

auto keychain_has_item(const std::string keygrip) {
    const auto query = get_keychain_query_for_keygrip(keygrip);
    return (SecItemCopyMatching(query, nullptr) == errSecSuccess);
}

auto add_key_to_keychain(const std::string keygrip, const auto data) {
    auto query = get_keychain_query_for_keygrip(keygrip);
    query << CF::Pair{ kSecValueData, data };
    return (SecItemAdd(query, nullptr) == errSecSuccess);
}

auto read_entire_file(const auto filename) {
    auto ifs = std::ifstream{ filename };
    auto buffer = std::stringstream{};
    buffer << ifs.rdbuf();
    return buffer.str();
}

auto &operator<<(auto &buffer, const auto streamable) {
    buffer << streamable.count << ' ' << streamable.noun;
    if (streamable.count > 1) {
        buffer << 's';
    }
    return buffer;
}

template <class T, class U>
auto get_plural(const T noun, const U count) {
    struct {
        T noun;
        U count;
    } streamable{ noun, count };
    return streamable;
}

} // anonymous namespace

int main() {
    const auto private_key_path = get_private_key_path();
    if (private_key_path.empty()) {
        std::cerr << "Error: Could not determine private key directory." << std::endl;
        return 1;
    }
    std::cout << "Private key directory: " << private_key_path << std::endl;
    auto successes = 0;
    auto failures = 0;
    for (auto entry : std::filesystem::directory_iterator(private_key_path)) {
        const auto keygrip = entry.path().filename();
        std::cout << "Found " << keygrip << "." << std::endl;
        const auto length = std::filesystem::file_size(entry);
        if (length < 5) {
            std::cout << "    Skipping this file because it appears to be a placeholder." << std::endl;
            continue;
        }
        std::cout << "    This appears to be a private key." << std::endl;
        if (keychain_has_item(keygrip)) {
            std::cout << "    This key is already in the keychain." << std::endl;
            std::cout << "    To avoid possible data loss, we aren't going to touch this keychain entry." << std::endl;
            continue;
        }
        const auto data = read_entire_file(entry);
        if (data.empty()) {
            std::cerr << "    Failed to read the private key into memory." << std::endl;
            ++failures;
        } else if (!add_key_to_keychain(keygrip, data)) {
            std::cerr << "    Failed to add the key to the keychain." << std::endl;
            ++failures;
        } else {
            std::cout << "    Successfully added the key to the keychain." << std::endl;
            ++successes;
            if (std::ofstream{ entry }.is_open()) {
                std::cout << "    Successfully removed the filesystem key and replaced it with a stub." << std::endl;
            }
        }
    }
    if (successes > 0) {
        std::cout << "Successfully added " << get_plural("key", successes) << " to the keychain." << std::endl;
    }
    if (failures > 0) {
        std::cerr << "Failed to add " << get_plural("key", failures) << " to the keychain." << std::endl;
    }
    if (successes == 0) {
        std::cout << "Nothing was changed." << std::endl;
    }
    return failures;
}