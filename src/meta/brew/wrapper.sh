#!/bin/bash -e

# shellcheck source-path=SCRIPTDIR
source "$(dirname "$0")"/env.sh
exec "${brew:?}" "$@"