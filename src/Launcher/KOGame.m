#import "KOGame.h"
#import "KONet.h"
#import "KOJava.h"
#import "KOCommon.h"

static BOOL g_running;

@implementation KOGame

+ (BOOL)isRunning
{
    return g_running;
}

+ (NSString *)playerName
{
    NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:@"KOPlayerName"];
    return name.length ? name : @"Player";
}

+ (void)setPlayerName:(NSString *)name
{
    [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"KOPlayerName"];
}

+ (NSString *)dir:(NSString *)name
{
    NSString *p = [[KOJava dataPath] stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:NULL];
    return p;
}

// A library is for this device unless its rules say otherwise (Kostka counts as "osx", as iOS calls itself Mac OS X)
+ (BOOL)allowed:(NSDictionary *)library
{
    NSArray *rules = library[@"rules"];
    if (![rules isKindOfClass:[NSArray class]] || !rules.count) return YES;
    BOOL allowed = NO;
    for (NSDictionary *rule in rules) {
        NSDictionary *os = rule[@"os"];
        if ([os isKindOfClass:[NSDictionary class]] && os[@"name"] && ![os[@"name"] isEqualToString:@"osx"]) continue;
        allowed = [rule[@"action"] isEqualToString:@"allow"];
    }
    return allowed;
}

