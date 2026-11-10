// Where the virtual gamepad's controls are drawn (DmGamepad.m), as pure functions of the view's bounds, its safe-area insets, the DmLayout split
// and the player's options, so the placement is tested without a device (dm/ios/tests/test_pad_geometry.py).
//   Every length is in u (1 = 430 points tall, iPhone Pro Max landscape), x measured from the outer edge, the right half mirrors.
//   The options come from the environment (the shell's settings, Documents/env.txt): DM_TOUCH_SIZE = small | medium | large scales u.
//   DM_TOUCH_STICK = corner | higher | inward places the left stick (inward takes the D-pad along); the right-hand controls never move.
//   DM_TOUCH_LAYOUT moves single controls, one arrangement per layout (2D, 3D, and both again for the split screen): see "The player's arrangement".
//   An option never moves a control off the screen or onto another one: a size that does not fit falls back step by step to the size that does
//   (dm_pad_geo_fits: every drawn shape inside its rectangle, no two drawn shapes overlap), and a moved control that does not fit goes back to its place.
#pragma once
#import "DmLayout.h"
#include <math.h>
#include <string.h>

NS_ASSUME_NONNULL_BEGIN

enum { DM_PAD_ZL = 0, DM_PAD_L, DM_PAD_ZR, DM_PAD_R };   // the order of DmPadGeo.drop
enum { DM_PAD_MINUS = 0, DM_PAD_PLUS };                  // the order of DmPadGeo.pill

enum { DM_PAD_STICK_CORNER = 0, DM_PAD_STICK_HIGHER, DM_PAD_STICK_INWARD };   // DM_TOUCH_STICK

// The controls DM_TOUCH_LAYOUT can move, in the order they are placed, by their names in the value. face is the whole A B X Y diamond,
// a b x y one key of it (from where the diamond is). The menu button stays where it is.
enum { DM_PAD_C_FACE = 0, DM_PAD_C_A, DM_PAD_C_B, DM_PAD_C_X, DM_PAD_C_Y, DM_PAD_C_STICK, DM_PAD_C_DPAD, DM_PAD_C_ZL, DM_PAD_C_L, DM_PAD_C_ZR, DM_PAD_C_R,
       DM_PAD_C_L3, DM_PAD_C_R3, DM_PAD_C_MINUS, DM_PAD_C_PLUS, DM_PAD_C_N };
// The layouts a value holds an arrangement for: 2D, 3D, and the same two when the controls sit below the picture (DmLayout.separated:
// an iPad held upright, iPhone Duo's inner display upright or half open).
enum { DM_PAD_SET_2D = 0, DM_PAD_SET_3D, DM_PAD_SET_2D_SPLIT, DM_PAD_SET_3D_SPLIT, DM_PAD_SET_N };
// Each control's offset from its built-in place, in steps of a quarter of a face key's width at the player's size, so it scales with the
// controls and not with the screen. 0 0 is the built-in place.
typedef struct { signed char dx[DM_PAD_SET_N][DM_PAD_C_N], dy[DM_PAD_SET_N][DM_PAD_C_N]; } DmPadLayout;

typedef struct {
    CGFloat scale;   // DM_TOUCH_SIZE: 0.8 small, 1 medium (the built-in size), 1.2 large
    int stick;       // DM_TOUCH_STICK: where the left stick sits (the D-pad moves with it when it moves inward); the right-hand controls keep their place
    const DmPadLayout *_Nullable layout;   // DM_TOUCH_LAYOUT: the player's arrangement, NULL for none
} DmPadOptions;

typedef struct {
    CGFloat u;                            // the unit every size below is a multiple of
    CGRect safe, corner;                  // the top row lives in safe, the bottom-corner controls in corner (reaching halfway into the side insets)
    BOOL portrait;                        // separated and taller than wide: both thumbs' clusters sit in the controls region's middle band
    CGPoint face; CGFloat faceGap, faceR, faceHitR;   // the A B X Y diamond: centre, key distance from it, key radius, hit radius
    CGPoint stick; CGFloat stickR, knobR;             // the left stick: ring centre and radius, knob radius
    CGPoint dpad; CGFloat dpadR, armW, armIn;         // the D-pad (3D only): centre, arm outer edge, arm half-width, arm tip from the centre
    CGPoint drop[4]; CGFloat dropR[4];                // ZL, L, ZR, R: teardrop centres and radii
    CGPoint click[2]; CGFloat clickR;                 // L3, R3 (3D only)
    CGRect pill[2];                                   // −, +
    CGPoint swap; CGFloat swapR;                      // the menu button
    CGPoint faceKey[4];                               // A B X Y where they are: the diamond around face, unless a key was moved on its own
    BOOL faceSplit;                                   // a key of the diamond was moved on its own: the diamond is then grabbed key by key
    unsigned moved, dropped;                          // DM_TOUCH_LAYOUT: the controls (1 << DM_PAD_C_*) it moved, and the ones it asked to move that kept their place
} DmPadGeo;

