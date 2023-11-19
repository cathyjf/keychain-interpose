// SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#import <AppKit/NSWorkspace.h>
#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>
#import <LocalAuthentication/LAContext.h>
#import <iostream>
#import <string_view>

#if !__has_feature(objc_arc)
    #error Please compile this file with `-fobjc-arc`.
#endif

namespace {

[[nodiscard]] auto nsurl_from_string_view(const std::string_view &string) {
    return [NSURL
        fileURLWithPath:[[NSString alloc] initWithCString:string.data()
                                                 encoding:NSASCIIStringEncoding]
            isDirectory:NO];
}

[[nodiscard]] auto default_application_for_file(const auto &filename) {
    return [[NSWorkspace sharedWorkspace]
        URLForApplicationToOpenURL:nsurl_from_string_view(filename)];
}

[[nodiscard]] auto string_from_nsurl(const auto &url) {
    const auto data = [url dataRepresentation];
    return std::string{ static_cast<const char *>(data.bytes), data.length };
}

} // anonymous namespace

[[nodiscard]] auto authenticate_user(const std::string_view &reason) {
    auto context = [LAContext new];
    auto sema = dispatch_semaphore_create(0);
    __block auto authentication_success = false;
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthentication
            localizedReason:[[NSString alloc] initWithCString:reason.data()
                                                     encoding:NSASCIIStringEncoding]
                      reply:^(BOOL success, NSError *) {
                                authentication_success = success;
                                dispatch_semaphore_signal(sema);
                            }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return authentication_success;
}

[[nodiscard]] auto open_script_with_default_terminal(const std::string_view &sample_binary, const std::string_view &script) {
    const auto terminalURL = default_application_for_file(sample_binary);
    if (terminalURL == nil) {
        return false;
    }
    std::cout << "Using this Terminal application: " << string_from_nsurl(terminalURL) << '.' << std::endl;
    std::cout << "Launching this script: " << script << '.' << std::endl;
    const auto spec = LSLaunchURLSpec{
        .appURL = (__bridge CFURLRef)terminalURL,
        .itemURLs = (__bridge CFArrayRef)@[nsurl_from_string_view(script)]
    };
    return (LSOpenFromURLSpec(&spec, nil) == errSecSuccess);
}