// SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#include <array>
#include <filesystem>
#include <format>
#include <iostream>
#include <map>
#include <ranges>
#include <set>
#include <span>
#include <stdio.h>
#include <sys/syslimits.h>
#include <unistd.h>

#include <boost/algorithm/string/replace.hpp>
#include <boost/regex.hpp>

import cathyjf.ki.common;

namespace {

[[nodiscard]] auto escape_shell_argument_single_quotes(const auto argument) {
    return boost::replace_all_copy(argument, "'", "'\"'\"'");
}

[[nodiscard]] auto get_dylibs_from_otool(const auto binary_file) {
    auto objects = std::set<std::string>{};
    const auto escaped_file = escape_shell_argument_single_quotes(binary_file);
    const auto file = managed_popen(std::format("otool -L '{}'", escaped_file).c_str(), "r");
    while (auto data = fgetln_string(file.get())) {
        auto what = boost::cmatch{};
        static const auto otool_dylib_regex = boost::regex{ "^\\h+(.*)\\h+\\(.*" };
        if (!boost::regex_match(data->c_str(), what, otool_dylib_regex)) {
            continue;
        }
        const auto dylib = what[1];
        objects.insert(dylib);
    }
    return objects;
}

auto populate_objects(const auto binary_file, auto &objects, const int depth = 1) -> void {
    if (!std::filesystem::is_regular_file(binary_file)) {
        return;
    }
    objects.insert(binary_file);
    std::cout << std::string(depth, '+') << ' ' << binary_file << std::endl;
    const auto new_objects = get_dylibs_from_otool(binary_file);
    for (const auto &object : new_objects) {
        if (objects.contains(object)) {
            continue;
        }
        populate_objects(object, objects, depth + 1);
    }
}

[[nodiscard]] auto make_relative_path(const auto &target) {
    return std::format("@executable_path/../Frameworks/{}",
        std::filesystem::path{ target }.filename().string());
}

[[nodiscard]] auto copy_objects_and_create_map(const auto &objects, const auto destination) {
    struct dylib_data {
        std::string target_path;
        std::string relative_target_path;
    };
    auto map = std::map<std::string, dylib_data>{};
    for (const auto &object : objects) {
        const auto source = std::filesystem::path{ object };
        const auto container = (source.extension() == ".dylib" ? "Frameworks" : "MacOS");
        const auto target = destination / container / source.filename();
        if (std::filesystem::is_regular_file(target)) {
            std::filesystem::permissions(target, std::filesystem::perms::owner_write, std::filesystem::perm_options::add);
        }
        std::filesystem::copy_file(source, target, std::filesystem::copy_options::overwrite_existing);
        std::cout << std::format("+ {} (from {})", target.string(), source.string()) << std::endl;
        map.insert({ source.string(), dylib_data {
            .target_path = target.string(),
            .relative_target_path = make_relative_path(target.string())
        } });
    }
    return map;
}

auto apply_install_name_tool_for_binary(const auto &binary_entry, const auto &map) -> void {
    std::system(std::format(
        "install_name_tool -id '{}' '{}' 2>/dev/null",
            escape_shell_argument_single_quotes(binary_entry.second.relative_target_path),
            escape_shell_argument_single_quotes(binary_entry.second.target_path)
    ).c_str());
    for (const auto &entry : map) {
        const auto command = std::format("install_name_tool -change '{}' '{}' '{}' 2>/dev/null",
            escape_shell_argument_single_quotes(entry.first),
            escape_shell_argument_single_quotes(entry.second.relative_target_path),
            escape_shell_argument_single_quotes(binary_entry.second.target_path)
        );
        std::system(command.c_str());
    }
}

auto apply_install_name_tool_for_map(const auto &map) -> void {
    for (const auto &entry : map) {
        std::cout << "+ " << entry.second.target_path << std::endl;
        apply_install_name_tool_for_binary(entry, map);
    }
}

[[nodiscard]] auto install_licensing_information(const auto &i, const auto &prefix, const auto &target) {
    const auto package_path = prefix / i;
    const auto pkg_info_path = target / i;
    if (std::filesystem::is_directory(pkg_info_path)) {
        std::filesystem::remove_all(pkg_info_path);
    }
    if (!std::filesystem::create_directory(pkg_info_path, target)) {
        std::cerr << "Failed to create directory: " << pkg_info_path << std::endl;
        return false;
    }
    for (const auto &entry : std::filesystem::directory_iterator{ package_path }) {
        if (!std::filesystem::is_regular_file(entry)) {
            continue;
        }
        std::filesystem::copy(entry, pkg_info_path);
    }
    std::cout << "+ " << i << std::endl;
    return true;
}

[[nodiscard]] auto handle_licensing_information(const auto &objects, const auto &extra_pkgs,
        const auto &prefix, const auto &target) -> bool {
    auto pkg_names = std::vector<std::string>{ std::cbegin(extra_pkgs), std::cend(extra_pkgs) };
    for (const auto &object : objects) {
        const auto file = std::filesystem::path{ object };
        const auto [i, j] = std::mismatch(file.begin(), file.end(), prefix.begin(), prefix.end());
        if ((j != prefix.end()) || (i == file.end())) {
            continue;
        }
        pkg_names.emplace_back(*i);
    }
    for (const auto &entry : pkg_names) {
        if (!install_licensing_information(entry, prefix, target)) {
            return false;
        }
    }
    return true;
}

} // anonymous namespace

