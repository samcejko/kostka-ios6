#import "KOOptiFineController.h"
#import "KOVersions.h"
#import "KOGame.h"
#import "KONet.h"
#import "KOJava.h"
#import "KOStyle.h"
#import "KOCommon.h"

static NSString *const KOOptiFineDownloads = @"http://optifine.net/downloads";

// One edition: "OptiFine_1.12.2_HD_U_G5.jar" for 1.12.2 ("HD U G5", released "24.01.2021")
@interface KOOptiFineEdition : NSObject
@property (nonatomic, copy) NSString *file, *edition, *date;
@property (nonatomic, strong) KOVersion *version;
@end

@implementation KOOptiFineEdition
@end

#pragma mark - The download page

// optifine.net's own page for one file (its "Mirror" page: plain http, which iOS 6 reads), as in a browser. The
// player taps its Download; Kostka takes that file instead of the browser and offers to install it. A link away
// from optifine.net (an advertisement) opens in Safari.
@interface KOOptiFinePageController : UIViewController <UIWebViewDelegate, UIAlertViewDelegate>
@property (nonatomic, strong) KOOptiFineEdition *edition;
@property (nonatomic, strong) UIWebView *web;
@property (nonatomic, strong) UILabel *note;
@property (nonatomic, strong) UIProgressView *progress;
@property (nonatomic, copy) NSString *installer;
@property (nonatomic) BOOL busy, tapForTest, installForTest;
@end

@implementation KOOptiFinePageController

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    // (tests: the page's Download link followed as a tap on it would be - once the page that has it has loaded)
    if (!self.tapForTest || self.busy) return;
    NSString *found = [webView stringByEvaluatingJavaScriptFromString:@"(function(){var a=document.getElementsByTagName('a');"
        "for(var i=0;i<a.length;i++){if(a[i].href.indexOf('downloadx')>=0){window.location.href=a[i].href;return 'yes';}}"
        "return '';})()"];
    if (found.length) self.tapForTest = NO;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = [NSString stringWithFormat:@"OptiFine %@", self.edition.version.identifier];
    UIView *v = self.view;
    v.backgroundColor = [KOStyle dirtColor];
    CGFloat w = v.bounds.size.width;
    self.note = [KOStyle labelWithFont:[UIFont boldSystemFontOfSize:17]];
    self.note.frame = CGRectMake(20, 10, w - 40, 24);
    self.note.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.note.text = L(@"Tap Download on OptiFine's page: Kostka takes the file.");
    [v addSubview:self.note];
    self.progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.progress.frame = CGRectMake(20, 40, w - 40, 10);
    self.progress.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.progress.hidden = YES;
    [v addSubview:self.progress];
    self.web = [[UIWebView alloc] initWithFrame:CGRectMake(0, 56, w, v.bounds.size.height - 56)];
    self.web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.web.scalesPageToFit = YES;
    self.web.delegate = self;
    [v addSubview:self.web];
    NSString *page = [NSString stringWithFormat:@"http://optifine.net/adloadx?f=%@", self.edition.file];
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:page]]];
}

- (void)dealloc
{
    _web.delegate = nil;
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)type
{
    NSURL *url = request.URL;
    // (the file itself: "downloadx?f=OptiFine_....jar&x=...")
    if ([url.path hasSuffix:@"downloadx"] || [url.absoluteString rangeOfString:@"/downloadx?"].location != NSNotFound) {
        if (!self.busy) [self download:url];
        return NO;
    }
    BOOL top = [request.mainDocumentURL isEqual:url];
    if (top && type == UIWebViewNavigationTypeLinkClicked && ![url.host hasSuffix:@"optifine.net"]) {
        [[UIApplication sharedApplication] openURL:url];
        return NO;
    }
    return YES;
}

