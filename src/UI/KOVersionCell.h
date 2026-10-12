#import <UIKit/UIKit.h>

// A row of a list of versions: the version's name (textLabel), and under it what is new in it - two lines at most.
// 70 points high.
@interface KOVersionCell : UITableViewCell
@property (nonatomic, strong, readonly) UILabel *summary;
- (id)initWithReuseIdentifier:(NSString *)reuse;
// The name, with a word on it in a colour after it ("Not tried yet", "Installed") when `tag` is given
- (void)setName:(NSString *)name tag:(NSString *)tag color:(UIColor *)color;
@end
