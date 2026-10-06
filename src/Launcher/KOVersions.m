#import "KOVersions.h"
#import "KONet.h"
#import "KOJava.h"
#import "KOCommon.h"

static NSString *const KOManifestURL = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";

// What was tried on an iPad 2 (iOS 6.1.3): Resources/Tested.json, written from the run that starts every version,
// makes a new world in it and plays there for a while. "plays": the versions that did; "notYet": the ones that did
// not, each with a word for what went wrong (KOVersion.problem)
static NSSet *g_plays;
static NSDictionary *g_notYet;

static void KOLoadTested(void)
{
    if (g_plays) return;
    NSData *d = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Tested" ofType:@"json"]];
    NSDictionary *json = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) json = @{};
    g_plays = [NSSet setWithArray:[json[@"plays"] isKindOfClass:[NSArray class]] ? json[@"plays"] : @[]];
    g_notYet = [json[@"notYet"] isKindOfClass:[NSDictionary class]] ? json[@"notYet"] : @{};
}

@implementation KOVersion

- (KOSupport)support
{
    // The whole LWJGL 2 era runs on Kostka's Java, windows and OpenGL; 17w43a, the first 1.13 snapshot (October
    // 2017), moved to LWJGL 3
    KOLoadTested();
    if ([g_plays containsObject:self.identifier]) return KOSupportPlays;
    if (g_notYet[self.identifier]) return KOSupportSoon;
    if ([self.released compare:@"2017-10-25"] != NSOrderedAscending) return KOSupportNever;
    return KOSupportTry;
}

- (NSString *)problem
{
    KOLoadTested();
    NSString *word = g_notYet[self.identifier];
    if (!word) return nil;
    NSDictionary *texts = @{
        @"crash": L(@"it stops while starting."),
        @"world": L(@"it stops while making or loading a world."),
        @"memory": L(@"it needs more memory than the iPad 2 has."),
    };
    return texts[word] ?: L(@"it did not play in the tries on an iPad 2.");
}

- (NSString *)localizedSupport
{
    switch (self.support) {
        case KOSupportPlays: return L(@"Plays");
        case KOSupportTry: return L(@"Not tried yet");
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
