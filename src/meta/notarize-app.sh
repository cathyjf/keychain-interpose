#!/bin/bash -e
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

if [[ ! -d "$1" ]] || { ! codesign --deep --verify --strict "$1"; } then
    echo "Error: $1 should be a signed app bundle but is not." 1>&2
    exit 1
elif { spctl -a "$1" > /dev/null 2>&1; } && { xcrun stapler validate -q "$1"; } then
    echo "$1 is already validly notarized."
    exit 0
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
chmod go-rwx "${tmp_dir}"
zip_path="${tmp_dir}/$(basename "$1").zip"
/usr/bin/ditto -ck --keepParent "$1" "${zip_path}"

auth_args=( "--keychain-profile" "${NOTARY_KEYCHAIN_PROFILE:?}" )
xcrun notarytool submit "${zip_path}" "${auth_args[@]}" --wait | tee "${tmp_dir}/submit.log"
# submission_id=$(grep -o -E -m 1 "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" "$tmp_dir/submit.log")
# echo "Submission ID: $submission_id"
# xcrun notarytool log "$submission_id" "${auth_args[@]}"

staple_app() {
    local bundle
    bundle=$(sed 's/\/Contents\/Info\.plist//' < <(echo "$1"))
    [[ -d "${bundle}" ]] || return 1
    xcrun stapler staple "${bundle}"
}

export -f staple_app
# shellcheck disable=SC2016
find "$1" -name 'Info.plist' -print0 | xargs -0 -I{} "${BASH}" -efc 'staple_app "$1"' shell {}

# Verify that the notarization was successful.
spctl -vva "$1"