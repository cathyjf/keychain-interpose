#include <filesystem>
#include <fstream>
#include <iostream>
#include <span>
#include <sstream>
#include <vector>

#include <boost/program_options/options_description.hpp>
#include <boost/program_options/parsers.hpp>
#include <boost/program_options/variables_map.hpp>
#include <fmt/core.h>
#include <CF++.hpp>
#include <CoreFoundation/CFArray.h>
#include <Security/Security.h>

import cathyjf.ki.common;

// The `authenticate_user` function is defined in `biometric-auth.mm`.
auto authenticate_user(const std::string_view &) -> bool;

namespace {

auto keychain_has_item(const std::string keygrip) {
    const auto query = get_keychain_query_for_keygrip(keygrip);
    return (SecItemCopyMatching(query, nullptr) == errSecSuccess);
}

auto get_string_from_cf_string(const auto string) {
    const auto length = CFStringGetLength(string);
    const auto bytes = std::make_unique<uint8_t[]>(length);
    auto bytes_written = CFIndex{};
    CFStringGetBytes(string, CFRangeMake(0, length),
        kCFStringEncodingASCII, 0, CF::Boolean{ false },
        bytes.get(), length, &bytes_written);
    return std::string{ bytes.get(), bytes.get() + bytes_written };
}

auto get_error_string(const auto status) -> std::string {
    const auto error = keychain_entry::managed_cf_ref<CFStringRef>{
        SecCopyErrorMessageString(status, nullptr) };
    if (!error) {
        return {};
    }
    return get_string_from_cf_string(error.get());
}

auto add_key_to_keychain(const std::string keygrip, const auto data) {
    auto query = get_keychain_query_for_keygrip(keygrip);
    query << CF::Pair{ kSecUseDataProtectionKeychain, CF::Boolean{ true } };
    query << CF::Pair{ kSecValueData, CF::Data{ data } };
    const auto status = SecItemAdd(query, nullptr);
    if (status == errSecSuccess) {
        return true;
    }
    std::cerr << "    SecItemAdd failed with this error: " << get_error_string(status) << std::endl;
    return false;
}

auto get_all_keys_from_keychain() -> std::optional<std::vector<std::string>> {
    auto query = get_keychain_query_for_keygrip(std::nullopt);
    query << CF::Pair{ kSecReturnAttributes, CF::Boolean{ true } };
    query << CF::Pair{ kSecMatchLimit, kSecMatchLimitAll };
    typedef keychain_entry::managed_cf_ref<CFArrayRef> managed_cf_array;
    const auto ref = ([&query]() -> managed_cf_array {
        auto ref = CFTypeRef{};
        if (SecItemCopyMatching(query, &ref) != errSecSuccess) {
            return nullptr;
        }
        return managed_cf_array{ static_cast<CFArrayRef>(ref) };
    })();
    if (!ref) {
        return std::nullopt;
    }
    auto keys = std::vector<std::string>{};
    const auto length = CFArrayGetCount(ref.get());
    for (auto i = 0; i < length; ++i) {
        const auto dict = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex(ref.get(), i));
        const auto account = static_cast<CFStringRef>(CFDictionaryGetValue(dict, kSecAttrAccount));
        assert((account != nullptr) && "The key dictionary should have a non-null value for kSecAttrAccount.");
        keys.emplace_back(get_string_from_cf_string(account));
    }
    return keys;
}

auto read_entire_file(const auto filename) {
    auto ifs = std::ifstream{ filename };
    auto buffer = std::stringstream{};
    buffer << ifs.rdbuf();
    return buffer.str();
}

auto get_plural(const auto noun, const auto count) {
    auto buffer = std::stringstream{};
    buffer << count << ' ' << noun;
    if (count > 1) {
        buffer << 's';
    }
    return buffer.str();
}

auto is_file_placeholder(const auto file) {
    return (std::filesystem::file_size(file) < 5);
}

auto is_same_key_in_keychain(const auto data, const auto keygrip) {
    const auto key = get_key_from_keychain<keychain_entry>(keygrip);
    assert((key != nullptr) && "Specified key should already be in the keychain.");
    return std::equal(
        data.cbegin(), data.cend(),
        key->password, key->password + key->password_length);
}

auto write_placeholder(const auto entry) {
    if (std::ofstream{ entry }.is_open()) {
        std::cout << "    Successfully removed the filesystem key and replaced it with a placeholder." << std::endl;
        return true;
    }
    std::cout << "    Failed to remove the filesystem key." << std::endl;
    return false;
}

auto migrate_keys_to_keychain(const auto private_key_path) {
    auto successes = 0;
    auto failures = 0;
    auto replacements = 0;
    for (auto entry : std::filesystem::directory_iterator(private_key_path)) {
        const auto keygrip = entry.path().filename();
        std::cout << "Found " << keygrip << "." << std::endl;
        if (is_file_placeholder(entry)) {
            std::cout << "    Skipping this file because it appears to be a placeholder." << std::endl;
            continue;
        }
        std::cout << "    This appears to be a private key." << std::endl;
        const auto data = read_entire_file(entry);
        if (keychain_has_item(keygrip)) {
            if (is_same_key_in_keychain(std::string_view{ data }, keygrip)) {
                std::cout << "    A copy of this key is already in the keychain." << std::endl;
                if (write_placeholder(entry)) {
                    ++replacements;
                }
            } else {
                std::cout << "    A different version of this key is already in the keychain." << std::endl;
                std::cout << "    To avoid possible data loss, we aren't going to touch this keychain entry." << std::endl;
            }
            continue;
        }
        if (data.empty()) {
            std::cerr << "    Failed to read the private key into memory." << std::endl;
            ++failures;
        } else if (!add_key_to_keychain(keygrip, data)) {
            std::cerr << "    Failed to add the key to the keychain." << std::endl;
            ++failures;
        } else {
            std::cout << "    Successfully added the key to the keychain." << std::endl;
            ++successes;
            if (write_placeholder(entry)) {
                ++replacements;
            }
        }
    }
    if (successes > 0) {
        std::cout << "Successfully added " << get_plural("key", successes) << " to the keychain." << std::endl;
    }
    if (replacements > 0) {
        std::cout << "Successfully removed " << get_plural("key", replacements) <<
            " from the filesytem and replaced the " << get_plural("file", replacements) <<
            " with placeholders." << std::endl;
    }
    if (failures > 0) {
        std::cerr << "Failed to add " << get_plural("key", failures) << " to the keychain." << std::endl;
    }
    if ((successes == 0) && (replacements == 0)) {
        std::cout << "Nothing was changed." << std::endl;
    }
    return failures;
}

