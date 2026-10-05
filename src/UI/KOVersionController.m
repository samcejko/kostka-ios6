#import "KOVersionController.h"
#import "KOGame.h"
#import "KOStyle.h"
#import "KOCommon.h"

@interface KOVersionController ()
@property (nonatomic, strong) KOVersion *version;
@property (nonatomic, strong) UIButton *play;
@property (nonatomic, strong) UIProgressView *progress;
@property (nonatomic, strong) UILabel *status;
@end

@implementation KOVersionController

- (id)initWithVersion:(KOVersion *)version
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.version = version;
        self.title = version.identifier;
    }
    return self;
}

- (NSString *)explanation
{
    KOVersion *v = self.version;
    switch (v.support) {
        case KOSupportPlays:
            return L(@"RubyDung: the very first Minecraft, from May 2009. One world of grass and stone to build in. Move a finger to look around, tap to take a block away, hold a finger down to put one. The arrows walk, Jump jumps, Esc ends the game (and closes Kostka: open it again to play once more).");
        case KOSupportSoon:
            return L(@"Kostka does not run this version yet. Everything up to 1.12.2 is its aim: Classic to 1.5.2 still need Java's window toolkit (AWT), which Kostka does not have yet, the newer ones more memory than Kostka gives the game now.");
        default:
            return L(@"This version needs LWJGL 3 and newer OpenGL and Java than Kostka has: more than iOS 6 and this iPad can give.");
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIView *v = self.view;
    v.backgroundColor = [KOStyle dirtColor];
    CGFloat w = v.bounds.size.width, m = 40;

    UILabel *name = [KOStyle labelWithFont:[UIFont boldSystemFontOfSize:40]];
    name.frame = CGRectMake(m, 30, w - 2 * m, 50);
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    name.text = self.version.identifier;
    [v addSubview:name];

    UILabel *date = [KOStyle labelWithFont:[UIFont systemFontOfSize:18]];
    date.frame = CGRectMake(m, 84, w - 2 * m, 24);
    date.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    date.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    date.text = [NSString stringWithFormat:L(@"Released %@"), self.version.localizedReleased];
    [v addSubview:date];

    UILabel *support = [KOStyle labelWithFont:[UIFont boldSystemFontOfSize:20]];
    support.frame = CGRectMake(m, 120, w - 2 * m, 26);
    support.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    support.text = self.version.localizedSupport;
    support.textColor = self.version.support == KOSupportPlays ? [UIColor colorWithRed:0.6 green:1 blue:0.45 alpha:1]
                      : self.version.support == KOSupportSoon ? [UIColor colorWithWhite:0.8 alpha:1]
                                                              : [UIColor colorWithRed:1 green:0.55 blue:0.45 alpha:1];
    [v addSubview:support];

    UILabel *text = [KOStyle labelWithFont:[UIFont systemFontOfSize:18]];
    text.numberOfLines = 0;
    text.text = [self explanation];
    CGSize size = [text.text sizeWithFont:text.font constrainedToSize:CGSizeMake(w - 2 * m, 400) lineBreakMode:NSLineBreakByWordWrapping];
    text.frame = CGRectMake(m, 160, w - 2 * m, size.height);
    text.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:text];

    CGFloat y = 160 + size.height + 30;
    self.play = [KOStyle bigButton:L(@"Play")];
    self.play.frame = CGRectMake(m, y, 260, 56);
    self.play.enabled = self.version.support == KOSupportPlays ||
                        (self.version.support == KOSupportSoon && [[NSUserDefaults standardUserDefaults] boolForKey:@"KOTryAll"]);
    [self.play addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:self.play];

    self.progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.progress.frame = CGRectMake(m, y + 76, 400, 10);
    self.progress.hidden = YES;
    [v addSubview:self.progress];

    self.status = [KOStyle labelWithFont:[UIFont systemFontOfSize:16]];
    self.status.frame = CGRectMake(m, y + 94, w - 2 * m, 22);
    self.status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:self.status];
}

- (void)playTapped
{
    self.play.enabled = NO;
    self.navigationItem.hidesBackButton = YES;
    self.progress.hidden = NO;
    self.progress.progress = 0;
    __weak KOVersionController *weakSelf = self;
    [KOGame play:self.version status:^(NSString *text, float fraction) {
        weakSelf.status.text = text;
        if (fraction >= 0) weakSelf.progress.progress = fraction;
    } failed:^(NSError *error) {
        KOVersionController *s = weakSelf;
        s.play.enabled = YES;
        s.navigationItem.hidesBackButton = NO;
        s.progress.hidden = YES;
        s.status.text = nil;
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:L(@"The game could not start") message:error.localizedDescription
                                                       delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil];
        [alert show];
    }];
}

@end
