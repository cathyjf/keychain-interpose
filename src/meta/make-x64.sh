#!/usr/bin/arch -x86_64 sh -e

# We can compile with the arm64 clang even for the x86_64 target.
CXX=$(src/meta/print-compiler.sh)
LIBTOOL=$(dirname $CXX)/llvm-libtool-darwin

export HOMEBREW_REPOSITORY=
export HOMEBREW_CELLAR=
export HOMEBREW_PREFIX=
BREW_X64=/usr/local/bin/brew
if [ ! -x "$BREW_X64" ]; then
    echo "You must install brew for x86_64 before running this script."
    exit 1
fi
eval $($BREW_X64 shellenv)

install_if_needed() {
    [ -d "$HOMEBREW_PREFIX/opt/$1" ] || brew install "$1";
}

install_if_needed boost
install_if_needed fmt
install_if_needed gnupg

make CPPFLAGS_EXTRA="-arch x86_64" BUILD_DIR="x64" CXX="$CXX" LIBTOOL="$LIBTOOL" $@