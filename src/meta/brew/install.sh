#!/bin/sh -e

if [ -z "$HOMEBREW_WRAPPER_ARCH" ]; then
    HOMEBREW_WRAPPER_ARCH=$(arch)
fi
case "$HOMEBREW_WRAPPER_ARCH" in
    "arm64") bottle_arch="arm";;
    "x86_64") bottle_arch="intel";;
    *) exit 1
esac

script_dir="$(dirname $(readlink -f "$0"))"
relevant_prefix=$("$script_dir/wrapper.sh" --prefix)
if [ -d "$relevant_prefix/opt/$1" ]; then
    echo "$1-$bottle_arch is already installed."
    exit 0
fi

my_deps=( $(brew deps -1 "$1") )
for i in "${my_deps[@]}"; do
    "$0" "$i"
done

echo "Need to install $1-$bottle_arch".

brew fetch --force --arch "$bottle_arch" "$1"
bottle_path=$(brew --cache --arch "$bottle_arch" "$1")
"$script_dir/wrapper.sh" install --force-bottle "$bottle_path"