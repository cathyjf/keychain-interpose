# SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 3.30.5)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_CXX_SCAN_FOR_MODULES ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -flto -Wall -Werror")
set(CMAKE_OBJCXX_FLAGS "${CMAKE_OBJCXX_FLAGS} -fobjc-arc")

set(TEAM_ID "KVRBCYNMT7"
    CACHE STRING "Team ID used for code signing.")
set(IDENTITY "Developer ID Application: Cathy Fitzpatrick (${TEAM_ID})"
    CACHE STRING "Developer ID used for code signing.")
set(CODESIGN "${CMAKE_CURRENT_SOURCE_DIR}/src/meta/codesign.sh")
set(MAKE_BUNDLE "${CMAKE_CURRENT_SOURCE_DIR}/src/meta/make-bundle.sh")
set(MAIN_APP_BUNDLE "${CMAKE_BINARY_DIR}/keychain-interpose.app")

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
get_filename_component(CLANG_CXX_DIR ${CMAKE_CXX_COMPILER} DIRECTORY)
set(CMAKE_AR "${CLANG_CXX_DIR}/llvm-ar")

project(keychain-interpose LANGUAGES CXX OBJCXX)

set(Boost_USE_STATIC_LIBS ON)
find_package(Boost 1.86 REQUIRED COMPONENTS program_options regex)
# The Boost::regex target automatically links to icudata, icui18n, and icuuc,
# but we don't need any of those.
set_property(TARGET Boost::regex PROPERTY INTERFACE_LINK_LIBRARIES "")

###############################################################################
# libCF++

file(GLOB cfpp_src CONFIGURE_DEPENDS "dependencies/libCF++/CF++/source/*.cpp")
add_library(cfpp STATIC ${cfpp_src})
target_include_directories(cfpp PUBLIC "dependencies/libCF++/CF++/include")

###############################################################################
# keychain-interpose-common

add_library(keychain-interpose-common OBJECT)
target_sources(keychain-interpose-common PUBLIC FILE_SET CXX_MODULES FILES
    "src/modules/cathyjf.ki.common.cppm")
block()
    find_library(CORE_FOUNDATION_F CoreFoundation REQUIRED)
    find_library(SECURITY_F Security REQUIRED)
    target_link_libraries(keychain-interpose-common
        PUBLIC cfpp
        PUBLIC ${CORE_FOUNDATION_F}
        PUBLIC ${SECURITY_F})
endblock()

###############################################################################
# encapsulate-app

add_executable(encapsulate-app
    "src/encapsulate-app.cpp")
target_link_libraries(encapsulate-app
    PRIVATE keychain-interpose-common
    PRIVATE Boost::regex)

###############################################################################
# provisionprofile_target

add_custom_command(
    OUTPUT
        "keychain-interpose.provisionprofile"
    COMMAND /usr/bin/base64 ARGS -d
        -i "src/meta/profiles/keychain-interpose.provisionprofile.base64"
        -o "${CMAKE_BINARY_DIR}/keychain-interpose.provisionprofile"
    DEPENDS
        "src/meta/profiles/keychain-interpose.provisionprofile.base64"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)

add_custom_target("provisionprofile_target" DEPENDS
    "keychain-interpose.provisionprofile")

###############################################################################
# gpg-agent.app

set(AGENT_APP_BUNDLE_PARENT "${MAIN_APP_BUNDLE}/Contents/MacOS")
set(AGENT_APP_BUNDLE "${AGENT_APP_BUNDLE_PARENT}/gpg-agent.app")
set(AGENT_FRAMEWORKS "${AGENT_APP_BUNDLE}/Contents/Frameworks")

find_package(PkgConfig REQUIRED)
pkg_check_modules(GPG_ERROR REQUIRED gpg-error)
block(PROPAGATE AGENT_LIBGPG_ERROR)
    get_filename_component(libgpg_error_realpath
        "${GPG_ERROR_LIBRARY_DIRS}/lib${GPG_ERROR_LIBRARIES}.dylib" REALPATH)
    get_filename_component(libgpg_error_filename ${libgpg_error_realpath} NAME)
    set(AGENT_LIBGPG_ERROR "${AGENT_FRAMEWORKS}/${libgpg_error_filename}")
endblock()

add_custom_command(
    OUTPUT
        ${AGENT_APP_BUNDLE}
        ${AGENT_LIBGPG_ERROR}
        "${AGENT_APP_BUNDLE}/Contents/embedded.provisionprofile"
    COMMAND /bin/bash ARGS -c
        [[
        "$1" "$(brew --prefix gnupg)"/bin/gpg-agent "$2" "$(brew --prefix)" boost
        ]]
        "shell"
        $<TARGET_FILE:encapsulate-app>
        ${AGENT_APP_BUNDLE}
    COMMAND /bin/bash ARGS -c
        [[
        find "$1" -name '*.dylib' -print0 | xargs -0 -I{} "$2" "{}" "$3"
        ]]
        "shell"
        ${AGENT_FRAMEWORKS}
        ${CODESIGN}
        ${IDENTITY}
    COMMAND ${MAKE_BUNDLE} ARGS
        "gpg-agent"
        ${AGENT_APP_BUNDLE_PARENT}
        ${CMAKE_BINARY_DIR}
        ${IDENTITY}
    DEPENDS
        ${MAKE_BUNDLE}
        "gpg-agent-entitlements"
        "keychain-interpose.provisionprofile"
        "provisionprofile_target"
        "src/meta/Info.plist.m4"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)

add_custom_target("gpg-agent_target" DEPENDS
    ${AGENT_APP_BUNDLE} ${AGENT_LIBGPG_ERROR})
set_property(TARGET gpg-agent_target APPEND
    PROPERTY ADDITIONAL_CLEAN_FILES ${AGENT_APP_BUNDLE})

