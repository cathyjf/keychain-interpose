CPPFLAGS := -std=c++20 $(shell pkg-config --cflags gpg-error) -Wall
LDFLAGS := -framework Security $(shell pkg-config --libs gpg-error)
IDENTITY = $(eval value := $(shell security find-identity -v -p codesigning | grep -o "[A-F0-9]\{25,\}"))$(value)
CODESIGN = codesign -f --options runtime $(2) -s "$(IDENTITY)" $(1)

keychain-interpose.dylib : src/keychain-interpose.cpp src/log.o
	$(CXX) -dynamiclib $^ -o $@ $(CPPFLAGS) $(LDFLAGS)
	$(call CODESIGN, $@)

src/log.o : src/log.cpp

clean :
	-rm keychain-interpose.dylib src/log.o

sign-gpg-agent :
	$(call CODESIGN, $(shell brew --prefix libgcrypt)/lib/libgcrypt.dylib)
	$(call CODESIGN, $(shell brew --prefix libassuan)/lib/libassuan.dylib)
	$(call CODESIGN, $(shell brew --prefix npth)/lib/libnpth.dylib)
	$(call CODESIGN, $(shell brew --prefix libgpg-error)/lib/libgpg-error.dylib)
	$(call CODESIGN, $(shell brew --prefix gettext)/lib/libintl.dylib)
	$(call CODESIGN, $(shell which gpg-agent), --entitlements gpg-agent/entitlements.plist)

install : keychain-interpose.dylib
	install -m u=rw keychain-interpose.dylib $$GNUPGHOME/keychain-interpose.dylib
	install -m u=rwx agent.sh $$GNUPGHOME/keychain-agent.sh

.PHONY : clean sign-gpg-agent install