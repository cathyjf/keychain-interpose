#!/bin/bash -e

# $1: Directory where keychain-interpose.app was built.
# $2: Installation directory.
: "${1:?}" "${2:?}"

APP_NAME="keychain-interpose.app"
set -x
tmp_dir=$(mktemp -d)
cp -R "$1/$APP_NAME" "$tmp_dir"
rm -Rf "${2:?}/${APP_NAME:?}"
mv -f "$tmp_dir/$APP_NAME" "$2/$APP_NAME"

# Set up some symlinks.
ln -s -f "$2/$APP_NAME/Contents/MacOS/migrate-keys" "$2/migrate-keys"
ln -s -f "$2/$APP_NAME/Contents/MacOS/gpg-agent.app/Contents/MacOS/gpg-agent" "$2/gpg-agent"
ln -s -f "$2/$APP_NAME/Contents/Frameworks/keychain-interpose.dylib" "$2/keychain-interpose.dylib"