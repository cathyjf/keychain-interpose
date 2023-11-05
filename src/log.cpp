#include <chrono>
#include <cstdlib>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <time.h>

#include "include/log.h"

namespace {

constexpr auto DISABLE_LOGGING_ENV_VAR = "KEYCHAIN_INTERPOSE_DISABLE_LOGGING";

std::filesystem::path getDylibPath() {
    auto info = Dl_info{};
    if (dladdr(reinterpret_cast<void *>(static_cast<void(*)(const char *)>(write_log_message)), &info)) {
        return info.dli_fname;
    }
    return {};
}

} // anonymous namespace

void write_log_message(const std::string message) {
    write_log_message(message.c_str());
}

void write_log_message(const char *message) {
    static auto mutex = std::mutex{};
    const auto lock = std::scoped_lock{ mutex };
    static auto exeName = std::string{};
    static auto logStream = ([]() -> std::ofstream {
        if (getenv(DISABLE_LOGGING_ENV_VAR) != nullptr) {
            return {};
        }
        const auto logPath = ([]() -> std::string {
            auto exePath = getDylibPath();
            if (exePath.empty()) [[unlikely]] {
                return {};
            }
            exeName = exePath.filename().string();
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
