<?xml version="1.0" encoding="UTF-8"?>
<!--
SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>keychain-access-groups</key>
    <array>
        <string>MY_TEAM_ID.com.cathyjf.keychain-interpose</string>
    </array>

    changequote(`[', `]')
    ifdef([ALLOW_DYLD], [
        <key>com.apple.security.cs.allow-dyld-environment-variables</key>
        <true/>
    ])
</dict>
</plist>