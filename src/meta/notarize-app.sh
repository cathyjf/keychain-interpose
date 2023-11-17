#!/bin/bash -ex

if [ ! -d "$1" ] || { ! codesign --deep --verify --strict "$1"; }; then
    echo "Error: $1 should be a signed app bundle but is not." 1>&2
    exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT
chmod go-rwx "$tmp_dir"
zip_path="$tmp_dir/app.zip"
/usr/bin/ditto -ck --keepParent "$1" "$zip_path"

pass apple/app-store-connect-383L4JV2SD.p8 > "$tmp_dir/key.p8"
NOTARY_KEY_PATH="$tmp_dir/key.p8"
NOTARY_KEY_ID="383L4JV2SD"
NOTARY_KEY_ISSUER="f0e30a15-345a-4150-a66f-a78aa1180e22"
auth_args=( "--key" "$NOTARY_KEY_PATH" "--key-id" "$NOTARY_KEY_ID" "--issuer" "$NOTARY_KEY_ISSUER" )

xcrun notarytool submit "$zip_path" "${auth_args[@]}" --wait | tee "$tmp_dir/submit.log"
# submission_id=$(grep -o -E -m 1 "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" "$tmp_dir/submit.log")
# echo "Submission ID: $submission_id"
# xcrun notarytool log "$submission_id" "${auth_args[@]}"

xcrun stapler staple "$1"