// Layout constants (in u), the values DmGamepad.m has always used.
static const CGFloat
    DM_PAD_ZL_X = 44, DM_PAD_ZL_Y = 40, DM_PAD_ZL_R = 26,     // ZL / ZR: centre from the outer edge and the top, radius
    DM_PAD_L_X = 44, DM_PAD_L_Y = 108, DM_PAD_L_R = 24,       // L / R: same column as ZL / ZR
    DM_PAD_DROP_TIP = 1.45,                                   // teardrop tip distance from the centre (times the radius)
    DM_PAD_CORNER_IN = 0.5,                                   // how far the bottom-corner controls reach into the side safe-area inset
    DM_PAD_FACE_X = 81, DM_PAD_Y = 82,                        // diamond centre from the outer edge; diamond and stick centre from the bottom
    DM_PAD_FACE_GAP = 50, DM_PAD_FACE_R = 27,                 // diamond: key distance from the centre, key radius
    DM_PAD_PILL_DX = 52, DM_PAD_PILL_Y = 22, DM_PAD_PILL_W = 50, DM_PAD_PILL_H = 28,   // − / +: centre from the midline and from the top, size
    DM_PAD_SWAP_R = 15,                                       // menu button: top centre, level with − / +
    DM_PAD_STICK_X = 81, DM_PAD_STICK_R = 77, DM_PAD_KNOB_R = 30,   // left stick: mirrors the diamond
    DM_PAD_LOW_X = 231, DM_PAD_LOW_Y = 64,                    // D-pad centre from the outer edge and the bottom
    DM_PAD_DPAD_R = 48, DM_PAD_ARM_W = 17, DM_PAD_ARM_IN = 11,
    DM_PAD_CLICK_X = 102, DM_PAD_CLICK_R = 17;                // L3 / R3: centre from the outer edge (level with ZL / ZR), radius

// DM_TOUCH_SIZE: small, medium (also unset, empty or unknown) or large.
static inline CGFloat dm_pad_size_scale(const char *_Nullable v) {
    if (v && !strcmp(v, "small")) return 0.8;
    if (v && !strcmp(v, "large")) return 1.2;
    return 1;
}

// DM_TOUCH_STICK: corner (also unset, empty or unknown), higher or inward.
static inline int dm_pad_stick_place(const char *_Nullable v) {
    if (v && !strcmp(v, "higher")) return DM_PAD_STICK_HIGHER;
    if (v && !strcmp(v, "inward")) return DM_PAD_STICK_INWARD;
    return DM_PAD_STICK_CORNER;
}
static const CGFloat DM_PAD_STICK_UP = 70, DM_PAD_STICK_IN = 60;   // how far higher / inward moves the left stick (in u), at most

static inline CGPoint dm_pad_side(CGRect s, int right, CGFloat dx, CGFloat y) { return CGPointMake(right ? CGRectGetMaxX(s) - dx : CGRectGetMinX(s) + dx, y); }
// A key of the diamond around c: A right, B bottom, X top, Y left (i = 0..3 in that order).
static inline CGPoint dm_pad_diamond_key(CGPoint c, CGFloat d, int i) {
    switch (i) { case 0: return CGPointMake(c.x + d, c.y); case 1: return CGPointMake(c.x, c.y + d); case 2: return CGPointMake(c.x, c.y - d); default: return CGPointMake(c.x - d, c.y); }
}

