/*
 * Copyright (c) 2026 samcejko (Kostka: the iOS backend of LWJGL)
 * All rights reserved. BSD license, as LWJGL (see lwjgl/README.md).
 */

// The Display's window on iOS (the JNI side of Kostka's MacOSXDisplay and MacOSXSysImplementation).
//
// The window is a full-screen view over the app (KOGameView). In it, a view on an EAGL layer as big as the
// game's framebuffer, scaled to fit the screen, and the on-screen controls. Touches become the mouse: while
// the game grabs the mouse (looking around), a moving finger turns, a tap is the right button (use, place)
// and a held finger the left one (attack, break); otherwise the finger is the pointer with the left button
// down. The controls are keys, the keyboard button brings up iOS's keyboard for typing.
//
// UIKit runs on the main thread; the game calls in from its own thread: events go through a queue that
// MacOSXDisplay.update() empties. Built without ARC (C structures hold the views).
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGLDrawable.h>
#include <pthread.h>
#include <errno.h>
#include <sys/time.h>
#include <mach/mach_time.h>
#include <jni.h>
#include "common_tools.h"
#include "ios_common.h"

// (LWJGL's key codes)
enum {
    KO_KEY_NONE = 0, KO_KEY_ESCAPE = 1, KO_KEY_BACK = 14, KO_KEY_E = 18, KO_KEY_T = 20, KO_KEY_RETURN = 28,
    KO_KEY_W = 17, KO_KEY_A = 30, KO_KEY_S = 31, KO_KEY_D = 32, KO_KEY_LSHIFT = 42, KO_KEY_SPACE = 57
};

typedef char ko_event_size_check[sizeof(KOEvent) == 24 ? 1 : -1];

static NSString *KOText(NSString *key)
{
    // (the app's Localizable.strings: English and Czech)
    return [[NSBundle mainBundle] localizedStringForKey:key value:key table:nil];
}

static void ko_on_main(void (^block)(void))
{
    if ([NSThread isMainThread]) block();
    else dispatch_sync(dispatch_get_main_queue(), block);
}

#pragma mark - Events

#define KO_MAX_EVENTS 1024
static KOEvent g_events[KO_MAX_EVENTS];
static int g_event_head, g_event_count;
static pthread_mutex_t g_event_lock = PTHREAD_MUTEX_INITIALIZER;
static volatile int g_grabbed;

static int64_t ko_nanos(void)
{
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (int64_t)(mach_absolute_time() * tb.numer / tb.denom);
}

void ko_post_event(int type, int a, int b, int c)
{
    pthread_mutex_lock(&g_event_lock);
    if (g_event_count < KO_MAX_EVENTS) {
        KOEvent *e = &g_events[(g_event_head + g_event_count) % KO_MAX_EVENTS];
        e->type = type;
        e->a = a;
        e->b = b;
        e->c = c;
        e->nanos = ko_nanos();
        g_event_count++;
    }
    pthread_mutex_unlock(&g_event_lock);
}

static void ko_post_key(int key, int character)
{
    ko_post_event(KO_EVENT_KEY, key, 1, character);
    ko_post_event(KO_EVENT_KEY, key, 0, 0);
}

static int ko_key_for_char(unichar c)
{
    static const char *letters = "qwertyuiop\0\0\0\0asdfghjkl\0\0\0\0\0zxcvbnm";   // from KEY_Q (16)
    if (c >= 'A' && c <= 'Z') c += 'a' - 'A';
    if (c >= 'a' && c <= 'z') {
        for (int i = 0; i < 35; i++) if (letters[i] == c) return 16 + i;
    }
    if (c >= '1' && c <= '9') return 2 + (c - '1');
    switch (c) {
        case '0': return 11;
        case '-': return 12;
        case '=': return 13;
        case '[': return 26;
        case ']': return 27;
        case ';': return 39;
        case '\'': return 40;
        case '`': return 41;
        case '\\': return 43;
        case ',': return 51;
        case '.': return 52;
        case '/': return 53;
        case ' ': return KO_KEY_SPACE;
    }
    return KO_KEY_NONE;
}

#pragma mark - Pausing in the background

