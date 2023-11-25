#!/bin/bash -f
# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

clear
echo "***************************************************************************"
echo "                       WELCOME TO KEYCHAIN-INTERPOSE"
echo "***************************************************************************"
echo
echo "This application currently has only a command-line interface."
echo "The \`migrate-keys\` binary is located at the following path:"
binary_path=$(realpath "$(dirname "$(readlink -f "$0")")/../MacOS/migrate-keys")
echo "    $binary_path"
echo
echo "***************************************************************************"
echo
if cd "$(dirname "$binary_path")"; then
    ./migrate-keys --help
else
    "$binary_path" --help
fi
user_shell=$(dscl . -read "/Users/$USER" UserShell | sed "s/^UserShell: //")
if [ -x "$user_shell" ]; then
    exec "$user_shell"
elif [ -x "$SHELL" ]; then
    exec "$SHELL"
else
    exec "/bin/bash"
fi