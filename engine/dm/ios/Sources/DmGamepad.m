// Virtual gamepad (Nintendo button positions) + physical controllers (GameController), handed to the host through dm_input_set and dm_pad_set_player (hle_hid.c, bit layout in dm_input.h).
//   Two layouts, three in handheld mode, picked in the in-game menu (GameMenu.swift) that the menu button at the top centre (a gear) opens; the choice is kept in NSUserDefaults (each game is its own app, so per game); the first launch uses the game profile's pad_layout (DM_GAME_PAD_LAYOUT).
//   The menu button stays while a physical controller is connected, so the menu is there in every layout and with every controller. Its last item quits the game
//     (a prompt, front_ios.m), and so does holding a controller's Home button for 2 seconds.
//   Tap (touch): no control but the menu button, every other touch goes to the game's local touch viewport; offered only while the game is in handheld mode, the only one in which it reads the touch screen (Balatro, played by touch).
//   2D (simple): top corners ZL above L (one column), ZR above R likewise, teardrops with the tip toward the screen corner; − and + side by side at the top centre; the left stick in the bottom-left corner (fixed ring, tilt measured from the ring centre, small dead zone);
//     the A (right) B (bottom) X (top) Y (left) diamond in the bottom-right corner, sliding a finger between keys switches keys. Each bottom corner holds a single control, so it sits close in (reaching halfway into the side safe-area inset).
//   3D (full, Pro Controller style): everything in 2D (left stick and diamond keep their place and size), plus a D-pad (inward of and below the left stick, 8-way), a right stick that is not drawn
//     (a touch landing in the right third of the screen on no control holds it: centred where it lands, the centre dragged along once the finger passes the stick radius) and L3 / R3 (small round keys in the top row, inward of ZL / ZR).
//     Breath of the Wild crouches with L3 and uses the scope with R3; 3D World and Breath of the Wild turn the camera with the right stick.
//     The first time the 3D layout shows in a launch, a few words (DM_TOUCH_HINT) say where the undrawn right stick is, for two seconds; see "The right-stick hint".
//   Touch-down ownership (dm_pad_menu_takes and dm_pad_hit in DmPadGeometry.h): the menu button where it is nearer than a locked key (a view of its own, DmMenuButton), locked keys next (shoulders, − / +, L3 / R3), then whichever of the diamond, the D-pad and the left stick has the smallest distance / grab radius (the left stick's grab circle borders the D-pad),
//     then in 3D the right stick for a touch in the right third.
//   The player can move single controls in the shell's settings (DM_TOUCH_LAYOUT, one arrangement per layout): the geometry places each only where it fits and keeps the rest where they were.
//   Everything hugs the edges and corners to leave the picture room; controls sit over the picture, one CAShapeLayer each: a press only swaps the fill, a stick only moves its knob, nothing redraws the whole screen.
//   Where each control sits is DmPadGeometry.h (pure, tested on the Mac); the player picks the size there through DM_TOUCH_SIZE (small, medium, large; a size that does not fit the screen moves toward medium) and the left stick's place through DM_TOUCH_STICK (corner, higher, inward).
//   Touches no control takes (in 3D, those outside the right third) go to the game's touch screen when DmLayout assigns a local game viewport (pushGame; Super Mario Galaxy's pointer in handheld mode).
//   The virtual gamepad (all but the menu button) hides while a physical controller is connected and comes back when it is removed; unclaimed touches go to the game only when a local game viewport exists. Physical controllers keep every button (D-pad and right stick included) and map by position: bottom = B, right = A, left = Y, top = X (same positions as on a Switch controller); a Nintendo pad maps by its labels (pad_apple.h).
//   Each physical controller is a player of its own (local co-op), as on the Mac: the first one connected is player 1, together with the touch gamepad, the next player 2, and so on up to 8; see "Physical controllers" below.
//   Shaking the phone shakes the controller (DM_BTN_SHAKE: its six-axis sensor, hle_hid.c), whichever controls are in use; see "Shaking the phone" below.
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <CoreMotion/CoreMotion.h>
#import <CoreText/CoreText.h>
#include <pthread.h>
#include "dm.h"
#include "dm_input.h"
#include "front.h"
#include "game_profile.h"
#include "haptics_apple.h"
#include "motion_apple.h"
#include "motion_fusion.h"
#include "pad_apple.h"
#include "pad_slots.h"
#include "input_map.h"
#include <stdatomic.h>
#import "DmLayout.h"
#import "DmPadGeometry.h"
#import "DmGameMenu.h"

enum { B_A = 0, B_B, B_X, B_Y, B_LS, B_RS, B_L, B_R, B_ZL, B_ZR, B_PLUS, B_MINUS, B_LEFT, B_UP, B_RIGHT, B_DOWN, B_N };
enum { C_NONE = 0, C_STICK, C_DPAD, C_FACE, C_BTN, C_GAME };   // which control a touch holds; C_GAME: none, the touch goes to the game's touch screen (finger slot << 8)

static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;
static uint64_t g_touch_btn, g_shake_btn;
static int32_t g_touch_lx, g_touch_ly, g_touch_rx, g_touch_ry;
static void publish(void) {   // the touch gamepad and the shake; the host ORs them with player 1's controller and takes whichever stick is deflected more (hle_hid.c)
    pthread_mutex_lock(&g_mu);
    dm_input_set(g_touch_btn | g_shake_btn, g_touch_lx, g_touch_ly, g_touch_rx, g_touch_ry);
    pthread_mutex_unlock(&g_mu);
}

// ---- Shaking the phone ----
// The accelerometer at 60 Hz (no gyroscope, no permission prompt): gravity is followed by a slow low-pass (about 0.8 s), and a sample whose acceleration beyond it exceeds DM_SHAKE_G
// (1.5 G by default; Documents/env.txt overrides) is a hit. The controller is shaken until 120 ms after the last hit: a flick is one shake (the host finishes it as a whole cycle)
// and shaking on keeps it going. Holding the phone and pressing the screen stays far below the threshold. Each detected shake is logged with its peak
static CMMotionManager *g_motion;
static void motion_start(void) {
    if (g_motion) return;
    g_motion = [CMMotionManager new];
    if (!g_motion.accelerometerAvailable) { LOG("front end: no accelerometer, shaking the phone does nothing"); return; }
    const char *e = getenv("DM_SHAKE_G"); double thr = e && atof(e) > 0 ? atof(e) : 1.5;
    LOG("front end: shaking the phone shakes the controller (threshold %.2f G)", thr);
    g_motion.accelerometerUpdateInterval = 1.0 / 60;
    NSOperationQueue *q = [NSOperationQueue new]; q.maxConcurrentOperationCount = 1;
    __block double gx = 0, gy = 0, gz = 0, last = -1, peak = 0; __block BOOL init = NO;
    [g_motion startAccelerometerUpdatesToQueue:q withHandler:^(CMAccelerometerData *d, NSError *err) {
        (void)err; if (!d) return;
        CMAcceleration a = d.acceleration;
        if (!init) { gx = a.x; gy = a.y; gz = a.z; init = YES; }
        double dx = a.x - gx, dy = a.y - gy, dz = a.z - gz, g = sqrt(dx * dx + dy * dy + dz * dz);
        gx += (a.x - gx) * 0.02; gy += (a.y - gy) * 0.02; gz += (a.z - gz) * 0.02;
        if (g > thr) { if (last < 0) peak = 0; last = d.timestamp; peak = fmax(peak, g); }
        BOOL on = last >= 0 && d.timestamp - last < 0.12;
        if (!on && last >= 0) { LOG("front end: phone shaken (peak %.1f G)", peak); last = -1; }
        uint64_t want = on ? DM_BTN_SHAKE : 0;
        pthread_mutex_lock(&g_mu); BOOL changed = g_shake_btn != want; g_shake_btn = want; pthread_mutex_unlock(&g_mu);
        if (changed) publish();
    }];
}

