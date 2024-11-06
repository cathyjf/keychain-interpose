# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

NOTARY_KEYCHAIN_PROFILE := cathyjf

default :
	cmake -S . -B build -G Ninja
	cmake --build build

all universal universal/keychain-interpose.app :
	src/meta/make-universal.sh

notarize : universal/keychain-interpose.app
	NOTARY_KEYCHAIN_PROFILE="$(NOTARY_KEYCHAIN_PROFILE)" src/meta/notarize-app.sh "$<"

release : universal/keychain-interpose.app
	@make notarize
	src/meta/download-source.sh
	/usr/bin/ditto -ck --keepParent "$<" "$<.zip"

clean clean-all :
	rm -Rf arm64 build universal x86

#################

test :
	testing/run-test.sh

shellcheck :
	find src testing -name '*.sh' -exec shellcheck {} +

.DELETE_ON_ERROR :

.PHONY : all clean clean-all default release test shellcheck notarize