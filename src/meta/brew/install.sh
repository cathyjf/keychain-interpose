#!/bin/bash -ef

: "${HOMEBREW_WRAPPER_ARCH:=$(arch)}"
case "$HOMEBREW_WRAPPER_ARCH" in
    "arm64") bottle_arch="arm";;
    "x86_64") bottle_arch="intel";;
    *) echo "Unrecognized architecture: $1" 1>&2; return 1;;
esac

script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source-path=SCRIPTDIR
source "$script_dir/env.sh"

packages=()
for i in "${@}"; do
    # shellcheck disable=SC2207
    IFS=$'\n' packages+=( "$i" $("${brew[@]:?}" deps "$i") )
done
# shellcheck disable=SC2207
IFS=$'\n' packages=( $(echo "${packages[@]}" | tr ' ' '\n' | sort | uniq) )

upgrade_info=$(mktemp)
"${brew[@]:?}" upgrade -n "${packages[@]}" 1>/dev/null 2>"$upgrade_info" || true
skipped_packages=""
for i in "${!packages[@]}"; do
    if ! match=$(grep -w "${packages[$i]}" "$upgrade_info"); then
        continue
    elif grep -q "already installed" < <(echo "$match"); then
        skipped_packages+=", ${packages[$i]}"
        unset "packages[$i]"
    fi
done

if [ -n "$skipped_packages" ]; then
    echo "[$bottle_arch] No need to install or upgrade these packages: ${skipped_packages:2}."
fi
if [ "${#packages[@]}" -eq "0" ]; then
    # No packages to install or upgrade.
    exit 0
fi

"${brew[@]:?}" fetch -q --force --arch "$bottle_arch" "${packages[@]}"
# shellcheck disable=SC2207
IFS=$'\n' bottles=( $("${brew[@]:?}" --cache --arch "$bottle_arch" "${packages[@]}") )
echo "*** Please ignore the following message about \`--ignore-dependencies\`."
echo "*** The \`--ignore-dependencies\` option is needed to use brew as a cross-compilation tool."
"${brew[@]:?}" install --ignore-dependencies --force-bottle "${bottles[@]}"