// iOS kills an app that draws in the background: when the app leaves the front, the game's next swap waits
// (ios_context.m) until it is back, and the main thread waits a moment for that to happen.
static pthread_mutex_t g_pause_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_pause_cond = PTHREAD_COND_INITIALIZER;
static int g_inactive, g_parked, g_windows;

void ko_wait_while_inactive(void)
{
    pthread_mutex_lock(&g_pause_lock);
    if (g_inactive) {
        void (*finish)(void) = (void (*)(void))ko_gles_proc_address("glFinish");
        if (finish) finish();
        g_parked = 1;
        pthread_cond_broadcast(&g_pause_cond);
        while (g_inactive) pthread_cond_wait(&g_pause_cond, &g_pause_lock);
        g_parked = 0;
    }
    pthread_mutex_unlock(&g_pause_lock);
}

static void ko_set_inactive(int inactive)
{
    pthread_mutex_lock(&g_pause_lock);
    g_inactive = inactive;
    if (inactive) {
        struct timeval now;
        gettimeofday(&now, NULL);
        struct timespec until = { now.tv_sec + 2, now.tv_usec * 1000 };
        while (!g_parked && g_windows > 0) {
            if (pthread_cond_timedwait(&g_pause_cond, &g_pause_lock, &until) == ETIMEDOUT) break;
        }
    } else {
        pthread_cond_broadcast(&g_pause_cond);
    }
    pthread_mutex_unlock(&g_pause_lock);
}

#pragma mark - Views

@interface KOGLView : UIView
@end

@implementation KOGLView
+ (Class)layerClass
{
    return [CAEAGLLayer class];
}
@end

// A key on the screen: down while touched
@interface KOKeyButton : UIControl {
@public
    int key;
    NSString *label;
    int arrow;   // 0, or a triangle drawn instead of the label: 1 up, 2 left, 3 down, 4 right (iOS 6 draws the
                 // arrow characters as emoji)
}
@end

@implementation KOKeyButton

- (id)initWithFrame:(CGRect)frame key:(int)k label:(NSString *)text
{
    if ((self = [super initWithFrame:frame])) {
        key = k;
        label = [text copy];
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        [self addTarget:self action:@selector(keyDown) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(keyUp)
            forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    }
    return self;
}

- (void)dealloc
{
    [label release];
    [super dealloc];
}

- (void)keyDown
{
    ko_post_event(KO_EVENT_KEY, key, 1, key == KO_KEY_SPACE ? ' ' : 0);
}

- (void)keyUp
{
    ko_post_event(KO_EVENT_KEY, key, 0, 0);
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGRect r = CGRectInset(self.bounds, 1.5, 1.5);
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:MIN(r.size.width, r.size.height) * 0.22];
    [[UIColor colorWithWhite:self.highlighted ? 0.5 : 0.1 alpha:0.5] setFill];
    [p fill];
    // (the glass: light on the upper half)
    CGContextSaveGState(c);
    [p addClip];
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = { 1, 1, 1, 0.32, 1, 1, 1, 0.06 };
    CGFloat locations[] = { 0, 1 };
    CGGradientRef g = CGGradientCreateWithColorComponents(space, colors, locations, 2);
    CGContextDrawLinearGradient(c, g, CGPointMake(0, CGRectGetMinY(r)), CGPointMake(0, CGRectGetMidY(r)), 0);
    CGGradientRelease(g);
    CGColorSpaceRelease(space);
    CGContextRestoreGState(c);
    [[UIColor colorWithWhite:1 alpha:0.5] setStroke];
    p.lineWidth = 1.5;
    [p stroke];
    if (arrow) {
        CGFloat cx = CGRectGetMidX(self.bounds), cy = CGRectGetMidY(self.bounds), s = MIN(r.size.width, r.size.height) * 0.22;
        CGContextSaveGState(c);
        CGContextTranslateCTM(c, cx, cy);
        CGContextRotateCTM(c, (arrow - 1) * -M_PI_2);   // (drawn pointing up, turned)
        CGContextMoveToPoint(c, 0, -s);
        CGContextAddLineToPoint(c, s * 1.1, s * 0.8);
        CGContextAddLineToPoint(c, -s * 1.1, s * 0.8);
        CGContextClosePath(c);
        CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 0, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
        CGContextSetRGBFillColor(c, 1, 1, 1, 0.92);
        CGContextFillPath(c);
        CGContextRestoreGState(c);
        return;
    }
    UIFont *font = [UIFont boldSystemFontOfSize:label.length > 2 ? 15 : 22];
    CGSize size = [label sizeWithFont:font];
    [[UIColor colorWithWhite:0 alpha:0.6] set];
    CGPoint at = CGPointMake(floor((self.bounds.size.width - size.width) / 2), floor((self.bounds.size.height - size.height) / 2));
    [label drawAtPoint:CGPointMake(at.x, at.y + 1) withFont:font];
    [[UIColor colorWithWhite:1 alpha:0.92] set];
    [label drawAtPoint:at withFont:font];
}

