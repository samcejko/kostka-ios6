#import <UIKit/UIKit.h>

// The device test (what this iPad allows a Java VM) and the log of what was run from a link (kostka:probe,
// kostka:java). Reached from the settings; the links work whether it is on screen or not.
@interface KOProbeController : UIViewController
- (void)enqueue:(NSString *)test;
- (void)append:(NSString *)line;
@end
