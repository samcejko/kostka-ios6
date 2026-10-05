#import "KOStyle.h"

@implementation KOStyle

+ (UIColor *)barColor
{
    return [UIColor colorWithRed:0.30 green:0.50 blue:0.20 alpha:1];
}

+ (UIColor *)playsColor
{
    return [UIColor colorWithRed:0.20 green:0.55 blue:0.15 alpha:1];
}

+ (UIColor *)soonColor
{
    return [UIColor colorWithWhite:0.45 alpha:1];
}

+ (UIColor *)neverColor
{
    return [UIColor colorWithRed:0.70 green:0.25 blue:0.20 alpha:1];
}

// 16 x 16 blocks of brown, 4 points each, as Minecraft's dirt texture, darkened as behind its menus
+ (UIColor *)dirtColor
{
    static UIColor *color;
    if (color) return color;
    const int n = 16, px = 4;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(n * px, n * px), YES, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    static const CGFloat browns[][3] = {
        { 0.53, 0.38, 0.26 }, { 0.45, 0.31, 0.21 }, { 0.37, 0.26, 0.17 }, { 0.60, 0.45, 0.31 }, { 0.42, 0.29, 0.19 },
    };
    unsigned seed = 12345;
    for (int y = 0; y < n; y++) {
        for (int x = 0; x < n; x++) {
            seed = seed * 1103515245u + 12345u;
            const CGFloat *b = browns[(seed >> 16) % 5];
            CGContextSetRGBFillColor(c, b[0] * 0.42, b[1] * 0.42, b[2] * 0.42, 1);
            CGContextFillRect(c, CGRectMake(x * px, y * px, px, px));
        }
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    color = [UIColor colorWithPatternImage:image];
    return color;
}

+ (void)styleNavigationBar:(UINavigationBar *)bar
{
    bar.tintColor = [self barColor];
}

+ (UIImage *)buttonImageTop:(UIColor *)top bottom:(UIColor *)bottom
{
    CGSize size = CGSizeMake(44, 44);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect r = CGRectMake(1, 1, size.width - 2, size.height - 3);
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:10];
    // (the shadow under it, then the body: a gradient, the glass on its upper half, a dark edge)
    CGContextSaveGState(c);
    CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 1, [UIColor colorWithWhite:0 alpha:0.5].CGColor);
    [bottom setFill];
    [p fill];
    CGContextRestoreGState(c);
    CGContextSaveGState(c);
    [p addClip];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[ (__bridge id)top.CGColor, (__bridge id)bottom.CGColor ];
    CGGradientRef g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, CGRectGetMinY(r)), CGPointMake(0, CGRectGetMaxY(r)), 0);
    CGGradientRelease(g);
    NSArray *glass = @[ (__bridge id)[UIColor colorWithWhite:1 alpha:0.35].CGColor, (__bridge id)[UIColor colorWithWhite:1 alpha:0.05].CGColor ];
    g = CGGradientCreateWithColors(space, (__bridge CFArrayRef)glass, NULL);
    CGContextClipToRect(c, CGRectMake(0, 0, size.width, CGRectGetMidY(r)));
    CGContextDrawLinearGradient(c, g, CGPointMake(0, CGRectGetMinY(r)), CGPointMake(0, CGRectGetMidY(r)), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(c);
    [[UIColor colorWithWhite:0 alpha:0.45] setStroke];
    p.lineWidth = 1;
    [p stroke];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(12, 12, 12, 12)];
}

+ (UIButton *)bigButton:(NSString *)title
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setBackgroundImage:[self buttonImageTop:[UIColor colorWithRed:0.50 green:0.80 blue:0.30 alpha:1]
                                        bottom:[UIColor colorWithRed:0.22 green:0.50 blue:0.12 alpha:1]] forState:UIControlStateNormal];
    [b setBackgroundImage:[self buttonImageTop:[UIColor colorWithRed:0.32 green:0.58 blue:0.18 alpha:1]
                                        bottom:[UIColor colorWithRed:0.15 green:0.36 blue:0.08 alpha:1]] forState:UIControlStateHighlighted];
    [b setBackgroundImage:[self buttonImageTop:[UIColor colorWithWhite:0.62 alpha:1]
                                        bottom:[UIColor colorWithWhite:0.42 alpha:1]] forState:UIControlStateDisabled];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.9 alpha:1] forState:UIControlStateDisabled];
    [b setTitleShadowColor:[UIColor colorWithWhite:0 alpha:0.5] forState:UIControlStateNormal];
    b.titleLabel.shadowOffset = CGSizeMake(0, -1);
    return b;
}

+ (UILabel *)labelWithFont:(UIFont *)font
{
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectZero];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [UIColor whiteColor];
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.7];
    l.shadowOffset = CGSizeMake(0, 1);
    l.font = font;
    return l;
}

+ (UIView *)sectionHeader:(NSString *)title width:(CGFloat)width
{
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 40)];
    v.backgroundColor = [UIColor clearColor];
    UILabel *l = [self labelWithFont:[UIFont boldSystemFontOfSize:18]];
    // (grouped tables on the iPad are inset: the title over the cells)
    l.frame = CGRectMake(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 50 : 20, 10, width - 70, 26);
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    l.text = title;
    [v addSubview:l];
    return v;
}

@end