@end

// The controls' layer: lets the touches between the keys through to the game
@interface KOControlsView : UIView
@end

@implementation KOControlsView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *v = [super hitTest:point withEvent:event];
    return v == self ? nil : v;
}
@end

@interface KOGameView : UIView <UITextFieldDelegate> {
@public
    KOGLView *glView;
    int fbWidth, fbHeight;
    KOControlsView *controls;
    UIView *moveControls;       // shown while the mouse is grabbed
    UITextField *textInput;     // brings up the keyboard
    UITouch *pointer;           // the finger that is the mouse
    BOOL pointerGrabbed;        // (how that finger started: looking around or pointing)
    BOOL holding;               // left button down by a held finger
    CGPoint last;
    CGFloat moved, restX, restY;
    NSTimeInterval began;
    NSTimer *holdTimer;
}
@end

@implementation KOGameView

- (id)initWithFrame:(CGRect)frame width:(int)width height:(int)height
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor blackColor];
        self.multipleTouchEnabled = YES;
        fbWidth = width;
        fbHeight = height;
        glView = [[KOGLView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
        // (one point a framebuffer pixel; the view is scaled to the screen instead)
        glView.contentScaleFactor = 1;
        glView.userInteractionEnabled = NO;
        CAEAGLLayer *layer = (CAEAGLLayer *)glView.layer;
        layer.opaque = YES;
        layer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool:NO], kEAGLDrawablePropertyRetainedBacking,
            kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat, nil];
        [self addSubview:glView];
        [self buildControls];
        [self layoutGame];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(willResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
        [nc addObserver:self selector:@selector(didBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [holdTimer invalidate];
    textInput.delegate = nil;
    [glView release];
    [controls release];
    [moveControls release];
    [textInput release];
    [super dealloc];
}

- (KOKeyButton *)key:(int)key label:(NSString *)label frame:(CGRect)frame in:(UIView *)parent mask:(UIViewAutoresizing)mask
{
    KOKeyButton *b = [[KOKeyButton alloc] initWithFrame:frame key:key label:label];
    b.autoresizingMask = mask;
    [parent addSubview:b];
    [b release];
    return b;
}

- (void)buildControls
{
    CGSize s = self.bounds.size;
    controls = [[KOControlsView alloc] initWithFrame:self.bounds];
    controls.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    controls.backgroundColor = [UIColor clearColor];
    controls.multipleTouchEnabled = YES;
    [self addSubview:controls];

    moveControls = [[KOControlsView alloc] initWithFrame:controls.bounds];
    moveControls.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    moveControls.backgroundColor = [UIColor clearColor];
    moveControls.multipleTouchEnabled = YES;
    moveControls.hidden = !g_grabbed;
    [controls addSubview:moveControls];

    const CGFloat k = 70, gap = 6, m = 22;
    UIViewAutoresizing bottomLeft = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
    UIViewAutoresizing bottomRight = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin;
    UIViewAutoresizing topRight = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin;
    // the cross: forwards, left, backwards, right
    CGFloat x0 = m, y0 = s.height - m - 3 * k - 2 * gap;
    [self key:KO_KEY_W label:@"" frame:CGRectMake(x0 + k + gap, y0, k, k) in:moveControls mask:bottomLeft]->arrow = 1;
    [self key:KO_KEY_A label:@"" frame:CGRectMake(x0, y0 + k + gap, k, k) in:moveControls mask:bottomLeft]->arrow = 2;
    [self key:KO_KEY_S label:@"" frame:CGRectMake(x0 + k + gap, y0 + 2 * (k + gap), k, k) in:moveControls mask:bottomLeft]->arrow = 3;
    [self key:KO_KEY_D label:@"" frame:CGRectMake(x0 + 2 * (k + gap), y0 + k + gap, k, k) in:moveControls mask:bottomLeft]->arrow = 4;
    // jump and sneak
    CGFloat big = 92;
    [self key:KO_KEY_SPACE label:KOText(@"Jump") frame:CGRectMake(s.width - m - big, s.height - m - big, big, big) in:moveControls mask:bottomRight];
    [self key:KO_KEY_LSHIFT label:KOText(@"Sneak") frame:CGRectMake(s.width - m - big - gap - k, s.height - m - k, k, k) in:moveControls mask:bottomRight];
    // inventory and chat
    CGFloat small = 54;
    [self key:KO_KEY_E label:@"E" frame:CGRectMake(s.width - m - 3 * small - 2 * gap, m, small, small) in:moveControls mask:topRight];
    [self key:KO_KEY_T label:@"T" frame:CGRectMake(s.width - m - 4 * small - 3 * gap, m, small, small) in:moveControls mask:topRight];
    // always: the pause menu (back) and the keyboard
    [self key:KO_KEY_ESCAPE label:@"Esc" frame:CGRectMake(s.width - m - small, m, small, small) in:controls mask:topRight];
    KOKeyButton *kb = [self key:KO_KEY_NONE label:@"Aa" frame:CGRectMake(s.width - m - 2 * small - gap, m, small, small) in:controls mask:topRight];
    [kb removeTarget:kb action:NULL forControlEvents:UIControlEventAllEvents];
    [kb addTarget:self action:@selector(toggleKeyboard) forControlEvents:UIControlEventTouchUpInside];

    textInput = [[UITextField alloc] initWithFrame:CGRectMake(-100, -100, 10, 10)];
    textInput.autocorrectionType = UITextAutocorrectionTypeNo;
    textInput.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textInput.keyboardAppearance = UIKeyboardAppearanceAlert;
    textInput.text = @" ";   // (something to delete: a backspace on an empty field is not reported)
    textInput.delegate = self;
    [self addSubview:textInput];
}

- (void)layoutGame
{
    CGSize b = self.bounds.size;
    CGFloat scale = MIN(b.width / fbWidth, b.height / fbHeight);
    glView.transform = CGAffineTransformIdentity;
    glView.bounds = CGRectMake(0, 0, fbWidth, fbHeight);
    glView.center = CGPointMake(b.width / 2, b.height / 2);
    glView.transform = CGAffineTransformMakeScale(scale, scale);
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self layoutGame];
}

- (void)grabbedChanged
{
    moveControls.hidden = !g_grabbed;
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    if (!newSuperview) {
        [holdTimer invalidate];
        holdTimer = nil;
        [textInput resignFirstResponder];
    }
}

#pragma mark Keyboard

- (void)toggleKeyboard
{
    if (textInput.isFirstResponder) [textInput resignFirstResponder];
    else [textInput becomeFirstResponder];
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    if (string.length == 0) {
        ko_post_key(KO_KEY_BACK, '\b');
        return NO;
    }
    for (NSUInteger i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c == '\n') ko_post_key(KO_KEY_RETURN, '\r');
        else ko_post_key(ko_key_for_char(c), c);
    }
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field
{
    ko_post_key(KO_KEY_RETURN, '\r');
    return NO;
}

#pragma mark Touches

// A touch's place on the framebuffer (pixels from the top left)
- (CGPoint)framebufferPoint:(UITouch *)touch
{
    CGPoint p = [touch locationInView:glView];
    p.x = MAX(0, MIN(fbWidth - 1, p.x));
    p.y = MAX(0, MIN(fbHeight - 1, p.y));
    return p;
}

- (void)postPosition:(CGPoint)p
{
    ko_post_event(KO_EVENT_MOUSE_MOVE, (int)p.x, fbHeight - 1 - (int)p.y, 0);
}

- (void)holdFired:(NSTimer *)timer
{
    holdTimer = nil;
    if (pointer && pointerGrabbed && !holding) {
        holding = YES;
        ko_post_event(KO_EVENT_MOUSE_BUTTON, 0, 1, 0);
    }
}

// Minecraft's hotbar, while playing: a tap on one of its nine slots is the slot's number key. Where it is follows the
// game's own arithmetic: the largest GUI scale that keeps 320 x 240 units, the bar 182 x 22 units at the bottom.
- (int)hotbarSlotAt:(CGPoint)p
{
    int scale = 1;
    while (fbWidth / (scale + 1) >= 320 && fbHeight / (scale + 1) >= 240) scale++;
    CGFloat left = (fbWidth / scale / 2 - 91) * scale, top = (fbHeight / scale - 22) * scale;
    if (p.y < top || p.x < left || p.x >= left + 182 * scale) return -1;
    return MIN(8, (int)((p.x - left) / (20 * scale)));
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    for (UITouch *t in touches) {
        if (g_grabbed) {
            int slot = [self hotbarSlotAt:[self framebufferPoint:t]];
            if (slot >= 0) {
                ko_post_key(2 + slot, '1' + slot);   // (KEY_1 is 2)
                continue;
            }
        }
        if (pointer) break;   // (one finger is the mouse)
        pointer = t;
        pointerGrabbed = g_grabbed;
        holding = NO;
        last = [self framebufferPoint:t];
        moved = restX = restY = 0;
        began = t.timestamp;
        if (pointerGrabbed) {
            [holdTimer invalidate];
            holdTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(holdFired:) userInfo:nil repeats:NO];
        } else {
            [self postPosition:last];
            ko_post_event(KO_EVENT_MOUSE_BUTTON, 0, 1, 0);
        }
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (!pointer || ![touches containsObject:pointer]) return;
    CGPoint p = [self framebufferPoint:pointer];
    CGFloat dx = p.x - last.x, dy = p.y - last.y;
    last = p;
    moved += fabs(dx) + fabs(dy);
    if (pointerGrabbed) {
        if (moved > 12 && holdTimer) {
            [holdTimer invalidate];
            holdTimer = nil;
        }
        // (look around by as much as the finger moved; up is positive for the game)
        restX += dx;
        restY -= dy;
        int ix = (int)restX, iy = (int)restY;
        restX -= ix;
        restY -= iy;
        if (ix || iy) ko_post_event(KO_EVENT_MOUSE_DELTA, ix, iy, 0);
    } else {
        [self postPosition:p];
    }
}

- (void)endPointer:(UITouch *)t cancelled:(BOOL)cancelled
{
    [holdTimer invalidate];
    holdTimer = nil;
    if (pointerGrabbed) {
        if (holding) {
            ko_post_event(KO_EVENT_MOUSE_BUTTON, 0, 0, 0);
        } else if (!cancelled && moved < 12 && t.timestamp - began < 0.3) {
            // a tap: the right button (use, place)
            ko_post_event(KO_EVENT_MOUSE_BUTTON, 1, 1, 0);
            ko_post_event(KO_EVENT_MOUSE_BUTTON, 1, 0, 0);
        }
    } else {
        [self postPosition:[self framebufferPoint:t]];
        // (a quick tap is held down at least 0.15 s for the game: Minecraft reads clicks 20 times a second, and its
        // lists - GuiSlot - throw away the ones whose button is already up when they draw)
        NSTimeInterval held = t.timestamp - began;
        if (held >= 0.15) {
            ko_post_event(KO_EVENT_MOUSE_BUTTON, 0, 0, 0);
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((0.15 - held) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                ko_post_event(KO_EVENT_MOUSE_BUTTON, 0, 0, 0);
            });
        }
    }
    holding = NO;
    pointer = nil;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (pointer && [touches containsObject:pointer]) [self endPointer:pointer cancelled:NO];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (pointer && [touches containsObject:pointer]) [self endPointer:pointer cancelled:YES];
}

