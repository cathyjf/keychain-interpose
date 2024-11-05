#!/bin/bash -e
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# $1: Name of binary (e.g., "migrate-keys")
# $2: Name of directory where binaries are built (e.g., "bin")
# $3: Name of directory where object files are built (e.g., "objects")
# $4: Code signing identity or "--skip-signing"
# $5: Empty string or "--sign-only"
: "${1:?}" "${2:?}" "${3:?}" "${4:?}"

magic_name="$1"
if [[ ${magic_name} == "keychain-interpose" ]]; then
    magic_name="migrate-keys"
fi

if [[ "$5" != "--sign-only" ]]; then
    mkdir -p "$2/$1.app/Contents/MacOS"
    m4 -D MY_BINARY_NAME="$magic_name" src/meta/Info.plist.m4 > "$2/$1.app/Contents/Info.plist"
    install -m u=rw "src/meta/profiles/keychain-interpose.provisionprofile" \
        "$2/$1.app/Contents/embedded.provisionprofile"
    source="$2/$1"
    target="$2/$1.app/Contents/MacOS/$1"
    if [[ (-x "${source}") && (! -x "${target}") ]]; then
        install -m u=rwx "${source}" "${target}"
    fi
fi

if [[ "$4" != "--skip-signing" ]]; then
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    "$SCRIPT_DIR/codesign.sh" "$2/$1.app" "$4" "--entitlements $3/$magic_name-entitlements.plist"
fi