// The geometry at one unit, with no fitting.
static inline DmPadGeo dm_pad_geo_at(CGRect bounds, UIEdgeInsets insets, DmLayout layout, BOOL full, CGFloat u) {
    DmPadGeo g; memset(&g, 0, sizeof g);
    BOOL sep = layout.separated;
    g.u = u;
    g.safe = CGRectIntersection(layout.controls, UIEdgeInsetsInsetRect(bounds, dm_game_safe_insets(bounds, insets, layout.topSafeOnly)));
    UIEdgeInsets ci = insets; ci.left *= DM_PAD_CORNER_IN; ci.right *= DM_PAD_CORNER_IN;
    g.corner = sep ? g.safe : UIEdgeInsetsInsetRect(bounds, ci);
    g.portrait = sep && bounds.size.height > bounds.size.width;
    CGRect s = g.safe, c = g.corner;
    CGPoint thumbL = CGPointMake(CGRectGetMinX(s) + s.size.width * 0.28, CGRectGetMinY(s) + s.size.height * 0.58);
    CGPoint thumbR = CGPointMake(CGRectGetMinX(s) + s.size.width * 0.72, thumbL.y);
    g.faceGap = DM_PAD_FACE_GAP * u; g.faceR = DM_PAD_FACE_R * u; g.faceHitR = MAX(g.faceR * 1.25, sep ? 22 : 0);
    g.stickR = DM_PAD_STICK_R * u; g.knobR = DM_PAD_KNOB_R * u;
    g.dpadR = DM_PAD_DPAD_R * u; g.armW = DM_PAD_ARM_W * u; g.armIn = DM_PAD_ARM_IN * u;
    if (g.portrait) {
        g.face = thumbR;
        g.stick = thumbL; if (full) g.stick.x -= g.dpadR + 6 * u;
        g.dpad = CGPointMake(thumbL.x + g.stickR + 6 * u, thumbL.y);
    } else {
        CGFloat edge = sep ? g.faceGap + g.faceHitR : 0;
        g.face = dm_pad_side(c, 1, MAX(DM_PAD_FACE_X * u, edge), CGRectGetMaxY(c) - MAX(DM_PAD_Y * u, edge));
        g.stick = dm_pad_side(c, 0, DM_PAD_STICK_X * u, CGRectGetMaxY(c) - DM_PAD_Y * u);
        g.dpad = dm_pad_side(c, 0, DM_PAD_LOW_X * u, CGRectGetMaxY(c) - DM_PAD_LOW_Y * u);
    }
    CGFloat edge = sep ? 22 : 0;
    for (int i = 0; i < 4; i++) {
        BOOL z = i == DM_PAD_ZL || i == DM_PAD_ZR;
        g.drop[i] = dm_pad_side(s, i >= DM_PAD_ZR, MAX((z ? DM_PAD_ZL_X : DM_PAD_L_X) * u, edge), CGRectGetMinY(s) + MAX((z ? DM_PAD_ZL_Y : DM_PAD_L_Y) * u, edge));
        g.dropR[i] = (z ? DM_PAD_ZL_R : DM_PAD_L_R) * u;
    }
    for (int i = 0; i < 2; i++) g.click[i] = dm_pad_side(s, i, MAX(DM_PAD_CLICK_X * u, edge), CGRectGetMinY(s) + MAX(DM_PAD_ZL_Y * u, edge));
    g.clickR = DM_PAD_CLICK_R * u;
    CGFloat top = CGRectGetMinY(s) + MAX(DM_PAD_PILL_Y * u, sep ? 14 : 0), w = DM_PAD_PILL_W * u, h = DM_PAD_PILL_H * u;
    for (int i = 0; i < 2; i++) {
        CGFloat x = CGRectGetMidX(s) + (i == DM_PAD_PLUS ? DM_PAD_PILL_DX : -DM_PAD_PILL_DX) * u;   // − on the left, + on the right
        g.pill[i] = CGRectMake(x - w / 2, top - h / 2, w, h);
    }
    g.swap = CGPointMake(CGRectGetMidX(s), top); g.swapR = DM_PAD_SWAP_R * u;
    for (int i = 0; i < 4; i++) g.faceKey[i] = dm_pad_diamond_key(g.face, g.faceGap, i);
    return g;
}

// The face key positions: A right, B bottom, X top, Y left (i = 0..3 in that order).
static inline CGPoint dm_pad_face_key(const DmPadGeo *g, int i) { return g->faceKey[i]; }
static inline CGPoint dm_pad_drop_tip(const DmPadGeo *g, int i) {
    CGFloat a = i >= DM_PAD_ZR ? -M_PI_4 : -3 * M_PI_4, d = g->dropR[i] * DM_PAD_DROP_TIP;   // tip toward the near top corner
    return CGPointMake(g->drop[i].x + d * cos(a), g->drop[i].y + d * sin(a));
}