#pragma mark The app in the background

- (void)willResignActive:(NSNotification *)n
{
    ko_post_event(KO_EVENT_FOCUS, 0, 0, 0);
    ko_set_inactive(1);
}

- (void)didBecomeActive:(NSNotification *)n
{
    ko_set_inactive(0);
    ko_post_event(KO_EVENT_FOCUS, 1, 0, 0);
}

@end

#pragma mark - The window

struct KOWindow {
    KOGameView *view;   // retained
    CAEAGLLayer *layer; // the view's
    int width, height;
};

void *ko_window_layer(KOWindow *window)
{
    return window->layer;
}

int ko_window_width(KOWindow *window)
{
    return window->width;
}

int ko_window_height(KOWindow *window)
{
    return window->height;
}

static KOWindow *ko_window(JNIEnv *env, jobject handle)
{
    return handle ? (KOWindow *)(*env)->GetDirectBufferAddress(env, handle) : NULL;
}

// The screen in pixels, landscape (the app is landscape only; iOS 6 reports the screen portrait)
static CGSize ko_screen_pixels(void)
{
    __block CGSize size;
    ko_on_main(^{
        UIScreen *screen = [UIScreen mainScreen];
        CGSize s = screen.bounds.size;
        size = CGSizeMake(MAX(s.width, s.height) * screen.scale, MIN(s.width, s.height) * screen.scale);
    });
    return size;
}

