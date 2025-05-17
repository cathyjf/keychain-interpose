# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

if(NOT CMAKE_CXX_COMPILER)
    # Homebrew's version of Clang is required because we use C++ standard
    # modules. Apple's Clang does not currently support the standard version
    # of modules.
    execute_process(
        COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/src/meta/print-compiler.sh"
        OUTPUT_VARIABLE CMAKE_CXX_COMPILER)
endif()

# For consistency, we need to use the `ar` binary that comes with the version
# of Clang that we're using.
cmake_path(REPLACE_FILENAME CMAKE_CXX_COMPILER "llvm-ar" OUTPUT_VARIABLE CMAKE_AR)

set(CMAKE_OSX_SYSROOT "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")