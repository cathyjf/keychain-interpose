OBJECT_DIR := objects
BIN_DIR := bin
CPPFLAGS_MINIMAL := -std=c++20 -O3 -Wall -Werror -fprebuilt-module-path="$(OBJECT_DIR)"
CPPFLAGS := $(CPPFLAGS_MINIMAL) $(shell pkg-config --cflags gpg-error)
LDFLAGS := -framework Security
MODULE_OBJECTS := $(addprefix $(OBJECT_DIR)/, cathyjf.ki.common.pcm cathyjf.ki.log.pcm)
MIGRATE_OBJECTS := $(addprefix $(OBJECT_DIR)/, migrate-keys.o cathyjf.ki.common.o)
DYLIB_OBJECTS := $(addprefix $(OBJECT_DIR)/, keychain-interpose.o cathyjf.ki.common.o cathyjf.ki.log.o)
OBJECTS := $(MIGRATE_OBJECTS) $(DYLIB_OBJECTS) $(MODULE_OBJECTS)
BINARIES := $(addprefix $(BIN_DIR)/, migrate-keys keychain-interpose.dylib)
IDENTITY = $(eval value := $(shell security find-identity -v -p codesigning | grep -o "[A-F0-9]\{25,\}"))$(value)
GNUPGHOME = $(eval value := $(shell printf $$GNUPGHOME))$(value)
CODESIGN = @src/meta/codesign.sh $(1) "$(IDENTITY)" "$(2)"

# Homebrew's version of clang is required because we use C++ standard modules.
# Apple's clang does not currently support the standard version of modules.
CXX = $(eval value := $(shell src/meta/print-compiler.sh))$(value)

all : $(BINARIES)

$(BIN_DIR)/keychain-interpose.dylib : $(DYLIB_OBJECTS)
	$(CXX) -dynamiclib $^ -o $@ $(CPPFLAGS) $(LDFLAGS) $(shell pkg-config --libs gpg-error)
	$(call CODESIGN, $@)

$(BIN_DIR)/migrate-keys : $(MIGRATE_OBJECTS)
	$(CXX) $^ -o $@ $(CPPFLAGS) $(LDFLAGS) -framework CoreFoundation
	$(call CODESIGN, $@)

$(OBJECT_DIR)/%.o : src/%.cpp
	$(CXX) -c $^ -o $@ $(CPPFLAGS)

$(OBJECTS) : | $(OBJECT_DIR)
$(BINARIES) : | $(BIN_DIR)
$(OBJECT_DIR) $(BIN_DIR) :
	mkdir $@

###########
# Modules

$(MIGRATE_OBJECTS) $(DYLIB_OBJECTS) : | $(MODULE_OBJECTS)

$(OBJECT_DIR)/%.pcm : src/modules/%.cppm
	$(CXX) --precompile $^ -o $@ $(CPPFLAGS)

$(OBJECT_DIR)/%.o : $(OBJECT_DIR)/%.pcm
	$(CXX) -c $^ -o $@ $(CPPFLAGS_MINIMAL)

###########

test : $(BIN_DIR)/keychain-interpose.dylib
	testing/run-test.sh

clean :
	rm -Rf $(OBJECT_DIR) $(BIN_DIR)

sign-gpg-agent : src/meta/ggp-agent-entitlements.plist
	$(call CODESIGN, "$(shell brew --prefix libgcrypt)/lib/libgcrypt.dylib")
	$(call CODESIGN, "$(shell brew --prefix libassuan)/lib/libassuan.dylib")
	$(call CODESIGN, "$(shell brew --prefix npth)/lib/libnpth.dylib")
	$(call CODESIGN, "$(shell brew --prefix libgpg-error)/lib/libgpg-error.dylib")
	$(call CODESIGN, "$(shell brew --prefix gettext)/lib/libintl.dylib")
	$(call CODESIGN, "$(shell which gpg-agent)", --entitlements $<)

$(GNUPGHOME)/keychain-interpose.dylib : $(BIN_DIR)/keychain-interpose.dylib
	install -m u=rw $< $@

$(GNUPGHOME)/migrate-keys : $(BIN_DIR)/migrate-keys
	install -m u=rwx $< $@

$(GNUPGHOME)/keychain-agent.sh : testing/agent.sh
	install -m u=rwx $< $@

install : $(GNUPGHOME)/keychain-interpose.dylib $(GNUPGHOME)/migrate-keys sign-gpg-agent

.PHONY : all test clean sign-gpg-agent install