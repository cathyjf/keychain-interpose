#!/bin/sh -x

AGENT="$(dirname $(readlink -f "$0"))/agent.sh"

# make -C ~/git/gnupg -j

killall gpg-agent
eval "$AGENT" --daemon
# gpg -vv --output /dev/null --agent-program "$AGENT" --decrypt Makefile.gpg
# gpg -vv -K --with-keygrip --agent-program "$AGENT"
git pull
killall gpg-agent
wait
