// SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
// SPDX-License-Identifier: GPL-3.0-or-later

module;
#include <chrono>
#include <cstdlib>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <time.h>

export module cathyjf.ki.log;

constexpr auto ENV_VAR_DISABLE_LOGGING = "KEYCHAIN_INTERPOSE_DISABLE_LOGGING";
constexpr auto ENV_VAR_LOG_FILE_PATH = "KEYCHAIN_INTERPOSE_LOG_FILE_PATH";

export void write_log_message(const char *); // Forward declaration for `getDylibPath`.

std::filesystem::path getDylibPath() {
    auto info = Dl_info{};
    if (dladdr(reinterpret_cast<void *>(static_cast<void(*)(const char *)>(write_log_message)), &info)) {
        return info.dli_fname;
    }
    return {};
}

export void write_log_message(const std::string message) {
    write_log_message(message.c_str());
}

export void write_log_message(const char *message) {
    static auto mutex = std::mutex{};
    const auto lock = std::scoped_lock{ mutex };
    static auto exeName = std::string{};
    static auto logStream = ([]() -> std::ofstream {
        if (getenv(ENV_VAR_DISABLE_LOGGING) != nullptr) {
            return {};
        }
        const auto logPath = ([]() -> std::string {
            auto exePath = getDylibPath();
            if (exePath.empty()) [[unlikely]] {
                return {};
            }
            exeName = exePath.filename().string();
            if (const auto env_filename = getenv(ENV_VAR_LOG_FILE_PATH)) {
                return { env_filename };
            }
            return exePath.replace_filename("keychain-interpose.log").string();
        })();
        if (logPath.empty()) [[unlikely]] {
            return {};
        }
        return std::ofstream{ logPath };
    })();
    if (logStream.is_open()) {
        const auto timeString = ([]() -> std::string {
            const auto time = std::time(nullptr);
            if (time == -1) [[unlikely]] {
                return "[time failed] ";
            }
            auto localtime = tm{};
            if (localtime_r(&time, &localtime) == nullptr) [[unlikely]] {
                return "[localtime_r failed] ";
            }
            auto buffer{ std::array<char, std::size("yyyy-mm-dd hh:mm:ss")>{} };
            const auto length = std::strftime(buffer.data(), buffer.size(), "%F %T", &localtime);
            if (length == 0) [[unlikely]] {
                return "[strftime failed] ";
            }
            return "[" + std::string{ buffer.data() } + "] ";
        })();
        const auto exeString = "[" + exeName + "] ";
        logStream << exeString << timeString << message << std::endl;
    }
}