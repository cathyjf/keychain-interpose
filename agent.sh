#!/usr/bin/env fish --no-config

export DYLD_INSERT_LIBRARIES=(realpath (status dirname))/keychain-interpose.dylib
exec gpg-agent $argv