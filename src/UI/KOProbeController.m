#import "KOProbeController.h"
#import "KOProbe.h"
#import "KOStyle.h"
#import "KOCommon.h"

@interface KOProbeController ()
@property (nonatomic, strong) UITextView *log;
@property (nonatomic, strong) NSMutableString *text;
@property (nonatomic, strong) NSMutableArray *queue;
@property (nonatomic) BOOL running;
@end

@implementation KOProbeController

- (id)init
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.title = L(@"Device test");
        self.text = [NSMutableString string];
        self.queue = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIView *v = self.view;
    v.backgroundColor = [KOStyle dirtColor];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Run the tests") style:UIBarButtonItemStyleBordered
                                                                             target:self action:@selector(runAll)];
    UILabel *sub = [KOStyle labelWithFont:[UIFont systemFontOfSize:15]];
    sub.frame = CGRectMake(20, 12, v.bounds.size.width - 40, 22);
    sub.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    sub.text = L(@"What this device allows a Java VM: generated code, memory, graphics, speed.");
    [v addSubview:sub];

    self.log = [[UITextView alloc] initWithFrame:CGRectMake(12, 44, v.bounds.size.width - 24, v.bounds.size.height - 56)];
    self.log.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.log.backgroundColor = [UIColor blackColor];
    self.log.textColor = [UIColor colorWithRed:0.6 green:1 blue:0.6 alpha:1];
    self.log.font = [UIFont fontWithName:@"Courier" size:13];
    self.log.editable = NO;
    self.log.text = self.text;
    [v addSubview:self.log];
}

- (void)append:(NSString *)line
{
    if (self.text.length) [self.text appendString:@"\n"];
    [self.text appendString:line];
    if (self.isViewLoaded) {
        self.log.text = self.text;
        [self.log scrollRangeToVisible:NSMakeRange(self.text.length, 0)];
    }
}

- (void)runAll
{
    // (all but the memory test, which ends with the app killed: that one only from a link)
    for (NSString *t in [KOProbe testNames]) if (![t isEqualToString:@"mem"]) [self.queue addObject:t];
    [self next];
}

- (void)enqueue:(NSString *)test
{
    [self.queue addObject:test];
    [self next];
}

- (void)next
{
    if (self.running || !self.queue.count) return;
    NSString *test = self.queue[0];
    [self.queue removeObjectAtIndex:0];
    self.running = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self append:[NSString stringWithFormat:@"> %@", test]];
    __weak KOProbeController *weakSelf = self;
    [KOProbe run:test output:^(NSString *line) {
        [weakSelf append:line];
    } done:^{
        KOProbeController *s = weakSelf;
        s.running = NO;
        s.navigationItem.rightBarButtonItem.enabled = YES;
        [s next];
    }];
}

@end
