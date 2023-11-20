#!/bin/bash -ef
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

script_dir=$(realpath "$(dirname "$0")")
export DYLD_INSERT_LIBRARIES="$script_dir/../Frameworks/keychain-interpose.dylib"
if [ -z "$KEYCHAIN_INTERPOSE_LOG_FILE_PATH" ]; then
    export KEYCHAIN_INTERPOSE_DISABLE_LOGGING=1
fi
exec "$script_dir/../MacOS/gpg-agent.app/Contents/MacOS/gpg-agent" "$@"