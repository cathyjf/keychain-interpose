#!/bin/bash -e
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

# $1: Directory where keychain-interpose.app was built.
# $2: Installation directory.
: "${1:?}" "${2:?}"

APP_NAME="keychain-interpose.app"

tmp_dir=$(mktemp -d)
readonly tmp_dir
trap 'rm -rf -- "$tmp_dir"' EXIT

declare -r spctl_log="${tmp_dir}/spctl.log"
if ! spctl -avv "$1/${APP_NAME}" >"${spctl_log}" 2>&1; then
    echo "Warning: The spctl(8) utility reports failure with this log:"
    sed 's/^/    /' < "${spctl_log}"
    echo "Depending on your use case, this might be acceptable to you."
    declare spctl_reply
    read -p "Proceed with the installation [N/y]? " -n 1 -r spctl_reply
    echo
    [[ -z "${spctl_reply}" ]] || echo
    if [[ "${spctl_reply}" != "y" ]] && [[ "${spctl_reply}" != "Y" ]]; then
        echo "Aborting installation based on user response."
        exit 1
    fi
fi

print_cdhash() {
    local data
    data="$(codesign -dvvv "$1" -a "$2" 2>&1)" || return 0
    sed -En 's/^CDHash=([0-9a-f]*)$/\1/p' < <(echo "${data}")
}

print_multiarch_cdhash() {
    print_cdhash "$1" "arm64"
    print_cdhash "$1" "x86_64"
}

new_cdhash=$(set -e; print_multiarch_cdhash "$1/${APP_NAME}")
old_cdhash=$(set -e; print_multiarch_cdhash "$2/${APP_NAME}")
if [[ -z "${new_cdhash}" ]]; then
    echo "Error: App bundle is not properly signed. Aborting installation."
    exit 1
elif [[ "${#new_cdhash}" -lt "${#old_cdhash}" ]]; then
    echo "Error: New app bundle supports fewer architectures than existing installed version."
    echo "Aborting installation."
    exit 1
elif [[ "${new_cdhash}" = "${old_cdhash}" ]]; then
    echo "The installed version of keychain-interpose.app is up-to-date."
    exit 0
fi

set -x
cp -R "$1/${APP_NAME}" "${tmp_dir}"
rm -Rf "${2:?}/${APP_NAME:?}"
mv -f "${tmp_dir}/${APP_NAME}" "$2/${APP_NAME}"

# Set up some symlinks.
ln -s -f "$2/${APP_NAME}/Contents/MacOS/migrate-keys" "$2/migrate-keys"
ln -s -f "$2/${APP_NAME}/Contents/Resources/gpg-keychain-agent.sh" "$2/gpg-keychain-agent"
