CPPFLAGS := -std=c++20 -O3 -Wall -Werror
LDFLAGS := -framework Security
OBJECT_DIR := objects
BIN_DIR := bin
DYLIB_OBJECTS := $(addprefix $(OBJECT_DIR)/, keychain-interpose.o log.o)
OBJECTS := $(addprefix $(OBJECT_DIR)/, migrate-keys.o) $(DYLIB_OBJECTS)
BINARIES := $(addprefix $(BIN_DIR)/, migrate-keys keychain-interpose.dylib)
IDENTITY = $(eval value := $(shell security find-identity -v -p codesigning | grep -o "[A-F0-9]\{25,\}"))$(value)
GNUPGHOME = $(eval value := $(shell printf $$GNUPGHOME))$(value)
define CODESIGN
	@if ! codesign -d --verbose $(1) 2>&1 | grep -q "flags=0x10000(runtime)"; then \
		echo "We need to sign" $(1) "with identity $(IDENTITY)."; \
		echo "This should only be required in one of the following two cases: "; \
		echo "    (1) This is your first time installing keychain-interpose for gpg-agent; or"; \
		echo "    (2) You have updated gpg-agent or one of its components since you last signed it."; \
		echo "If neither of these is true, something unexpected is happening, so you might"; \
		echo "want to cancel this process and figure out what is going on. However, if one"; \
		echo "of the two cases above applies, then it is normal that we need to sign this file."; \
		codesign -f --options runtime $(2) -s "$(IDENTITY)" $(1); \
	fi
endef

all : $(BINARIES)

$(BIN_DIR)/keychain-interpose.dylib : $(DYLIB_OBJECTS)
	$(CXX) -dynamiclib $^ -o $@ $(CPPFLAGS) $(LDFLAGS) $(shell pkg-config --libs gpg-error)
	$(call CODESIGN, $@)

$(BIN_DIR)/migrate-keys : $(OBJECT_DIR)/migrate-keys.o
	$(CXX) $^ -o $@ $(CPPFLAGS) $(LDFLAGS)

$(OBJECT_DIR)/%.o : src/%.cpp
	$(CXX) -c $^ -o $@ $(CPPFLAGS) $(shell pkg-config --cflags gpg-error)

$(OBJECTS) : | $(OBJECT_DIR)
$(BINARIES) : | $(BIN_DIR)
$(OBJECT_DIR) $(BIN_DIR) :
	mkdir $@

test : $(BIN_DIR)/keychain-interpose.dylib
	testing/run-test.sh

clean :
	rm $(OBJECTS) $(BINARIES) >/dev/null 2>&1 || true
	rmdir $(OBJECT_DIR) $(BIN_DIR) >/dev/null 2>&1 || true

sign-gpg-agent : src/meta/ggp-agent-entitlements.plist
	$(call CODESIGN, "$(shell brew --prefix libgcrypt)/lib/libgcrypt.dylib")
	$(call CODESIGN, "$(shell brew --prefix libassuan)/lib/libassuan.dylib")
	$(call CODESIGN, "$(shell brew --prefix npth)/lib/libnpth.dylib")
	$(call CODESIGN, "$(shell brew --prefix libgpg-error)/lib/libgpg-error.dylib")
	$(call CODESIGN, "$(shell brew --prefix gettext)/lib/libintl.dylib")
	$(call CODESIGN, "$(shell which gpg-agent)", --entitlements $<)

$(GNUPGHOME)/keychain-interpose.dylib : $(BIN_DIR)/keychain-interpose.dylib
	install -m u=rw $< $@

$(GNUPGHOME)/keychain-agent.sh : testing/agent.sh
	install -m u=rwx $< $@

install : $(GNUPGHOME)/keychain-interpose.dylib sign-gpg-agent

.PHONY : all test clean sign-gpg-agent install