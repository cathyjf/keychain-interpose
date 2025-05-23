# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

notarize : export NOTARY_KEYCHAIN_PROFILE := cathyjf

default :
	cmake -S . -B build -G Ninja
	cmake --build build

all universal universal/keychain-interpose.app :
	src/meta/make-universal.sh

notarize : universal/keychain-interpose.app
	src/meta/notarize-app.sh "$<"

release : universal/keychain-interpose.app
	@make notarize
	@cmake --build "$(<D)" --target dependency-sources
	/usr/bin/ditto -ck --keepParent "$<" "$<.zip"

upload : release
	src/meta/upload-to-github.sh

clean clean-all :
	rm -Rf arm64 build universal x86

#################

test :
	testing/run-test.sh

shellcheck :
	find src testing -name '*.sh' -exec shellcheck {} +

.DELETE_ON_ERROR :

.PHONY : all clean clean-all default notarize release shellcheck test upload