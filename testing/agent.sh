#!/bin/bash -ef
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

script_dir="$(dirname "$(readlink -f "$0")")"
agent_path="${script_dir}/../bin/keychain-interpose.app/Contents/Resources/gpg-keychain-agent.sh"
[[ -x "${agent_path}" ]] || exit 1

pinentry_path="${script_dir}/../bin/keychain-interpose.app/Contents/MacOS/pinentry-wrapper"
[[ -x "${pinentry_path}" ]] || exit 1

export KEYCHAIN_INTERPOSE_LOG_FILE_PATH="${script_dir}/keychain-interpose.log"
exec "${agent_path}" --pinentry-program "${pinentry_path}" "$@"
