#!/bin/bash -e
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

if [ ! -d "$1" ] || { ! codesign --deep --verify --strict "$1"; }; then
    echo "Error: $1 should be a signed app bundle but is not." 1>&2
    exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
chmod go-rwx "$tmp_dir"
zip_path="$tmp_dir/$(basename "$1").zip"
/usr/bin/ditto -ck --keepParent "$1" "$zip_path"

auth_args=( "--keychain-profile" "${NOTARY_KEYCHAIN_PROFILE:?}" )
xcrun notarytool submit "$zip_path" "${auth_args[@]}" --wait | tee "$tmp_dir/submit.log"
# submission_id=$(grep -o -E -m 1 "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" "$tmp_dir/submit.log")
# echo "Submission ID: $submission_id"
# xcrun notarytool log "$submission_id" "${auth_args[@]}"

xcrun stapler staple "$1"