// ---- The phone's gyro ----
// A controller mounted on the phone (Backbone One, Razer Kishi, GameSir G8) has no motion sensors of its own: the phone in the middle is the console, as a Switch in handheld.
// So the phone's device motion (gyro + accelerometer, CoreMotion's fused gravity and user acceleration, 100 Hz, no permission prompt) drives player 1's six-axis sensor, turned
// into the Switch frame for the screen's orientation (motion_phone_to_switch, motion_fusion.h): x to the right of the picture, y to its top, z toward the player.
// The host keeps phone and controller orientations separately, choosing fresh controller data in auto mode and the phone alone in forced mode.
// DM_PHONE_MOTION: auto (default) while no controller supplies fresh gyro data (a DualSense held apart from the phone uses its own, motion_apple.h), 1 always, 0 never.
// DM_MOTION=0 (all live motion off; the NSP script's --no-motion builds it in) never starts device motion.
// Which frame the samples come in: on iOS 27 and later the pad view (full screen, over the picture) is the motion body (CMMotionManager.deviceMotionBody), so Core Motion delivers
// them in that view's frame for whichever display shows it and however it is turned: x to the right of the picture, y to its top, z toward the player, the Switch frame as it is.
// Before that they come in the hardware frame, turned here by the interface orientation, which holds only where the hardware frame is the screen's portrait frame: not on iPhone
// Duo's inner display, whose picture is a quarter turn from it (up / down and left / right swapped, GitHub issue #569). Open: while the scene is not full screen (Split View on the
// inner display) Core Motion falls back to the hardware frame without saying so, and the samples are then taken as the view's frame
static _Atomic int g_iface_orient = 3;      // UIInterfaceOrientation, updated on layout
static BOOL g_motion_body;                  // samples in the body's frame (iOS 27+)
static void phone_motion_start(UIView *body) {
    const char *e = getenv("DM_MOTION");
    if (e && !atoi(e)) { LOG("front end: motion is off (DM_MOTION=0), the phone's gyro is not used"); return; }
    e = getenv("DM_PHONE_MOTION"); int mode = !e || !strcmp(e, "auto") ? -1 : atoi(e);
    if (!mode) { LOG("front end: the phone's gyro is off (DM_PHONE_MOTION=0)"); return; }
    if (!g_motion.deviceMotionAvailable) { LOG("front end: no device motion, the phone's gyro is not used"); return; }
    LOG("front end: the phone's gyro drives the controller's six-axis sensor %s", mode < 0 ? "while no controller supplies fresh motion" : "always (DM_PHONE_MOTION=1)");
    g_motion.deviceMotionUpdateInterval = 1.0 / 100;
    if (@available(iOS 27.0, *)) { g_motion.deviceMotionBody = body; g_motion_body = YES; LOG("front end: the phone's motion comes in the pad view's frame (deviceMotionBody)"); }
    NSOperationQueue *q = [NSOperationQueue new]; q.maxConcurrentOperationCount = 1;
    [g_motion startDeviceMotionUpdatesToQueue:q withHandler:^(CMDeviceMotion *d, NSError *err) {
        (void)err; if (!d) return;
        float a[3] = {(float)(d.gravity.x + d.userAcceleration.x), (float)(d.gravity.y + d.userAcceleration.y), (float)(d.gravity.z + d.userAcceleration.z)};
        float w[3] = {(float)d.rotationRate.x, (float)d.rotationRate.y, (float)d.rotationRate.z}, as[3], ws[3];
        int o = g_motion_body ? 1 : atomic_load(&g_iface_orient);   // the body's frame is already the picture's: the portrait map, which leaves it as it is
        motion_phone_to_switch(o, a, as); motion_phone_to_switch(o, w, ws);
        dm_motion_set_switch(0, as, ws);
    }];
}

// ---- Layout constants ----
// Where each control is drawn (in u, x measured from the outer edge, the right half mirrors) is DmPadGeometry.h: pure functions of the bounds, the safe area,
// the DmLayout split and the player's options (DM_TOUCH_SIZE), tested on the Mac (dm/ios/tests/test_pad_geometry.py). Drawing, the hit-test and the grab all read it.
// The bottom-corner controls reach halfway into the side safe-area inset (in landscape there is only the rounded screen corner there; the Dynamic Island is mid-edge);
// the stick's ring is as large as the whole diamond (key distance + key radius), the knob a little larger than a diamond key; the D-pad sits inward of and below the
// left stick, as on a Pro Controller. The menu button is at the top centre, level with - / +, and takes a touch within 1.6 times its radius (at least 22 points, half of a 44-point target). What stays here is how touches are taken:
static const CGFloat                               // (the grab radii of the stick and the D-pad are DmPadGeometry.h's DM_PAD_STICK_GRAB and DM_PAD_DPAD_GRAB)
    K_FULL = 0.8,                                   // full tilt at this fraction of the ring radius (the knob still travels to the ring edge)
    K_DEAD = 0.1,                                   // stick dead zone (times the ring radius)
    K_RSTICK_R = 60,                                // right stick (not drawn): radius around its centre, the touch-down point
    K_RSWIPE = 1.0 / 3;                             // right stick area: this fraction of the screen width from the right edge (not in u)
static const int k_btns[] = {B_ZL, B_L, B_ZR, B_R, B_MINUS, B_PLUS, B_LS, B_RS};   // keys locked at touch-down (L3 / R3 only in the 3D layout)
static NSString *const k_layout_key = @"DmPadLayout";   // NSUserDefaults: 0 = 2D, 1 = 3D, 2 = Tap (DM_GAME_PAD_LAYOUT's numbers)
int dm_opmode(void);   // hle_oe.c: 0 = handheld
void front_ios_quit_poll(void);          // front_ios.m: a controller's buttons changed (the Home hold, A and B in the quit prompt)
int front_ios_quit_blocks_input(void);   // front_ios.m: the quit prompt has the controllers, the game gets none
void front_ios_quit_controllers(void);   // front_ios.m: the controllers changed (it reads the Home button setting once)

@interface DmGamepad : UIView
- (void)arrange:(DmLayout)layout;
- (BOOL)menuTakes:(CGPoint)p;
@end
// The menu button: a UIButton whose menu is the in-game menu (UIKit draws it and takes the touches while it is open). Its hit circle is larger than the drawn one, and a key nearer
// to the touch wins (− / + sit beside it), so it asks the pad
@interface DmMenuButton : UIButton
@end
@implementation DmMenuButton
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e { DmGamepad *pad = (DmGamepad *)self.superview; return [pad menuTakes:[self convertPoint:p toView:pad]]; }
@end
static __weak DmGamepad *g_view;
static void pads_start(void);   // Physical controllers, below

