#!/bin/bash
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later
set -efu -o pipefail

which -s brew
read -r -d '' brewfile_text << 'BREWFILE_END' || true
    brew "bash"
    brew "cmake"
    brew "llvm"
    brew "procmail"
    brew "wget"
    brew "yq"
BREWFILE_END
brew_bundle_args=( --no-upgrade --no-lock --quiet --file - )

export HOMEBREW_NO_AUTO_UPDATE=1
if ! brew bundle check "${brew_bundle_args[@]}" 1>&2 <<< "${brewfile_text}"; then
    brew bundle install "${brew_bundle_args[@]}" 1>&2 <<< "${brewfile_text}"
fi

BREW_CLANG="$(brew --prefix 2>/dev/null || true)/opt/llvm/bin/clang++"
if [[ -x "$BREW_CLANG" ]]; then
    echo -n "$BREW_CLANG"
else
    printf \\n"**** Homebrew's version of clang (llvm) is required to compile this program. ****"\\n\\n 1>&2
    printf "To obtain Homebrew's version of clang, install Homebrew and then run:"\\n 1>&2
    printf "    brew install llvm"\\n\\n 1>&2
    printf "Error messages below here can be ignored."\\n\\n 1>&2

    # Return "false" as the compiler to use in the Makefile so that the Makefile does not run.
    echo "false"
    exit 1
fi