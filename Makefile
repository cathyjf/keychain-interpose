OBJECT_DIR := objects
BIN_DIR := bin
CPPFLAGS_MINIMAL := -std=c++20 -O3 -flto -Wall -Werror -fprebuilt-module-path="$(OBJECT_DIR)"
CPPFLAGS := $(CPPFLAGS_MINIMAL) $(shell pkg-config --cflags fmt gpg-error) -Idependencies/libCF++/CF++/include \
	-I$(shell brew --prefix boost)/include
OBJCFLAGS := -fobjc-arc -Wno-unused-but-set-variable
LIBCF++ := dependencies/libCF++/Build/lib/libCF++.a
LIBOTOOL := $(OBJECT_DIR)/libotool.a
LDFLAGS := -fuse-ld=lld -framework Security -framework CoreFoundation $(shell brew --prefix fmt)/lib/libfmt.a \
	$(shell brew --prefix boost)/lib/libboost_program_options.a
MODULE_OBJECTS := $(addprefix $(OBJECT_DIR)/, cathyjf.ki.common.pcm cathyjf.ki.log.pcm)
MIGRATE_OBJECTS := $(addprefix $(OBJECT_DIR)/, migrate-keys.o cathyjf.ki.common.o biometric-auth.o)
DYLIB_OBJECTS := $(addprefix $(OBJECT_DIR)/, keychain-interpose.o cathyjf.ki.common.o cathyjf.ki.log.o)
OBJECTS := $(MIGRATE_OBJECTS) $(DYLIB_OBJECTS) $(MODULE_OBJECTS)
BINARIES := $(addprefix $(BIN_DIR)/, migrate-keys keychain-interpose.dylib)
IDENTITY = $(eval value := $(shell security find-identity -v -p codesigning | grep -o "[A-F0-9]\{25,\}"))$(value)
TEAM_ID := KVRBCYNMT7
GNUPGHOME = $(eval value := $(shell printf $$GNUPGHOME))$(value)
CODESIGN = HIDE_CODESIGN_EXPLANATION=1 src/meta/codesign.sh $(1) "$(IDENTITY)" "$(2)"

# Homebrew's version of clang is required because we use C++ standard modules.
# Apple's clang does not currently support the standard version of modules.
CC = $(eval value := $(shell src/meta/print-compiler.sh))$(value)
CXX := $(CC)++
LIBTOOL := $(shell brew --prefix llvm)/bin/llvm-libtool-darwin

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
	make -C $^ CXX="$(CXX)" LIBTOOL="$(LIBTOOL)"

CCTOOLS_DIR := dependencies/cctools
OTOOL_OBJECTS := $(patsubst %.c, %.o, \
	$(wildcard $(CCTOOLS_DIR)/otool/*.c) $(wildcard $(CCTOOLS_DIR)/libstuff/*.c))
$(CCTOOLS_DIR)/%.o : $(CCTOOLS_DIR)/%.c
	$(CC) -o $@ $< -c -Wno-macro-redefined -Wno-deprecated-declarations -Wno-deprecated-non-prototype \
		-O3 -flto -I$(CCTOOLS_DIR)/include -I$(CCTOOLS_DIR)/include/stuff
$(LIBOTOOL) : $(OTOOL_OBJECTS) | $(OBJECT_DIR)
	$(LIBTOOL) -static -o $@ $^

clean-libotool :
	rm -f $(OTOOL_OBJECTS)

#################
# App bundles

$(BIN_DIR)/migrate-keys.app : | $(BIN_DIR)/migrate-keys
	src/meta/make-bundle.sh "migrate-keys" $(BIN_DIR) $(OBJECT_DIR) $(IDENTITY)

$(BIN_DIR)/gpg-agent.app : | sign-gpg-agent
	install -m u=rwx "$(shell which gpg-agent)" $(BIN_DIR)/gpg-agent
	src/meta/make-bundle.sh "gpg-agent" $(BIN_DIR) $(OBJECT_DIR) $(IDENTITY)

bundle : $(BIN_DIR)/migrate-keys.app $(BIN_DIR)/gpg-agent.app

clean-bundle :
	rm -Rf $(BIN_DIR)/*.app

#################

test : $(BIN_DIR)/keychain-interpose.dylib $(BIN_DIR)/gpg-agent.app
	testing/run-test.sh

clean :
	rm -Rf $(OBJECT_DIR) $(BIN_DIR)

clean-deps:
	make -C dependencies/libCF++ clean
	make clean-libotool

sign-gpg-agent-binary : $(OBJECT_DIR)/gpg-agent-entitlements.plist
	@$(call CODESIGN, "$(shell which gpg-agent)", --entitlements "$<")

sign-gpg-agent-deps :
	@$(call CODESIGN, "$(shell brew --prefix libgcrypt)/lib/libgcrypt.dylib")
	@$(call CODESIGN, "$(shell brew --prefix libassuan)/lib/libassuan.dylib")
	@$(call CODESIGN, "$(shell brew --prefix npth)/lib/libnpth.dylib")
	@$(call CODESIGN, "$(shell brew --prefix libgpg-error)/lib/libgpg-error.dylib")
	@$(call CODESIGN, "$(shell brew --prefix gettext)/lib/libintl.dylib")

sign-gpg-agent : sign-gpg-agent-deps sign-gpg-agent-binary

$(GNUPGHOME)/keychain-interpose.dylib : $(BIN_DIR)/keychain-interpose.dylib
	install -m u=rw $< $@

$(GNUPGHOME)/% : $(BIN_DIR)/%.app
	rm -Rf "$(dir $@)bundles/$(notdir $@).app"
	mkdir -p "$(dir $@)bundles"
	cp -R "$<" "$(dir $@)bundles/$(notdir $@).app"
	ln -s -f "$(dir $@)bundles/$(notdir $@).app/Contents/MacOS/$(notdir $@)" "$@"

install : $(GNUPGHOME)/keychain-interpose.dylib $(GNUPGHOME)/migrate-keys $(GNUPGHOME)/gpg-agent

.PHONY : all bundle test clean clean-bundle clean-libotool clean-deps \
	sign-gpg-agent sign-gpg-agent-deps sign-gpg-agent-binary install