@implementation DmGamepad {
    NSMapTable<UITouch *, NSNumber *> *_owner;     // touch → control (with the key for C_BTN or the stick for C_STICK, << 8)
    UITouch *_stick[2]; CGPoint _stickNow[2];      // the touch holding each stick and where it is now (0 left, 1 right)
    CGPoint _rCentre;                              // the right stick's centre: where its touch landed, dragged along past K_RSTICK_R
    uint64_t _faceBits, _dpadBits, _btnBits;
    NSMapTable<UITouch *, NSNumber *> *_faceOf;    // which keys each touch on the diamond currently holds
    CAShapeLayer *_key[B_N]; CATextLayer *_label[B_N];   // one layer per key
    CAShapeLayer *_ring, *_knob;                   // the left stick (the right one is not drawn)
    CALayer *_hint; CATextLayer *_hintText; NSString *_hintWords;   // the 3D layout's right-stick hint: words only, once per launch (see "The right-stick hint")
    DmMenuButton *_menu;                           // opens the in-game menu (GameMenu.swift)
    UIImpactFeedbackGenerator *_touchFeedback;       // one short feedback per touch-control press edge
    unsigned _hapticSticks;
    BOOL _stickShown;                              // the left stick was held at the last refresh
    BOOL _full, _tap;                              // the 3D layout / the Tap layout is current
    CALayer *_controls;                            // holds every control layer: hidden while a physical controller is connected (the view itself stays, for game touches)
    BOOL _padOff;                                  // a physical controller is connected: every touch goes to the game
    DmLayout _layout;
    DmPadOptions _opts;                            // the player's options from the environment (DM_TOUCH_SIZE, DM_TOUCH_STICK, DM_TOUCH_LAYOUT)
    DmPadLayout _arrangement;                      // DM_TOUCH_LAYOUT, which _opts.layout points to
    DmPadGeo _geo; CGRect _geoBounds; UIEdgeInsets _geoInsets; BOOL _geoFull, _geoValid;   // where the controls are, and what it was computed for
    unsigned _loggedDropped;                       // the moved controls that kept their place, as last logged
    UITouch *_game[16];                           // touches on the game's touch screen by finger slot
}

static UIColor *k_idle, *k_on, *k_line, *k_ringFill, *k_text, *k_textOn;
static CAShapeLayer *shape(CALayer *parent) {
    CAShapeLayer *l = [CAShapeLayer layer];
    l.fillColor = k_idle.CGColor; l.strokeColor = k_line.CGColor; l.lineWidth = 1.5;
    l.shadowColor = UIColor.blackColor.CGColor; l.shadowOpacity = 0.2; l.shadowRadius = 3; l.shadowOffset = CGSizeMake(0, 1);
    [parent addSublayer:l]; return l;
}
static CATextLayer *label(CALayer *parent, NSString *s) {
    CATextLayer *t = [CATextLayer layer];
    t.string = s; t.alignmentMode = kCAAlignmentCenter; t.foregroundColor = k_text.CGColor;
    [parent addSublayer:t]; return t;
}
static BOOL fullOnly(int b) { return b == B_LS || b == B_RS || b >= B_LEFT; }   // keys shown only in the 3D layout

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _layout = dm_layout(self.bounds, UIEdgeInsetsZero, NO, CGRectNull, DM_PICTURE_16_9);   // until the front end arranges it
        const char *size = getenv("DM_TOUCH_SIZE");
        _opts.scale = dm_pad_size_scale(size);
        if (size && *size) LOG("front end: touch controls size %s (DM_TOUCH_SIZE)", _opts.scale < 1 ? "small" : _opts.scale > 1 ? "large" : "medium");
        const char *stick = getenv("DM_TOUCH_STICK");
        _opts.stick = dm_pad_stick_place(stick);
        if (stick && *stick) LOG("front end: left stick %s (DM_TOUCH_STICK)", _opts.stick == DM_PAD_STICK_HIGHER ? "higher" : _opts.stick == DM_PAD_STICK_INWARD ? "inward" : "in the corner");
        const char *arrangement = getenv("DM_TOUCH_LAYOUT");
        if (!dm_pad_layout_parse(arrangement, &_arrangement)) LOG("front end: DM_TOUCH_LAYOUT ignored (not a layout the engine reads, %zu characters): every control keeps its place", strlen(arrangement));
        else if (dm_pad_layout_count(&_arrangement)) LOG("front end: touch controls arranged by the player (DM_TOUCH_LAYOUT, %d moved over every layout)", dm_pad_layout_count(&_arrangement));
        _opts.layout = &_arrangement;
        [self registerForTraitChanges:@[UITraitDisplayScale.class] withHandler:^(id<UITraitEnvironment> environment, UITraitCollection *previous) {
            [(UIView *)environment setNeedsLayout];
        }];
        self.multipleTouchEnabled = YES; self.opaque = NO; self.backgroundColor = UIColor.clearColor;
        const char *feedback = getenv("DM_TOUCH_HAPTICS");
        if (!feedback || atoi(feedback)) {
            _touchFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [_touchFeedback prepare];
        }
        _owner = [NSMapTable strongToStrongObjectsMapTable]; _faceOf = [NSMapTable strongToStrongObjectsMapTable];
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            // each colour carries its own low opacity instead of lowering the whole view's alpha (that would add an off-screen pass for the full-screen layer)
            k_idle = [UIColor colorWithWhite:1 alpha:0.14]; k_on = [UIColor colorWithWhite:1 alpha:0.45]; k_line = [UIColor colorWithWhite:1 alpha:0.38];
            k_ringFill = [UIColor colorWithWhite:1 alpha:0.06]; k_text = [UIColor colorWithWhite:1 alpha:0.6]; k_textOn = [UIColor colorWithWhite:0 alpha:0.7];
        });
        _controls = [CALayer layer]; [self.layer addSublayer:_controls];
        _ring = shape(_controls); _ring.fillColor = k_ringFill.CGColor;
        _knob = shape(_controls);
        CAShapeLayer *in = [CAShapeLayer layer]; in.fillColor = nil; in.strokeColor = k_line.CGColor; in.lineWidth = 1.5;   // inner ring of the knob
        [_knob addSublayer:in];
        static NSString *const names[B_N] = {@"A", @"B", @"X", @"Y", @"L3", @"R3", @"L", @"R", @"ZL", @"ZR", @"+", @"−"};
        for (int b = 0; b < B_N; b++) {
            _key[b] = shape(_controls);
            if (names[b]) _label[b] = label(_key[b], names[b]);   // the D-pad arms carry no label
        }
        _menu = [DmMenuButton buttonWithType:UIButtonTypeCustom];
        _menu.backgroundColor = k_idle; _menu.layer.borderColor = k_line.CGColor; _menu.layer.borderWidth = 1.5;
        _menu.layer.shadowColor = UIColor.blackColor.CGColor; _menu.layer.shadowOpacity = 0.2; _menu.layer.shadowRadius = 3; _menu.layer.shadowOffset = CGSizeMake(0, 1);
        _menu.tintColor = k_text; _menu.accessibilityLabel = @"Menu";
        _menu.menu = CFBridgingRelease(dm_game_menu()); _menu.showsMenuAsPrimaryAction = YES;
        __weak DmGamepad *weakSelf = self;
        [_menu addAction:[UIAction actionWithHandler:^(UIAction *a) { (void)a; [weakSelf reset]; }] forControlEvents:UIControlEventMenuActionTriggered];   // the menu opens: release every key and touch first
        [self addSubview:_menu];
        const char *hint = getenv("DM_TOUCH_HINT");   // the shell passes the player's language; empty turns the hint off
        _hintWords = hint ? [NSString stringWithUTF8String:hint] : @"Right stick: drag here";
        _hint = [CALayer layer]; _hint.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5].CGColor; _hint.opacity = 0; _hint.hidden = YES;
        _hintText = [CATextLayer layer]; _hintText.string = _hintWords; _hintText.alignmentMode = kCAAlignmentCenter;
        _hintText.foregroundColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor; [_hint addSublayer:_hintText]; [_controls addSublayer:_hint];
        NSNumber *saved = [NSUserDefaults.standardUserDefaults objectForKey:k_layout_key];
        int l = saved ? (int)saved.integerValue : dm_profile()->pad_layout;
        if (l == 2 && dm_opmode() != 0) l = 0;   // Tap only in handheld mode (env.txt's DM_OPMODE may have changed it)
        _full = l == 1; _tap = l == 2;
        [self applyLayout];
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserver:self selector:@selector(padsChanged:) name:GCControllerDidConnectNotification object:nil];
        [nc addObserver:self selector:@selector(padsChanged:) name:GCControllerDidDisconnectNotification object:nil];
        pads_start();
        [self padsChanged:nil];
        motion_start();
        phone_motion_start(self);
    }
    return self;
}
- (void)applyLayout {   // show / hide the controls for the current layout
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (int b = 0; b < B_N; b++) _key[b].hidden = _tap || (fullOnly(b) && !_full);
    _ring.hidden = _knob.hidden = _tap;
    [CATransaction commit];
}
- (int)padLayout { return _tap ? 2 : _full ? 1 : 0; }
- (void)setPadLayout:(int)l {   // the in-game menu's pick: release every touch first (no key stays held), save, lay out again
    if (l == 2 && dm_opmode() != 0) l = 0;
    [self reset];
    _full = l == 1; _tap = l == 2;
    [NSUserDefaults.standardUserDefaults setObject:@(l) forKey:k_layout_key];
    [self applyLayout]; [self setNeedsLayout];
}
- (void)opmodeChanged {   // docked: the Tap layout goes (the game reads no touch screen then), unsaved, so handheld mode at the next start brings it back
    if (!_tap || dm_opmode() == 0) return;
    [self reset]; _tap = NO; _full = NO; [self applyLayout]; [self setNeedsLayout];
}
- (void)setTouchFeedback:(BOOL)on {
    if (!on) { _touchFeedback = nil; return; }
    if (!_touchFeedback) { _touchFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [_touchFeedback prepare]; }
}

