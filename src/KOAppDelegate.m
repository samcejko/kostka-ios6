#import "KOAppDelegate.h"
#import "KOVersionListController.h"
#import "KOProbeController.h"
#import "KOVersions.h"
#import "KOGame.h"
#import "KOStyle.h"
#import "KOJava.h"
#import "KOCommon.h"
#include <dlfcn.h>

// The launcher: the versions of Minecraft from Mojang's list (KOVersionListController), each one's screen with the
// button that downloads and starts it. For tests from a computer, links:
//   kostka:probe?test=info|jit|jitwx|vm|mem|gl|cpu      the device test
//   kostka:java?main=Hello[&cp=a.jar:/var/x.jar][&xmx=96m][&debug=1][&args=a,b]   a Java program (jars of the bundle,
//                                                        or from /; args: its arguments)
//   kostka:screenshot                                    the screen into Library/Kostka/screen.png
//   kostka:play?version=1.7.10[&gldebug=1]               downloads and starts a version (any, for tests; gldebug: LWJGL
//                                                        stops the game at the first OpenGL call that fails;
//                                                        jvm=-Xa,-Xb: more VM options; env=NAME:value,...)
//   kostka:mouse?x=&y=[&button=] / key?code=[&char=] / text?s=   input for the running game
@interface KOAppDelegate ()
@property (nonatomic, strong, readwrite) KOProbeController *probe;
@end

