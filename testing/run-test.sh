#!/bin/sh -x

SCRIPT_DIR=$(dirname $(readlink -f "$0"))
AGENT="$SCRIPT_DIR/agent.sh"
MIGRATE_KEY_TARGET="../bin/migrate-keys.app/Contents/MacOS/migrate-keys"
if [ -x "$SCRIPT_DIR/$MIGRATE_KEY_TARGET" ]; then
    ln -s -f "$MIGRATE_KEY_TARGET" "$SCRIPT_DIR/pinentry-wrapper"
fi

# make -C ~/git/gnupg -j

killall gpg-agent
eval "$AGENT" --daemon
# gpg -vv --output /dev/null --agent-program "$AGENT" --decrypt Makefile.gpg
# gpg -vv -K --with-keygrip --agent-program "$AGENT"
git pull
killall gpg-agent
wait

rm -f "$SCRIPT_DIR/gpg-agent.log" "$SCRIPT_DIR/pinentry-wrapper"