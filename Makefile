# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

BUILD_DIR := .
OBJECT_DIR := $(BUILD_DIR)/objects
BIN_DIR := $(BUILD_DIR)/bin
BIN_APP := $(BIN_DIR)/keychain-interpose.app
CPPFLAGS_MINIMAL := -std=c++20 -O3 -flto -Wall -Werror -fprebuilt-module-path="$(OBJECT_DIR)" $(CPPFLAGS_EXTRA)
CPPFLAGS := $(CPPFLAGS_MINIMAL) $(shell pkg-config --cflags gpg-error) -Idependencies/libCF++/CF++/include \
	-I$(shell brew --prefix boost)/include
OBJCFLAGS := -fobjc-arc -Wno-unused-but-set-variable
LIBCF++ := dependencies/libCF++/$(BUILD_DIR)/Build/lib/libCF++.a
LDFLAGS := -framework Security -framework CoreFoundation \
	$(shell brew --prefix boost)/lib/libboost_program_options.a
MODULE_OBJECTS := $(addprefix $(OBJECT_DIR)/, cathyjf.ki.common.pcm cathyjf.ki.log.pcm)
MIGRATE_OBJECTS := $(addprefix $(OBJECT_DIR)/, migrate-keys.o cathyjf.ki.common.o migrate-keys-helper.o)
DYLIB_OBJECTS := $(addprefix $(OBJECT_DIR)/, keychain-interpose.o cathyjf.ki.common.o cathyjf.ki.log.o)
ENCAPSULATE_OBJECTS := $(addprefix $(OBJECT_DIR)/, encapsulate-app.o cathyjf.ki.common.o)
PINENTRY_OBJECTS :=  $(addprefix $(OBJECT_DIR)/, pinentry-wrapper.o)
OBJECTS := $(MODULE_OBJECTS) $(MIGRATE_OBJECTS) $(DYLIB_OBJECTS) $(ENCAPSULATE_OBJECTS) $(PINENTRY_OBJECTS)
BINARIES := $(addprefix $(BIN_DIR)/, migrate-keys keychain-interpose.app keychain-interpose.dylib \
	encapsulate-app pinentry-wrapper)
IDENTITY := Developer ID Application: Cathy Fitzpatrick (KVRBCYNMT7)
TEAM_ID := KVRBCYNMT7
NOTARY_KEYCHAIN_PROFILE := cathyjf
INSTALL_DIR := $(GNUPGHOME)
CODESIGN = src/meta/codesign.sh $(1) "$(IDENTITY)" "$(2)"

# Homebrew's version of clang is required because we use C++ standard modules.
# Apple's clang does not currently support the standard version of modules.
CXX = $(eval CXX := $$(shell src/meta/print-compiler.sh))$(CXX)
LIBTOOL = $(shell brew --prefix llvm)/bin/llvm-libtool-darwin

all : $(BINARIES)

$(BIN_DIR)/keychain-interpose.dylib : $(DYLIB_OBJECTS) $(LIBCF++) | $(OBJECT_DIR)/gpg-agent-deps
	$(CXX) -dynamiclib $^ -o $@ $(CPPFLAGS) $(LDFLAGS) \
		$(OBJECT_DIR)/gpg-agent-deps/bin/libgpg-error*.dylib
	$(call CODESIGN, $@)

$(BIN_DIR)/migrate-keys : $(MIGRATE_OBJECTS) $(LIBCF++) | $(OBJECT_DIR)/migrate-keys-entitlements.plist
	$(CXX) $^ -o $@ $(CPPFLAGS) $(LDFLAGS) -framework LocalAuthentication -framework Foundation \
		-framework CoreServices -framework AppKit
	$(call CODESIGN, $@, --entitlements "$(OBJECT_DIR)/migrate-keys-entitlements.plist")

$(BIN_DIR)/encapsulate-app : $(ENCAPSULATE_OBJECTS)
	$(CXX) $^ -o $@ $(CPPFLAGS) $(LDFLAGS) $(shell brew --prefix boost)/lib/libboost_regex.a

$(BIN_DIR)/pinentry-wrapper : $(PINENTRY_OBJECTS)
	$(CXX) $^ -o $@ $(CPPFLAGS) $(LDFLAGS)
	$(call CODESIGN, $@)

$(OBJECT_DIR)/%.o : src/%.cpp
	$(CXX) -c $^ -o $@ $(CPPFLAGS)

$(OBJECT_DIR)/%.o : src/%.mm
	$(CXX) -c $^ -o $@ $(CPPFLAGS) $(OBJCFLAGS)

$(OBJECTS) : | $(OBJECT_DIR)
$(BINARIES) : | $(BIN_DIR)
$(OBJECT_DIR) $(BIN_DIR) :
	mkdir -p $@

#################
# Entitlements

$(OBJECT_DIR)/migrate-keys-entitlements.plist : src/meta/entitlements.plist.m4 | $(OBJECT_DIR)
	m4 -D MY_TEAM_ID="$(TEAM_ID)" "$<" > "$@"

$(OBJECT_DIR)/gpg-agent-entitlements.plist : src/meta/entitlements.plist.m4 | $(OBJECT_DIR)
	m4 -D MY_TEAM_ID="$(TEAM_ID)" -D ALLOW_DYLD="1" "$<" > "$@"

#################
# Modules

$(MIGRATE_OBJECTS) $(DYLIB_OBJECTS) $(ENCAPSULATE_OBJECTS) : | $(MODULE_OBJECTS)

