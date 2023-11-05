#!/usr/bin/env fish --no-config

set -l agent (realpath (status dirname))"/agent.sh"

make -C ~/git/gnupg -j

killall gpg-agent
eval "$agent" --daemon
# gpg -vv --output /dev/null --agent-program $agent --decrypt Makefile.gpg
# gpg -vv -K --with-keygrip --agent-program $agent
git pull
killall gpg-agent
wait
