#import "KOVersionListController.h"
#import "KOVersionController.h"
#import "KOSettingsController.h"
#import "KOVersions.h"
#import "KOStyle.h"
#import "KOCommon.h"

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
    }];
}

- (void)arrange
{
    BOOL snapshots = [[NSUserDefaults standardUserDefaults] boolForKey:@"KOShowSnapshots"];
    NSMutableArray *plays = [NSMutableArray array], *releases = [NSMutableArray array], *betas = [NSMutableArray array],
                   *alphas = [NSMutableArray array], *snaps = [NSMutableArray array];
    for (KOVersion *v in self.versions) {
        if (v.support == KOSupportPlays) [plays addObject:v];
        else if ([v.type isEqualToString:@"release"]) [releases addObject:v];
        else if ([v.type isEqualToString:@"old_beta"]) [betas addObject:v];
        else if ([v.type isEqualToString:@"old_alpha"]) [alphas addObject:v];
        else if (snapshots) [snaps addObject:v];
    }
    NSMutableArray *sections = [NSMutableArray array];
    if (plays.count) [sections addObject:@{ @"title": L(@"Plays on this iPad"), @"versions": plays }];
    if (releases.count) [sections addObject:@{ @"title": L(@"Releases"), @"versions": releases }];
    if (betas.count) [sections addObject:@{ @"title": L(@"Beta"), @"versions": betas }];
    if (alphas.count) [sections addObject:@{ @"title": L(@"Alpha"), @"versions": alphas }];
    if (snaps.count) [sections addObject:@{ @"title": L(@"Snapshots"), @"versions": snaps }];
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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"v"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"v"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:18];
    }
    KOVersion *v = self.sections[indexPath.section][@"versions"][indexPath.row];
    cell.textLabel.text = v.identifier;
    cell.detailTextLabel.text = v.localizedSupport;
    cell.detailTextLabel.textColor = v.support == KOSupportPlays ? [KOStyle playsColor]
                                   : v.support == KOSupportSoon ? [KOStyle soonColor] : [KOStyle neverColor];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return self.sections.count ? 50 : 70;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.sections.count) {
        if (!self.loading) [self load];   // (tapping the problem tries again)
        return;
    }
    KOVersion *v = self.sections[indexPath.section][@"versions"][indexPath.row];
    [self.navigationController pushViewController:[[KOVersionController alloc] initWithVersion:v] animated:YES];
}

@end
