#import "KOVersionCell.h"

@interface KOVersionCell ()
@property (nonatomic, strong, readwrite) UILabel *summary;
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

- (void)setName:(NSString *)name tag:(NSString *)tag color:(UIColor *)color
{
    UIFont *font = [UIFont boldSystemFontOfSize:18];
    self.textLabel.font = font;
    self.textLabel.textColor = [UIColor blackColor];
    if (!tag.length) {
        self.textLabel.text = name;
        return;
    }
    NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:name
        attributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor blackColor] }];
    [t appendAttributedString:[[NSAttributedString alloc] initWithString:[@"   " stringByAppendingString:tag]
        attributes:@{ NSFontAttributeName: [UIFont boldSystemFontOfSize:14], NSForegroundColorAttributeName: color ?: [UIColor grayColor] }]];
    self.textLabel.attributedText = t;
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