// The drawn shapes as circles and rectangles, for the fit test and for tests: each with the rectangle it must stay inside.
typedef struct { CGPoint c; CGFloat r; CGRect rect; BOOL isRect; CGRect within; int id; } DmPadShape;
enum { DM_PAD_SHAPE_FACE = 0, DM_PAD_SHAPE_STICK = 4, DM_PAD_SHAPE_DPAD, DM_PAD_SHAPE_DROP, DM_PAD_SHAPE_TIP = 10, DM_PAD_SHAPE_CLICK = 14, DM_PAD_SHAPE_PILL = 16, DM_PAD_SHAPE_SWAP = 18 };
static inline int dm_pad_shapes(const DmPadGeo *g, BOOL full, DmPadShape out[_Nonnull 20]) {
    int n = 0;
    for (int i = 0; i < 4; i++) out[n++] = (DmPadShape){dm_pad_face_key(g, i), g->faceR, CGRectNull, NO, g->corner, DM_PAD_SHAPE_FACE + i};
    out[n++] = (DmPadShape){g->stick, g->stickR, CGRectNull, NO, g->corner, DM_PAD_SHAPE_STICK};
    if (full) out[n++] = (DmPadShape){g->dpad, hypot(g->dpadR, g->armW), CGRectNull, NO, g->corner, DM_PAD_SHAPE_DPAD};
    for (int i = 0; i < 4; i++) {
        out[n++] = (DmPadShape){g->drop[i], g->dropR[i], CGRectNull, NO, g->safe, DM_PAD_SHAPE_DROP + i};
        out[n++] = (DmPadShape){dm_pad_drop_tip(g, i), 0, CGRectNull, NO, g->safe, DM_PAD_SHAPE_TIP + i};
    }
    if (full) for (int i = 0; i < 2; i++) out[n++] = (DmPadShape){g->click[i], g->clickR, CGRectNull, NO, g->safe, DM_PAD_SHAPE_CLICK + i};
    for (int i = 0; i < 2; i++) out[n++] = (DmPadShape){CGPointZero, 0, g->pill[i], YES, g->safe, DM_PAD_SHAPE_PILL + i};
    out[n++] = (DmPadShape){g->swap, g->swapR, CGRectNull, NO, g->safe, DM_PAD_SHAPE_SWAP};
    return n;
}
static inline BOOL dm_pad_shape_inside(const DmPadShape *s) {
    const CGFloat e = 0.5;
    CGRect b = s->isRect ? s->rect : CGRectMake(s->c.x - s->r, s->c.y - s->r, 2 * s->r, 2 * s->r);
    return CGRectGetMinX(b) >= CGRectGetMinX(s->within) - e && CGRectGetMaxX(b) <= CGRectGetMaxX(s->within) + e
        && CGRectGetMinY(b) >= CGRectGetMinY(s->within) - e && CGRectGetMaxY(b) <= CGRectGetMaxY(s->within) + e;
}
static inline BOOL dm_pad_shapes_overlap(const DmPadShape *a, const DmPadShape *b) {
    const CGFloat e = 0.5;
    if (a->isRect && b->isRect) return CGRectIntersectsRect(CGRectInset(a->rect, e, e), CGRectInset(b->rect, e, e));
    if (a->isRect || b->isRect) {
        const DmPadShape *r = a->isRect ? a : b, *c = a->isRect ? b : a;
        CGFloat nx = fmax(CGRectGetMinX(r->rect), fmin(c->c.x, CGRectGetMaxX(r->rect))), ny = fmax(CGRectGetMinY(r->rect), fmin(c->c.y, CGRectGetMaxY(r->rect)));
        return hypot(c->c.x - nx, c->c.y - ny) < c->r - e;
    }
    return hypot(a->c.x - b->c.x, a->c.y - b->c.y) < a->r + b->r - e;
}
// A teardrop's tip belongs to its own circle; the tips are points, so they only count when they land inside another shape.
static inline BOOL dm_pad_same_control(const DmPadShape *a, const DmPadShape *b) {
    return (a->id >= DM_PAD_SHAPE_DROP && a->id < DM_PAD_SHAPE_TIP && b->id == a->id + 4) || (b->id >= DM_PAD_SHAPE_DROP && b->id < DM_PAD_SHAPE_TIP && a->id == b->id + 4);
}
// Every drawn shape inside its rectangle and no two overlapping.
static inline BOOL dm_pad_geo_fits(const DmPadGeo *g, BOOL full) {
    DmPadShape s[20]; int n = dm_pad_shapes(g, full, s);
    for (int i = 0; i < n; i++) {
        if (!dm_pad_shape_inside(&s[i])) return NO;
        for (int j = i + 1; j < n; j++) if (!dm_pad_same_control(&s[i], &s[j]) && dm_pad_shapes_overlap(&s[i], &s[j])) return NO;
    }
    return YES;
}

// The unit of the built-in size: the screen height (inside the controls region when it is split off), up to 1.3.
static inline CGFloat dm_pad_base_unit(CGRect bounds, UIEdgeInsets insets, DmLayout layout) {
    if (!layout.separated) return MIN(bounds.size.height / 430.0, 1.3);
    CGRect s = CGRectIntersection(layout.controls, UIEdgeInsetsInsetRect(bounds, dm_game_safe_insets(bounds, insets, layout.topSafeOnly)));
    return MIN(MIN(s.size.height / 430.0, s.size.width / 700.0), 1.3);
}

// The geometry before the player's arrangement: the player's size, moved toward the built-in size in steps until it fits (a large size
// that does not fit gets smaller; a small one in a split region whose minimum edges crowd it gets larger), and the left stick's place.
// The built-in size is never changed.
static inline DmPadGeo dm_pad_geo_placed(CGRect bounds, UIEdgeInsets insets, DmLayout layout, BOOL full, DmPadOptions o) {
    CGFloat u0 = dm_pad_base_unit(bounds, insets, layout), scale = o.scale > 0 ? o.scale : 1;
    DmPadGeo g = dm_pad_geo_at(bounds, insets, layout, full, u0 * scale);
    while (scale != 1 && !dm_pad_geo_fits(&g, full)) {
        scale = scale > 1 ? fmax(1, scale - 0.05) : fmin(1, scale + 0.05);
        g = dm_pad_geo_at(bounds, insets, layout, full, u0 * scale);
    }
    // The left stick's place: higher lifts it toward the shoulders, inward moves it (and the D-pad, which sits inward of it) toward the
    // middle. The move shrinks in steps until nothing overlaps; on a screen with no room the stick stays in the corner.
    if (o.stick != DM_PAD_STICK_CORNER) {
        BOOL up = o.stick == DM_PAD_STICK_HIGHER;
        CGPoint stick = g.stick, dpad = g.dpad;
        for (CGFloat d = (up ? DM_PAD_STICK_UP : DM_PAD_STICK_IN) * g.u; d > 0; d -= 2 * g.u) {
            if (up) g.stick = CGPointMake(stick.x, stick.y - d);
            else { g.stick = CGPointMake(stick.x + d, stick.y); g.dpad = CGPointMake(dpad.x + d, dpad.y); }
            if (dm_pad_geo_fits(&g, full)) return g;
        }
        g.stick = stick; g.dpad = dpad;
    }
    return g;
}

