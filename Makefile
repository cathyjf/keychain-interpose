BUILD_DIR := .
OBJECT_DIR := $(BUILD_DIR)/objects
BIN_DIR := $(BUILD_DIR)/bin
CPPFLAGS_MINIMAL := -std=c++20 -O3 -flto -Wall -Werror -fprebuilt-module-path="$(OBJECT_DIR)" $(CPPFLAGS_EXTRA)
CPPFLAGS := $(CPPFLAGS_MINIMAL) $(shell pkg-config --cflags fmt gpg-error) -Idependencies/libCF++/CF++/include \
	-I$(shell brew --prefix boost)/include
OBJCFLAGS := -fobjc-arc -Wno-unused-but-set-variable
LIBCF++ := dependencies/libCF++/$(BUILD_DIR)/Build/lib/libCF++.a
LDFLAGS := -fuse-ld=lld -framework Security -framework CoreFoundation $(shell brew --prefix fmt)/lib/libfmt.a \
	$(shell brew --prefix boost)/lib/libboost_program_options.a
MODULE_OBJECTS := $(addprefix $(OBJECT_DIR)/, cathyjf.ki.common.pcm cathyjf.ki.log.pcm)
MIGRATE_OBJECTS := $(addprefix $(OBJECT_DIR)/, migrate-keys.o cathyjf.ki.common.o biometric-auth.o)
DYLIB_OBJECTS := $(addprefix $(OBJECT_DIR)/, keychain-interpose.o cathyjf.ki.common.o cathyjf.ki.log.o)
ENCAPSULATE_OBJECTS := $(addprefix $(OBJECT_DIR)/, encapsulate-app.o)
OBJECTS := $(MODULE_OBJECTS) $(MIGRATE_OBJECTS) $(DYLIB_OBJECTS) $(ENCAPSULATE_OBJECTS)
BINARIES := $(addprefix $(BIN_DIR)/, migrate-keys migrate-keys.app keychain-interpose.dylib gpg-agent.app encapsulate-app)
IDENTITY = $(eval value := $(shell security find-identity -v -p codesigning | grep -o "[A-F0-9]\{25,\}"))$(value)
TEAM_ID := KVRBCYNMT7
GNUPGHOME = $(eval value := $(shell printf $$GNUPGHOME))$(value)
INSTALL_DIR := $(GNUPGHOME)
CODESIGN = src/meta/codesign.sh $(1) "$(IDENTITY)" "$(2)"

# Homebrew's version of clang is required because we use C++ standard modules.
# Apple's clang does not currently support the standard version of modules.
CXX = $(eval value := $(shell src/meta/print-compiler.sh))$(value)
LIBTOOL = $(shell brew --prefix llvm)/bin/llvm-libtool-darwin

all : $(BINARIES)

$(BIN_DIR)/keychain-interpose.dylib : $(DYLIB_OBJECTS) $(LIBCF++) | $(OBJECT_DIR)/gpg-agent-deps
	$(CXX) -dynamiclib $^ -o $@ $(CPPFLAGS) $(LDFLAGS) $(OBJECT_DIR)/gpg-agent-deps/libgpg-error*.dylib
	$(call CODESIGN, $@)

$(BIN_DIR)/migrate-keys : $(MIGRATE_OBJECTS) $(LIBCF++) | $(OBJECT_DIR)/migrate-keys-entitlements.plist
	$(CXX) $^ -o $@ $(CPPFLAGS) $(LDFLAGS) -framework LocalAuthentication -framework Foundation
	$(call CODESIGN, $@, --entitlements "$(OBJECT_DIR)/migrate-keys-entitlements.plist")

$(BIN_DIR)/encapsulate-app : $(ENCAPSULATE_OBJECTS)
	$(CXX) $^ -o $@ $(CPPFLAGS) $(LDFLAGS) $(shell brew --prefix boost)/lib/libboost_regex.a

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

$(OBJECT_DIR)/%.plist : src/meta/%.plist.m4 | $(OBJECT_DIR)
	m4 -D MY_TEAM_ID=$(TEAM_ID) "$<" > "$@"

#################
# Modules

$(MIGRATE_OBJECTS) $(DYLIB_OBJECTS) : | $(MODULE_OBJECTS)

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
	mkdir -p $@
	$(BIN_DIR)/encapsulate-app "$(shell brew --prefix gnupg)/bin/gpg-agent" "$@"
	$(call CODESIGN, "$@/gpg-agent", --entitlements $(OBJECT_DIR)/gpg-agent-entitlements.plist)
	export FORCE_CODESIGN=1; find "$@" -name "*.dylib" -exec $(call CODESIGN, {}) \;

#################
# App bundles

$(BIN_DIR)/migrate-keys.app : $(BIN_DIR)/migrate-keys
	src/meta/make-bundle.sh "migrate-keys" $(BIN_DIR) $(OBJECT_DIR) $(IDENTITY)

$(BIN_DIR)/gpg-agent.app : $(OBJECT_DIR)/gpg-agent-deps $(BIN_DIR)/keychain-interpose.dylib
	install -m u=rwx "$</gpg-agent" $(BIN_DIR)/gpg-agent
	src/meta/make-bundle.sh "gpg-agent" $(BIN_DIR) $(OBJECT_DIR) --skip-signing
	mkdir -p "$@/Contents/Frameworks"
	find "$<" -name "*.dylib" -exec cp -f "{}" "$@/Contents/Frameworks" \;
	install -m u=rw  "$(BIN_DIR)/keychain-interpose.dylib" "$@/Contents/Frameworks"
	src/meta/make-bundle.sh "gpg-agent" $(BIN_DIR) $(OBJECT_DIR) $(IDENTITY) --sign-only

#################
# Installation

INSTALL_APP = \
	set -e; \
	rm -Rf "$(dir $(1))bundles/$(notdir $(1)).app"; \
	mkdir -p "$(dir $(1))bundles"; \
	cp -R $(2) "$(dir $(1))bundles/$(notdir $(1)).app"; \
	ln -s -f "$(dir $(1))bundles/$(notdir $(1)).app/Contents/MacOS/$(notdir $(1))" $(1)

INSTALL_SYMLINK = \
	ln -s -f "$(dir $(2))bundles/$(notdir $(2)).app/Contents/Frameworks/keychain-interpose.dylib" $(1)

$(INSTALL_DIR)/% : $(BIN_DIR)/%.app
	$(call INSTALL_APP, $@, $<)

$(INSTALL_DIR)/keychain-interpose.dylib : $(INSTALL_DIR)/gpg-agent
	$(call INSTALL_SYMLINK, $@, $<)

install : $(INSTALL_DIR)/migrate-keys $(INSTALL_DIR)/gpg-agent $(INSTALL_DIR)/keychain-interpose.dylib

universal universal/bin :
	src/meta/make-universal.sh

install-universal : universal/bin
	$(call INSTALL_APP, $(INSTALL_DIR)/migrate-keys, $</migrate-keys.app)
	$(call INSTALL_APP, $(INSTALL_DIR)/gpg-agent, $</gpg-agent.app)
	$(call INSTALL_SYMLINK, $(INSTALL_DIR)/keychain-interpose.dylib, $(INSTALL_DIR)/gpg-agent)

#################

test : $(BIN_DIR)/keychain-interpose.dylib $(BIN_DIR)/gpg-agent.app
	testing/run-test.sh

clean :
	rm -Rf $(OBJECT_DIR) $(BIN_DIR) universal

clean-all : clean clean-deps

.PHONY : all bundle test clean clean-all clean-deps install install-universal