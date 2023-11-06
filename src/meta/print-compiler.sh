#!/bin/sh

BREW_CLANG="$(brew --prefix)/opt/llvm/bin/clang++"
if [ -x "$BREW_CLANG" ]; then
    echo "$BREW_CLANG"
else
    printf \\n"**** Homebrew's version of clang (llvm) is required to compile this program. ****"\\n\\n 1>&2
    printf "To obtain Homebrew's version of clang, install Homebrew and then run:"\\n 1>&2
    printf "    brew install llvm"\\n\\n 1>&2
    printf "Error messages below here can be ignored."\\n\\n 1>&2

    # Return "false" as the compiler to use in the Makefile so that the Makefile does not run.
    echo "false"
fi