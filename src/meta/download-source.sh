#!/bin/bash -efu
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later
set -o pipefail

fastfail() {
    "$@" || kill -- "-$$"
}

source_dir=$(dirname "$(fastfail readlink -f "$0")")
base_dir="$source_dir/../.."
pkg_info_dir="${base_dir}/universal/keychain-interpose.app/Contents/Resources/pkg-info"
readonly source_dir base_dir pkg_info_dir

[[ -d ${pkg_info_dir} ]] || exit 1

declare -a packages
while IFS= read -r -d $'\0' pkg; do
    packages+=( "$(basename "${pkg}")" )
done < <(fastfail find -L "${pkg_info_dir}" -mindepth 1 -type directory -print0)

target_dir="${base_dir}/universal/sources"
[[ -d ${target_dir} ]] && rm -R "${target_dir}"
mkdir -p "${target_dir}"

release_message=''
echo "Downloading source code of dependencies:"
while IFS=':' read -r pkg version uri; do
    echo "+ ${uri} (for ${pkg})"
    filename_basename="$(fastfail basename "$uri")"
    if [[ ${filename_basename} != ${pkg}* ]]; then
        filename_basename="${pkg}-${filename_basename}"
    fi
    filename="${target_dir}/${filename_basename}"
    wget --quiet "${uri}" -O "${filename}"
    du -sh "$(fastfail readlink -f "$filename")"
    release_message+="- ${pkg}-${version}"$'\n'
done < <(
    fastfail brew info --json "${packages[@]}" | \
        fastfail yq '.[] | (.name + ":" + .versions.stable + ":" + .urls.stable.url)')

echo "Creating archive of dependency source code:"
zip_basename='dependency-sources.zip'
zip_path="${base_dir}/universal/${zip_basename}"
/usr/bin/ditto -ckV --keepParent "${target_dir}" "${zip_path}"
rm -R "${target_dir}"
du -sh "$(fastfail readlink -f "$zip_path")"
echo "The ${zip_basename} file contains the source code of the following packages:"
sort <(echo -n "${release_message}")