static UIView *ko_host_view(void)
{
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *window = app.keyWindow;
    if (!window && app.windows.count) window = [app.windows objectAtIndex:0];
    return window.rootViewController.view ?: window;
}

JNIEXPORT jint JNICALL Java_org_lwjgl_opengl_MacOSXDisplay_nGetScreenWidth(JNIEnv *env, jclass clazz)
{
    @autoreleasepool {
        return (jint)ko_screen_pixels().width;
    }
}

JNIEXPORT jint JNICALL Java_org_lwjgl_opengl_MacOSXDisplay_nGetScreenHeight(JNIEnv *env, jclass clazz)
{
    @autoreleasepool {
        return (jint)ko_screen_pixels().height;
    }
}

JNIEXPORT jobject JNICALL Java_org_lwjgl_opengl_MacOSXDisplay_nCreateWindow(JNIEnv *env, jclass clazz, jint width, jint height, jboolean fullscreen)
{
    @autoreleasepool {
        CGSize screen = ko_screen_pixels();
        // (in fullscreen, or for a size beyond what the GPU and the memory take: the screen's size)
        if (fullscreen || width <= 0 || height <= 0 || width > 2048 || height > 2048) {
            width = (jint)screen.width;
            height = (jint)screen.height;
        }
        __block KOWindow *window = NULL;
        ko_on_main(^{
            UIView *host = ko_host_view();
            if (!host) return;
            KOGameView *view = [[KOGameView alloc] initWithFrame:host.bounds width:width height:height];
            view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [host addSubview:view];
            window = calloc(1, sizeof(KOWindow));
            window->view = view;
            window->layer = (CAEAGLLayer *)view->glView.layer;
            window->width = width;
            window->height = height;
        });
        if (!window) {
            throwException(env, "There is no view to show the game in");
            return NULL;
        }
        pthread_mutex_lock(&g_pause_lock);
        g_windows++;
        pthread_mutex_unlock(&g_pause_lock);
        printfDebugJava(env, "Window %dx%d", (int)width, (int)height);
        return (*env)->NewDirectByteBuffer(env, window, sizeof(KOWindow));
    }
}