auto export_keys_from_keychain(const auto private_key_path) {
    const auto keys = get_all_keys_from_keychain();
    if (!keys) {
        std::cout << "No GPG keys found in keychain. Nothing to do." << std::endl;
        return 0;
    }
    std::cout << "Found " << get_plural("GPG key", keys->size()) << " in the keychain." << std::endl;
    std::cout << "Obtaining user authorization before exporting any keys." << std::endl;
    if (!authenticate_user("export GPG private keys from the keychain and save them to the filesystem")) {
        std::cout << "Failed to obtain authorization." << std::endl;
        return 1;
    }
    for (const auto &keygrip : *keys) {
        std::cout << "Found keychain entry for \"" << keygrip << "\"." << std::endl;
        const auto file = private_key_path / keygrip;
        if (std::filesystem::is_regular_file(file) && !is_file_placeholder(file)) {
            std::cout << "    Skipping this entry because a key with the same "
                "keygrip is already in the filesystem." << std::endl;
            continue;
        }
        const auto key = get_key_from_keychain<keychain_entry>(keygrip);
        if (!key) {
            std::cout << "    Failed to obtain this key from the keychain." << std::endl;
            continue;
        }
        std::ofstream{ file }.write(
            std::bit_cast<const std::ofstream::char_type *>(key->password), key->password_length);
        std::cout << "    Successfully wrote key to the filesystem." << std::endl;
    }
    return 0;
}

void throw_if_invalid_options(const auto argc, const auto argv) {
    for (const auto arg : std::span(argv + 1, argc - 1)) {
        const auto string = std::string{ arg };
        // All valid options must begin with "--".
        if ((string.length() > 2) && (string[0] == '-') && (string[1] == '-')) {
            continue;
        }
        throw boost::program_options::error{
            fmt::format("Invalid command line argument: '{}'", string)
        };
    }
}

template <class T>
void throw_if_conflicting_options(const auto &vm, const std::initializer_list<T> options) {
    auto seen_options = std::vector<T>{};
    std::copy_if(options.begin(), options.end(), std::back_inserter(seen_options),
        [&vm](const T &i) {
            return (vm.count(i) != 0);
        });
    if (seen_options.size() <= 1) {
        return;
    }
    const auto error = ([&seen_options]() {
        auto buffer = std::stringstream{};
        buffer << "Choose only one of the following options: ";
        const auto size = seen_options.size();
        for (auto i = 0; i < size; ++i) {
            buffer << "'--" << seen_options[i] << '\'';
            if (i != (size - 1)) {
                buffer << ", ";
            }
        }
        return buffer.str();
    })();
    throw boost::program_options::error{ error };
}

} // anonymous namespace

int main(const int argc, char *const *argv) {
    namespace po = boost::program_options;
    auto desc = po::options_description{ fmt::format("Allowed options for {}", argv[0]) };
    desc.add_options()
        ("help", "Print this help message.")
        ("migrate-to-keychain",
            "Migrate GPG keys from the filesystem into the keychain and replace the "
            "filesystem keys with placeholders. This is the default if no options are "
            "specified on the command line.")
        ("export-from-keychain", "Copy GPG keys from the keychain into the filesystem.");

    po::variables_map vm;
    try {
        throw_if_invalid_options(argc, argv);
        po::store(po::parse_command_line(argc, argv, desc), vm);
        throw_if_conflicting_options(vm, { "migrate-to-keychain", "export-from-keychain" });
    } catch (po::error &ex) {
        const auto error = ([&ex]() -> std::string {
            if (const auto unknown = dynamic_cast<po::unknown_option *>(&ex)) {
                return fmt::format("Invalid option: '{}'", unknown->get_option_name());
            }
            return ex.what();
        })();
        std::cerr << "Error: " << error << ".\n\n" << desc << std::endl;
        return -1;
    }
    po::notify(vm);

    if (vm.count("help")) {
        std::cout << desc << std::endl;
        return 1;
    }

    const auto private_key_path = get_private_key_path();
    if (private_key_path.empty()) {
        std::cerr << "Error: Could not determine private key directory." << std::endl;
        std::cerr << "Make sure that either GNUPG or HOME is set." << std::endl;
        return 1;
    }
    std::cout << "Private key directory: " << private_key_path << std::endl;

    if (vm.count("migrate-to-keychain")) {
        return migrate_keys_to_keychain(private_key_path);
    } else if (vm.count("export-from-keychain")) {
        return export_keys_from_keychain(private_key_path);
    }

    std::cout << "No operation was specified. Assuming --migrate-to-keychain." << std::endl;
    return migrate_keys_to_keychain(private_key_path);
}