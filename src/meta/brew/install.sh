#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later
set -efu -o pipefail
shopt -s inherit_errexit

fastfail() {
    "${@}" || {
        /bin/kill -- "-$(/bin/ps -o pgid= "${$}")" "${$}" > /dev/null 2>&1
    }
}

my_arch=$(arch)
[[ "${my_arch}" == "i386" ]] && my_arch="x86_64"
: "${HOMEBREW_WRAPPER_ARCH:=${my_arch}}"
case "${HOMEBREW_WRAPPER_ARCH}" in
    'arm64') bottle_arch='arm' tag_prefix='arm64_';;
    'x86_64' | 'i386') bottle_arch='intel' tag_prefix='';;
    *) echo "[install] Unrecognized architecture: ${HOMEBREW_WRAPPER_ARCH}" 1>&2; exit 1
esac

script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source-path=SCRIPTDIR
source "${script_dir}/env.sh"

packages=()
for i in "${@}"; do
    # shellcheck disable=SC2207
    IFS=$'\n' packages+=( "${i}" $("${brew[@]:?}" deps "${i}") )
done
# shellcheck disable=SC2207
IFS=$'\n' packages=( $(echo "${packages[@]}" | tr ' ' '\n' | sort | uniq) )

upgrade_info=$(mktemp)
"${brew[@]:?}" upgrade -n "${packages[@]}" 1>/dev/null 2>"${upgrade_info}" || true
skipped_packages=""
for i in "${!packages[@]}"; do
    if ! match=$(grep -w "${packages[${i}]}" "${upgrade_info}"); then
        continue
    elif grep -q "already installed" < <(echo "${match}"); then
        skipped_packages+=", ${packages[${i}]}"
        unset "packages[${i}]"
    fi
done

if [[ -n "${skipped_packages}" ]]; then
    echo "[${bottle_arch}] No need to install or upgrade these packages: ${skipped_packages:2}."
fi
if [[ "${#packages[@]}" -eq "0" ]]; then
    # No packages to install or upgrade.
    exit 0
fi

# On Intel, Homebrew does not provide specific bottles for Sequoia, but the
# Sonoma bottles should be fine. Unfortunately, the `brew fetch` command
# will fail unless we specifically identify which formula will use a Sequoia
# bottle and which will use a Sonoma bottle.
#
# To solve this problem, we first need to figure out which bottles are
# available for each formula that we plan to install.
valid_tags=( "${tag_prefix}tahoe" "${tag_prefix}sequoia" "${tag_prefix}sonoma" "${tag_prefix}ventura" )
declare -A installable
while IFS=':' read -r package tag; do
    candidate=${installable[${package}]:-}
    if [[ -z ${candidate} ]]; then
        installable[${package}]=${tag}
        continue
    fi
    for i in "${valid_tags[@]}"; do
        if [[ ${i} == "${candidate}" ]]; then
            break
        elif [[ ${i} == "${tag}" ]]; then
            installable[${package}]=${tag}
            break
        fi
    done
done < <(
    fastfail "${brew[@]:?}" info --json "${packages[@]}" |
        fastfail yq '.[] | (.name + ":" + (.bottle.stable.files.* | key))'
)

for i in "${valid_tags[@]}"; do
    formulae=()
    for j in "${!installable[@]}"; do
        if [[ ${i} == "${installable[${j}]}" ]]; then
            formulae+=( "${j}" )
        fi
    done
    if [[ ${#formulae[@]} -eq 0 ]]; then
        continue
    fi

    # Now, let's install the formulae whose bottles have this tag.
    "${brew[@]:?}" fetch -q --force --bottle-tag "${i}" "${formulae[@]}"
    # shellcheck disable=SC2207
    IFS=$'\n' bottles=( $("${brew[@]:?}" --cache --bottle-tag "${i}" "${formulae[@]}") )
    echo "*** Please ignore the following message about \`--ignore-dependencies\`."
    echo "*** The \`--ignore-dependencies\` option is needed to use brew as a cross-compilation tool."
    # For background on why we set HOMEBREW_DEVELOPER=1, see the following links:
    #     - https://github.com/Homebrew/brew/pull/20414
    #     - https://github.com/Homebrew/brew/issues/20441
    HOMEBREW_DEVELOPER=1 "${brew[@]:?}" install --ignore-dependencies --force-bottle "${bottles[@]}"
done