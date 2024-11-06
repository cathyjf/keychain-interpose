#!/bin/bash -e
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

tmp_dir=$(mktemp -d)
trap 'rm -rf -- "$tmp_dir"' EXIT

pass apple/app-store-connect-383L4JV2SD.p8 > "${tmp_dir}/key.p8"
NOTARY_KEY_PATH="${tmp_dir}/key.p8"
NOTARY_KEY_ID="383L4JV2SD"
NOTARY_KEY_ISSUER="f0e30a15-345a-4150-a66f-a78aa1180e22"
auth_args=( "--key" "${NOTARY_KEY_PATH}" "--key-id" "${NOTARY_KEY_ID}" "--issuer" "${NOTARY_KEY_ISSUER}" )

: "${PROFILE_NAME:=cathyjf}"
xcrun notarytool store-credentials "${PROFILE_NAME}" "${auth_args[@]}"
