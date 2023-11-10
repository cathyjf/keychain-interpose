OBJECT_DIR := objects
BIN_DIR := bin
CPPFLAGS_MINIMAL := -std=c++20 -O3 -flto -Wall -Werror -fprebuilt-module-path="$(OBJECT_DIR)"
CPPFLAGS := $(CPPFLAGS_MINIMAL) $(shell pkg-config --cflags fmt gpg-error) -Idependencies/libCF++/CF++/include \
	-I$(shell brew --prefix boost)/include
OBJCFLAGS := -fobjc-arc -Wno-unused-but-set-variable
LIBCF++ := dependencies/libCF++/Build/lib/libCF++.a
LDFLAGS := -fuse-ld=lld -framework Security -framework CoreFoundation $(shell brew --prefix fmt)/lib/libfmt.a \
	$(shell brew --prefix boost)/lib/libboost_program_options.a
MODULE_OBJECTS := $(addprefix $(OBJECT_DIR)/, cathyjf.ki.common.pcm cathyjf.ki.log.pcm)
MIGRATE_OBJECTS := $(addprefix $(OBJECT_DIR)/, migrate-keys.o cathyjf.ki.common.o biometric-auth.o)
DYLIB_OBJECTS := $(addprefix $(OBJECT_DIR)/, keychain-interpose.o cathyjf.ki.common.o cathyjf.ki.log.o)
OBJECTS := $(MIGRATE_OBJECTS) $(DYLIB_OBJECTS) $(MODULE_OBJECTS)
BINARIES := $(addprefix $(BIN_DIR)/, migrate-keys keychain-interpose.dylib)
IDENTITY = $(eval value := $(shell security find-identity -v -p codesigning | grep -o "[A-F0-9]\{25,\}"))$(value)
TEAM_ID = $(eval value := \
	$(shell security find-identity -v -p codesigning | grep -o "([A-Z0-9]\{10\})" | grep -o "[A-Z0-9]\{10\}"))$(value)
GNUPGHOME = $(eval value := $(shell printf $$GNUPGHOME))$(value)
CODESIGN = @src/meta/codesign.sh $(1) "$(IDENTITY)" "$(2)"

# Homebrew's version of clang is required because we use C++ standard modules.
# Apple's clang does not currently support the standard version of modules.
CXX = $(eval value := $(shell src/meta/print-compiler.sh))$(value)

all : $(BINARIES)

$(BIN_DIR)/keychain-interpose.dylib : $(DYLIB_OBJECTS) $(LIBCF++)
	$(CXX) -dynamiclib $^ -o $@ $(CPPFLAGS) $(LDFLAGS) $(shell pkg-config --libs gpg-error)
	$(call CODESIGN, $@)

$(BIN_DIR)/migrate-keys : $(MIGRATE_OBJECTS) $(LIBCF++) | $(OBJECT_DIR)/migrate-keys-entitlements.plist
	$(CXX) $^ -o $@ $(CPPFLAGS) $(LDFLAGS) -framework LocalAuthentication -framework Foundation
	$(call CODESIGN, $@, --entitlements "$(OBJECT_DIR)/migrate-keys-entitlements.plist")

$(OBJECT_DIR)/%.o : src/%.cpp
	$(CXX) -c $^ -o $@ $(CPPFLAGS)

$(OBJECT_DIR)/%.o : src/%.mm
	$(CXX) -c $^ -o $@ $(CPPFLAGS) $(OBJCFLAGS)

$(OBJECTS) : | $(OBJECT_DIR)
$(BINARIES) : | $(BIN_DIR)
$(OBJECT_DIR) $(BIN_DIR) :
	mkdir $@

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
	make -C $^ CXX="$(CXX)" LIBTOOL="$(shell brew --prefix llvm)/bin/llvm-libtool-darwin"

#################

test : $(BIN_DIR)/keychain-interpose.dylib
	testing/run-test.sh

clean :
	rm -Rf $(OBJECT_DIR) $(BIN_DIR)

clean-deps:
	make -C dependencies/libCF++ clean

sign-gpg-agent-binary : $(OBJECT_DIR)/gpg-agent-entitlements.plist
	$(call CODESIGN, "$(shell which gpg-agent)", --entitlements "$<")

sign-gpg-agent-deps :
	$(call CODESIGN, "$(shell brew --prefix libgcrypt)/lib/libgcrypt.dylib")
	$(call CODESIGN, "$(shell brew --prefix libassuan)/lib/libassuan.dylib")
	$(call CODESIGN, "$(shell brew --prefix npth)/lib/libnpth.dylib")
	$(call CODESIGN, "$(shell brew --prefix libgpg-error)/lib/libgpg-error.dylib")
	$(call CODESIGN, "$(shell brew --prefix gettext)/lib/libintl.dylib")

sign-gpg-agent : sign-gpg-agent-deps sign-gpg-agent-binary

$(GNUPGHOME)/keychain-interpose.dylib : $(BIN_DIR)/keychain-interpose.dylib
	install -m u=rw $< $@

$(GNUPGHOME)/migrate-keys : $(BIN_DIR)/migrate-keys
	install -m u=rwx $< $@

$(GNUPGHOME)/keychain-agent.sh : testing/agent.sh
	install -m u=rwx $< $@

install : $(GNUPGHOME)/keychain-interpose.dylib $(GNUPGHOME)/migrate-keys sign-gpg-agent

.PHONY : all test clean clean-deps sign-gpg-agent sign-gpg-agent-deps sign-gpg-agent-binary install