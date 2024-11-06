#!/bin/bash -ef
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later
: "${1:?}" "${2:?}"

declare SIGNING_STATUS LOCKFILE_BIN CODESIGNING_LOCKFILE
SIGNING_STATUS=1
LOCKFILE_BIN=$(which lockfile)
CODESIGNING_LOCKFILE="$(dirname "$(readlink -f "$0")")/.codesigning.lock"
readonly LOCKFILE_BIN CODESIGNING_LOCKFILE

# This function is invoked by a trap handler below.
# shellcheck disable=SC2317
on_exit() {
    if [[ ${SIGNING_STATUS:?} -ne 0 ]]; then
        rm -Rf -- "${1:?}"
    fi
    rm -f -- "${CODESIGNING_LOCKFILE:?}"
}
trap 'on_exit "$1"' EXIT

if [[ -x "${LOCKFILE_BIN}" ]]; then
    "${LOCKFILE_BIN}" -1 -l 10 "${CODESIGNING_LOCKFILE}"
fi

# shellcheck disable=SC2206
IFS=' ' extra_args=( $3 )
readonly extra_args
(set +e; codesign -f --timestamp --options runtime "${extra_args[@]}" -s "${2}" "${1}")
SIGNING_STATUS=${?}
readonly SIGNING_STATUS

exit "${SIGNING_STATUS}"