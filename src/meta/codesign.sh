#!/bin/bash -ef
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later
: "${1:?}" "${2:?}"

if [ -n "$SKIP_CODESIGN" ] && codesign -d --verbose "$1" 2>&1 | grep -q "flags=0x10000(runtime)"; then
    exit
fi

declare SIGNING_STATUS LOCKFILE_BIN CODESIGNING_LOCKFILE
SIGNING_STATUS=1
LOCKFILE_BIN=$(which lockfile)
CODESIGNING_LOCKFILE="$(dirname "$(readlink -f "$0")")/.codesigning.lock"
readonly LOCKFILE_BIN CODESIGNING_LOCKFILE

# This function is invoked by a trap handler below.
# shellcheck disable=SC2317
on_exit() {
    if [ "${SIGNING_STATUS:?}" -ne "0" ]; then
        rm -Rf -- "${1:?}"
    fi
    rm -f -- "${CODESIGNING_LOCKFILE:?}"
}
trap 'on_exit "$1"' EXIT

if [ -x "$LOCKFILE_BIN" ]; then
    "$LOCKFILE_BIN" -1 -l 10 "$CODESIGNING_LOCKFILE"
fi

if [ -n "$SHOW_CODESIGN_EXPLANATION" ]; then
    echo
    echo "We need to sign $1 with identity $2.";
    echo "This should only be required in one of the following two cases: ";
    echo "    (1) This is your first time installing keychain-interpose for gpg-agent; or";
    echo "    (2) You have updated gpg-agent or one of its components since you last signed it.";
    echo "If neither of these is true, something unexpected is happening, so you might";
    echo "want to cancel this process and figure out what is going on. However, if one";
    echo "of the two cases above applies, then it is normal that we need to sign this file.";
fi

# shellcheck disable=SC2206
IFS=' ' extra_args=( $3 )
readonly extra_args
(set -x +e; codesign -f --timestamp --options runtime "${extra_args[@]}" -s "$2" "$1")
SIGNING_STATUS=$?
readonly SIGNING_STATUS

exit "$SIGNING_STATUS"