// ---- Layout (points; computed inside the safe area) ----
- (void)arrange:(DmLayout)layout {
    if (CGRectEqualToRect(_layout.controls, layout.controls) && CGRectEqualToRect(_layout.game, layout.game) && _layout.separated == layout.separated && _layout.topSafeOnly == layout.topSafeOnly) return;
    [self reset];   // A finger held across a pose change must not leave a key or game touch stuck.
    _layout = layout; _geoValid = NO;
    [self setNeedsLayout];
}
- (const DmPadGeo *)geo {   // DmPadGeometry.h, computed again whenever the bounds, the safe area, the split or the layout changed
    CGRect b = self.bounds; UIEdgeInsets i = self.safeAreaInsets;
    if (!_geoValid || !CGRectEqualToRect(b, _geoBounds) || !UIEdgeInsetsEqualToEdgeInsets(i, _geoInsets) || _geoFull != _full) {
        _geo = dm_pad_geo(b, i, _layout, _full, _opts);
        _geoBounds = b; _geoInsets = i; _geoFull = _full; _geoValid = YES;
        if (_geo.dropped != _loggedDropped) {   // a moved control with no room on this screen: said once per change, for the log a player sends
            _loggedDropped = _geo.dropped;
            NSMutableArray<NSString *> *names = [NSMutableArray array];
            for (int c = 0; c < DM_PAD_C_N; c++) if (_geo.dropped & (1u << c)) [names addObject:@(dm_pad_control_names[c])];
            if (names.count) LOG("front end: touch layout: %s kept at the built-in place (no room there on this screen, or on another control)", [names componentsJoinedByString:@" "].UTF8String);
        }
    }
    return &_geo;
}
- (CGFloat)u { return self.geo->u; }   // 1 = 430 points tall (iPhone Pro Max landscape), times the player's size
- (CGPoint)faceCenter { return self.geo->face; }
- (CGFloat)faceGap { return self.geo->faceGap; }
- (CGFloat)faceR { return self.geo->faceR; }
- (CGFloat)faceHitR { return self.geo->faceHitR; }
- (CGPoint)facePos:(int)b { return dm_pad_face_key(self.geo, b - B_A); }   // B_A..B_Y are A, B, X, Y: the geometry's order
- (CGPoint)stickHome { return self.geo->stick; }
- (CGPoint)stickCentre:(int)i { return i ? _rCentre : self.stickHome; }
- (CGFloat)stickR:(int)i { return i ? K_RSTICK_R * self.u : self.geo->stickR; }
- (BOOL)inRightArea:(CGPoint)p { CGRect b = _layout.controls; return p.x >= CGRectGetMaxX(b) - b.size.width * K_RSWIPE; }
- (CGPoint)dpadCenter { return self.geo->dpad; }
- (CGFloat)dpadR { return self.geo->dpadR; }
static BOOL isDrop(int b) { return b == B_ZL || b == B_L || b == B_ZR || b == B_R; }
static BOOL isClick(int b) { return b == B_LS || b == B_RS; }
static int dropIndex(int b) { return b == B_ZL ? DM_PAD_ZL : b == B_L ? DM_PAD_L : b == B_ZR ? DM_PAD_ZR : DM_PAD_R; }
- (CGPoint)dropCenter:(int)b { return self.geo->drop[dropIndex(b)]; }
- (CGFloat)dropR:(int)b { return self.geo->dropR[dropIndex(b)]; }
- (CGPoint)clickCenter:(int)b { return self.geo->click[b == B_RS]; }
- (CGRect)pillRect:(int)b { return self.geo->pill[b == B_PLUS ? DM_PAD_PLUS : DM_PAD_MINUS]; }
- (CGPoint)menuCenter { return self.geo->swap; }

