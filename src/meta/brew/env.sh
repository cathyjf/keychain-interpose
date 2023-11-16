#!/bin/sh -e

unset HOMEBREW_REPOSITORY
unset HOMEBREW_CELLAR
unset HOMEBREW_PREFIX
unset HOMEBREW_MAKE_JOBS

get_prefix_for_arch() {
    case "$1" in
        "arm64") echo "/opt/homebrew";;
        "x86_64") echo "/usr/local";;
        *) echo "Unrecognized architecture: $i" 1>2; return 1;;
    esac
}

my_arch=$(arch)
brew_prefix=$(get_prefix_for_arch "$my_arch")
brew="$brew_prefix"/bin/brew
if [ ! -x "$brew" ]; then
    echo "Error: $brew is not executable."
    echo "Homebrew must be installed normally before running this script."
    echo "See https://brew.sh for installation instructions."
    exit 1
fi

brew_arch=$({ [ -n "$HOMEBREW_WRAPPER_ARCH" ] && echo "$HOMEBREW_WRAPPER_ARCH"; } || echo "$my_arch")
if [ "$my_arch" != "$brew_arch" ]; then
    # If we get here, the user has requested a foreign installation of Homebrew.
    # On arm64, the user might have an x64 installation of Homebrew located in /usr/local.
    # If that exists, we can use it. Otherwise, we'll set up a new installation.
    potential_local_brew=$(get_prefix_for_arch "$brew_arch")"/bin/brew"
    if [ "$brew_arch" = "x86_64" ] && [ -x "$potential_local_brew" ]; then
        brew=$potential_local_brew
    else
        local_root=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
        local_brew_dir="$local_root"/.homebrew
        brew_prefix="$local_brew_dir/$brew_arch"
        brew="$brew_prefix"/bin/brew
        if [ ! -x "$brew" ]; then
            tmp_dir=$(mktemp -d)
            curl -s -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "$tmp_dir"
            mkdir -p "$local_brew_dir"
            mv -f "$tmp_dir" "$brew_prefix"
            if [ ! -x "$brew" ]; then
                echo "Failed to set up a local brew installaton in $brew_prefix." 1>2
                exit 1
            fi
            "$brew" update --force --quiet
        fi
    fi
fi

eval "$("$brew" shellenv)"