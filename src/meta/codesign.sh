#!/usr/bin/env bash

if [ -z "$FORCE_CODESIGN" ] && codesign -d --verbose "$1" 2>&1 | grep -q "flags=0x10000(runtime)"; then
    exit
fi

echo
echo "We need to sign $1 with identity $2.";
echo "This should only be required in one of the following two cases: ";
echo "    (1) This is your first time installing keychain-interpose for gpg-agent; or";
echo "    (2) You have updated gpg-agent or one of its components since you last signed it.";
echo "If neither of these is true, something unexpected is happening, so you might";
echo "want to cancel this process and figure out what is going on. However, if one";
echo "of the two cases above applies, then it is normal that we need to sign this file.";
codesign -f --options runtime $3 -s "$2" "$1";