JNIEXPORT void JNICALL Java_org_lwjgl_opengl_MacOSXDisplay_nDestroyWindow(JNIEnv *env, jclass clazz, jobject handle)
{
    @autoreleasepool {
        KOWindow *window = ko_window(env, handle);
        if (!window) return;
        KOGameView *view = window->view;
        ko_on_main(^{
            [view removeFromSuperview];
            [view release];
        });
        pthread_mutex_lock(&g_pause_lock);
        g_windows--;
        pthread_mutex_unlock(&g_pause_lock);
        free(window);
    }
}

JNIEXPORT jint JNICALL Java_org_lwjgl_opengl_MacOSXDisplay_nGetWidth(JNIEnv *env, jclass clazz, jobject handle)
{
    KOWindow *window = ko_window(env, handle);
    return window ? window->width : 0;
}

JNIEXPORT jint JNICALL Java_org_lwjgl_opengl_MacOSXDisplay_nGetHeight(JNIEnv *env, jclass clazz, jobject handle)
{
    KOWindow *window = ko_window(env, handle);
    return window ? window->height : 0;
}

JNIEXPORT jint JNICALL Java_org_lwjgl_opengl_MacOSXDisplay_nPollEvents(JNIEnv *env, jclass clazz, jobject handle, jobject buffer, jint max_events)
{
    KOEvent *out = (KOEvent *)(*env)->GetDirectBufferAddress(env, buffer);
    if (!out) return 0;
    pthread_mutex_lock(&g_event_lock);
    int n = g_event_count < max_events ? g_event_count : max_events;
    for (int i = 0; i < n; i++) out[i] = g_events[(g_event_head + i) % KO_MAX_EVENTS];
    g_event_head = (g_event_head + n) % KO_MAX_EVENTS;
    g_event_count -= n;
    pthread_mutex_unlock(&g_event_lock);
    return n;
}

