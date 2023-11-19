#!/bin/bash -e
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# $1: Name of binary (e.g., "migrate-keys")
# $2: Name of directory where binaries are built (e.g., "bin")
# $3: Name of directory where object files are built (e.g., "objects")
# $4: Code signing identity or "--skip-signing"
# $5: Empty string or "--sign-only"
: "${1:?}" "${2:?}" "${3:?}" "${4:?}"

if [ "$5" != "--sign-only" ]; then
    mkdir -p "$2/$1.app/Contents/MacOS"
    m4 -D MY_BINARY_NAME="$1" src/meta/Info.plist.m4 > "$2/$1.app/Contents/Info.plist"
    install -m u=rw "src/meta/profiles/keychain-interpose.provisionprofile" "$2/$1.app/Contents/embedded.provisionprofile"
    install -m u=rwx "$2/$1" "$2/$1.app/Contents/MacOS/$1"
fi

if [ "$4" != "--skip-signing" ]; then
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    FORCE_CODESIGN=1 "$SCRIPT_DIR/codesign.sh" "$2/$1.app" "$4" "--entitlements $3/$1-entitlements.plist"
fi