// ---- The player's arrangement (DM_TOUCH_LAYOUT) ----
// One value for every game, written by the shell's layout editor: "1", then for each layout ";", its name and "/control:dx,dy" for each moved
// control, for example 1;2d/face:0,-2/stick:1,-1;3d/a:-1,0 (layouts 2d 3d 2s 3s, controls as dm_pad_control_names, steps -64 to 64, y down).
// An unknown layout or control is skipped (a newer shell). Anything else that is not this form, or a value longer than DM_PAD_LAYOUT_MAX,
// is ignored whole, so every control keeps its built-in place. A value with no field for a control or a layout leaves it where it is.
// dm_pad_arrange then moves a control only to where it stays inside the area its built-in place uses and clear of every other control.
static const char *_Nonnull const dm_pad_control_names[DM_PAD_C_N] = {"face", "a", "b", "x", "y", "stick", "dpad", "zl", "l", "zr", "r", "l3", "r3", "minus", "plus"};
static const char *_Nonnull const dm_pad_set_names[DM_PAD_SET_N] = {"2d", "3d", "2s", "3s"};
enum { DM_PAD_LAYOUT_MAX = 1024, DM_PAD_STEP_MAX = 64 };
static const CGFloat DM_PAD_MOVE_GAP = 10;   // a moved control keeps this far from every other drawn control: 10 u, and at least 10 points

