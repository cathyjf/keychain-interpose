#!/bin/sh -e

MY_ARCH="$(arch)"
if [ "$MY_ARCH" != "arm64" ]; then
    echo "Error: Building universal binaries currently requires arm64" \
        "but your platform was detected as $MY_ARCH."
    exit 1
fi

make_arm64() {
    make CPPFLAGS_EXTRA="-arch arm64" BUILD_DIR="arm64" $@
}

SCRIPT_DIR="$(dirname $(readlink -f "$0"))"
if ! make_arm64 clean-all && "$SCRIPT_DIR/make-x64.sh" clean-all; then
    exit $?
fi

make_arm64
"$SCRIPT_DIR/make-x64.sh"
wait

for i in $(find arm64/bin); do
    if [ ! -f "$i" ] || (! lipo -archs "$i" &> /dev/null); then
        # Ignore things that aren't object files.
        continue
    fi
    other_version=$(printf "$i" | sed "s/^arm64/x64/")
    lipo -create "$i" "$other_version" -output "$i.universal"
    mv -f "$i.universal" "$i"
    echo "Made $i universal."
done

rm -Rf universal x64 arm64/objects
mv arm64 universal
echo "Moved \`arm64\` to \`universal\`."