@implementation KOAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    KOLog(@"Kostka %@ starting", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.probe = [[KOProbeController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[KOVersionListController alloc] init]];
    [KOStyle styleNavigationBar:nav.navigationBar];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if (![[url.scheme lowercaseString] isEqualToString:@"kostka"]) return NO;
    // ("kostka:probe?test=jit" has no host and, for NSURL, no query: both are read from what follows the scheme)
    NSString *rest = [url.resourceSpecifier stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    NSRange q = [rest rangeOfString:@"?"];
    NSString *target = [(q.location == NSNotFound ? rest : [rest substringToIndex:q.location]) lowercaseString];
    NSString *query = q.location == NSNotFound ? @"" : [rest substringFromIndex:q.location + 1];
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2) p[kv[0]] = [kv[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }
    if ([target isEqualToString:@"java"]) {
        NSString *bundle = [NSBundle mainBundle].bundlePath;
        NSMutableArray *cp = [NSMutableArray array];
        for (NSString *part in [p[@"cp"] ?: @"test/hello.jar" componentsSeparatedByString:@":"]) {
            if (part.length) [cp addObject:[part hasPrefix:@"/"] ? part : [bundle stringByAppendingPathComponent:part]];
        }
        // (LWJGL's native library is the bundle's, lwjgl/; debug=1 turns on LWJGL's log)
        NSMutableArray *options = [NSMutableArray arrayWithObjects:
            [@"-Xmx" stringByAppendingString:p[@"xmx"] ?: @"96m"],
            [@"-Dorg.lwjgl.librarypath=" stringByAppendingString:[bundle stringByAppendingPathComponent:@"lwjgl"]], nil];
        if ([p[@"debug"] isEqualToString:@"1"]) [options addObject:@"-Dorg.lwjgl.util.Debug=true"];
        [self.probe append:[NSString stringWithFormat:@"> java %@", p[@"main"] ?: @"Hello"]];
        __weak KOAppDelegate *weakSelf = self;
        NSArray *args = p[@"args"] ? [p[@"args"] componentsSeparatedByString:@","] : @[];
        [KOJava runMainClass:p[@"main"] ?: @"Hello" classPath:cp options:options args:args
                        done:^(int code, NSString *error) {
            [weakSelf.probe append:[NSString stringWithFormat:@"java: exit %d %@", code, error ?: @""]];
        }];
        return YES;
    }
    // (UIGetScreenImage: a private UIKit function, looked up at run time; the game's OpenGL is in the picture too)
    if ([target isEqualToString:@"screenshot"]) {
        CGImageRef (*grab)(void) = (CGImageRef (*)(void))dlsym(RTLD_DEFAULT, "UIGetScreenImage");
        CGImageRef image = grab ? grab() : NULL;
        if (image) {
            NSData *png = UIImagePNGRepresentation([UIImage imageWithCGImage:image]);
            [png writeToFile:[[KOJava dataPath] stringByAppendingPathComponent:@"screen.png"] atomically:YES];
            CGImageRelease(image);
        }
        KOLog(@"screenshot %@", image ? @"saved" : @"not available");
        return YES;
    }
    if ([target isEqualToString:@"probe"]) {
        [self.probe enqueue:p[@"test"] ?: @"info"];
    }
    // Input for the running game, as touches and keys would give it (LWJGL's events, ios_display.m):
    //   kostka:mouse?x=512&y=400[&button=0]   moves the mouse (from the bottom left), clicks if a button is given
    //   kostka:key?code=28[&char=13]           a key down and up (LWJGL's key codes)
    //   kostka:text?s=Svet                     characters, as typed
    if ([target isEqualToString:@"mouse"] || [target isEqualToString:@"key"] || [target isEqualToString:@"text"]) {
        void (*post)(int, int, int, int) = (void (*)(int, int, int, int))dlsym(RTLD_DEFAULT, "ko_post_event");
        if (!post) {
            KOLog(@"input: no game running");
            return YES;
        }
        if ([target isEqualToString:@"mouse"]) {
            post(1, [p[@"x"] intValue], [p[@"y"] intValue], 0);
            if (p[@"button"]) {
                // (held 0.15 s, as a finger: Minecraft's lists drop a click whose button is up when they draw)
                int b = [p[@"button"] intValue];
                post(3, b, 1, 0);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    post(3, b, 0, 0);
                });
            }
        } else if ([target isEqualToString:@"key"]) {
            post(5, [p[@"code"] intValue], 1, [p[@"char"] intValue]);
            post(5, [p[@"code"] intValue], 0, 0);
        } else {
            NSString *s = p[@"s"] ?: @"";
            for (NSUInteger i = 0; i < s.length; i++) {
                post(5, 0, 1, [s characterAtIndex:i]);
                post(5, 0, 0, 0);
            }
        }
        return YES;
    }
    // kostka:play?version=1.7.10: downloads and starts a version, whether it runs here or not yet (for tests)
    if ([target isEqualToString:@"play"] && p[@"version"]) {
        [KOGame setDebugGL:[p[@"gldebug"] isEqualToString:@"1"]];
        // (jvm=-XX:Foo=1,-Dbar=2: more options for the VM; env=LIBGL_FOO:1,BAR:2 - gl4es's settings, for instance)
        [KOGame setExtraOptions:p[@"jvm"] ? [p[@"jvm"] componentsSeparatedByString:@","] : nil];
        for (NSString *pair in p[@"env"] ? [p[@"env"] componentsSeparatedByString:@","] : @[]) {
            NSRange colon = [pair rangeOfString:@":"];
            if (colon.location != NSNotFound)
                setenv([[pair substringToIndex:colon.location] UTF8String], [[pair substringFromIndex:colon.location + 1] UTF8String], 1);
        }
        [KOVersions load:^(NSArray *versions, NSError *error) {
            for (KOVersion *v in versions) {
                if (![v.identifier isEqualToString:p[@"version"]]) continue;
                [KOJava note:@"play %@", v.identifier];
                [KOGame play:v status:^(NSString *text, float progress) {
                    KOLog(@"play %@: %@ %.0f%%", v.identifier, text, progress * 100);
                } failed:^(NSError *e) {
                    KOLog(@"play %@ failed: %@", v.identifier, e.localizedDescription);
                    [KOJava note:@"failed %@", e.localizedDescription];
                }];
                return;
            }
            KOLog(@"play: no version %@ (%@)", p[@"version"], error.localizedDescription ?: @"");
            [KOJava note:@"failed no version %@", p[@"version"]];
        }];
    }
    return YES;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    KOLog(@"memory warning (%d MB in use)", [KOJava memoryInUse]);
}

@end
