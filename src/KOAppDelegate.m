#import "KOAppDelegate.h"
#import "KOVersionListController.h"
#import "KOProbeController.h"
#import "KOStyle.h"
#import "KOJava.h"
#import "KOCommon.h"
#include <dlfcn.h>

// The launcher: the versions of Minecraft from Mojang's list (KOVersionListController), each one's screen with the
// button that downloads and starts it. For tests from a computer, links:
//   kostka:probe?test=info|jit|jitwx|vm|mem|gl|cpu      the device test
//   kostka:java?main=Hello[&cp=a.jar:/var/x.jar][&xmx=96m][&debug=1]   a Java program (jars of the bundle, or from /)
//   kostka:screenshot                                    the screen into Library/Kostka/screen.png
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
        [KOJava runMainClass:p[@"main"] ?: @"Hello" classPath:cp options:options args:@[]
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
    return YES;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    KOLog(@"memory warning");
}

@end
