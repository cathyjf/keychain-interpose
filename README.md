# keychain-interpose

This software makes it possible to store GPG secret key files in the
[MacOS keychain](https://developer.apple.com/documentation/security/keychain_services/)
instead of in the `~/.gnupg/private-keys-v1.d` directory.

## Background

By default, `gpg-agent(1)` stores secret keys in the `private-keys-v1.d` directory inside
the `gpg(1)` home directory (typically `~/.gnupg`). If the secret keys are password-protected,
these files are stored in a password-protected format. However, an attacker who obtains
these key files could hold onto them for potential later use. For example:

- The attacker could run offline brute-forcing techniques on the key files;
- As machines became more powerful or new algorithms are invented, it may become possible to
  decrypt the exfiltrated keys using techniques that are more advanced than brute-forcing; or
- If the paswords were later compromised, the compromised passwords could be used to decrypt
  the already-exfiltrated key files at the attacker's leisure.

Storing the secret key files in the keychain instead of in the `private-keys-v1.d` directory
makes it more difficult to exfiltrate the key files because access to the key files can be
limited to the authorized `gpg-agent(1)` process and its authorized dependencies.

## How `keychain-interpose` works

There are four components involved in migrating the secret keys to the keychain:

1. A supplied program called `migrate-keys` reads the keys from the `private-keys-v1.d`
   directory, adds them to the keychain, and then replaces the keys in the `private-keys-v1.d`
   directory with empty files (placeholders). See `src/migrate-keys.cpp`.

2. A supplied library called `keychain-interpose.dylib` is designed to be injected into
   the `gpg-agent(1)` process when it starts up. This library causes `gpg-agent(1)` to
   attempt to find secret keys in the keychain before falling back to the filesystem.
   See `src/keychain-interpose.cpp`.

3. To prevent any unauthorized code from accessing the keychain entries, it is necessary
   to enable the [Hardened Runtime](https://developer.apple.com/documentation/security/hardened_runtime)
   environment for `gpg-agent(1)` and all of its dependencies (including  `keychain-interpose.dylib`)
   and to sign `gpg-agent(1)` and its dependencies with a codesigning key or keys bearing
   a single [Team ID](https://developer.apple.com/documentation/xcode/sharing-your-teams-signing-certificates).
   The `Makefile` in the repository properly signs `migrate-keys` and `keychain-interpose.dylib`
   as they are built. There also exists a make target (`make sign-gpg-agent`) to sign
   `gpg-agent(1)` and its other dependencies, assuming that `gpg-agent(1)` was installed using
   the Homebrew `gnupg` package.

4. The user's GPG configuration file (typically `~/.gnupg/gpg.conf`) must be modified to
   set the `agent-program` to be a shell script that loads `gpg-agent(1)` with
   the `keychain-interpose.dylib` library injected into it. An example script can be
   found at `testing/agent.sh` in the repository.

## Building the software

Clone the repository with `git pull https://github.com/cathyjf/keychain-interpose`.

To build the software, the following Homebrew packages must be installed:
[`gnupg`](https://formulae.brew.sh/formula/gnupg),
[`fmt`](https://formulae.brew.sh/formula/fmt), and
[`llvm`](https://formulae.brew.sh/formula/llvm).

Run `make install -j` in the project directory to build the software and sign it with your
codesigning identity. The `codesign` command, which is invoked several times by the `Makefile`,
may prompt you for your password.

The binaries will be installed at `~/.gnupg/keychain-interpose.dylib` and `~/.gnupg/migrate-keys`.

## Difference between `keychain-interpose` and `pinentry-mac`

The `pinentry-mac` program can be configured to store the *passwords* for secret keys
in the keychain. This is unrelated to the purpose of `keychain-interpose`, which is to
store the password-protected secret keys themseleves in the keychain. The `keychain-interpose`
project is not a replacement for `pinentry` and works in conjunction with a `pinentry`
program like `pinentry-mac`, if you wish to use one.

## Warning

This is experimental software that I made for my own use only. You should back up your
private keys and other valuable data before using this software. Although this software
is intended to be useful, I can make no guarantees that it will work correctly. If the
software has bugs (and it might), you may find yourself unable to use your local secret
keys at all, which is why you should have backups.

## License

The `keychain-interpose` project was created by Cathy J. Fitzpatrick &lt;cathy@cathyjf.com&gt; (copyright 2023).

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.