static CGFloat dist(CGPoint a, CGPoint b) { return hypot(a.x - b.x, a.y - b.y); }
static int lockedKey(int c) {   // DmPadGeometry.h's control → the key it presses
    switch (c) { case DM_PAD_C_ZL: return B_ZL; case DM_PAD_C_L: return B_L; case DM_PAD_C_ZR: return B_ZR; case DM_PAD_C_R: return B_R;
                 case DM_PAD_C_MINUS: return B_MINUS; case DM_PAD_C_PLUS: return B_PLUS; case DM_PAD_C_L3: return B_LS; default: return B_RS; }
}
- (BOOL)menuTakes:(CGPoint)p {   // the menu button takes a touch in its hit circle unless a locked key's target is nearer (the drawn keys are hidden in Tap and with a controller)
    if (dm_pad_menu_distance(self.geo, p) > 1) return NO;
    if (_tap || _padOff || (_layout.separated && !CGRectContainsPoint(_layout.controls, p))) return YES;
    return dm_pad_menu_takes(self.geo, _full, _layout.separated, p);
}
- (uint64_t)faceAt:(CGPoint)p {   // keys under the finger in the diamond (between two keys both count)
    uint64_t m = 0; CGFloat r = self.faceHitR;
    for (int b = B_A; b <= B_Y; b++) if (dist(p, [self facePos:b]) <= r) m |= 1ull << b;
    return m;
}
- (uint64_t)dpadAt:(CGPoint)p {   // 8 directions: 45° each, diagonals press two keys; a small centre circle counts as none
    CGPoint c = self.dpadCenter; CGFloat dx = p.x - c.x, dy = p.y - c.y;
    if (hypot(dx, dy) < self.dpadR * 0.25) return 0;
    double a = atan2(-dy, dx) * 180 / M_PI; uint64_t m = 0;
    if (a > -67.5 && a < 67.5) m |= 1ull << B_RIGHT;
    if (a > 22.5 && a < 157.5) m |= 1ull << B_UP;
    if (a > 112.5 || a < -112.5) m |= 1ull << B_LEFT;
    if (a < -22.5 && a > -157.5) m |= 1ull << B_DOWN;
    return m;
}
- (CGPoint)knobOffset:(int)i {   // knob offset from the stick centre (clamped to the stick radius)
    if (!_stick[i]) return CGPointZero;
    CGPoint h = [self stickCentre:i]; CGFloat dx = _stickNow[i].x - h.x, dy = _stickNow[i].y - h.y, d = hypot(dx, dy), R = [self stickR:i];
    if (d > R) { dx *= R / d; dy *= R / d; }
    return CGPointMake(dx, dy);
}

// ---- Touch ----
- (void)recompute {
    uint64_t face = 0; for (UITouch *t in _faceOf) face |= [_faceOf objectForKey:t].unsignedLongLongValue;
    uint64_t btn = 0, dpad = 0;
    for (UITouch *t in _owner) { uint64_t v = [_owner objectForKey:t].unsignedLongLongValue; int c = (int)(v & 0xff);
        if (c == C_BTN) btn |= 1ull << (v >> 8);
        else if (c == C_DPAD) dpad |= [self dpadAt:[t locationInView:self]]; }
    int32_t ax[4] = {0};
    for (int i = 0; i < 2; i++) {
        CGPoint o = [self knobOffset:i]; CGFloat R = [self stickR:i], d = hypot(o.x, o.y), dz = R * K_DEAD;
        if (d <= dz) continue;
        CGFloat m = fmin((d - dz) / (R * K_FULL - dz), 1) / d;   // outside the dead zone: 0 rising to full at the full-tilt radius
        ax[i * 2] = (int32_t)lrint(o.x * m * 32767); ax[i * 2 + 1] = (int32_t)lrint(-o.y * m * 32767);   // host: up is positive; rounded so full tilt is exactly 32767
    }
    BOOL changed = face != _faceBits || dpad != _dpadBits || btn != _btnBits;
    uint64_t pressed = (face | dpad | btn) & ~(_faceBits | _dpadBits | _btnBits);
    unsigned gripping = (_stick[0] ? 1u : 0) | (_stick[1] ? 2u : 0);
    if (pressed || (gripping & ~_hapticSticks)) {
        [_touchFeedback impactOccurredWithIntensity:0.6]; [_touchFeedback prepare];
    }
    _hapticSticks = gripping;
    _faceBits = face; _dpadBits = dpad; _btnBits = btn;
    pthread_mutex_lock(&g_mu);
    g_touch_btn = face | dpad | btn; g_touch_lx = ax[0]; g_touch_ly = ax[1]; g_touch_rx = ax[2]; g_touch_ry = ax[3];
    pthread_mutex_unlock(&g_mu);
    publish();
    BOOL stick = _stick[0] != nil;   // only the left stick is drawn: the right one needs no refresh
    if (changed || stick || _stickShown) [self refresh];   // also refresh on the stick release so the knob returns to the centre
    _stickShown = stick;
}
// Touches no control takes go to the game's touch screen, normalized on front_ios.m's actual 16:9 viewport (including portrait and tabletop splits, and the cropped Fill picture): Super Mario Galaxy's pointer in handheld mode (profile op_mode). The host reports them only in handheld mode, as on the Switch (hle_hid.c touch_read)
- (void)pushGame {
    CGRect b = _layout.game;
    if (b.size.width <= 0 || b.size.height <= 0) { dm_touch_set(NULL, 0); return; }
    dm_touch t[16]; int n = 0;
    for (int i = 0; i < 16; i++) if (_game[i]) {
        CGPoint p = dm_game_touch_point(b, [_game[i] locationInView:self]);   // with Fill the game rectangle is larger than the view (DmLayout.h)
        t[n++] = (dm_touch){(uint32_t)i, (float)p.x, (float)p.y};
    }
    dm_touch_set(t, n);
}
- (BOOL)gameBegin:(UITouch *)t {
    if (CGRectIsEmpty(_layout.game) || (_layout.separated && !CGRectContainsPoint(_layout.game, [t locationInView:self]))) return NO;
    for (int i = 0; i < 16; i++) if (!_game[i]) { _game[i] = t; [_owner setObject:@(C_GAME | (uint64_t)i << 8) forKey:t]; return YES; }
    return NO;
}
// While an offline HTML page is shown over the picture (web_apple.m front_web_touch), a touch no control would take goes to the page instead of the game's touch screen:
// the gamepad lets it through. The same tests as touchesBegan
int front_web_touch(void);
- (BOOL)controlAt:(CGPoint)p {
    if (_padOff || (_layout.separated && !CGRectContainsPoint(_layout.controls, p))) return NO;
    if (_tap) return NO;
    if (dm_pad_hit(self.geo, _full, _layout.separated, _tap, !_stick[0], p).kind != DM_PAD_HIT_NONE) return YES;   // the geometry touchesBegan hits with (DmPadGeometry.h)
    return _full && !_stick[1] && [self inRightArea:p];
}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v = [super hitTest:p withEvent:e];
    return v == self && front_web_touch() && ![self controlAt:p] ? nil : v;
}
- (void)touchesBegan:(NSSet<UITouch *> *)ts withEvent:(UIEvent *)e {
    BOOL game = NO;
    for (UITouch *t in ts) {
        if (_padOff) { game |= [self gameBegin:t]; continue; }
        CGPoint p = [t locationInView:self];
        if (_layout.separated && !CGRectContainsPoint(_layout.controls, p)) { game |= [self gameBegin:t]; continue; }
        DmPadHit hit = dm_pad_hit(self.geo, _full, _layout.separated, _tap, !_stick[0], p);   // the same geometry the controls are drawn with (the menu button took its own touches, menuTakes)
        if (hit.kind == DM_PAD_HIT_KEY) { [_owner setObject:@(C_BTN | (uint64_t)lockedKey(hit.key) << 8) forKey:t]; continue; }
        if (_tap) { game |= [self gameBegin:t]; continue; }
        int kind = hit.kind == DM_PAD_HIT_FACE ? C_FACE : hit.kind == DM_PAD_HIT_DPAD ? C_DPAD : hit.kind == DM_PAD_HIT_STICK ? C_STICK : C_NONE, idx = 0;
        if (kind == C_NONE && _full && !_stick[1] && [self inRightArea:p]) { kind = C_STICK; idx = 1; _rCentre = p; [self hideHint]; }   // the right stick: centred where the touch lands (the hint's job is done)
        if (kind == C_FACE) { [_owner setObject:@(C_FACE) forKey:t]; [_faceOf setObject:@([self faceAt:p]) forKey:t]; }
        else if (kind == C_DPAD) [_owner setObject:@(C_DPAD) forKey:t];
        else if (kind == C_STICK) { [_owner setObject:@(C_STICK | (uint64_t)idx << 8) forKey:t]; _stick[idx] = t; _stickNow[idx] = p; }
        else game |= [self gameBegin:t];
    }
    if (game) [self pushGame];
    [self recompute];
}
- (void)touchesMoved:(NSSet<UITouch *> *)ts withEvent:(UIEvent *)e {
    BOOL game = NO;
    for (UITouch *t in ts) {
        uint64_t v = [_owner objectForKey:t].unsignedLongLongValue; int c = (int)(v & 0xff); CGPoint p = [t locationInView:self];
        if (c == C_FACE) [_faceOf setObject:@([self faceAt:p]) forKey:t];
        else if (c == C_STICK) { _stickNow[v >> 8] = p;
            if ((v >> 8) == 1) { CGFloat d = dist(p, _rCentre), R = [self stickR:1];   // the right stick's centre follows a finger past its radius, so turning back responds at once
                if (d > R) _rCentre = CGPointMake(p.x - (p.x - _rCentre.x) * R / d, p.y - (p.y - _rCentre.y) * R / d); } }
        else if (c == C_GAME) game = YES;
    }
    if (game) [self pushGame];
    [self recompute];
}
- (void)endTouches:(NSSet<UITouch *> *)ts tapped:(BOOL)ended {
    BOOL game = NO;
    for (UITouch *t in ts) {
        uint64_t v = [_owner objectForKey:t].unsignedLongLongValue;
        if ((v & 0xff) == C_GAME && (v >> 8) < 16) { _game[v >> 8] = nil; game = YES; }
        [_owner removeObjectForKey:t]; [_faceOf removeObjectForKey:t]; for (int i = 0; i < 2; i++) if (t == _stick[i]) _stick[i] = nil;
    }
    if (game) [self pushGame];
    [self recompute];
}
- (void)touchesEnded:(NSSet<UITouch *> *)ts withEvent:(UIEvent *)e { [self endTouches:ts tapped:YES]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)ts withEvent:(UIEvent *)e { [self endTouches:ts tapped:NO]; }
- (void)reset { [_owner removeAllObjects]; [_faceOf removeAllObjects]; _stick[0] = _stick[1] = nil; for (int i = 0; i < 16; i++) _game[i] = nil; [self pushGame]; [self recompute]; }

