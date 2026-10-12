#import "KOVersionListController.h"
#import "KOVersionController.h"
#import "KOSettingsController.h"
#import "KOOptiFineController.h"
#import "KOVersions.h"
#import "KOChangelog.h"
#import "KOStyle.h"
#import "KOCommon.h"

// A row of the list: the version's name, and under it what is new in it - two lines at most
@interface KOVersionCell : UITableViewCell
@property (nonatomic, strong) UILabel *summary;
@end

@implementation KOVersionCell

- (id)initWithReuseIdentifier:(NSString *)reuse
{
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse])) {
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        self.summary = [[UILabel alloc] init];
        self.summary.font = [UIFont systemFontOfSize:14];
        self.summary.textColor = [UIColor grayColor];
        self.summary.highlightedTextColor = [UIColor whiteColor];
        self.summary.backgroundColor = [UIColor clearColor];
        self.summary.numberOfLines = 2;
        [self.contentView addSubview:self.summary];
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat x = 10, w = b.size.width - 2 * x;
    self.textLabel.frame = CGRectMake(x, 7, w, 22);
    CGSize size = [self.summary sizeThatFits:CGSizeMake(w, 40)];
    self.summary.frame = CGRectMake(x, 30, w, MIN(size.height, b.size.height - 32));
}

@end

@interface KOVersionListController ()
@property (nonatomic, strong) NSArray *versions;
@property (nonatomic, strong) NSArray *sections;   // { title, versions }
@property (nonatomic, copy) NSString *problem;
@property (nonatomic) BOOL loading;
@end

@implementation KOVersionListController

- (id)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Kostka";
    UIView *back = [[UIView alloc] initWithFrame:self.tableView.bounds];
    back.backgroundColor = [KOStyle dirtColor];
    self.tableView.backgroundView = back;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:L(@"Settings") style:UIBarButtonItemStyleBordered
                                                                             target:self action:@selector(settings)];
    self.refreshControl = [[UIRefreshControl alloc] init];
    self.refreshControl.tintColor = [UIColor whiteColor];
    [self.refreshControl addTarget:self action:@selector(load) forControlEvents:UIControlEventValueChanged];
    [self load];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self arrange];   // (snapshots may have been switched on or off)
}

- (void)settings
{
    [self.navigationController pushViewController:[[KOSettingsController alloc] init] animated:YES];
}

- (void)load
{
    self.loading = YES;
    self.problem = nil;
    [self.tableView reloadData];
    [KOVersions load:^(NSArray *versions, NSError *error) {
        self.loading = NO;
        [self.refreshControl endRefreshing];
        if (versions) self.versions = versions;
        if (!versions) self.problem = [NSString stringWithFormat:@"%@ (%@)", L(@"Mojang's list of versions could not be loaded."), error.localizedDescription];
        [self arrange];
        // (Mojang's notes: what is new in some fifty versions at once)
        __weak KOVersionListController *weakSelf = self;
        if (versions) [KOChangelog prepare:^{ [weakSelf.tableView reloadRowsAtIndexPaths:weakSelf.tableView.indexPathsForVisibleRows
                                                                          withRowAnimation:UITableViewRowAnimationNone]; }];
    }];
}

// The rows on the screen of a version whose summary has come
- (void)summaryCame:(NSString *)name
{
    NSMutableArray *rows = [NSMutableArray array];
    for (NSIndexPath *p in self.tableView.indexPathsForVisibleRows) {
        if (p.section >= (NSInteger)self.sections.count || p.row >= (NSInteger)[self.sections[p.section][@"versions"] count]) continue;
        KOVersion *v = self.sections[p.section][@"versions"][p.row];
        if ([v isKindOfClass:[KOVersion class]] && [(v.parent ?: v).identifier isEqualToString:name]) [rows addObject:p];
    }
    if (rows.count) [self.tableView reloadRowsAtIndexPaths:rows withRowAnimation:UITableViewRowAnimationNone];
}

