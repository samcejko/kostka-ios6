#import <Foundation/Foundation.h>

extern NSString *const KOErrorDomain;

// Fetching from Mojang's servers: JSON, and files checked against their SHA-1. Callbacks on the main thread.
@interface KONet : NSObject

+ (void)fetchJSON:(NSURL *)url done:(void (^)(id json, NSData *data, NSError *error))done;

// Downloads `url` into `path` (through path.part; an existing file with the right SHA-1 is kept as it is)
+ (void)download:(NSURL *)url to:(NSString *)path sha1:(NSString *)sha1
        progress:(void (^)(long long received, long long expected))progress
            done:(void (^)(NSError *error))done;

+ (NSString *)sha1OfFile:(NSString *)path;
+ (NSError *)errorWithText:(NSString *)text;

@end