// ---- Shapes ----
static CGPathRef circlePath(CGPoint c, CGFloat r) { return CGPathCreateWithEllipseInRect(CGRectMake(c.x - r, c.y - r, 2 * r, 2 * r), NULL); }
static CGPathRef dropPath(CGPoint c, CGFloat r, CGFloat tipAngle, CGFloat round) {   // teardrop: circle + two tangents meeting at the tip, tip slightly rounded
    CGFloat d = r * DM_PAD_DROP_TIP, th = acos(r / d);
    CGPoint tip = CGPointMake(c.x + d * cos(tipAngle), c.y + d * sin(tipAngle));
    CGPoint p1 = CGPointMake(c.x + r * cos(tipAngle + th), c.y + r * sin(tipAngle + th)), p2 = CGPointMake(c.x + r * cos(tipAngle - th), c.y + r * sin(tipAngle - th));
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, p2.x, p2.y);
    CGPathAddArcToPoint(p, NULL, tip.x, tip.y, p1.x, p1.y, round);
    CGPathAddArc(p, NULL, c.x, c.y, r, tipAngle + th, tipAngle - th + 2 * M_PI, false);
    CGPathCloseSubpath(p); return p;
}
static CGPathRef armPath(CGPoint c, CGFloat R, CGFloat w, CGFloat in, CGFloat angle, CGFloat round) {   // one D-pad arm: an upward pentagon (tip toward the centre) rotated by angle around the centre
    CGPoint v[5] = {{-w, -R}, {w, -R}, {w, -(in + w)}, {0, -in}, {-w, -(in + w)}};
    CGFloat cs = cos(angle), sn = sin(angle);
    for (int i = 0; i < 5; i++) v[i] = CGPointMake(c.x + v[i].x * cs - v[i].y * sn, c.y + v[i].x * sn + v[i].y * cs);
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathMoveToPoint(p, NULL, (v[4].x + v[0].x) / 2, (v[4].y + v[0].y) / 2);
    for (int i = 0; i < 5; i++) CGPathAddArcToPoint(p, NULL, v[i].x, v[i].y, v[(i + 1) % 5].x, v[(i + 1) % 5].y, round);
    CGPathCloseSubpath(p); return p;
}
static void setPath(CAShapeLayer *l, CGPathRef p) { l.path = p; l.shadowPath = p; CGPathRelease(p); }
static void placeLabel(CATextLayer *t, CGPoint c, CGFloat fs) {
    CTFontRef f = CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, fs, NULL);
    t.font = f; t.fontSize = fs;
    CGFloat h = CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f), w = fs * 3;
    t.frame = CGRectMake(c.x - w / 2, c.y - h / 2, w, h);
    CFRelease(f);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIWindowScene *ws = self.window.windowScene; if (ws) atomic_store(&g_iface_orient, (int)ws.effectiveGeometry.interfaceOrientation);
    CGFloat u = self.u;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGFloat scale = MAX(self.traitCollection.displayScale, 1);
    for (int b = 0; b < B_N; b++) if (_label[b] && _label[b].contentsScale != scale) {
        _label[b].contentsScale = scale; [_label[b] setNeedsDisplay];
    }
    _controls.frame = self.layer.bounds;
    for (int b = B_A; b <= B_Y; b++) { CGPoint c = [self facePos:b]; setPath(_key[b], circlePath(c, self.faceR)); placeLabel(_label[b], c, 20 * u); }
    for (int i = 0; i < (int)(sizeof k_btns / sizeof *k_btns); i++) { int b = k_btns[i];
        if (isDrop(b)) {
            BOOL right = b == B_ZR || b == B_R; CGPoint c = [self dropCenter:b];
            setPath(_key[b], dropPath(c, [self dropR:b], right ? -M_PI_4 : -3 * M_PI_4, 4 * u)); placeLabel(_label[b], c, 16 * u);   // tip toward the near top corner
        } else if (isClick(b)) {
            CGPoint c = [self clickCenter:b]; setPath(_key[b], circlePath(c, self.geo->clickR)); placeLabel(_label[b], c, 13 * u);
        } else {
            CGRect rc = [self pillRect:b];
            setPath(_key[b], CGPathCreateWithRoundedRect(rc, rc.size.height / 2, rc.size.height / 2, NULL)); placeLabel(_label[b], CGPointMake(CGRectGetMidX(rc), CGRectGetMidY(rc)), 18 * u);
        }
    }
    static const struct { int b; CGFloat angle; } arms[] = {{B_UP, 0}, {B_RIGHT, M_PI_2}, {B_DOWN, M_PI}, {B_LEFT, -M_PI_2}};   // the same arm in 90° steps
    for (int i = 0; i < 4; i++) setPath(_key[arms[i].b], armPath(self.dpadCenter, self.dpadR, self.geo->armW, self.geo->armIn, arms[i].angle, 6 * u));
    CGFloat mr = self.geo->swapR; CGPoint mc = self.menuCenter;
    _menu.frame = CGRectMake(mc.x - mr, mc.y - mr, 2 * mr, 2 * mr); _menu.layer.cornerRadius = mr;
    _menu.layer.shadowPath = [UIBezierPath bezierPathWithOvalInRect:_menu.bounds].CGPath;
    [_menu setImage:[UIImage systemImageNamed:@"gearshape.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 * u weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    setPath(_ring, circlePath(self.stickHome, [self stickR:0]));
    CGFloat k = self.geo->knobR; _knob.bounds = CGRectMake(0, 0, 2 * k, 2 * k);
    setPath(_knob, circlePath(CGPointMake(k, k), k));
    CAShapeLayer *in = (CAShapeLayer *)_knob.sublayers.firstObject; CGPathRef ip = circlePath(CGPointMake(k, k), k * 0.62);
    in.frame = _knob.bounds; in.path = ip; CGPathRelease(ip);
    [CATransaction commit];
    [self placeHint];
    [self refresh];
}

// ---- The right-stick hint ----
// The 3D layout's right stick is not drawn (it answers anywhere in the right third), and players read the layout as having none (GitHub issues #347, #414).
// So the first time the 3D layout shows in a launch, a few words say where it is, for two seconds, then fade. Words only: a ring or a knob would read as
// a fixed stick that has to be hit. It sits in the right third between the top row and the diamond, clear of every control (dm_pad_hint_rect); with no
// room, or with a controller connected, it waits. A touch on the right stick ends it at once. DM_TOUCH_HINT carries the words (the shell's language),
// empty turns it off; without it the words are English.
static BOOL g_hintShown;   // once per launch
- (void)placeHint {
    if (g_hintShown && _hint.hidden) return;
    if (!_full || _tap || _padOff || !_hintWords.length || CGRectIsEmpty(self.bounds)) { if (!_hint.hidden) [self hideHint]; return; }
    CGFloat u = self.u, fs = fmin(fmax(15 * u, 13), 20);
    UIFont *font = [UIFont systemFontOfSize:fs weight:UIFontWeightSemibold];
    CGSize t = [_hintWords sizeWithAttributes:@{NSFontAttributeName: font}];
    CGSize box = CGSizeMake(ceil(t.width) + 2 * fs, ceil(t.height) + fs * 0.8);
    CGRect area = _layout.controls;
    CGRect r = dm_pad_hint_rect(self.geo, CGRectGetMaxX(area) - area.size.width * K_RSWIPE, box);
    if (CGRectIsNull(r)) { if (!_hint.hidden) [self hideHint]; return; }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _hint.frame = r; _hint.cornerRadius = box.height / 2;
    CTFontRef f = CTFontCreateUIFontForLanguage(kCTFontUIFontEmphasizedSystem, fs, NULL); _hintText.font = f; _hintText.fontSize = fs; CFRelease(f);
    _hintText.contentsScale = MAX(self.traitCollection.displayScale, 1);
    _hintText.frame = CGRectMake(0, (box.height - ceil(t.height)) / 2, box.width, ceil(t.height));
    [CATransaction commit];
    if (g_hintShown) return;   // already on screen: only follow the layout
    g_hintShown = YES;
    LOG("front end: right-stick hint shown");
    _hint.hidden = NO; _hint.opacity = 1;
    __weak DmGamepad *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weak hideHint]; });
}
- (void)hideHint {
    if (_hint.hidden) return;
    [CATransaction begin]; [CATransaction setAnimationDuration:0.4];
    [CATransaction setCompletionBlock:^{ self->_hint.hidden = YES; }];
    _hint.opacity = 0;   // an implicit fade
    [CATransaction commit];
}
- (void)safeAreaInsetsDidChange { [super safeAreaInsetsDidChange]; [self setNeedsLayout]; }
- (void)refresh {   // pressed state → fill, sticks → knob position
    uint64_t all = _faceBits | _dpadBits | _btnBits;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (int b = 0; b < B_N; b++) { BOOL on = (all >> b) & 1;
        _key[b].fillColor = (on ? k_on : k_idle).CGColor; _label[b].foregroundColor = (on ? k_textOn : k_text).CGColor; }
    CGPoint h = self.stickHome, o = [self knobOffset:0];
    _knob.position = CGPointMake(h.x + o.x, h.y + o.y); _knob.fillColor = (_stick[0] ? k_on : k_idle).CGColor;
    [CATransaction commit];
}

