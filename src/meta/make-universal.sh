#!/bin/sh -e

SCRIPT_DIR="$(dirname $(readlink -f "$0"))"
CXX=$(src/meta/print-compiler.sh)
LIBTOOL=$(dirname $CXX)/llvm-libtool-darwin

make_arch() {
    export HOMEBREW_WRAPPER_ARCH=$1
    build_dir=$2
    shift 2
    source "$SCRIPT_DIR"/brew/env.sh
    echo "Using this brew for $HOMEBREW_WRAPPER_ARCH: $brew."
    "$SCRIPT_DIR/brew/install.sh" boost
    "$SCRIPT_DIR/brew/install.sh" fmt
    "$SCRIPT_DIR/brew/install.sh" gnupg
    make CPPFLAGS_EXTRA="-arch '$HOMEBREW_WRAPPER_ARCH'" BUILD_DIR="$build_dir" \
        CXX="$CXX" LIBTOOL="$LIBTOOL" "$@"
}

is_universal() {
    archs=( $(lipo -archs "$1" | tr " " "\n" | sort) )
    if [ "${#archs[@]}" -ne 2 ]; then
        return 1
    elif [ "${archs[0]}" != "arm64" ] && [ "${archs[0]}" != "arm64e" ]; then
        return 1
    elif [ "${archs[1]}" != "x86_64" ]; then
        return 1
    fi
}

make_arm64() { make_arch "arm64" "arm64" $@; }
make_x86_64() { make_arch "x86_64" "x64" $@; }

if ! make_arm64 clean-all && make_x86_64 clean-all; then
    exit $?
fi

make_arm64 &
make_x86_64 &
wait

for i in $(find arm64/bin); do
    if [ ! -f "$i" ] || (! lipo -archs "$i" &> /dev/null); then
        # Ignore things that aren't object files.
        continue
    fi
    other_version=$(printf "$i" | sed "s/^arm64/x64/")
    lipo -create "$i" "$other_version" -output "$i.universal"
    if ! is_universal "$i.universal"; then
        echo "Failed to make a universal version of $i."
        exit 1
    fi
    mv -f "$i.universal" "$i"
    echo "Made $i universal."
done

rm -Rf universal x64 arm64/objects
mv arm64 universal
echo "Moved \`arm64\` to \`universal\`."