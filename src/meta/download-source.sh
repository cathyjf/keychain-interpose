#!/bin/bash -efu
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later
set -o pipefail

fastfail() {
    "$@" || kill -- "-$$"
}

source_dir=$(dirname "$(fastfail readlink -f "$0")")
base_dir="$source_dir/../.."
pkg_info_dir="${base_dir}/universal/bin/keychain-interpose.app/Contents/Resources/pkg-info"
readonly source_dir base_dir pkg_info_dir

[[ -d ${pkg_info_dir} ]] || exit 1

declare -a packages
while IFS= read -r -d $'\0' pkg; do
    packages+=( "$(basename "${pkg}")" )
done < <(fastfail find -L "${pkg_info_dir}" -mindepth 1 -type directory -print0)

target_dir="${base_dir}/universal/bin/sources"
mkdir -p "${target_dir}"

echo "Downloading source code of dependencies:"
while IFS=':' read -r pkg uri; do
    echo "+ ${uri} (for ${pkg})"
    filename="${target_dir}/$(fastfail basename "$uri")"
    wget --quiet "${uri}" -O "${filename}"
    du -sh "$(fastfail readlink -f "$filename")"
done < <(
    fastfail brew info --json "${packages[@]}" | \
        fastfail yq '.[] | ((.name + ":") + .urls.stable.url)')