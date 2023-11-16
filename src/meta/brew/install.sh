#!/bin/bash -e

: "${HOMEBREW_WRAPPER_ARCH:=$(arch)}"
case "$HOMEBREW_WRAPPER_ARCH" in
    "arm64") bottle_arch="arm";;
    "x86_64") bottle_arch="intel";;
    *) echo "Unrecognized architecture: $1" 1>&2; return 1;;
esac

script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/env.sh"
if [ -d "$("${brew:?}" --prefix)/opt/$1" ]; then
    echo "$1-$bottle_arch is already installed."
    exit 0
fi

# shellcheck disable=SC2207
my_deps=( $("${native_brew:?}" deps -1 "$1") )
for i in "${my_deps[@]}"; do
    "$0" "$i"
done

echo "Need to install $1-$bottle_arch".

"${native_brew:?}" fetch --force --arch "$bottle_arch" "$1"
bottle_path=$("${native_brew:?}" --cache --arch "$bottle_arch" "$1")
"${brew:?}" install --force-bottle "$bottle_path"