- (void)download:(NSURL *)url
{
    self.busy = YES;
    self.navigationItem.hidesBackButton = YES;
    self.note.text = L(@"Downloading OptiFine");
    self.progress.hidden = NO;
    self.progress.progress = 0;
    NSString *dir = [[KOJava dataPath] stringByAppendingPathComponent:@"optifine"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *to = [dir stringByAppendingPathComponent:self.edition.file];
    __weak KOOptiFinePageController *weakSelf = self;
    [KONet download:url to:to sha1:nil progress:^(long long received, long long expected) {
        if (expected > 0) weakSelf.progress.progress = (float)received / expected;
    } done:^(NSError *error) {
        KOOptiFinePageController *s = weakSelf;
        if (!s) return;
        s.progress.hidden = YES;
        KOLog(@"optifine: %@ %@", s.edition.file, error ? error.localizedDescription : @"downloaded");
        if (error) {
            s.busy = NO;
            s.navigationItem.hidesBackButton = NO;
            s.note.text = L(@"Tap Download on OptiFine's page: Kostka takes the file.");
            [[[UIAlertView alloc] initWithTitle:L(@"OptiFine could not be downloaded") message:error.localizedDescription
                                       delegate:nil cancelButtonTitle:L(@"OK") otherButtonTitles:nil] show];
            return;
        }
        s.installer = to;
        s.note.text = nil;
        NSString *title = [NSString stringWithFormat:L(@"Install OptiFine %@ for %@?"), s.edition.edition, s.edition.version.identifier];
        UIAlertView *ask = [[UIAlertView alloc] initWithTitle:title
            message:L(@"Kostka installs it - a minute or two - and then closes: open it again and OptiFine is in the list.")
            delegate:s cancelButtonTitle:L(@"Cancel") otherButtonTitles:L(@"Install"), nil];
        ask.tag = 1;
        [ask show];
        KOLog(@"optifine: asks \"%@\"", title);
        if (s.installForTest) {
            [ask dismissWithClickedButtonIndex:ask.firstOtherButtonIndex animated:NO];
            [s alertView:ask clickedButtonAtIndex:ask.firstOtherButtonIndex];
        }
    }];
}

- (void)alertView:(UIAlertView *)alert clickedButtonAtIndex:(NSInteger)index
{
    if (alert.tag == 2) {
        // (Java has run: Kostka closes, as after a game)
        exit(0);
    }
    if (index == alert.cancelButtonIndex) {
        self.busy = NO;
        self.navigationItem.hidesBackButton = NO;
        self.note.text = L(@"Tap Download on OptiFine's page: Kostka takes the file.");
        return;
    }
    self.web.userInteractionEnabled = NO;
    self.web.alpha = 0.4;
    self.progress.hidden = NO;
    __weak KOOptiFinePageController *weakSelf = self;
    [KOGame installOptiFine:self.installer for:self.edition.version status:^(NSString *text, float fraction) {
        weakSelf.note.text = text;
        if (fraction >= 0) weakSelf.progress.progress = fraction;
    } done:^(int code, NSString *error) {
        KOOptiFinePageController *s = weakSelf;
        if (!s) return;
        s.progress.hidden = YES;
        BOOL ok = code == 0 && !error;
        KOLog(@"optifine: says %@", ok ? @"installed" : @"not installed");
        NSString *closing = L(@"Kostka closes: open it again to play.");
        s.note.text = ok ? L(@"OptiFine is installed") : L(@"OptiFine could not be installed");
        UIAlertView *end = [[UIAlertView alloc]
            initWithTitle:s.note.text
                  message:ok ? closing : [NSString stringWithFormat:@"%@\n\n%@", error ?: [KOJava stopReason] ?: @"", closing]
                 delegate:s cancelButtonTitle:L(@"OK") otherButtonTitles:nil];
        end.tag = 2;
        [end show];
    }];
}

@end

#pragma mark - The list

@interface KOOptiFineController ()
@property (nonatomic, strong) NSArray *versions;
@property (nonatomic, strong) NSArray *editions;
@property (nonatomic, copy) NSString *problem;
@end

@implementation KOOptiFineController

- (id)initWithVersions:(NSArray *)versions
{
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.versions = versions;
        self.title = @"OptiFine";
    }
    return self;
}

+ (UIViewController *)pageForFile:(NSString *)file version:(KOVersion *)version tap:(BOOL)tap install:(BOOL)install
{
    KOOptiFineEdition *e = [[KOOptiFineEdition alloc] init];
    e.file = file;
    NSRange hd = [file rangeOfString:@"HD_"];
    e.edition = hd.location != NSNotFound ? [[[file substringFromIndex:hd.location] stringByDeletingPathExtension]
                                             stringByReplacingOccurrencesOfString:@"_" withString:@" "] : file;
    e.version = version;
    KOOptiFinePageController *page = [[KOOptiFinePageController alloc] initWithNibName:nil bundle:nil];
    page.edition = e;
    page.tapForTest = tap;
    page.installForTest = install;
    return page;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIView *back = [[UIView alloc] initWithFrame:self.tableView.bounds];
    back.backgroundColor = [KOStyle dirtColor];
    self.tableView.backgroundView = back;
    [self load];
}

- (void)load
{
    self.problem = nil;
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:KOOptiFineDownloads]
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    __weak KOOptiFineController *weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        KOOptiFineController *s = weakSelf;
        if (!s) return;
        NSString *html = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?:
                                [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] : nil;
        s.editions = html ? [s parse:html] : nil;
        if (!s.editions.count) s.problem = [NSString stringWithFormat:@"%@ %@", L(@"optifine.net could not be reached."), error.localizedDescription ?: @""];
        [s.tableView reloadData];
    }];
}