static inline int dm_pad_name_index(const char *p, size_t n, const char *_Nonnull const *_Nonnull names, int count) {
    for (int i = 0; i < count; i++) if (strlen(names[i]) == n && !strncmp(p, names[i], n)) return i;
    return -1;
}
static inline BOOL dm_pad_parse_step(const char *_Nonnull *_Nonnull pp, signed char *out) {
    const char *p = *pp; int sign = 1, v = 0, digits = 0;
    if (*p == '-') { sign = -1; p++; }
    while (*p >= '0' && *p <= '9') { if (++digits > 3) return NO; v = v * 10 + (*p++ - '0'); }
    if (!digits || v > DM_PAD_STEP_MAX) return NO;
    *out = (signed char)(sign * v); *pp = p;
    return YES;
}
// NO for a value it ignored. out is then the built-in layout, as for an unset or empty value (which give YES).
static inline BOOL dm_pad_layout_parse(const char *_Nullable v, DmPadLayout *out) {
    memset(out, 0, sizeof *out);
    if (!v || !*v) return YES;
    if (strnlen(v, DM_PAD_LAYOUT_MAX + 1) > DM_PAD_LAYOUT_MAX || v[0] != '1' || (v[1] && v[1] != ';')) return NO;
    DmPadLayout l; memset(&l, 0, sizeof l);
    const char *p = v + 1;
    while (*p == ';') {
        const char *name = ++p;
        while (*p && *p != '/' && *p != ';') p++;
        int set = dm_pad_name_index(name, (size_t)(p - name), dm_pad_set_names, DM_PAD_SET_N);
        while (*p == '/') {
            const char *control = ++p;
            while ((*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9')) p++;
            size_t n = (size_t)(p - control);
            signed char dx, dy;
            if (!n || *p != ':') return NO;
            p++;
            if (!dm_pad_parse_step(&p, &dx) || *p != ',') return NO;
            p++;
            if (!dm_pad_parse_step(&p, &dy)) return NO;
            int c = dm_pad_name_index(control, n, dm_pad_control_names, DM_PAD_C_N);
            if (set >= 0 && c >= 0) { l.dx[set][c] = dx; l.dy[set][c] = dy; }
        }
        if (*p && *p != ';') return NO;
    }
    if (*p) return NO;
    *out = l;
    return YES;
}
static inline int dm_pad_layout_count(const DmPadLayout *l) {   // the moved controls a value holds, over every layout
    int n = 0;
    for (int s = 0; s < DM_PAD_SET_N; s++) for (int c = 0; c < DM_PAD_C_N; c++) n += l->dx[s][c] || l->dy[s][c];
    return n;
}

// The drawn shapes (dm_pad_shapes ids) of a control.
static inline BOOL dm_pad_is_shape_of(int id, int c) {
    switch (c) {
    case DM_PAD_C_FACE: return id >= DM_PAD_SHAPE_FACE && id < DM_PAD_SHAPE_FACE + 4;
    case DM_PAD_C_A: case DM_PAD_C_B: case DM_PAD_C_X: case DM_PAD_C_Y: return id == DM_PAD_SHAPE_FACE + (c - DM_PAD_C_A);
    case DM_PAD_C_STICK: return id == DM_PAD_SHAPE_STICK;
    case DM_PAD_C_DPAD: return id == DM_PAD_SHAPE_DPAD;
    case DM_PAD_C_L3: case DM_PAD_C_R3: return id == DM_PAD_SHAPE_CLICK + (c - DM_PAD_C_L3);
    case DM_PAD_C_MINUS: case DM_PAD_C_PLUS: return id == DM_PAD_SHAPE_PILL + (c - DM_PAD_C_MINUS);
    default: return id == DM_PAD_SHAPE_DROP + (c - DM_PAD_C_ZL) || id == DM_PAD_SHAPE_TIP + (c - DM_PAD_C_ZL);
    }
}
static inline BOOL dm_pad_control_drawn(int c, BOOL full) { return full || (c != DM_PAD_C_DPAD && c != DM_PAD_C_L3 && c != DM_PAD_C_R3); }
static inline void dm_pad_shift(CGPoint *p, CGFloat dx, CGFloat dy) { p->x += dx; p->y += dy; }
static inline void dm_pad_move(DmPadGeo *g, int c, CGFloat dx, CGFloat dy) {
    switch (c) {
    case DM_PAD_C_FACE: dm_pad_shift(&g->face, dx, dy); for (int i = 0; i < 4; i++) dm_pad_shift(&g->faceKey[i], dx, dy); break;
    case DM_PAD_C_A: case DM_PAD_C_B: case DM_PAD_C_X: case DM_PAD_C_Y: dm_pad_shift(&g->faceKey[c - DM_PAD_C_A], dx, dy); break;
    case DM_PAD_C_STICK: dm_pad_shift(&g->stick, dx, dy); break;
    case DM_PAD_C_DPAD: dm_pad_shift(&g->dpad, dx, dy); break;
    case DM_PAD_C_L3: case DM_PAD_C_R3: dm_pad_shift(&g->click[c - DM_PAD_C_L3], dx, dy); break;
    case DM_PAD_C_MINUS: case DM_PAD_C_PLUS: dm_pad_shift(&g->pill[c - DM_PAD_C_MINUS].origin, dx, dy); break;
    default: dm_pad_shift(&g->drop[c - DM_PAD_C_ZL], dx, dy); break;
    }
}
static inline CGRect dm_pad_shape_box(const DmPadShape *s) { return s->isRect ? s->rect : CGRectMake(s->c.x - s->r, s->c.y - s->r, 2 * s->r, 2 * s->r); }
// a and b closer than gap (a grown by gap all round, a rectangle with square corners: on the safe side).
static inline BOOL dm_pad_shapes_near(const DmPadShape *a, const DmPadShape *b, CGFloat gap) {
    DmPadShape x = *a;
    if (x.isRect) x.rect = CGRectInset(x.rect, -gap, -gap); else x.r += gap;
    return dm_pad_shapes_overlap(&x, b);
}
// Control c where g has it: every shape of it inside its rectangle (the one its built-in place uses), none closer than the gap to a shape of
// another control, and none inside the menu button's hit circle.
static inline BOOL dm_pad_control_fits(const DmPadGeo *g, BOOL full, int c) {
    DmPadShape s[20]; int n = dm_pad_shapes(g, full, s);
    CGFloat gap = fmax(DM_PAD_MOVE_GAP * g->u, DM_PAD_MOVE_GAP);
    for (int i = 0; i < n; i++) {
        if (!dm_pad_is_shape_of(s[i].id, c)) continue;
        if (!dm_pad_shape_inside(&s[i])) return NO;
        for (int j = 0; j < n; j++) {
            if (dm_pad_is_shape_of(s[j].id, c)) continue;
            DmPadShape o = s[j];
            if (o.id == DM_PAD_SHAPE_SWAP) o.r = fmax(o.r + gap, MAX(g->swapR * 1.6, 22)) - gap;   // the menu button: its whole hit circle
            if (dm_pad_shapes_near(&s[i], &o, gap)) return NO;
        }
    }
    return YES;
}
static inline CGFloat dm_pad_clamp_1d(CGFloat lo, CGFloat hi, CGFloat rlo, CGFloat rhi) {   // the shift that brings lo..hi inside rlo..rhi (centred if wider)
    if (hi - lo > rhi - rlo) return (rlo + rhi) / 2 - (lo + hi) / 2;
    return lo < rlo ? rlo - lo : hi > rhi ? rhi - hi : 0;
}
// How far control c has to move to be inside its rectangle: a control dragged past the edge stops at the edge.
static inline CGPoint dm_pad_clamp(const DmPadGeo *g, BOOL full, int c) {
    DmPadShape s[20]; int n = dm_pad_shapes(g, full, s);
    CGFloat x0 = CGFLOAT_MAX, y0 = CGFLOAT_MAX, x1 = -CGFLOAT_MAX, y1 = -CGFLOAT_MAX; CGRect within = CGRectNull;
    for (int i = 0; i < n; i++) if (dm_pad_is_shape_of(s[i].id, c)) {
        CGRect b = dm_pad_shape_box(&s[i]); within = s[i].within;
        x0 = fmin(x0, CGRectGetMinX(b)); y0 = fmin(y0, CGRectGetMinY(b)); x1 = fmax(x1, CGRectGetMaxX(b)); y1 = fmax(y1, CGRectGetMaxY(b));
    }
    if (CGRectIsNull(within)) return CGPointZero;
    return CGPointMake(dm_pad_clamp_1d(x0, x1, CGRectGetMinX(within), CGRectGetMaxX(within)), dm_pad_clamp_1d(y0, y1, CGRectGetMinY(within), CGRectGetMaxY(within)));
}
// The arrangement of the current layout, on top of the size and the stick's place. Two rounds: the diamond and the other controls, then the
// keys of the diamond on their own, from where the diamond ended up. Each round places every control that fits and tries the rest again,
// so a control can take a place another one has left. A control that never fits keeps its place (dropped). Whatever the value, the result
// is a layout in which every control is inside its area and no two overlap.
static inline void dm_pad_arrange(DmPadGeo *g, BOOL full, BOOL separated, const DmPadLayout *layout) {
    int set = (separated ? DM_PAD_SET_2D_SPLIT : DM_PAD_SET_2D) + (full ? 1 : 0);
    CGFloat step = g->faceR / 2;   // a quarter of a face key's width
    const unsigned keys = 1u << DM_PAD_C_A | 1u << DM_PAD_C_B | 1u << DM_PAD_C_X | 1u << DM_PAD_C_Y;
    unsigned want = 0;
    for (int c = 0; c < DM_PAD_C_N; c++) if (dm_pad_control_drawn(c, full) && (layout->dx[set][c] || layout->dy[set][c])) want |= 1u << c;
    for (int round = 0; round < 2; round++) {
        unsigned todo = want & (round ? keys : ~keys);
        for (BOOL progress = YES; todo && progress; ) {
            progress = NO;
            for (int c = 0; c < DM_PAD_C_N; c++) if (todo & (1u << c)) {
                DmPadGeo t = *g;
                dm_pad_move(&t, c, layout->dx[set][c] * step, layout->dy[set][c] * step);
                CGPoint d = dm_pad_clamp(&t, full, c);
                dm_pad_move(&t, c, d.x, d.y);
                if (!dm_pad_control_fits(&t, full, c)) continue;
                *g = t; g->moved |= 1u << c; todo &= ~(1u << c); progress = YES;
                if ((1u << c) & keys) g->faceSplit = YES;
            }
        }
        g->dropped |= todo;
    }
}

// The geometry the gamepad draws, hit-tests and grabs with: the size and the stick's place (dm_pad_geo_placed), then the player's arrangement.
static inline DmPadGeo dm_pad_geo(CGRect bounds, UIEdgeInsets insets, DmLayout layout, BOOL full, DmPadOptions o) {
    DmPadGeo g = dm_pad_geo_placed(bounds, insets, layout, full, o);
    if (o.layout) dm_pad_arrange(&g, full, layout.separated, o.layout);
    return g;
}

// ---- Which control a touch-down takes ----
// The menu button (a view of its own, DmMenuButton) where it is nearer than a locked key (dm_pad_menu_takes). Then locked keys (the
// shoulders, − and +, L3 / R3: in the overlay layout the first in this order that is near enough, in the split one or with a moved control
// the nearest), then whichever of the diamond, the D-pad and the left stick is nearest in units of its grab radius. NONE: no control (in 3D
// the right third then holds the right stick, else the touch goes to the game).
enum { DM_PAD_HIT_NONE = 0, DM_PAD_HIT_KEY, DM_PAD_HIT_FACE, DM_PAD_HIT_DPAD, DM_PAD_HIT_STICK };
typedef struct { int kind, key; } DmPadHit;   // key: the DM_PAD_C_* of a locked key
static const int dm_pad_locked[8] = {DM_PAD_C_ZL, DM_PAD_C_L, DM_PAD_C_ZR, DM_PAD_C_R, DM_PAD_C_MINUS, DM_PAD_C_PLUS, DM_PAD_C_L3, DM_PAD_C_R3};
static const CGFloat DM_PAD_STICK_GRAB = 1.4, DM_PAD_DPAD_GRAB = 1.3;   // grab radius: times the ring radius, times the D-pad's outer edge
static inline CGFloat dm_pad_dist(CGPoint a, CGPoint b) { return hypot(a.x - b.x, a.y - b.y); }
// A locked key's distance from p in units of its hit radius (1 or less is a hit).
static inline CGFloat dm_pad_key_distance(const DmPadGeo *g, BOOL sep, int c, CGPoint p) {
    if (c >= DM_PAD_C_ZL && c <= DM_PAD_C_R) return dm_pad_dist(p, g->drop[c - DM_PAD_C_ZL]) / MAX(g->dropR[c - DM_PAD_C_ZL] * 1.35, sep ? 22 : 0);
    if (c == DM_PAD_C_L3 || c == DM_PAD_C_R3) return dm_pad_dist(p, g->click[c - DM_PAD_C_L3]) / MAX(g->clickR * 1.35, sep ? 22 : 0);
    CGRect r = CGRectInset(g->pill[c - DM_PAD_C_MINUS], -8 * g->u, -8 * g->u);
    if (!sep && !CGRectContainsPoint(r, p)) return CGFLOAT_MAX;
    CGFloat w = MAX(r.size.width, sep ? 28 : 0), h = MAX(r.size.height, sep ? 28 : 0);
    return MAX(fabs(p.x - CGRectGetMidX(r)) / (w / 2), fabs(p.y - CGRectGetMidY(r)) / (h / 2));
}
// The locked key a touch-down at p takes, -1 for none, and its distance.
static inline int dm_pad_locked_at(const DmPadGeo *g, BOOL full, BOOL sep, CGPoint p, CGFloat *_Nullable distance) {
    int key = -1; CGFloat kd = 1;
    for (int i = 0; i < 8; i++) {
        int c = dm_pad_locked[i];
        if ((c == DM_PAD_C_L3 || c == DM_PAD_C_R3) && !full) continue;
        CGFloat d = dm_pad_key_distance(g, sep, c, p);
        if (d <= 1 && (key < 0 || d < kd)) { key = c; kd = d; if (!sep && !g->moved) break; }
    }
    if (distance) *distance = kd;
    return key;
}
// The menu button's hit circle: 1.6 times its radius, at least 22 points.
static inline CGFloat dm_pad_menu_hit_r(const DmPadGeo *g) { return MAX(g->swapR * 1.6, 22); }
static inline CGFloat dm_pad_menu_distance(const DmPadGeo *g, CGPoint p) { return dm_pad_dist(p, g->swap) / dm_pad_menu_hit_r(g); }
// Whether the menu button takes a touch-down at p (with the controls shown): in its hit circle and nearer than any locked key's target.
// A moved control never reaches into that circle (dm_pad_control_fits), so the menu never takes a touch on one.
static inline BOOL dm_pad_menu_takes(const DmPadGeo *g, BOOL full, BOOL sep, CGPoint p) {
    CGFloat d = dm_pad_menu_distance(g, p), kd;
    if (d > 1) return NO;
    return dm_pad_locked_at(g, full, sep, p, &kd) < 0 || d < kd;
}
// A touch-down the menu button did not take. tap: the Tap layout (no control but the menu). stickFree: no touch holds the left stick yet.
static inline DmPadHit dm_pad_hit(const DmPadGeo *g, BOOL full, BOOL sep, BOOL tap, BOOL stickFree, CGPoint p) {
    if (tap) return (DmPadHit){DM_PAD_HIT_NONE, -1};
    int key = dm_pad_locked_at(g, full, sep, p, NULL);
    if (key >= 0) return (DmPadHit){DM_PAD_HIT_KEY, key};
    CGFloat best = 1, f = CGFLOAT_MAX; int kind = DM_PAD_HIT_NONE;
    if (g->faceSplit) for (int i = 0; i < 4; i++) f = fmin(f, dm_pad_dist(p, g->faceKey[i]) / MAX(g->faceR * 1.6, g->faceHitR));
    else f = dm_pad_dist(p, g->face) / (g->faceGap + MAX(g->faceR * 1.6, g->faceHitR));
    if (f <= best) { best = f; kind = DM_PAD_HIT_FACE; }
    if (full) { CGFloat d = dm_pad_dist(p, g->dpad) / MAX(g->dpadR * DM_PAD_DPAD_GRAB, sep ? 22 : 0); if (d < best) { best = d; kind = DM_PAD_HIT_DPAD; } }
    if (stickFree) { CGFloat s = dm_pad_dist(p, g->stick) / MAX(g->stickR * DM_PAD_STICK_GRAB, sep ? 22 : 0); if (s < best) { best = s; kind = DM_PAD_HIT_STICK; } }
    return (DmPadHit){kind, -1};
}

// Where the 3D layout's right-stick hint goes: a few words, no shape, in the area the undrawn right stick answers in (x from areaMinX to
// the right edge), between the top row and the diamond, inside the safe area and clear of every drawn control (a gap of 6 u around it).
// text is the label's size including its padding. CGRectNull when there is no room: the hint is then not shown.
static inline CGRect dm_pad_hint_rect(const DmPadGeo *g, CGFloat areaMinX, CGSize text) {
    CGRect s = g->safe; CGFloat gap = 6 * g->u;
    CGFloat left = MAX(areaMinX, CGRectGetMinX(s)), right = CGRectGetMaxX(s);
    if (right - left < text.width) { left = right - text.width; if (left < CGRectGetMinX(s)) return CGRectNull; }
    CGFloat top = CGRectGetMinY(s);   // below the right half of the top row
    for (int i = DM_PAD_ZR; i <= DM_PAD_R; i++) top = MAX(top, g->drop[i].y + g->dropR[i]);
    top = MAX(top, g->click[1].y + g->clickR);
    top = MAX(top, CGRectGetMaxY(g->pill[DM_PAD_PLUS]));
    CGFloat bottom = g->face.y - g->faceGap - g->faceR;   // above the diamond's X
    CGFloat x = (left + right) / 2 - text.width / 2, y = (top + bottom) / 2 - text.height / 2;
    x = fmax(left, fmin(x, right - text.width));
    CGRect r = CGRectMake(x, y, text.width, text.height);
    DmPadShape sh[20]; int n = dm_pad_shapes(g, YES, sh);
    DmPadShape me = {CGPointZero, 0, CGRectInset(r, -gap, -gap), YES, s, -1};
    if (!CGRectContainsRect(s, r)) return CGRectNull;
    for (int i = 0; i < n; i++) if (dm_pad_shapes_overlap(&me, &sh[i])) return CGRectNull;
    return r;
}

NS_ASSUME_NONNULL_END
