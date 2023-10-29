#!/usr/bin/env fish --no-config

killall gpg-agent
gpg -vv --output /dev/null --agent-program (realpath (status dirname))"/agent.sh" --decrypt Makefile.gpg
# gpg -vv -K --with-keygrip --agent-program (realpath (status dirname))"/agent.sh"
killall gpg-agent