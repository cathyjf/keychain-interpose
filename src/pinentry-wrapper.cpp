#include <cstdlib>
#include <unistd.h>

auto main(const int argc, char **argv) -> int {
    constexpr static auto PINENTRY_TOUCHID = "pinentry-touchid";
    constexpr static auto PINENTRY_TTY = "pinentry-tty";
    const auto binary = std::getenv("SSH_TTY") ? PINENTRY_TTY : PINENTRY_TOUCHID;
    const auto status = execvp(binary, argv);
    if ((status != -1) || (binary == PINENTRY_TTY)) {
        return status;
    }
    return execvp(PINENTRY_TTY, argv);
}