// The libraries to fetch: the game's Java ones. Not LWJGL (Kostka has its own, for iOS), not JInput (no game
// controllers), not the native ones (for other systems).
+ (NSArray *)libraries:(NSDictionary *)json
{
    NSMutableArray *list = [NSMutableArray array];
    for (NSDictionary *lib in json[@"libraries"]) {
        if (![lib isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = lib[@"name"];
        if ([name hasPrefix:@"org.lwjgl"] || [name hasPrefix:@"net.java.jinput"] || [name hasPrefix:@"net.java.jutils"]) continue;
        if (lib[@"natives"] || ![self allowed:lib]) continue;
        NSDictionary *artifact = lib[@"downloads"][@"artifact"];
        if (![artifact isKindOfClass:[NSDictionary class]] || !artifact[@"url"] || !artifact[@"path"]) continue;
        [list addObject:artifact];
    }
    return list;
}

+ (NSArray *)arguments:(NSDictionary *)json version:(KOVersion *)version gameDir:(NSString *)gameDir
{
    NSArray *words;
    if ([json[@"minecraftArguments"] isKindOfClass:[NSString class]]) {
        words = [json[@"minecraftArguments"] componentsSeparatedByString:@" "];
    } else {
        NSMutableArray *plain = [NSMutableArray array];
        for (id a in json[@"arguments"][@"game"]) if ([a isKindOfClass:[NSString class]]) [plain addObject:a];
        words = plain;
    }
    NSString *assets = [self dir:@"assets"];
    NSDictionary *values = @{
        @"auth_player_name": [self playerName],
        @"auth_session": @"-",
        @"auth_uuid": @"00000000000000000000000000000000",
        @"auth_access_token": @"-",
        @"user_properties": @"{}",
        @"user_type": @"legacy",
        @"version_name": version.identifier,
        @"version_type": version.type ?: @"release",
        @"game_directory": gameDir,
        @"game_assets": assets,
        @"assets_root": assets,
        @"assets_index_name": json[@"assets"] ?: @"legacy",
    };
    NSMutableArray *args = [NSMutableArray array];
    for (NSString *w in words) {
        if (!w.length) continue;
        if ([w hasPrefix:@"${"] && [w hasSuffix:@"}"]) {
            NSString *key = [w substringWithRange:NSMakeRange(2, w.length - 3)];
            [args addObject:values[key] ?: @""];
        } else {
            [args addObject:w];
        }
    }
    return args;
}

+ (void)play:(KOVersion *)version status:(void (^)(NSString *, float))status failed:(void (^)(NSError *))failed
{
    if (g_running) {
        failed([KONet errorWithText:L(@"Java has already run since the app was opened: close the app and open it again.")]);
        return;
    }
    g_running = YES;
    void (^fail)(NSError *) = ^(NSError *e) {
        g_running = NO;
        failed(e);
    };
    NSString *versionDir = [[KOVersions versionsPath] stringByAppendingPathComponent:version.identifier];
    NSString *jsonPath = [versionDir stringByAppendingPathComponent:[version.identifier stringByAppendingPathExtension:@"json"]];
    status(L(@"Asking Mojang about the version"), -1);
    [KONet download:[NSURL URLWithString:version.url] to:jsonPath sha1:version.sha1 progress:nil done:^(NSError *error) {
        if (error) { fail(error); return; }
        NSData *data = [NSData dataWithContentsOfFile:jsonPath];
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *client = [json isKindOfClass:[NSDictionary class]] ? json[@"downloads"][@"client"] : nil;
        if (![client isKindOfClass:[NSDictionary class]] || !json[@"mainClass"]) {
            fail([KONet errorWithText:L(@"Mojang's description of the version is not readable.")]);
            return;
        }
        // the game, then its libraries, one after the other
        NSMutableArray *files = [NSMutableArray array];
        NSString *jar = [versionDir stringByAppendingPathComponent:[version.identifier stringByAppendingPathExtension:@"jar"]];
        [files addObject:@{ @"url": client[@"url"], @"sha1": client[@"sha1"] ?: @"", @"to": jar, @"what": L(@"Downloading the game") }];
        NSString *libDir = [self dir:@"libraries"];
        NSMutableArray *classPath = [NSMutableArray array];
        for (NSDictionary *a in [self libraries:json]) {
            NSString *to = [libDir stringByAppendingPathComponent:a[@"path"]];
            [files addObject:@{ @"url": a[@"url"], @"sha1": a[@"sha1"] ?: @"", @"to": to, @"what": L(@"Downloading the libraries") }];
            [classPath addObject:to];
        }
        [classPath addObject:jar];
        NSString *lwjgl = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"lwjgl"];
        [classPath addObject:[lwjgl stringByAppendingPathComponent:@"lwjgl.jar"]];
        [classPath addObject:[lwjgl stringByAppendingPathComponent:@"lwjgl_util.jar"]];

        [self fetch:files index:0 status:status done:^(NSError *e) {
            if (e) { fail(e); return; }
            [self start:version json:json classPath:classPath status:status failed:fail];
        }];
    }];
}

// The files one after the other
+ (void)fetch:(NSArray *)files index:(NSUInteger)index status:(void (^)(NSString *, float))status done:(void (^)(NSError *))done
{
    if (index == files.count) {
        done(nil);
        return;
    }
    NSDictionary *f = files[index];
    status(f[@"what"], (float)index / files.count);
    [KONet download:[NSURL URLWithString:f[@"url"]] to:f[@"to"] sha1:f[@"sha1"]
           progress:^(long long received, long long expected) {
               float part = expected > 0 ? (float)received / expected : 0;
               status(f[@"what"], (index + part) / files.count);
           } done:^(NSError *e) {
               if (e) { done(e); return; }
               [self fetch:files index:index + 1 status:status done:done];
           }];
}

+ (void)start:(KOVersion *)version json:(NSDictionary *)json classPath:(NSArray *)classPath
       status:(void (^)(NSString *, float))status failed:(void (^)(NSError *))failed
{
    NSString *gameDir = [self dir:[@"games" stringByAppendingPathComponent:version.identifier]];
    NSArray *args = [self arguments:json version:version gameDir:gameDir];
    NSString *lwjgl = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"lwjgl"];
    NSArray *options = @[
        @"-Xmx160m",
        [@"-Dorg.lwjgl.librarypath=" stringByAppendingString:lwjgl],
        @"-Dminecraft.launcher.brand=Kostka",
    ];
    status(L(@"Starting Java"), -1);
    KOLog(@"play %@: %@ %@", version.identifier, json[@"mainClass"], [args componentsJoinedByString:@" "]);
    [KOJava runMainClass:json[@"mainClass"] classPath:classPath options:options args:args workingDirectory:gameDir
                    done:^(int code, NSString *error) {
        // (the game has ended: one Java VM per process, so Kostka closes too and is opened again for the next one)
        KOLog(@"game ended: %d %@", code, error ?: @"");
        if (error) {
            failed([KONet errorWithText:error]);
            return;
        }
        exit(0);
    }];
}

@end