// The versions by kind, newest first, each with what it does here; the releases too new for iOS 6 at the end, and
// the snapshots of that time after them when snapshots are shown and so are the versions that do not run yet
// (hundreds of them)
- (void)arrange
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL snapshots = [defaults boolForKey:@"KOShowSnapshots"];
    BOOL all = snapshots && [defaults boolForKey:@"KOTryAll"];
    NSMutableArray *releases = [NSMutableArray array], *betas = [NSMutableArray array], *alphas = [NSMutableArray array],
                   *snaps = [NSMutableArray array], *tooNew = [NSMutableArray array], *tooNewSnaps = [NSMutableArray array],
                   *optiFine = [NSMutableArray array];
    for (KOVersion *v in self.versions) {
        BOOL snapshot = ![v.type isEqualToString:@"release"] && ![v.type isEqualToString:@"old_beta"] &&
                        ![v.type isEqualToString:@"old_alpha"];
        if (v.parent) {
            [optiFine addObject:v];
        } else if (v.support == KOSupportNever) {
            if (!snapshot) [tooNew addObject:v];
            else if (all) [tooNewSnaps addObject:v];
        } else if ([v.type isEqualToString:@"release"]) {
            [releases addObject:v];
        } else if ([v.type isEqualToString:@"old_beta"]) {
            [betas addObject:v];
        } else if ([v.type isEqualToString:@"old_alpha"]) {
            [alphas addObject:v];
        } else if (snapshots) {
            [snaps addObject:v];
        }
    }
    NSMutableArray *sections = [NSMutableArray array];
    // (OptiFine first: what is installed, and the way to add it - for the releases 1.7.2 to 1.12.2)
    if (self.versions.count) {
        [optiFine addObject:@"add"];
        [sections addObject:@{ @"title": @"OptiFine", @"versions": optiFine }];
    }
    if (releases.count) [sections addObject:@{ @"title": L(@"Releases"), @"versions": releases }];
    if (betas.count) [sections addObject:@{ @"title": L(@"Beta"), @"versions": betas }];
    if (alphas.count) [sections addObject:@{ @"title": L(@"Alpha, Infdev, Classic"), @"versions": alphas }];
    if (snaps.count) [sections addObject:@{ @"title": L(@"Snapshots"), @"versions": snaps }];
    if (tooNew.count) [sections addObject:@{ @"title": L(@"Too new for iOS 6"), @"versions": tooNew }];
    if (tooNewSnaps.count) [sections addObject:@{ @"title": L(@"Snapshots too new for iOS 6"), @"versions": tooNewSnaps }];
    self.sections = sections;
    [self.tableView reloadData];
}

#pragma mark Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.sections.count ?: 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (!self.sections.count) return 1;   // (loading, or what went wrong)
    return [self.sections[section][@"versions"] count];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (!self.sections.count) return nil;
    return [KOStyle sectionHeader:self.sections[section][@"title"] width:tableView.bounds.size.width];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return self.sections.count ? 44 : 20;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!self.sections.count) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.textLabel.text = self.loading ? L(@"Loading Mojang's list of versions…") : (self.problem ?: @"");
        if (!self.loading) {
            cell.detailTextLabel.text = nil;
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
        cell.selectionStyle = self.loading ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
        return cell;
    }
    KOVersionCell *cell = (KOVersionCell *)[tableView dequeueReusableCellWithIdentifier:@"v"];
    if (!cell) cell = [[KOVersionCell alloc] initWithReuseIdentifier:@"v"];
    cell.textLabel.font = [UIFont boldSystemFontOfSize:18];
    cell.textLabel.textColor = [UIColor blackColor];
    id item = self.sections[indexPath.section][@"versions"][indexPath.row];
    if (![item isKindOfClass:[KOVersion class]]) {
        cell.textLabel.text = L(@"Add OptiFine…");
        cell.summary.text = @"1.7.2 – 1.12.2";
        return cell;
    }
    KOVersion *v = item;
    NSString *name = v.parent ? [NSString stringWithFormat:@"%@  OptiFine %@", v.parent.identifier, v.optiFineEdition] : v.identifier;
    // (what plays, and the versions too new for iOS 6 in their own section: the name; a version of the LWJGL 2 era
    // that was not tried yet or did not play yet: that too, in its colour)
    if (v.support == KOSupportTry || v.support == KOSupportSoon) {
        NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:name
            attributes:@{ NSFontAttributeName: [UIFont boldSystemFontOfSize:18], NSForegroundColorAttributeName: [UIColor blackColor] }];
        [t appendAttributedString:[[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:v.localizedSupport]
            attributes:@{ NSFontAttributeName: [UIFont boldSystemFontOfSize:14],
                          NSForegroundColorAttributeName: v.support == KOSupportTry ? [KOStyle tryColor] : [KOStyle soonColor] }]];
        cell.textLabel.attributedText = t;
    } else {
        cell.textLabel.text = name;
    }
    // under it what is new in it (in the parent, for OptiFine's): Mojang's notes or the wiki's, fetched for the rows on
    // the screen and kept - till then its date
    NSString *key = (v.parent ?: v).identifier;
    NSString *summary = [KOChangelog summaryFor:key];
    cell.summary.text = summary ?: (v.parent ?: v).localizedReleased;
    if (!summary) {
        __weak KOVersionListController *weakSelf = self;
        [KOChangelog want:key done:^(NSString *s) {
            if (s) [weakSelf summaryCame:key];
        }];
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 70;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.sections.count) {
        if (!self.loading) [self load];   // (tapping the problem tries again)
        return;
    }
    id item = self.sections[indexPath.section][@"versions"][indexPath.row];
    if (![item isKindOfClass:[KOVersion class]]) {
        [self.navigationController pushViewController:[[KOOptiFineController alloc] initWithVersions:self.versions] animated:YES];
        return;
    }
    [self.navigationController pushViewController:[[KOVersionController alloc] initWithVersion:item] animated:YES];
}

@end
