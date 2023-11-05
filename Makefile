CPPFLAGS := -std=c++20 $(shell pkg-config --cflags gpg-error) -Wall
LDFLAGS := -framework Security $(shell pkg-config --libs gpg-error)
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

keychain-interpose.dylib : src/keychain-interpose.cpp src/log.o
	$(CXX) -dynamiclib $^ -o $@ $(CPPFLAGS) $(LDFLAGS)
	$(call CODESIGN, $@)

src/log.o : src/log.cpp

clean :
	-rm keychain-interpose.dylib src/log.o

sign-gpg-agent :
	$(call CODESIGN, "$(shell brew --prefix libgcrypt)/lib/libgcrypt.dylib")
	$(call CODESIGN, "$(shell brew --prefix libassuan)/lib/libassuan.dylib")
	$(call CODESIGN, "$(shell brew --prefix npth)/lib/libnpth.dylib")
	$(call CODESIGN, "$(shell brew --prefix libgpg-error)/lib/libgpg-error.dylib")
	$(call CODESIGN, "$(shell brew --prefix gettext)/lib/libintl.dylib")
	$(call CODESIGN, "$(shell which gpg-agent)", --entitlements gpg-agent/entitlements.plist)

$(GNUPGHOME)/keychain-interpose.dylib : keychain-interpose.dylib
	install -m u=rw $< $@

$(GNUPGHOME)/keychain-agent.sh : agent.sh
	install -m u=rwx $< $@

install : $(GNUPGHOME)/keychain-interpose.dylib sign-gpg-agent

.PHONY : clean sign-gpg-agent install