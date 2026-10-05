#import <UIKit/UIKit.h>

@class KOProbeController;

@interface KOAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong, readonly) KOProbeController *probe;   // the device test, and the log of the links
@end
