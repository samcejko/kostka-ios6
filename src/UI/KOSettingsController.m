#import "KOSettingsController.h"
#import "KOAppDelegate.h"
#import "KOProbeController.h"
#import "KOGame.h"
#import "KOStyle.h"
#import "KOCommon.h"

@interface KOSettingsController () <UITextFieldDelegate>
@end

@implementation KOSettingsController

- (id)init
{
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        self.title = L(@"Settings");
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIView *back = [[UIView alloc] initWithFrame:self.tableView.bounds];
    back.backgroundColor = [KOStyle dirtColor];
    self.tableView.backgroundView = back;
}

// (sections: the player, the game, the versions, about)
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 1 ? 2 : section == 2 ? 3 : 1;
}

- (NSString *)titleFor:(NSInteger)section
{
    return section == 0 ? L(@"Player") : section == 1 ? L(@"In the game") : section == 2 ? L(@"Versions") : L(@"About");
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    return [KOStyle sectionHeader:[self titleFor:section] width:tableView.bounds.size.width];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 44;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    NSString *text = section == 0 ? L(@"The name the old versions show for the player.")
                   : section == 1 ? L(@"The frame rate shows in the game's upper left corner. With the joystick you walk every way; pushed to its edge, forwards, you sprint.")
                   : section == 2 ? L(@"The versions that do not run yet may not start, or end soon after: MC6 gets there one step after another. With snapshots shown, the ones too new for iOS 6 are listed too.")
                   : section == 3 ? L(@"MC6 downloads Minecraft's files from Mojang. Minecraft is a game by Mojang Studios; MC6 is not an official product. Inside: OpenJDK 8 (GPL v2 with the Classpath exception), LWJGL 2 (BSD license), gl4es (MIT license).")
                                  : nil;
    if (!text) return nil;
    UILabel *l = [KOStyle labelWithFont:[UIFont systemFontOfSize:14]];
    l.numberOfLines = 0;
    l.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    l.text = text;
    CGFloat inset = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 50 : 20;
    CGFloat w = tableView.bounds.size.width - 2 * inset;
    CGSize size = [text sizeWithFont:l.font constrainedToSize:CGSizeMake(w, 300) lineBreakMode:NSLineBreakByWordWrapping];
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, size.height + 16)];
    l.frame = CGRectMake(inset, 6, w, size.height);
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [v addSubview:l];
    return v;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    UIView *v = [self tableView:tableView viewForFooterInSection:section];
    return v ? v.bounds.size.height : 10;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if (indexPath.section == 0) {
        cell.textLabel.text = L(@"Name");
        UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 300, 30)];
        field.text = [KOGame playerName];
        field.textAlignment = NSTextAlignmentRight;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.returnKeyType = UIReturnKeyDone;
        field.delegate = self;
        field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        cell.accessoryView = field;
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        // (how the player walks: the arrows' cross, or a joystick as Minecraft on phones has it)
        cell.textLabel.text = L(@"Movement");
        UISegmentedControl *c = [[UISegmentedControl alloc] initWithItems:@[ L(@"Arrows"), L(@"Joystick") ]];
        c.segmentedControlStyle = UISegmentedControlStyleBar;
        c.tintColor = [KOStyle barColor];
        c.selectedSegmentIndex = [[NSUserDefaults standardUserDefaults] integerForKey:@"KOMoveControl"] == 1 ? 1 : 0;
        c.frame = CGRectMake(0, 0, 200, 32);
        [c addTarget:self action:@selector(movementChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = c;
    } else if (indexPath.section == 1 || indexPath.section == 2) {
        // (a switch's tag: its row, 10 more in the versions' section)
        NSInteger tag = indexPath.section == 1 ? indexPath.row : 10 + indexPath.row;
        cell.textLabel.text = tag == 0 ? L(@"Show the frame rate (FPS)")
                            : tag == 10 ? L(@"Show snapshots")
                            : tag == 11 ? L(@"Try the versions that do not run yet") : L(@"Download sounds and music (100 MB and more)");
        UISwitch *s = [[UISwitch alloc] init];
        s.on = [[NSUserDefaults standardUserDefaults] boolForKey:[self switchKey:tag]];
        s.onTintColor = [KOStyle barColor];
        s.tag = tag;
        [s addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = s;
    } else {
        cell.textLabel.text = L(@"Device test");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 3) {
        KOAppDelegate *app = (KOAppDelegate *)[UIApplication sharedApplication].delegate;
        [self.navigationController pushViewController:app.probe animated:YES];
    }
}

- (NSString *)switchKey:(NSInteger)tag
{
    return tag == 0 ? @"KOShowFPS" : tag == 10 ? @"KOShowSnapshots" : tag == 11 ? @"KOTryAll" : @"KOSounds";
}

- (void)switchChanged:(UISwitch *)s
{
    [[NSUserDefaults standardUserDefaults] setBool:s.on forKey:[self switchKey:s.tag]];
}

- (void)movementChanged:(UISegmentedControl *)c
{
    [[NSUserDefaults standardUserDefaults] setInteger:c.selectedSegmentIndex forKey:@"KOMoveControl"];
}

- (void)textFieldDidEndEditing:(UITextField *)field
{
    // (Minecraft's names: letters, digits and _, 3 to 16 of them)
    NSString *name = [[field.text componentsSeparatedByCharactersInSet:
                       [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"] invertedSet]]
                      componentsJoinedByString:@""];
    if (name.length > 16) name = [name substringToIndex:16];
    if (name.length >= 3) [KOGame setPlayerName:name];
    field.text = [KOGame playerName];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field
{
    [field resignFirstResponder];
    return YES;
}

@end
