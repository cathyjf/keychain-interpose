#!/usr/bin/env fish --no-config

export KEYCHAIN_INTERPOSE_LOG_FILE_PATH=(realpath (status dirname))/keychain-interpose.log
export DYLD_INSERT_LIBRARIES=(path resolve (realpath (status dirname))/../bin/keychain-interpose.dylib)
exec gpg-agent $argv