// ---- Physical controllers ----
// Each controller with an extended gamepad profile is a player of its own, as on the Mac (front_mac.m): it holds a slot (pad_slots.h: player 1 first, a reconnected controller
// gets its player back) and goes to dm_pad_set_player, and hle_hid.c reports player n on its own npad while the slot is held (dm_pad_players). Player 1's controller is ORed
// with the touch gamepad; a one-player game that supports only No1 / Handheld still sees every controller as player 1 (hle_hid.c). Each player has its controller's rumble and
// gyro; the phone's gyro is player 1's. With DM_PAD_MERGE=1 every controller is player 1, as before (the last one moved wins)
static pad_slots g_slots;
static GCController *g_held[DM_PLAYERS];   // the controller of each slot, kept alive while it holds it (the slot table keys on its pointer)
static int g_merge;
static pad_map g_padmap;   // DM_PAD_MAP affects physical controllers only
static int32_t axis(float v) { return (int32_t)(fmaxf(-1.f, fminf(1.f, v)) * 32767); }
static void read_pad(GCExtendedGamepad *g) {
    front_ios_quit_poll(); if (front_ios_quit_blocks_input()) return;   // the quit prompt has the controllers (Home held 2 s, or Quit in the in-game menu)
    int p = g_merge ? 0 : pad_slot_of(&g_slots, (__bridge const void *)g.controller); if (p < 0) return;
    dm_haptics_apple_controller(p, g.controller);
    _Static_assert(DM_BTN_A == 1u << B_A && DM_BTN_B == 1u << B_B && DM_BTN_X == 1u << B_X && DM_BTN_Y == 1u << B_Y, "face button bits");
    uint64_t m = dm_pad_face(g);   // by position, a Nintendo pad by its labels
    #define K(btn, bit) if (btn.isPressed) m |= 1ull << bit
    K(g.leftShoulder, B_L); K(g.rightShoulder, B_R); K(g.leftTrigger, B_ZL); K(g.rightTrigger, B_ZR);
    K(g.buttonMenu, B_PLUS); if (g.buttonOptions) K(g.buttonOptions, B_MINUS);
    if (g.leftThumbstickButton) K(g.leftThumbstickButton, B_LS); if (g.rightThumbstickButton) K(g.rightThumbstickButton, B_RS);
    K(g.dpad.left, B_LEFT); K(g.dpad.up, B_UP); K(g.dpad.right, B_RIGHT); K(g.dpad.down, B_DOWN);
    #undef K
    m = pad_map_apply(&g_padmap, m);
    dm_pad_set_player(p, m, axis(g.leftThumbstick.xAxis.value), axis(g.leftThumbstick.yAxis.value), axis(g.rightThumbstick.xAxis.value), axis(g.rightThumbstick.yAxis.value));
}
// Home and Capture: without this iOS takes them as system gestures (Home opens the Games overlay, Capture a screenshot); the app gives them no function
static void pad_keep_system_buttons(GCController *c) {   // Home held for 2 s opens the quit prompt (front_ios.m): iOS 27 respects the claim when the Home button setting for apps lets the app decide
    for (NSString *b in @[GCInputButtonHome, GCInputButtonShare]) c.physicalInputProfile.buttons[b].preferredSystemGestureState = GCSystemGestureStateDisabled;
    c.extendedGamepad.buttonHome.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL down) { (void)b; (void)v; (void)down; front_ios_quit_poll(); };
}
static const char *pad_name(GCController *c) { return c.vendorName.UTF8String ?: "?"; }
static void npad_name(int p, char *out, size_t cap) { uint32_t id = dm_player_npad(p); if (id == 0x20) snprintf(out, cap, "handheld"); else snprintf(out, cap, "%u", id); }
static void pads_start(void) {
    pad_map_default(&g_padmap);
    const char *pm = getenv("DM_PAD_MAP");
    if (pm && *pm) { int bad = pad_map_parse(&g_padmap, pm); LOG("front end: controller buttons from DM_PAD_MAP (%s)%s", pm, bad ? ", malformed entries left out" : ""); }
    const char *e = getenv("DM_PAD_MERGE"); g_merge = e && atoi(e);
    LOG("front end: %s", g_merge ? "every controller is player 1 (DM_PAD_MERGE)" : "each controller is a player of its own, the touch gamepad plays with player 1");
}
// Called at start and on every connect / disconnect (gone: the controller that was just removed, nil otherwise); returns whether a controller is in use
static BOOL pads_merged(GCController *gone) {
    if (gone) { gone.extendedGamepad.valueChangedHandler = nil; dm_motion_detach(gone, 0); }
    BOOL any = NO; int motion = 0;
    for (GCController *c in GCController.controllers) if (c != gone && c.extendedGamepad) {
        if (c.motion.hasRotationRate) motion = 1;
        any = YES; pad_keep_system_buttons(c); c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { (void)el; read_pad(g); };
        dm_motion_attach(c, 0);   // every controller is player 1: the last one moved drives its six-axis sensor
        read_pad(c.extendedGamepad);
    }
    if (!any || !motion) dm_motion_clear(0);   // the phone's gyro (if on) takes over from its next sample
    if (!any) { dm_haptics_apple_controller(0, nil); dm_pad_set(0, 0, 0, 0, 0); }
    return any;
}
static BOOL pads_slotted(GCController *gone) {
    NSArray<GCController *> *now = GCController.controllers; char nb[16];
    for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p] && (g_held[p] == gone || ![now containsObject:g_held[p]])) {
        npad_name(p, nb, sizeof nb); LOG("controller '%s' disconnected: player %d (npad %s) is free", pad_name(g_held[p]), p + 1, nb);
        g_held[p].extendedGamepad.valueChangedHandler = nil;
        dm_motion_detach(g_held[p], p);   // player 1's: the phone's gyro (if on) takes over from its next sample
        dm_haptics_apple_controller(p, nil);
        pad_slot_free(&g_slots, (__bridge const void *)g_held[p]); g_held[p] = nil;
        dm_pad_set_player(p, 0, 0, 0, 0, 0);   // nothing stays pressed
    }
    for (GCController *c in now) if (c.extendedGamepad && c != gone && pad_slot_of(&g_slots, (__bridge const void *)c) < 0) {
        int p = pad_slot_take(&g_slots, (__bridge const void *)c, pad_name(c));
        if (p < 0) { LOG("controller '%s' connected: all %d players are taken, not used", pad_name(c), DM_PLAYERS); continue; }
        g_held[p] = c; pad_keep_system_buttons(c);
        c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad *g, GCControllerElement *el) { (void)el; read_pad(g); };
        dm_motion_attach(c, p);
        npad_name(p, nb, sizeof nb); LOG("controller '%s' connected: player %d (npad %s)%s", pad_name(c), p + 1, nb, c.motion.hasRotationRate ? ", with motion (gyro)" : "");
        read_pad(c.extendedGamepad);
    }
    dm_pad_players(pad_slot_mask(&g_slots));
    return pad_slot_mask(&g_slots) != 0;
}
- (void)padsChanged:(NSNotification *)note {
    GCController *c = note.object, *gone = [note.name isEqual:GCControllerDidDisconnectNotification] ? c : nil;
    if (c && (!c.extendedGamepad || g_merge)) LOG("controller %s: %s%s", gone ? "disconnected" : "connected", pad_name(c), c.extendedGamepad ? "" : " (no extended gamepad profile: not used)");
    BOOL any = g_merge ? pads_merged(gone) : pads_slotted(gone);
    dispatch_async(dispatch_get_main_queue(), ^{ self->_padOff = any; self->_controls.hidden = any; [self reset]; front_ios_quit_controllers(); });   // the touch gamepad hides while any controller is in use
}
@end

