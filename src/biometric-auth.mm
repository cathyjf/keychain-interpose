// SPDX-FileCopyrightText: Copyright 2023 Cathy J. Fitzpatrick <cathy@cathyjf.com>
// SPDX-License-Identifier: GPL-3.0-or-later

#import <string_view>
#import <LocalAuthentication/LAContext.h>

#if !__has_feature(objc_arc)
    #error Please compile this file with `-fobjc-arc`.
#endif

auto authenticate_user(const std::string_view &reason) {
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