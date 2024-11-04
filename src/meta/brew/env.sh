#!/bin/bash -e
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

unset HOMEBREW_REPOSITORY
unset HOMEBREW_CELLAR
unset HOMEBREW_PREFIX
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSECURE_REDIRECT=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

get_prefix_for_arch() {
    case "$1" in
        'arm64') echo "/opt/homebrew";;
        'x86_64' | 'i386') echo "/usr/local";;
        *) echo "[env] Unrecognized architecture: $1" 1>&2; return 1;;
    esac
}

install_brew() {
    tmp_dir=$(mktemp -d)
    curl -s -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$tmp_dir"
    mv -f "$tmp_dir" "$1"
    if [ ! -x "$2" ]; then
        echo "Failed to set up a local brew installaton in $1." 1>&2
        exit 1
    fi
    "$2" update --force --quiet
}

my_arch=$(arch)
[[ "$my_arch" == "i386" ]] && my_arch="x86_64"
brew_prefix=$(set -e; get_prefix_for_arch "$my_arch")
brew=( "$brew_prefix"/bin/brew )
if [ ! -x "${brew[0]}" ]; then
    echo "Error: ${brew[0]} is not executable."
    echo "Homebrew must be installed normally before running this script."
    echo "See https://brew.sh for installation instructions."
    exit 1
fi

brew_arch="${HOMEBREW_WRAPPER_ARCH:-$my_arch}"
if [ "$my_arch" != "$brew_arch" ]; then
    # If we get here, the user has requested a foreign installation of Homebrew.
    potential_local_brew=$(set -e; get_prefix_for_arch "$brew_arch")"/bin/brew"
    if [ -x "$potential_local_brew" ]; then
        brew=( "arch" "-$brew_arch" "$potential_local_brew" )
    else
        local_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
        local_brew_dir="$local_root"/.homebrew
        mkdir -p "$local_brew_dir"
        brew_prefix="$local_brew_dir/$brew_arch"
        brew=( "$brew_prefix"/bin/brew )
        if [ ! -x "${brew[0]}" ]; then
            install_brew "$brew_prefix" "${brew[0]}"
        fi
    fi
fi

eval "$("${brew[@]}" shellenv)"