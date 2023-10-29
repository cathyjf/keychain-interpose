CPPFLAGS :=  -std=c++17 `pkg-config --cflags gpg-error` -Wall
LDFLAGS := -framework Security `pkg-config --libs gpg-error`

keychain-interpose.dylib : src/keychain-interpose.cpp src/log.o
	$(CXX) -dynamiclib $^ -o $@ $(CPPFLAGS) $(LDFLAGS)

src/log.o : src/log.cpp

clean :
	-rm keychain-interpose.dylib src/log.o

.PHONY : clean

# @IDENTITY=$$(security find-identity -v -p codesigning | grep -o "[A-F0-9]\{25,\}"); \
# echo Signing $(output_binary) with identity $$IDENTITY.; \
# codesign -f -s "$$IDENTITY" $@