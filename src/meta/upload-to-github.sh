#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later
set -efuC -o pipefail
shopt -s inherit_errexit

fastfail() {
    "${@}" || {
        /bin/kill -- "-$(/bin/ps -o pgid= "${$}")" "${$}" > /dev/null 2>&1
    }
}

prompt_yn() {
    local __yes='y' __no='n' __default="${2:-}"
    if [[ ${__default,,} == 'y' ]]; then
        __yes='Y'
    elif [[ ${__default,,} == 'n' ]]; then
        __no='N'
    elif [[ -n "${__default}" ]]; then
        echo "prompt_yn: Unknown default: ${__default,,}" 1>&2
        return 2
    fi
    echo -n "${1:?} [${__yes}/${__no}] "
    local __prompt_yn=
    while [[ (${__prompt_yn,,} != 'y') && (${__prompt_yn,,} != 'n') ]]; do
        read -r -s -N 1 __prompt_yn
        if [[ (-n "${__default}") && (${__prompt_yn} == $'\n') ]]; then
            __prompt_yn=${__default,,}
        fi
    done
    echo "${__prompt_yn,,}"
    local __status=0
    [[ ${__prompt_yn,,} == 'y' ]] || __status=1
    return "${__status}"
}

__is_overwrite_required() {
    local -a refs
    mapfile -t refs < <(
        fastfail git show-ref -s -d -- \
            "refs/heads/${__branch}" "refs/tags/${1:?}" | \
                fastfail cut -d ' ' -f 1
    )
    __status=0
    [[ ${refs[0]} != "${refs[2]}" ]] || __status=1
    return "${__status}"
}

declare __force_push_required __skip_tag_creation
__inner_prompt_version() {
    version=
    while [[ -z "${version}" ]]; do
        __force_push_required=0 __skip_tag_creation=0
        IFS= read -r -p 'Enter new version to release: ' version
        if [[ ${version:0:1} != 'v' ]]; then
            version="v${version}"
        fi
        # shellcheck disable=SC2310
        if [[ ! ${version} =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            echo 'Supplied version does not match the required pattern (X.Y(.Z)?). Try again.'
            version=
        elif [[ -n "$(fastfail git tag -l "${version}")" ]]; then
            # shellcheck disable=SC2310
            if __is_overwrite_required "${version}"; then
                local warning1 warning2
                warning1=$(
                    echo -n $'\u2757'' Warning: Supplied version ('"${version}"') exists '
                    echo -n 'and is not the same revision. '$'\u2757'
                )
                warning2=$'\u2757''          It will be overwritten if you proceed.'
                printf "%s\n%s%$(( ${#warning1} - ${#warning2} - 1 ))s%s\n" \
                    "${warning1}" "${warning2}" '' $'\u2757'
                __force_push_required=1
            else
                __skip_tag_creation=1
            fi
        fi
    done
}

prompt_version() {
    local __confirmed_version=
    while [[ -z "${__confirmed_version}" ]]; do
        __inner_prompt_version
        local message='Use this version ('"${version}"')?'
        local default='y'
        if [[ ${__force_push_required} -eq 1 ]]; then
            message="${message::-1} even though it will overwrite existing version?"
            default='n'
        fi
        # shellcheck disable=SC2310
        if prompt_yn "${message}" "${default}"; then
            # shellcheck disable=SC2016
            message='This will require `git push -f`. Are you sure?'
            if [[ ${__force_push_required} -eq 0 ]] || prompt_yn "${message}" 'n'; then
                __confirmed_version=1
            fi
        fi
    done
}

declare __branch
__branch=$(git branch --show-current)
[[ -n "${__branch}" ]] || {
    echo 'Failed to determine current git branch. Aborting.'
    exit 1
}

declare build_directory="${1:-universal}"
# shellcheck disable=SC2310
prompt_yn 'Build directory "'"${build_directory}"'" will be used. Is this okay?' 'y' || {
    echo 'Aborting.'
    exit 1
}

echo 'Existing versions: '
git tag -ln

declare version release_message
prompt_version
release_message=$(
    m4 "src/meta/github-release.md.m4" -E \
        -D "RELEASE_VERSION=${version}" \
        -D "RELEASE_DEPENDENCY_LIST=$(< "${build_directory}/dependency-sources.zip.txt")"
)

if [[ ${__skip_tag_creation} -ne 1 ]]; then
    declare remote
    remote=$(git config get "branch.${__branch}.remote")
    [[ -n "${remote}" ]] || {
        echo 'Failed to determine default git remote. Aborting.'
        exit 1
    }
    declare -a git_args=()
    if [[ ${__force_push_required} -eq 1 ]]; then
        git_args+=( -f )
    fi
    echo 'Signing a tag for the release...'
    git tag "${git_args[@]}" -s "${version}" -m "version ${version:1}"
    echo 'Pushing the signed tag...'
    git push "${git_args[@]}" "${remote}" "${version}"
fi

declare releases
releases=$(
    gh release list --json tagName,isDraft \
        -q '.[] | select(.isDraft == true and .tagName == "'"${version}"'") | .tagName'
)
if [[ -n "${releases}" ]]; then
    echo 'One or more GitHub draft releases already exist for this version ('"${version}"').'
    declare num_releases=$(( $(wc -l <<< "${releases}") ))
    echo 'You can delete all '"${num_releases}"' of the drafts if you want.'
    # shellcheck disable=SC2310
    if prompt_yn $'\u2757'' Delete all drafts for version '"${version}"'?'; then
        declare i
        for ((i = 0; i < num_releases; ++i)); do
            gh release delete -y "${version}"
        done
    fi
fi

declare -A artifacts=(
    ["keychain-interpose.app.zip"]="keychain-interpose-${version}.zip"
    ["dependency-sources.zip"]="keychain-interpose-${version}-dependency-sources.zip"
)

declare i
for i in "${!artifacts[@]}"; do
    artifacts[${i}]="${build_directory}/${artifacts[${i}]}"
    ln -f "${build_directory}/${i}" "${artifacts[${i}]}"
done

echo 'Uploading artifacts...'
declare uri
uri=$(
    echo -n "${release_message}" |
        gh release create "${version}" --title "${version}" --notes-file - \
            --draft --verify-tag "${artifacts[@]}"
)
echo 'You can finish publishing the release at this URI:'
echo '    '"${uri}"
# shellcheck disable=SC2310
if prompt_yn 'Open this in your browser now?' 'y'; then
    open "${uri}"
fi