#!/bin/bash -ef
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CXX=$(src/meta/print-compiler.sh)
readonly SCRIPT_DIR CXX

# Print the direct and indirect descendents of the specified process or processes.
# If more than one process is specified in $1, the list of processes must be
# separated by commas.
print_descendents() {
    local IFS=$'\n'
    local -a pids
    # shellcheck disable=SC2207
    pids=( $(pgrep -P "$1") )
    echo "${pids[*]}"

    if [[ ${#pids[@]} -ne 0 ]]; then
        IFS=','
        print_descendents "${pids[*]}"
    fi
}

# Ensure that the entire process tree is killed if this script is interrupted.
on_exit() {
    local -r IFS=$'\n'
    local pids
    # shellcheck disable=SC2311
    pids="$(print_descendents "$$")"
    if [[ -n "${pids}" ]]; then
        # Some processes may have finished on their own before we had a chance
        # to kill them. This can cause the kill command to return a non-zero
        # exit status, which we don't care about.
        #
        # The $pids variable is intentionally not quoted because we want each
        # line of the variable to be interpreted as a separate word.
        #
        # shellcheck disable=SC2086
        kill ${pids} 2>/dev/null || true
    fi
}
trap 'on_exit' EXIT

make_arch() {
    export HOMEBREW_WRAPPER_ARCH=$1
    readonly HOMEBREW_WRAPPER_ARCH
    local -r build_dir=$2
    shift 2
    # shellcheck source-path=SCRIPTDIR
    source "${SCRIPT_DIR}"/brew/env.sh
    echo "Using this brew for ${HOMEBREW_WRAPPER_ARCH}: ${brew[*]:?}."
    if [[ -z "${skip_updates}" ]]; then
        "${brew[@]:?}" update --force --quiet
        "${SCRIPT_DIR}/brew/install.sh" "boost" "gnupg"
    fi
    cmake -S . -B "${build_dir}" -G Ninja \
        -D "CMAKE_CXX_COMPILER=${CXX}" \
        -D "CMAKE_OSX_ARCHITECTURES=${HOMEBREW_WRAPPER_ARCH}"
    cmake --build "${build_dir}"
}

is_universal() {
    local -r IFS=$'\n'
    # shellcheck disable=SC2207
    archs=( $(lipo -archs "$1" | tr ' ' $'\n' | sort) )
    if [[ ${#archs[@]} -ne 2 ]]; then
        return 1
    elif [[ (${archs[0]} != "arm64") && (${archs[0]} != "arm64e") ]]; then
        return 1
    elif [[ ${archs[1]} != "x86_64" ]]; then
        return 1
    fi
}

create_universal_binary() {
    if [[ (! -f "$1") || (-L "$1") ]] || { ! lipo -archs "$1" &> /dev/null; }; then
        # Ignore things that aren't object files.
        return 0
    fi
    local other_version
    other_version=$(printf "%s" "$1" | sed "s/^arm64/x64/")
    lipo -create "$1" "${other_version}" -output "$1.universal"
    # shellcheck disable=SC2310
    if ! is_universal "$1.universal"; then
        echo "Failed to make a universal version of $1." 1>&2
        return 1
    fi
    mv -f "$1.universal" "$1"
    echo "Made $1 universal."
}

# shellcheck disable=SC2120
make_multiarch() {
    local -a pids
    make_arch "arm64" "arm64" "${@}" &
    pids+=( "${!}" )
    make_arch "x86_64" "x64" "${@}" &
    pids+=( "${!}" )

    # Invoke wait in a loop rather than passing all of the pids to wait at once
    # in order to verify that every job returned with a successful exit status.
    local i
    for i in "${pids[@]}"; do
        wait "${i}"
    done
}

rm -Rf universal x64 arm64
make_multiarch

while IFS= read -r -d $'\0' filename; do
    create_universal_binary "${filename}"
done < <(find arm64/keychain-interpose.app -print0)
chmod -R go-rwx arm64/keychain-interpose.app

# Sign the universal bundles.
: "${IDENTITY:="$(cmake -L -N arm64 | grep '^IDENTITY:STRING=' | cut -d '=' -f 2-)"}"
"${SCRIPT_DIR}/codesign.sh" "arm64/keychain-interpose.app/Contents/MacOS/gpg-agent.app" \
    "${IDENTITY:?}" "--entitlements arm64/gpg-agent-entitlements.plist"
"${SCRIPT_DIR}/codesign.sh" "arm64/keychain-interpose.app" \
    "${IDENTITY:?}" "--entitlements arm64/migrate-keys-entitlements.plist"

rm -Rf universal x64
mv arm64 universal
echo "Moved \`arm64\` to \`universal\`."