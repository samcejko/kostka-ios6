#import "KOVersions.h"
#import "KONet.h"
#import "KOJava.h"
#import "KOCommon.h"

static NSString *const KOManifestURL = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";

@implementation KOVersion

- (KOSupport)support
{
    // RubyDung (May 2009) opens its window with LWJGL alone: it runs. Everything up to 1.12.2 is of LWJGL 2 and
    // Java 8 (17w43a, the first 1.13 snapshot of October 2017, moved to LWJGL 3); Classic to 1.5.2 open an AWT
    // window first, 1.6 and newer want more memory: not yet.
    if ([self.identifier hasPrefix:@"rd-"]) return KOSupportPlays;
    if ([self.released compare:@"2017-10-25"] != NSOrderedAscending) return KOSupportNever;
    // 1.6 started the game without an AWT window (1.6.4 plays). By number for the releases: 1.5.2 came out after
    // the first 1.6 snapshot (13w16a, 21 April 2013), and still opens one.
    if ([self.type isEqualToString:@"release"]) {
        NSArray *parts = [self.identifier componentsSeparatedByString:@"."];
        return parts.count > 1 && [parts[0] isEqualToString:@"1"] && [parts[1] intValue] >= 6 ? KOSupportTry : KOSupportSoon;
    }
    if ([self.type isEqualToString:@"snapshot"] && [self.released compare:@"2013-04-21"] != NSOrderedAscending) return KOSupportTry;
    return KOSupportSoon;
}

- (NSString *)localizedSupport
{
    switch (self.support) {
        case KOSupportPlays: return L(@"Plays");
        case KOSupportTry: return L(@"To try");
        case KOSupportSoon: return L(@"Not yet");
        default: return L(@"Too new for iOS 6");
    }
}

- (NSString *)localizedReleased
{
    static NSDateFormatter *in, *out;
    if (!in) {
        in = [[NSDateFormatter alloc] init];
        in.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        in.dateFormat = @"yyyy-MM-dd";
        out = [[NSDateFormatter alloc] init];
        out.dateStyle = NSDateFormatterMediumStyle;
        out.timeStyle = NSDateFormatterNoStyle;
    }
    NSDate *d = [in dateFromString:self.released];
    return d ? [out stringFromDate:d] : self.released;
}

@end

@implementation KOVersions

+ (NSString *)versionsPath
{
    NSString *p = [[KOJava dataPath] stringByAppendingPathComponent:@"versions"];
    [[NSFileManager defaultManager] createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:NULL];
    return p;
}

+ (NSString *)manifestPath
{
    return [[self versionsPath] stringByAppendingPathComponent:@"version_manifest_v2.json"];
}

+ (NSArray *)parse:(id)json
{
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *v in json[@"versions"]) {
        if (![v isKindOfClass:[NSDictionary class]] || ![v[@"id"] isKindOfClass:[NSString class]]) continue;
        KOVersion *version = [[KOVersion alloc] init];
        version.identifier = v[@"id"];
        version.type = v[@"type"];
        version.url = v[@"url"];
        version.sha1 = v[@"sha1"];
        NSString *t = v[@"releaseTime"];
        version.released = [t isKindOfClass:[NSString class]] && t.length >= 10 ? [t substringToIndex:10] : @"";
        [list addObject:version];
    }
    return list.count ? list : nil;
}

+ (void)load:(void (^)(NSArray *, NSError *))done
{
    [KONet fetchJSON:[NSURL URLWithString:KOManifestURL] done:^(id json, NSData *data, NSError *error) {
        NSArray *list = [self parse:json];
        if (list) {
            [data writeToFile:[self manifestPath] atomically:YES];
            done(list, nil);
            return;
        }
        // (offline: the list from the last time)
        NSData *cached = [NSData dataWithContentsOfFile:[self manifestPath]];
        id old = cached ? [NSJSONSerialization JSONObjectWithData:cached options:0 error:NULL] : nil;
        list = [self parse:old];
        done(list, list ? nil : (error ?: [KONet errorWithText:L(@"Mojang's list of versions is not readable.")]));
    }];
}

@end
