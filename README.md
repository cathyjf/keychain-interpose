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

1. A supplied program named `migrate-keys` reads the keys from the `private-keys-v1.d`
   directory, adds them to the keychain, and then replaces the keys in the `private-keys-v1.d`
   directory with empty files (placeholders). See `src/migrate-keys.cpp`.

2. A supplied library named `keychain-interpose.dylib` is designed to be injected into
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

Clone the repository with `git clone --recurse https://github.com/cathyjf/keychain-interpose`.

Install the project's dependencies with [Homebrew](https://brew.sh/):
`brew install boost fmt gnupg llvm`.

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

## Licensing

### License for `keychain-interpose`

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

### License for `libgpg-error`

The `keychain-interpose.dylib` library (built from the source in this repository) links
against `libgpg-error`, which was released under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation, either version 2.1 of the License, or
any later version.

I have chosen to use `libgpg-error` under the terms of version 3 of the GNU Lesser General
Public License. A copy of version 3 of the GNU Lesser General Public License is available
at the following location: <https://www.gnu.org/licenses/lgpl-3.0.en.html>

This repository does not contain a copy of `libgpg-error`. You should generally obtain
`libgpg-error` by installing the `gnupg` package from Homebrew, as described above
under the heading "[Building the software](#building-the-software)".

### License for `CoreFoundation++`

This repository incorporates [CoreFoundation++](https://github.com/macmade/CFPP), which was
released by its author ([@macmade](https://github.com/macmade)) under the following license:

> The MIT License (MIT)
>
> Copyright (c) 2014 Jean-David Gadina - www.xs-labs.com / www.digidna.net
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.