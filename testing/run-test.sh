#!/bin/sh -ef
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

script_dir=$(dirname "$(readlink -f "$0")")
gpg_agent="$script_dir/agent.sh"

# make -C ~/git/gnupg -j

: "$(killall gpg-agent)"
eval "$gpg_agent" --daemon
# gpg -vv --output /dev/null --agent-program "$gpg_agent" --decrypt Makefile.gpg
# gpg -vv -K --with-keygrip --agent-program "$gpg_agent"
git pull
killall gpg-agent
wait

rm -f "$script_dir/gpg-agent.log"