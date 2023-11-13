#!/usr/bin/arch -x86_64 sh
export HOMEBREW_REPOSITORY=
export HOMEBREW_CELLAR=
export HOMEBREW_PREFIX=
eval $(/usr/local/bin/brew shellenv)
# brew install llvm boost fmt gnupg

make CPPFLAGS_EXTRA="-arch x86_64" BUILD_DIR="x64" $@