class temporary_directory {
public:
    temporary_directory(): _path(([]() -> decltype(_path) {
        auto buffer = std::array<char, PATH_MAX>{};
        const auto template_path = std::filesystem::temp_directory_path() / "encapsulate-app.XXXXXXXX";
        strcpy(buffer.data(), template_path.string().c_str());
        if (mkdtemp(buffer.data()) == nullptr) {
            throw std::runtime_error("failed to create temporary directory");
        }
        return buffer.data();
    })()) {}
    auto &path() const {
        return _path;
    }
    auto reset() {
        _path.clear();
    }
    ~temporary_directory() {
        if (!_path.empty()) {
            std::filesystem::remove_all(_path);
        }
    }
private:
    std::filesystem::path _path;
};

class pushd {
public:
    pushd(const auto path): _old_path(std::filesystem::current_path()) {
        std::filesystem::current_path(path);
    }
    auto reset() {
        if (!_old_path.empty()) {
            std::filesystem::current_path(_old_path);
            _old_path.clear();
        }
    }
    ~pushd() {
        reset();
    }
private:
    std::filesystem::path _old_path;
};

auto main(const int argc, const char **argv) -> int {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " binary_file app_dir [brew_prefix [extra_pkg1...]]" << std::endl;
        return 1;
    }
    auto objects = std::set<std::string>{};
    const auto binary_file = std::string{ argv[1] };
    const auto final_destination = std::filesystem::path{ argv[2] };

    auto temp = temporary_directory{};
    auto pushd_guard = pushd{ temp.path() };
    const auto scratch = std::filesystem::path{ "app/Contents" };

    // Let's create a skeletal app bundle where we'll place the result.
    std::filesystem::create_directories(scratch / "MacOS");
    std::filesystem::create_directories(scratch / "Frameworks");
    std::filesystem::create_directories(scratch / "Resources/pkg-info");

    std::cout << "Object tree:" << std::endl;
    populate_objects(binary_file, objects);

    if (argc >= 4) {
        std::cout << "Copying package information for:" << std::endl;
        const auto success = handle_licensing_information(objects, std::span(argv + 4, argv + argc),
            std::filesystem::path{ argv[3] } / "opt", scratch / "Resources/pkg-info");
        if (!success) {
            return 1;
        }
    }

    std::cout << "Creating:" << std::endl;
    const auto map = copy_objects_and_create_map(objects, scratch);

    std::cout << "Remapping:" << std::endl;
    apply_install_name_tool_for_map(map);

    pushd_guard.reset();
    std::filesystem::remove_all(final_destination);
    std::filesystem::rename(temp.path() / "app", final_destination);
    std::cout << "Created " << final_destination << '.' << std::endl;
}