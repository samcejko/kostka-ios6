#import "KOVersions.h"
#import "KOChangelog.h"
#import "KONet.h"
#import "KOJava.h"
#import "KOCommon.h"

static NSString *const KOManifestURL = @"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";

// What was tried on an iPad 2 (iOS 6.1.3): Resources/Tested.json, written from the run that starts every version,
// makes a new world in it and plays there for a while. "plays": the versions that did; "notYet": the ones that did
// not, each with a word for what went wrong (KOVersion.problem)
static NSSet *g_plays, *g_english;
static NSDictionary *g_notYet;

static void KOLoadTested(void)
{
    if (g_plays) return;
    NSData *d = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Tested" ofType:@"json"]];
    NSDictionary *json = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![json isKindOfClass:[NSDictionary class]]) json = @{};
    g_plays = [NSSet setWithArray:[json[@"plays"] isKindOfClass:[NSArray class]] ? json[@"plays"] : @[]];
    g_notYet = [json[@"notYet"] isKindOfClass:[NSDictionary class]] ? json[@"notYet"] : @{};
    // ("english": versions that stop on a letter of another language - a bug of their own, 13w42b's font)
    g_english = [NSSet setWithArray:[json[@"english"] isKindOfClass:[NSArray class]] ? json[@"english"] : @[]];
}

@implementation KOVersion

- (KOSupport)support
{
    // The whole LWJGL 2 era runs on Kostka's Java, windows and OpenGL; 17w43a, the first 1.13 snapshot (October
    // 2017), moved to LWJGL 3. A version made from another (OptiFine) plays where it was tried, else as its parent
    // would, not tried yet.
    KOLoadTested();
    if ([g_plays containsObject:self.identifier]) return KOSupportPlays;
    if (self.parent) return self.parent.support == KOSupportNever ? KOSupportNever : KOSupportTry;
    if (g_notYet[self.identifier]) return KOSupportSoon;
    if ([self.released compare:@"2017-10-25"] != NSOrderedAscending) return KOSupportNever;
    return KOSupportTry;
}

- (BOOL)englishOnly
{
    KOLoadTested();
    return [g_english containsObject:self.identifier];
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
        @"twitch": L(@"it will not start without Twitch's streaming library, which there is none of for iOS (the next snapshots go on without it)."),
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

- (NSString *)optiFineEdition
{
    NSRange r = [self.identifier rangeOfString:@"-OptiFine_"];
    if (r.location == NSNotFound) return nil;
    return [[self.identifier substringFromIndex:NSMaxRange(r)] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
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

// The versions installed here from others (OptiFine): folders in versions/ whose JSON names a version of the list it
// inherits from, after the list's
+ (NSArray *)withInstalled:(NSArray *)list
{
    if (!list) return nil;
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    for (KOVersion *v in list) byId[v.identifier] = v;
    NSMutableArray *all = [list mutableCopy], *installed = [NSMutableArray array];
    NSString *root = [self versionsPath];
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names.reverseObjectEnumerator) {
        if (byId[name]) continue;
        NSString *path = [[root stringByAppendingPathComponent:name] stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]];
        NSData *d = [NSData dataWithContentsOfFile:path];
        NSDictionary *json = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
        if (![json isKindOfClass:[NSDictionary class]] || ![json[@"inheritsFrom"] isKindOfClass:[NSString class]]) continue;
        KOVersion *parent = byId[json[@"inheritsFrom"]];
        if (!parent) continue;
        KOVersion *v = [[KOVersion alloc] init];
        v.identifier = name;
        v.type = parent.type;
        v.released = parent.released;
        v.parent = parent;
        [installed addObject:v];
    }
    // (newest first, as the list: by their versions' dates)
    [installed sortUsingComparator:^NSComparisonResult(KOVersion *a, KOVersion *b) {
        NSComparisonResult r = [b.released compare:a.released];
        return r != NSOrderedSame ? r : [b.identifier compare:a.identifier];
    }];
    [all addObjectsFromArray:installed];
    return all;
}

+ (void)load:(void (^)(NSArray *, NSError *))done
{
    [KONet fetchJSON:[NSURL URLWithString:KOManifestURL] done:^(id json, NSData *data, NSError *error) {
        NSArray *list = [self parse:json];
        if (list) {
            [data writeToFile:[self manifestPath] atomically:YES];
            [KOChangelog setVersions:list];
            done([self withInstalled:list], nil);
            return;
        }
        // (offline: the list from the last time)
        NSData *cached = [NSData dataWithContentsOfFile:[self manifestPath]];
        id old = cached ? [NSJSONSerialization JSONObjectWithData:cached options:0 error:NULL] : nil;
        list = [self withInstalled:[self parse:old]];
        if (list) [KOChangelog setVersions:list];
        done(list, list ? nil : (error ?: [KONet errorWithText:L(@"Mojang's list of versions is not readable.")]));
    }];
}

@end