JNIEXPORT void JNICALL Java_org_lwjgl_opengl_MacOSXDisplay_nSetGrabbed(JNIEnv *env, jclass clazz, jobject handle, jboolean grabbed)
{
    @autoreleasepool {
        g_grabbed = grabbed ? 1 : 0;
        KOWindow *window = ko_window(env, handle);
        if (!window) return;
        KOGameView *view = window->view;
        dispatch_async(dispatch_get_main_queue(), ^{
            [view grabbedChanged];
        });
    }
}

#pragma mark - System (MacOSXSysImplementation)

JNIEXPORT jint JNICALL Java_org_lwjgl_DefaultSysImplementation_getJNIVersion(JNIEnv *env, jobject ignored)
{
    return 25;   // (MacOSXSysImplementation.JNI_VERSION)
}

static NSString *ko_string(JNIEnv *env, jstring s)
{
    if (!s) return @"";
    const jchar *chars = (*env)->GetStringChars(env, s, NULL);
    NSString *result = [NSString stringWithCharacters:chars length:(*env)->GetStringLength(env, s)];
    (*env)->ReleaseStringChars(env, s, chars);
    return result;
}

JNIEXPORT void JNICALL Java_org_lwjgl_MacOSXSysImplementation_nAlert(JNIEnv *env, jclass clazz, jstring title, jstring message)
{
    @autoreleasepool {
        NSString *t = ko_string(env, title), *m = ko_string(env, message);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:t message:m delegate:nil cancelButtonTitle:KOText(@"OK") otherButtonTitles:nil];
            [alert show];
            [alert release];
        });
    }
}

JNIEXPORT jboolean JNICALL Java_org_lwjgl_MacOSXSysImplementation_nOpenURL(JNIEnv *env, jclass clazz, jstring url)
{
    @autoreleasepool {
        NSURL *u = [NSURL URLWithString:ko_string(env, url)];
        if (!u) return JNI_FALSE;
        __block BOOL opened = NO;
        ko_on_main(^{
            opened = [[UIApplication sharedApplication] openURL:u];
        });
        return opened ? JNI_TRUE : JNI_FALSE;
    }
}

JNIEXPORT jstring JNICALL Java_org_lwjgl_MacOSXSysImplementation_nGetClipboard(JNIEnv *env, jclass clazz)
{
    @autoreleasepool {
        __block NSString *text = nil;
        ko_on_main(^{
            text = [[UIPasteboard generalPasteboard].string copy];
        });
        if (!text) return NULL;
        NSUInteger length = text.length;
        unichar *chars = malloc(sizeof(unichar) * (length ? length : 1));
        [text getCharacters:chars range:NSMakeRange(0, length)];
        jstring result = (*env)->NewString(env, chars, (jsize)length);
        free(chars);
        [text release];
        return result;
    }
}
