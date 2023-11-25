#!/bin/bash -e
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# $1: Directory where keychain-interpose.app was built.
# $2: Installation directory.
: "${1:?}" "${2:?}"

APP_NAME="keychain-interpose.app"

print_cdhash() {
    local data
    data="$(codesign -dvvv "$1" 2>&1)" || return 1
    sed -En 's/^CDHash=([0-9a-f]*)$/\1/p' < <(echo "$data")
}

new_cdhash=$(set -e; print_cdhash "$1/$APP_NAME")
# shellcheck disable=SC2311
old_cdhash=$(print_cdhash "$2/$APP_NAME")
if [ "$new_cdhash" = "$old_cdhash" ] && (xcrun stapler validate -q "$2/$APP_NAME"); then
    echo "The installed version of keychain-interpose.app is up-to-date."
    exit 0
fi

set -x
tmp_dir=$(mktemp -d)
cp -R "$1/$APP_NAME" "$tmp_dir"
rm -Rf "${2:?}/${APP_NAME:?}"
mv -f "$tmp_dir/$APP_NAME" "$2/$APP_NAME"

# Set up some symlinks.
ln -s -f "$2/$APP_NAME/Contents/MacOS/migrate-keys" "$2/migrate-keys"
ln -s -f "$2/$APP_NAME/Contents/Resources/gpg-keychain-agent.sh" "$2/gpg-keychain-agent"