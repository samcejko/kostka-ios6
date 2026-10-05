#import <UIKit/UIKit.h>
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

+ (NSArray *)arguments:(NSDictionary *)json version:(KOVersion *)version gameDir:(NSString *)gameDir gameAssets:(NSString *)gameAssets
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
        @"game_assets": gameAssets ?: assets,
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
    // (1.6 and newer take the window's size: the whole screen, in pixels)
    if ([args containsObject:@"--username"]) {
        CGSize s = [UIScreen mainScreen].bounds.size;
        CGFloat scale = [UIScreen mainScreen].scale;
        [args addObjectsFromArray:@[ @"--width", [NSString stringWithFormat:@"%d", (int)(MAX(s.width, s.height) * scale)],
                                     @"--height", [NSString stringWithFormat:@"%d", (int)(MIN(s.width, s.height) * scale)] ]];
    }
    return args;
}

+ (BOOL)isRubyDung:(NSDictionary *)json
{
    return [json[@"mainClass"] hasSuffix:@"RubyDung"];
}

// The assets (sounds, languages: 1.6 and newer read them from outside the jar): Mojang's index of them, then each
// file by its hash into assets/objects, four at a time. The old indexes want them under their names too: "legacy"
// in assets/virtual/legacy, "pre-1.6" in the game's resources folder. `done` gets the folder the game reads them from.
+ (void)assets:(NSDictionary *)json gameDir:(NSString *)gameDir status:(void (^)(NSString *, float))status
          done:(void (^)(NSString *gameAssets, NSError *error))done
{
    NSDictionary *index = json[@"assetIndex"];
    NSString *assets = [self dir:@"assets"];
    if (![index isKindOfClass:[NSDictionary class]] || !index[@"url"] || !index[@"id"] || [self isRubyDung:json]) {
        done(assets, nil);
        return;
    }
    NSString *indexPath = [[self dir:@"assets/indexes"] stringByAppendingPathComponent:[index[@"id"] stringByAppendingPathExtension:@"json"]];
    status(L(@"Downloading the sounds and languages"), -1);
    [KONet download:[NSURL URLWithString:index[@"url"]] to:indexPath sha1:index[@"sha1"] progress:nil done:^(NSError *error) {
        if (error) { done(nil, error); return; }
        NSData *data = [NSData dataWithContentsOfFile:indexPath];
        NSDictionary *list = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *objects = [list isKindOfClass:[NSDictionary class]] ? list[@"objects"] : nil;
        if (![objects isKindOfClass:[NSDictionary class]]) {
            done(nil, [KONet errorWithText:L(@"Mojang's description of the version is not readable.")]);
            return;
        }
        NSString *named = nil;
        if ([list[@"virtual"] boolValue]) named = [self dir:[@"assets/virtual" stringByAppendingPathComponent:index[@"id"]]];
        else if ([list[@"map_to_resources"] boolValue]) named = [gameDir stringByAppendingPathComponent:@"resources"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *missing = [NSMutableArray array];
        NSMutableArray *names = [NSMutableArray array];
        // (the sounds and the music are most of it, 100 MB and more: only when asked for in the settings)
        BOOL sounds = [[NSUserDefaults standardUserDefaults] boolForKey:@"KOSounds"];
        for (NSString *name in objects) {
            if (!sounds && [[name pathExtension] isEqualToString:@"ogg"]) continue;
            NSDictionary *o = objects[name];
            NSString *hash = o[@"hash"];
            if (![hash isKindOfClass:[NSString class]] || hash.length < 2) continue;
            NSString *path = [NSString stringWithFormat:@"%@/objects/%@/%@", assets, [hash substringToIndex:2], hash];
            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
            if (!attrs || [attrs fileSize] != [o[@"size"] unsignedLongLongValue]) {
                NSString *url = [NSString stringWithFormat:@"https://resources.download.minecraft.net/%@/%@", [hash substringToIndex:2], hash];
                [missing addObject:@{ @"url": url, @"sha1": hash, @"to": path }];
            }
            if (named) [names addObject:@[ path, [named stringByAppendingPathComponent:name] ]];
        }
        [self fetchMany:missing what:L(@"Downloading the sounds and languages") status:status done:^(NSError *e) {
            if (e) { done(nil, e); return; }
            for (NSArray *pair in names) {
                if ([fm fileExistsAtPath:pair[1]]) continue;
                [fm createDirectoryAtPath:[pair[1] stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
                if (![fm linkItemAtPath:pair[0] toPath:pair[1] error:NULL]) [fm copyItemAtPath:pair[0] toPath:pair[1] error:NULL];
            }
            done(named ?: assets, nil);
        }];
    }];
}

// Many files, four at a time
+ (void)fetchMany:(NSArray *)files what:(NSString *)what status:(void (^)(NSString *, float))status done:(void (^)(NSError *))done
{
    NSUInteger total = files.count;
    if (!total) {
        done(nil);
        return;
    }
    __block NSUInteger next = 0, finished = 0;
    __block BOOL over = NO;
    __block void (^one)(void);
    one = ^{
        if (over || next >= total) return;
        NSDictionary *f = files[next++];
        [KONet download:[NSURL URLWithString:f[@"url"]] to:f[@"to"] sha1:f[@"sha1"] progress:nil done:^(NSError *e) {
            if (over) return;
            if (e) {
                over = YES;
                one = nil;   // (the block held itself: let it go)
                done(e);
                return;
            }
            finished++;
            status(what, (float)finished / total);
            if (finished == total) {
                over = YES;
                one = nil;
                done(nil);
                return;
            }
            if (one) one();
        }];
    };
    for (int i = 0; i < 4; i++) one();
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

        NSString *gameDir = [self dir:[@"games" stringByAppendingPathComponent:version.identifier]];
        [self fetch:files index:0 status:status done:^(NSError *e) {
            if (e) { fail(e); return; }
            [self assets:json gameDir:gameDir status:status done:^(NSString *gameAssets, NSError *e2) {
                if (e2) { fail(e2); return; }
                [self start:version json:json classPath:classPath gameDir:gameDir gameAssets:gameAssets status:status failed:fail];
            }];
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

+ (void)start:(KOVersion *)version json:(NSDictionary *)json classPath:(NSArray *)classPath gameDir:(NSString *)gameDir
   gameAssets:(NSString *)gameAssets status:(void (^)(NSString *, float))status failed:(void (^)(NSError *))failed
{
    NSArray *args = [self arguments:json version:version gameDir:gameDir gameAssets:gameAssets];
    // (the first start of 1.6 and newer: settings the iPad can carry - the shortest view, plain graphics - and the
    // device's language; the game keeps what the player changes later. Each version reads the keys it knows.)
    NSString *optionsFile = [gameDir stringByAppendingPathComponent:@"options.txt"];
    if ([args containsObject:@"--username"] && ![[NSFileManager defaultManager] fileExistsAtPath:optionsFile]) {
        NSArray *languages = [NSLocale preferredLanguages];
        NSString *lang = languages.count && [languages[0] hasPrefix:@"cs"] ? @"cs_CZ" : @"en_US";
        NSString *text = [NSString stringWithFormat:@"viewDistance:3\nrenderDistance:2\nfancyGraphics:false\nao:0\nclouds:false\n"
                          @"renderClouds:false\nparticles:2\nmipmapLevels:0\nuseVbo:true\nlang:%@\n", lang];
        [text writeToFile:optionsFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    NSString *lwjgl = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"lwjgl"];
    // (the heap: what RubyDung needs, for the others what the iPad's 512 MB leave with the textures and the VM)
    NSArray *options = @[
        [self isRubyDung:json] ? @"-Xmx128m" : @"-Xmx192m",
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
