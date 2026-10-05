#import <UIKit/UIKit.h>

// Kostka's look: iOS 6 (glossy bars and buttons) in Minecraft's colors: grass-green bars, the darkened dirt
// behind Minecraft's own menus, white text with a shadow on it.
@interface KOStyle : NSObject

+ (UIColor *)barColor;
+ (UIColor *)dirtColor;          // a pattern
+ (UIColor *)playsColor;         // "Plays"
+ (UIColor *)tryColor;           // "To try"
+ (UIColor *)soonColor;          // "Not yet"
+ (UIColor *)neverColor;         // "Too new"

+ (void)styleNavigationBar:(UINavigationBar *)bar;
+ (UIButton *)bigButton:(NSString *)title;
+ (UILabel *)labelWithFont:(UIFont *)font;   // white, with a shadow, for text on the dirt
+ (UIView *)sectionHeader:(NSString *)title width:(CGFloat)width;

@end
