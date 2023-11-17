#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CXX=$(src/meta/print-compiler.sh)
LIBTOOL=$(dirname "$CXX")/llvm-libtool-darwin

make_arch() {
    export HOMEBREW_WRAPPER_ARCH=$1
    build_dir=$2
    shift 2
    # shellcheck source-path=SCRIPTDIR
    source "$SCRIPT_DIR"/brew/env.sh
    echo "Using this brew for $HOMEBREW_WRAPPER_ARCH: ${brew:?}."
    "$SCRIPT_DIR/brew/install.sh" boost
    "$SCRIPT_DIR/brew/install.sh" fmt
    "$SCRIPT_DIR/brew/install.sh" gnupg
    make CPPFLAGS_EXTRA="-arch '$HOMEBREW_WRAPPER_ARCH'" BUILD_DIR="$build_dir" \
        CXX="$CXX" LIBTOOL="$LIBTOOL" "$@"
}

is_universal() {
    # shellcheck disable=SC2207
    archs=( $(lipo -archs "$1" | tr " " "\n" | sort) )
    if [ "${#archs[@]}" -ne 2 ]; then
        return 1
    elif [ "${archs[0]}" != "arm64" ] && [ "${archs[0]}" != "arm64e" ]; then
        return 1
    elif [ "${archs[1]}" != "x86_64" ]; then
        return 1
    fi
}

create_universal_binary() {
    if [ ! -f "$1" ] || [ -L "$1" ] || (! lipo -archs "$1" &> /dev/null); then
        # Ignore things that aren't object files.
        return 0
    fi
    other_version=$(printf "%s" "$1" | sed "s/^arm64/x64/")
    lipo -create "$1" "$other_version" -output "$1.universal"
    if ! is_universal "$1.universal"; then
        echo "Failed to make a universal version of $1." 1>&2
        return 1
    fi
    mv -f "$1.universal" "$1"
    echo "Made $1 universal."
}

make_arm64() { make_arch "arm64" "arm64" "$@"; }
make_x86_64() { make_arch "x86_64" "x64" "$@"; }

make_arm64 clean-all
make_x86_64 clean-all
make_arm64 &
make_x86_64 &
wait

export -f is_universal create_universal_binary
# Single quotes are intentional here.
# shellcheck disable=SC2016
find arm64/bin -print0 | xargs -0 -I{} /bin/bash -e -c 'create_universal_binary "$1"' shell {}

# Sign the universal bundles.
"$SCRIPT_DIR/codesign.sh" "arm64/bin/keychain-interpose.app/Contents/MacOS/gpg-agent.app" \
    "${IDENTITY:?}" "--entitlements arm64/objects/gpg-agent-entitlements.plist"
"$SCRIPT_DIR/codesign.sh" "arm64/bin/keychain-interpose.app" \
    "${IDENTITY:?}" "--entitlements arm64/objects/migrate-keys-entitlements.plist"

rm -Rf universal x64 arm64/objects
mv arm64 universal
echo "Moved \`arm64\` to \`universal\`."