UIView *dm_gamepad_view(CGRect frame) { DmGamepad *v = [[DmGamepad alloc] initWithFrame:frame]; g_view = v; return v; }
void dm_gamepad_arrange(UIView *view, DmLayout layout) { [(DmGamepad *)view arrange:layout]; }
void dm_gamepad_opmode_changed(void) { [g_view opmodeChanged]; }
void dm_gamepad_touch_feedback(bool on) { [g_view setTouchFeedback:on]; }
int dm_pad_layout(void) { return g_view ? [g_view padLayout] : 0; }
bool dm_pad_layout_offered(int layout) { return layout == 0 || layout == 1 || (layout == 2 && dm_opmode() == 0); }
void dm_pad_layout_set(int layout) { [g_view setPadLayout:layout]; }
void dm_gamepad_pads_read(void) {   // front_ios.m: the quit prompt closed, the game reads every controller as it is now (a button held through it counts again)
    if (g_merge) { for (GCController *c in GCController.controllers) if (c.extendedGamepad) read_pad(c.extendedGamepad); }
    else for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p].extendedGamepad) read_pad(g_held[p].extendedGamepad);
}
void dm_gamepad_active(void) { dispatch_async(dispatch_get_main_queue(), ^{ for (GCController *c in GCController.controllers) dm_motion_rearm(c); }); }   // On become active: motion_apple.h
void dm_gamepad_reset(void) {   // On resign active: release everything (a key held while switching away and released in background gets no "release")
    dispatch_async(dispatch_get_main_queue(), ^{ [g_view reset]; });
    pthread_mutex_lock(&g_mu); g_shake_btn = 0; pthread_mutex_unlock(&g_mu); publish();
    if (g_merge) dm_pad_set(0, 0, 0, 0, 0);
    else for (int p = 0; p < DM_PLAYERS; p++) if (g_held[p]) dm_pad_set_player(p, 0, 0, 0, 0, 0);
}
