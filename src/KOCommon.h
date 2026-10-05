#import <Foundation/Foundation.h>

// Our own sources must not call APIs newer than iOS 6.0 (the SDK is 9.3): such a call is an error, not a warning
#pragma clang diagnostic error "-Wunguarded-availability"

#define KOLog(fmt, ...) NSLog(@"[Kostka] " fmt, ##__VA_ARGS__)
#define L(key) NSLocalizedString(key, nil)