$(OBJECT_DIR)/%.pcm : src/modules/%.cppm
	$(CXX) --precompile $^ -o $@ $(CPPFLAGS)

$(OBJECT_DIR)/%.o : $(OBJECT_DIR)/%.pcm
	$(CXX) -c $^ -o $@ $(CPPFLAGS_MINIMAL)

#################
# Dependencies

$(LIBCF++) : dependencies/libCF++
	make -C $^ CXX="$(CXX)" LIBTOOL="$(LIBTOOL)" \
		CPPFLAGS_EXTRA="$(CPPFLAGS_EXTRA)" BUILD_DIR="$(BUILD_DIR)"

clean-deps:
	make -C dependencies/libCF++ clean

$(OBJECT_DIR)/gpg-agent-deps : $(BIN_DIR)/encapsulate-app $(OBJECT_DIR)/gpg-agent-entitlements.plist
	mkdir -p $@/bin $@/pkg-info
	$(BIN_DIR)/encapsulate-app "$(shell brew --prefix gnupg)/bin/gpg-agent" "$@" \
		"$(shell brew --prefix)" boost
	$(call CODESIGN, "$@/bin/gpg-agent", --entitlements $(OBJECT_DIR)/gpg-agent-entitlements.plist)
	find "$@/bin" -name "*.dylib" -print0 | xargs -0 -I{} $(call CODESIGN, {})

#################
# App bundle

MAKE_AGENT_BUNDLE = \
	install -m u=rwx $(1)/bin/gpg-agent "$(BIN_DIR)/gpg-agent"; \
	src/meta/make-bundle.sh "gpg-agent" $(BIN_DIR) $(OBJECT_DIR) --skip-signing; \
	mkdir -p $(2)/Contents/Frameworks $(2)/Contents/Resources; \
	find $(1)/bin -name "*.dylib" -print0 | xargs -0 -I{} cp -f "{}" $(2)/Contents/Frameworks; \
	cp -R $(1)/pkg-info $(2)/Contents/Resources; \
	src/meta/make-bundle.sh "gpg-agent" $(BIN_DIR) $(OBJECT_DIR) "$(IDENTITY)" --sign-only

$(BIN_APP) : $(BIN_DIR)/migrate-keys $(OBJECT_DIR)/gpg-agent-deps \
		$(BIN_DIR)/keychain-interpose.dylib $(BIN_DIR)/pinentry-wrapper \
		src/resources/help-message.sh README.md
	src/meta/make-bundle.sh "migrate-keys" $(BIN_DIR) $(OBJECT_DIR) --skip-signing
	mkdir -p "$(BIN_DIR)/migrate-keys.app/Contents/Frameworks" "$(BIN_DIR)/migrate-keys.app/Contents/Resources"
	install -m u=rw  "$(BIN_DIR)/keychain-interpose.dylib" "$(BIN_DIR)/migrate-keys.app/Contents/Frameworks"
	$(call MAKE_AGENT_BUNDLE, $(OBJECT_DIR)/gpg-agent-deps, $(BIN_DIR)/gpg-agent.app)
	mv -f "$(BIN_DIR)/gpg-agent.app" "$(BIN_DIR)/migrate-keys.app/Contents/MacOS/gpg-agent.app"
	install -m u=rwx "$(BIN_DIR)/pinentry-wrapper" "$(BIN_DIR)/migrate-keys.app/Contents/MacOS"
	find src/resources -type file -print0 | \
		xargs -0 -I{} install -m u=rwx "{}" "$(BIN_DIR)/migrate-keys.app/Contents/Resources"
	find "$(BIN_DIR)/migrate-keys.app/Contents/Resources" -name '*.sh' -print0 | \
		xargs -0 -I{} $(call CODESIGN, {})
	install -m u=rw README.md "$(BIN_DIR)/migrate-keys.app/Contents/Resources"
	ln -f -s "../MacOS/gpg-agent.app/Contents/Resources/pkg-info" \
		"$(BIN_DIR)/migrate-keys.app/Contents/Resources/pkg-info"
	src/meta/make-bundle.sh "migrate-keys" $(BIN_DIR) $(OBJECT_DIR) "$(IDENTITY)" --sign-only
	rm -Rf "./$@"
	mv -f "$(BIN_DIR)/migrate-keys.app" "$@"

#################
# Installation

install : $(BINARIES)
	src/meta/install-app.sh "$(BIN_DIR)" "$(INSTALL_DIR)"

universal universal/bin :
	IDENTITY="$(IDENTITY)" src/meta/make-universal.sh

notarize : universal/bin
	NOTARY_KEYCHAIN_PROFILE="$(NOTARY_KEYCHAIN_PROFILE)" src/meta/notarize-app.sh "$</keychain-interpose.app"

install-universal : universal/bin
	@make notarize
	src/meta/install-app.sh "$<" "$(INSTALL_DIR)"

release : universal/bin
	@make notarize
	src/meta/download-source.sh
	/usr/bin/ditto -ck --keepParent "$</keychain-interpose.app" "$</keychain-interpose.app.zip"

#################

test : $(BINARIES)
	testing/run-test.sh

shellcheck :
	find src testing -name '*.sh' -exec shellcheck {} +

clean :
	rm -Rf $(OBJECT_DIR) $(BIN_DIR) universal

clean-all : clean clean-deps

.DELETE_ON_ERROR :

.PHONY : all bundle release test shellcheck clean clean-all clean-deps install notarize install-universal