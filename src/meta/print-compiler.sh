#!/bin/bash -efu
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

which -s brew && brew bundle install --no-lock --file - 1>&2 << 'BREWFILE_END'
    tap "homebrew/core"
    brew "llvm"
    brew "procmail"
    brew "wget"
    brew "yq"
BREWFILE_END

BREW_CLANG="$(brew --prefix 2>/dev/null || true)/opt/llvm/bin/clang++"
if [ -x "$BREW_CLANG" ]; then
    echo "$BREW_CLANG"
else
    printf \\n"**** Homebrew's version of clang (llvm) is required to compile this program. ****"\\n\\n 1>&2
    printf "To obtain Homebrew's version of clang, install Homebrew and then run:"\\n 1>&2
    printf "    brew install llvm"\\n\\n 1>&2
    printf "Error messages below here can be ignored."\\n\\n 1>&2

    # Return "false" as the compiler to use in the Makefile so that the Makefile does not run.
    echo "false"
    exit 1
fi