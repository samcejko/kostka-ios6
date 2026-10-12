#import "KOVersionController.h"
#import "KOGame.h"
#import "KOChangelog.h"
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
        self.title = version.parent ? [NSString stringWithFormat:@"%@ OptiFine", version.parent.identifier] : version.identifier;
    }
    return self;
}

// What the page says about the version besides what is new in it: nothing for one that plays here (OptiFine's and
// RubyDung's few words aside), else why it does not or may not
- (NSString *)explanation
{
    KOVersion *v = self.version;
    if ([v.identifier hasPrefix:@"rd-"])
        return L(@"RubyDung: the very first Minecraft, from May 2009. One world of grass and stone to build in. Move a finger to look around, tap to take a block away, hold a finger down to put one. The arrows walk, Jump jumps, Esc ends the game (and closes Kostka: open it again to play once more).");
    if (v.parent)
        return [NSString stringWithFormat:L(@"OptiFine %@ for Minecraft %@: faster, with more settings (Options, Video Settings). It plays in the same worlds as %@."),
                v.optiFineEdition, v.parent.identifier, v.parent.identifier];
    switch (v.support) {
        case KOSupportPlays:
            return nil;
        case KOSupportTry:
            return L(@"Not tried on an iPad yet: the versions of its time play on Kostka, so this one most likely does too.");
        case KOSupportSoon:
            return [NSString stringWithFormat:L(@"Kostka does not run this version yet: %@"), v.problem];
        default:
            return L(@"This version needs LWJGL 3 and newer OpenGL and Java than Kostka has: more than iOS 6 and this iPad can give.");
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIView *v = self.view;
    v.backgroundColor = [KOStyle dirtColor];
    CGFloat w = v.bounds.size.width, h = v.bounds.size.height, m = 40;

    KOVersion *version = self.version;
    UILabel *name = [KOStyle labelWithFont:[UIFont boldSystemFontOfSize:40]];
    name.frame = CGRectMake(m, 24, w - 2 * m, 50);
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    name.adjustsFontSizeToFitWidth = YES;
    name.text = version.parent ? [NSString stringWithFormat:@"%@  OptiFine %@", version.parent.identifier, version.optiFineEdition]
                               : version.identifier;
    [v addSubview:name];

    UILabel *date = [KOStyle labelWithFont:[UIFont systemFontOfSize:18]];
    date.frame = CGRectMake(m, 76, w - 2 * m, 24);
    date.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    date.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    date.text = [NSString stringWithFormat:L(@"Released %@"), version.localizedReleased];
    [v addSubview:date];

    CGFloat y = 112;
    NSString *why = [self explanation];
    if (version.support != KOSupportPlays) {
        UILabel *support = [KOStyle labelWithFont:[UIFont boldSystemFontOfSize:20]];
        support.frame = CGRectMake(m, y, w - 2 * m, 26);
        support.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        support.text = version.localizedSupport;
        support.textColor = version.support == KOSupportTry ? [UIColor colorWithRed:1 green:0.75 blue:0.3 alpha:1]
                          : version.support == KOSupportSoon ? [UIColor colorWithWhite:0.8 alpha:1]
                                                             : [UIColor colorWithRed:1 green:0.55 blue:0.45 alpha:1];
        [v addSubview:support];
        y += 34;
    }
    if (why) {
        UILabel *text = [KOStyle labelWithFont:[UIFont systemFontOfSize:18]];
        text.numberOfLines = 0;
        text.text = why;
        CGSize size = [why sizeWithFont:text.font constrainedToSize:CGSizeMake(w - 2 * m, 400) lineBreakMode:NSLineBreakByWordWrapping];
        text.frame = CGRectMake(m, y, w - 2 * m, size.height);
        text.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [v addSubview:text];
        y += size.height + 16;
    }

    self.play = [KOStyle bigButton:L(@"Play")];
    self.play.frame = CGRectMake(m, y, 260, 56);
    self.play.enabled = version.support == KOSupportPlays || version.support == KOSupportTry ||
                        (version.support == KOSupportSoon && [[NSUserDefaults standardUserDefaults] boolForKey:@"KOTryAll"]);
    [self.play addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [v addSubview:self.play];

    // (what happens after a tap on Play: beside the button)
    self.progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.progress.frame = CGRectMake(m + 290, y + 14, MIN(400, w - 2 * m - 290), 10);
    self.progress.hidden = YES;
    [v addSubview:self.progress];
    self.status = [KOStyle labelWithFont:[UIFont systemFontOfSize:16]];
    self.status.frame = CGRectMake(m + 290, y + 30, w - 2 * m - 290, 22);
    self.status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:self.status];
    y += 56 + 24;

    // what is new in the version (in its parent, for OptiFine's): the Minecraft Wiki's page
    UILabel *heading = [KOStyle labelWithFont:[UIFont boldSystemFontOfSize:20]];
    heading.frame = CGRectMake(m, y, w - 2 * m, 26);
    heading.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    heading.text = L(@"What is new");
    [v addSubview:heading];
    y += 32;
    UILabel *source = [KOStyle labelWithFont:[UIFont systemFontOfSize:13]];
    source.frame = CGRectMake(m, h - 30, w - 2 * m, 20);
    source.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    source.textColor = [UIColor colorWithWhite:0.75 alpha:1];
    source.text = L(@"From the Minecraft Wiki (minecraft.wiki), its text under the CC BY-NC-SA 3.0 license");
    [v addSubview:source];
    UITextView *changes = [[UITextView alloc] initWithFrame:CGRectMake(m - 8, y, w - 2 * m + 16, h - 34 - y)];
    changes.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    changes.editable = NO;
    changes.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    changes.textColor = [UIColor colorWithWhite:0.95 alpha:1];
    changes.font = [UIFont systemFontOfSize:16];
    changes.text = L(@"Loading what is new…");
    [v addSubview:changes];
    [KOChangelog load:(version.parent ?: version).identifier done:^(NSString *text, NSError *error) {
        changes.text = text.length ? text : [NSString stringWithFormat:L(@"What is new could not be loaded: %@"), error.localizedDescription ?: @""];
    }];
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
