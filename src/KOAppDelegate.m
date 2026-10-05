#import "KOAppDelegate.h"
#import "KOProbe.h"
#import "KOCommon.h"

// For now the app is the device test of the first milestone: what this iPad allows a Java VM. The tests run from
// the screen's button (all of them but the memory test, which ends with the app killed) or one by one from a link:
// kostka:probe?test=info|jit|jitwx|vm|mem|gl|cpu
@interface KOAppDelegate ()
@property (nonatomic, strong) UITextView *log;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) NSMutableArray *queue;
@property (nonatomic) BOOL running;
@end

@implementation KOAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    KOLog(@"Kostka %@ starting", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *root = [[UIViewController alloc] init];
    UIView *v = root.view;
    v.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 16, v.bounds.size.width - 40, 34)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.backgroundColor = [UIColor clearColor];
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:24];
    title.text = L(@"Device test");
    [v addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, v.bounds.size.width - 40, 20)];
    sub.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    sub.backgroundColor = [UIColor clearColor];
    sub.textColor = [UIColor colorWithWhite:0.7 alpha:1];
    sub.font = [UIFont systemFontOfSize:14];
    sub.text = L(@"What this device allows a Java VM: generated code, memory, graphics, speed.");
    [v addSubview:sub];

    self.runButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.runButton.frame = CGRectMake(v.bounds.size.width - 180, 18, 160, 36);
    self.runButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.runButton setTitle:L(@"Run the tests") forState:UIControlStateNormal];
    [self.runButton addTarget:self action:@selector(runAll) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:self.runButton];

    self.log = [[UITextView alloc] initWithFrame:CGRectMake(12, 80, v.bounds.size.width - 24, v.bounds.size.height - 92)];
    self.log.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.log.backgroundColor = [UIColor blackColor];
    self.log.textColor = [UIColor colorWithRed:0.6 green:1 blue:0.6 alpha:1];
    self.log.font = [UIFont fontWithName:@"Courier" size:13];
    self.log.editable = NO;
    [v addSubview:self.log];

    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];
    self.queue = [NSMutableArray array];
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
    if ([target isEqualToString:@"probe"]) {
        NSString *test = @"info";
        for (NSString *pair in [query componentsSeparatedByString:@"&"]) {
            NSArray *kv = [pair componentsSeparatedByString:@"="];
            if (kv.count == 2 && [kv[0] isEqualToString:@"test"]) test = kv[1];
        }
        [self.queue addObject:test];
        [self next];
    }
    return YES;
}

- (void)runAll
{
    for (NSString *t in [KOProbe testNames]) if (![t isEqualToString:@"mem"]) [self.queue addObject:t];
    [self next];
}

- (void)append:(NSString *)line
{
    self.log.text = self.log.text.length ? [self.log.text stringByAppendingFormat:@"\n%@", line] : line;
    [self.log scrollRangeToVisible:NSMakeRange(self.log.text.length, 0)];
}

- (void)next
{
    if (self.running || !self.queue.count) return;
    NSString *test = self.queue[0];
    [self.queue removeObjectAtIndex:0];
    self.running = YES;
    self.runButton.enabled = NO;
    [self append:[NSString stringWithFormat:@"> %@", test]];
    __weak KOAppDelegate *weakSelf = self;
    [KOProbe run:test output:^(NSString *line) {
        [weakSelf append:line];
    } done:^{
        KOAppDelegate *s = weakSelf;
        s.running = NO;
        s.runButton.enabled = YES;
        [s next];
    }];
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    KOLog(@"probe memory warning");
}

@end