###############################################################################
# generate_entitlements

function(generate_entitlements name)
    add_custom_command(OUTPUT "${name}.plist"
        COMMAND /bin/bash ARGS -c
            [[ m4 -D "$1" "${@:4}" < "$2" > "$3" ]]
            "shell"
            "MY_TEAM_ID=${TEAM_ID}"
            "${CMAKE_CURRENT_SOURCE_DIR}/src/meta/entitlements.plist.m4"
            "${CMAKE_BINARY_DIR}/${name}.plist"
            ${ARGN}
        MAIN_DEPENDENCY "src/meta/entitlements.plist.m4"
        VERBATIM)
    add_custom_target(${name} DEPENDS "${name}.plist")
endfunction()

generate_entitlements(migrate-keys-entitlements)
generate_entitlements(gpg-agent-entitlements -D "ALLOW_DYLD=1")

###############################################################################
# target_codesign

function(target_codesign name)
    add_custom_command(TARGET ${name} POST_BUILD
        COMMAND ${CODESIGN} ARGS
            $<TARGET_FILE:${name}> ${IDENTITY} ${ARGN}
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        VERBATIM
    )
endfunction()

###############################################################################
# migrate-keys

add_executable(migrate-keys
    "src/migrate-keys.cpp"
    "src/migrate-keys-helper.mm")
block()
    find_library(LOCAL_AUTHENTICATION_F LocalAuthentication REQUIRED)
    find_library(FOUNDATION_F Foundation REQUIRED)
    find_library(CORE_SERVICES_F CoreServices REQUIRED)
    find_library(APPKIT_F AppKit REQUIRED)
    target_link_libraries(migrate-keys
        PRIVATE keychain-interpose-common
        PRIVATE Boost::program_options
        PRIVATE ${LOCAL_AUTHENTICATION_F}
        PRIVATE ${FOUNDATION_F}
        PRIVATE ${CORE_SERVICES_F}
        PRIVATE ${APPKIT_F})
endblock()

###############################################################################
# pinentry-wrapper

add_executable(pinentry-wrapper
    "src/pinentry-wrapper.cpp")
target_codesign(pinentry-wrapper)

###############################################################################
# dependency-sources.zip

add_custom_command(
    OUTPUT
        "dependency-sources.zip"
        "dependency-sources.zip.txt"
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/src/meta/download-source.sh" ARGS
        ${CMAKE_BINARY_DIR}
    VERBATIM
    USES_TERMINAL
)

add_custom_target("dependency-sources"
    DEPENDS "dependency-sources.zip" "dependency-sources.zip.txt")

###############################################################################
# keychain-interpose.app

add_library(keychain-interpose SHARED "src/keychain-interpose.cpp")
set_target_properties(keychain-interpose PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${MAIN_APP_BUNDLE}/Contents/Frameworks"
    # Prevent cmake from adding a "lib" prefix to the output filename.
    PREFIX "")
set_target_properties(keychain-interpose PROPERTIES PREFIX "")
target_sources(keychain-interpose PRIVATE FILE_SET CXX_MODULES FILES
    "src/modules/cathyjf.ki.log.cppm")
add_dependencies(keychain-interpose "gpg-agent_target")
target_include_directories(keychain-interpose PRIVATE ${GPG_ERROR_INCLUDE_DIRS})
target_link_libraries(keychain-interpose
    PRIVATE keychain-interpose-common
    PRIVATE ${AGENT_LIBGPG_ERROR})
target_codesign(keychain-interpose)

set(APP_RESOURCES "${MAIN_APP_BUNDLE}/Contents/Resources")
add_custom_command(
    OUTPUT
        "${MAIN_APP_BUNDLE}/Contents/Info.plist"
        "${MAIN_APP_BUNDLE}/Contents/_CodeSignature/CodeResources"
        "${MAIN_APP_BUNDLE}/Contents/embedded.provisionprofile"
    COMMAND /usr/bin/install ARGS
        -m u=rx
        $<TARGET_FILE:migrate-keys>
        $<TARGET_FILE:pinentry-wrapper>
        "${MAIN_APP_BUNDLE}/Contents/MacOS"
    COMMAND /bin/mkdir ARGS
        -p ${APP_RESOURCES}
    COMMAND /usr/bin/install ARGS
        -m u=r
        "README.md"
        ${APP_RESOURCES}
    COMMAND /usr/bin/install ARGS
        -m u=rx
        "src/resources/gpg-keychain-agent.sh"
        "src/resources/help-message.sh"
        ${APP_RESOURCES}
    COMMAND /bin/ln ARGS
        -f -s "../MacOS/gpg-agent.app/Contents/Resources/pkg-info"
        "${MAIN_APP_BUNDLE}/Contents/Resources/pkg-info"
    COMMAND ${MAKE_BUNDLE} ARGS
        "keychain-interpose"
        ${CMAKE_BINARY_DIR}
        ${CMAKE_BINARY_DIR}
        ${IDENTITY}
    DEPENDS
        ${MAKE_BUNDLE}
        "keychain-interpose.provisionprofile"
        "provisionprofile_target"
        "keychain-interpose"
        "migrate-keys"
        "migrate-keys-entitlements"
        "pinentry-wrapper"
        "gpg-agent_target"
        "README.md"
        "src/meta/Info.plist.m4"
        "src/resources/gpg-keychain-agent.sh"
        "src/resources/help-message.sh"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    VERBATIM
)

add_custom_target("keychain-interpose_app_bundle" ALL
    DEPENDS "${MAIN_APP_BUNDLE}/Contents/Info.plist")
set_property(TARGET "keychain-interpose_app_bundle" APPEND
    PROPERTY ADDITIONAL_CLEAN_FILES ${MAIN_APP_BUNDLE})