// The newest edition for each version of Kostka's (the page lists the newest first; previews left out). OptiFine
// calls 1.8 and 1.9 "1.8.0" and "1.9.0".
- (NSArray *)parse:(NSString *)html
{
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    for (KOVersion *v in self.versions) if (!v.parent) byId[v.identifier] = v;
    NSRegularExpression *files = [NSRegularExpression regularExpressionWithPattern:
        @"adloadx\\?f=(OptiFine_(1\\.[0-9.]+)_(HD_U_[A-Za-z0-9]+)\\.jar)" options:0 error:NULL];
    NSRegularExpression *dates = [NSRegularExpression regularExpressionWithPattern:@"colDate'>([0-9.]+)<" options:0 error:NULL];
    NSMutableArray *list = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSTextCheckingResult *m in [files matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSString *file = [html substringWithRange:[m rangeAtIndex:1]];
        NSString *mc = [html substringWithRange:[m rangeAtIndex:2]];
        if ([seen containsObject:mc]) continue;
        [seen addObject:mc];
        KOVersion *v = byId[mc] ?: ([mc hasSuffix:@".0"] ? byId[[mc substringToIndex:mc.length - 2]] : nil);
        if (!v || v.support != KOSupportPlays) continue;
        KOOptiFineEdition *e = [[KOOptiFineEdition alloc] init];
        e.file = file;
        e.edition = [[html substringWithRange:[m rangeAtIndex:3]] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        e.version = v;
        NSUInteger from = NSMaxRange(m.range);
        NSTextCheckingResult *d = [dates firstMatchInString:html options:0 range:NSMakeRange(from, MIN(html.length - from, 600))];
        if (d) e.date = [html substringWithRange:[d rangeAtIndex:1]];
        [list addObject:e];
    }
    return list;
}

- (BOOL)installed:(KOOptiFineEdition *)e
{
    NSString *name = [NSString stringWithFormat:@"%@-OptiFine_%@", e.version.identifier,
                      [e.edition stringByReplacingOccurrencesOfString:@" " withString:@"_"]];
    for (KOVersion *v in self.versions) if (v.parent && [v.identifier isEqualToString:name]) return YES;
    return NO;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.editions.count ?: 1;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    return [KOStyle sectionHeader:L(@"OptiFine for these versions") width:tableView.bounds.size.width];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 44;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    NSString *text = L(@"OptiFine, by sp614x, makes Minecraft faster and gives it more settings. Kostka does not hand it out: it opens OptiFine's own download page (with its advertisement), where you tap Download, then installs it. The worlds are the version's own.");
    UILabel *l = [KOStyle labelWithFont:[UIFont systemFontOfSize:14]];
    l.numberOfLines = 0;
    l.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    l.text = text;
    CGFloat inset = 50, w = tableView.bounds.size.width - 2 * inset;
    CGSize size = [text sizeWithFont:l.font constrainedToSize:CGSizeMake(w, 300) lineBreakMode:NSLineBreakByWordWrapping];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, size.height + 16)];
    l.frame = CGRectMake(inset, 6, w, size.height);
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:l];
    return v;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return [self tableView:tableView viewForFooterInSection:section].bounds.size.height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (!self.editions.count) {
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.textLabel.text = self.problem ?: L(@"Loading what optifine.net offers…");
        cell.selectionStyle = self.problem ? UITableViewCellSelectionStyleBlue : UITableViewCellSelectionStyleNone;
        return cell;
    }
    KOOptiFineEdition *e = self.editions[indexPath.row];
    cell.textLabel.font = [UIFont boldSystemFontOfSize:18];
    cell.textLabel.text = [NSString stringWithFormat:@"%@  OptiFine %@", e.version.identifier, e.edition];
    BOOL installed = [self installed:e];
    cell.detailTextLabel.text = installed ? L(@"Installed") : e.date;
    cell.detailTextLabel.textColor = installed ? [KOStyle playsColor] : [UIColor grayColor];
    cell.accessoryType = installed ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = installed ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.editions.count) {
        if (self.problem) [self load];
        return;
    }
    KOOptiFineEdition *e = self.editions[indexPath.row];
    if ([self installed:e]) return;
    KOOptiFinePageController *page = [[KOOptiFinePageController alloc] initWithNibName:nil bundle:nil];
    page.edition = e;
    [self.navigationController pushViewController:page animated:YES];
}

@end
