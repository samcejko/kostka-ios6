#import <UIKit/UIKit.h>
#import "KOVersions.h"

// One version: what it is, whether it plays here, and the button that downloads and starts it
@interface KOVersionController : UIViewController
- (id)initWithVersion:(KOVersion *)version;
@end
