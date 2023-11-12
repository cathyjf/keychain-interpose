#!/usr/bin/env bash

if [ -n "$SKIP_CODESIGN" ] && codesign -d --verbose "$1" 2>&1 | grep -q "flags=0x10000(runtime)"; then
    exit
fi

LOCKFILE_BIN=$(which lockfile)
CODESIGNING_LOCKFILE="codesigning.lock"
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

set -x
codesign -f --timestamp --options runtime $3 -s "$2" "$1";
RETURN_VALUE=$?
if [ "$RETURN_VALUE" -ne "0" ]; then
    rm -f "$1"
fi
set +x

rm -f "$CODESIGNING_LOCKFILE"
exit $RETURN_VALUE