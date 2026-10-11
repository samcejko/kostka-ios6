#import <UIKit/UIKit.h>

// OptiFine (optifine.net, by sp614x) for the versions from 1.7.2 to 1.12.2. Kostka does not hand OptiFine out - it
// is to be downloaded from its own site only: this lists what optifine.net offers (its newest edition for each
// version), opens its download page - with its advertisement - for the one tapped, takes the file the player
// downloads there, and runs its installer.
@interface KOOptiFineController : UITableViewController
- (id)initWithVersions:(NSArray *)versions;   // KOVersions' list (Mojang's, with what is installed here)
@end
