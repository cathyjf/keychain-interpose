#!/bin/sh

SCRIPT_DIR="$(dirname $(readlink -f "$0"))"
set -x
KEYCHAIN_INTERPOSE_LOG_FILE_PATH="$SCRIPT_DIR/keychain-interpose.log"
DYLD_INSERT_LIBRARIES="$SCRIPT_DIR/../bin/keychain-interpose.dylib"
set +x

export KEYCHAIN_INTERPOSE_LOG_FILE_PATH
export DYLD_INSERT_LIBRARIES

set -x
exec "$SCRIPT_DIR/../bin/gpg-agent.app/Contents/MacOS/gpg-agent" \
    --pinentry-program "$SCRIPT_DIR/pinentry-wrapper"