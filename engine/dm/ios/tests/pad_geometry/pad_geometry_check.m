// The virtual gamepad's placement (DmPadGeometry.h) on the screens it runs on, checked on the Mac: built and run by test_pad_geometry.py.
// Every line that starts with FAIL is a broken rule; the exit status is the number of them (capped).
#import <UIKit/UIKit.h>
#import "DmPadGeometry.h"
#include <stdio.h>

typedef struct { const char *name; CGRect bounds; UIEdgeInsets insets; BOOL partiallyOpen; CGRect division; } Screen;

static int g_fail;
#define FAIL(...) do { printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); g_fail++; } while (0)
#define NEAR(a, b) (fabs((a) - (b)) < 0.01)

static const char *k_sizes[] = {"small", "medium", "large"};

static DmPadGeo geo(const Screen *s, BOOL full, DmPadOptions o) {
    return dm_pad_geo(s->bounds, s->insets, dm_layout(s->bounds, s->insets, s->partiallyOpen, s->division, DM_PICTURE_16_9), full, o);
}

static void check_fits(const Screen *s, BOOL full, const char *size, DmPadOptions o) {
    DmPadGeo g = geo(s, full, o);
    DmPadShape sh[20]; int n = dm_pad_shapes(&g, full, sh);
    for (int i = 0; i < n; i++) {
        if (!dm_pad_shape_inside(&sh[i])) FAIL("%s %s %s: shape %d leaves its rectangle", s->name, full ? "3D" : "2D", size, sh[i].id);
        for (int j = i + 1; j < n; j++)
            if (!dm_pad_same_control(&sh[i], &sh[j]) && dm_pad_shapes_overlap(&sh[i], &sh[j]))
                FAIL("%s %s %s: shapes %d and %d overlap", s->name, full ? "3D" : "2D", size, sh[i].id, sh[j].id);
    }
    // Nothing outside the screen at all, side insets included only up to the corner rule.
    CGRect b = s->bounds;
    for (int i = 0; i < n; i++) {
        CGRect r = sh[i].isRect ? sh[i].rect : CGRectMake(sh[i].c.x - sh[i].r, sh[i].c.y - sh[i].r, 2 * sh[i].r, 2 * sh[i].r);
        if (!CGRectContainsRect(CGRectInset(b, -0.5, -0.5), r)) FAIL("%s %s %s: shape %d is off the screen", s->name, full ? "3D" : "2D", size, sh[i].id);
    }
}

// ---- DM_TOUCH_LAYOUT ----

static int g_arranged;
static BOOL layout_empty(const DmPadLayout *l) { return dm_pad_layout_count(l) == 0; }

// The value's form: what is read, what is skipped, what is ignored whole.
static void check_layout_values(void) {
    DmPadLayout l;
    if (!dm_pad_layout_parse(NULL, &l) || !layout_empty(&l)) FAIL("DM_TOUCH_LAYOUT unset: the built-in layout");
    if (!dm_pad_layout_parse("", &l) || !layout_empty(&l)) FAIL("DM_TOUCH_LAYOUT empty: the built-in layout");
    if (!dm_pad_layout_parse("1", &l) || !layout_empty(&l)) FAIL("DM_TOUCH_LAYOUT 1: nothing moved");
    if (!dm_pad_layout_parse("1;3d", &l) || !layout_empty(&l)) FAIL("DM_TOUCH_LAYOUT 1;3d: a layout with no field moves nothing");
    if (!dm_pad_layout_parse("1;2d/face:0,-2/stick:1,-1;3d/a:-1,0;3s/zl:64,-64", &l)
        || l.dx[DM_PAD_SET_2D][DM_PAD_C_FACE] != 0 || l.dy[DM_PAD_SET_2D][DM_PAD_C_FACE] != -2 || l.dx[DM_PAD_SET_2D][DM_PAD_C_STICK] != 1
        || l.dy[DM_PAD_SET_2D][DM_PAD_C_STICK] != -1 || l.dx[DM_PAD_SET_3D][DM_PAD_C_A] != -1 || l.dx[DM_PAD_SET_3D_SPLIT][DM_PAD_C_ZL] != 64
        || l.dy[DM_PAD_SET_3D_SPLIT][DM_PAD_C_ZL] != -64 || dm_pad_layout_count(&l) != 4) FAIL("DM_TOUCH_LAYOUT: a valid value is not read as written");
    // A newer shell's layout or control: skipped, the rest is read.
    if (!dm_pad_layout_parse("1;4d/a:1,1;2d/home:3,3/b:2,0", &l) || dm_pad_layout_count(&l) != 1 || l.dx[DM_PAD_SET_2D][DM_PAD_C_B] != 2)
        FAIL("DM_TOUCH_LAYOUT: an unknown layout or control is not skipped");
    // Anything else is ignored whole: the controls keep their built-in places.
    static const char *bad[] = {
        "2;2d/a:1,1", "x", "1x", "1;2d/a", "1;2d/a:", "1;2d/a:1", "1;2d/a:1,", "1;2d/a:1,1,1", "1;2d/a:+1,1", "1;2d/a:65,0", "1;2d/a:0,-65",
        "1;2d/a:1000,0", "1;2d/a:0001,0", "1;2d/A:1,1", "1;2d/a:1,1 ", " 1;2d/a:1,1", "1;2d/a:1,1/", "1;2d/:1,1", "1;2d/a:--1,1", "1;2d/a:1.5,1",
        "1;2d/a:1,1\n2d", "1;2d/a=1,1", "1;2d//a:1,1",
    };
    for (size_t i = 0; i < sizeof bad / sizeof *bad; i++) {
        memset(&l, 0x55, sizeof l);
        if (dm_pad_layout_parse(bad[i], &l) || !layout_empty(&l)) FAIL("DM_TOUCH_LAYOUT '%s' is not ignored", bad[i]);
    }
    // Too long: ignored whole, even when every part of it is a valid field.
    char longv[DM_PAD_LAYOUT_MAX + 64]; size_t n = 0;
    n += (size_t)snprintf(longv + n, sizeof longv - n, "1;2d");
    while (n < DM_PAD_LAYOUT_MAX + 8) n += (size_t)snprintf(longv + n, sizeof longv - n, "/a:1,1");
    if (dm_pad_layout_parse(longv, &l) || !layout_empty(&l)) FAIL("DM_TOUCH_LAYOUT of %zu characters is not ignored", n);
    longv[DM_PAD_LAYOUT_MAX - (DM_PAD_LAYOUT_MAX - 4) % 6] = 0;   // the same fields, cut at a field's end below the limit
    if (!dm_pad_layout_parse(longv, &l) || l.dx[DM_PAD_SET_2D][DM_PAD_C_A] != 1) FAIL("DM_TOUCH_LAYOUT: a value just under the limit is not read");
    // Random bytes never crash the reader, and what it does not reject is a layout like any other (checked below by the arrangement).
    uint32_t r = 7;
    for (int k = 0; k < 20000; k++) {
        char v[48]; int len = 1 + (int)(r % 46);
        static const char alphabet[] = "1;/:,-0123456789abcdfilmnprstuvxyz23d2s3s";
        v[0] = '1';
        for (int i = 1; i < len; i++) { r ^= r << 13; r ^= r >> 17; r ^= r << 5; v[i] = alphabet[r % (sizeof alphabet - 1)]; }
        v[len] = 0;
        BOOL ok = dm_pad_layout_parse(v, &l);
        if (!ok && !layout_empty(&l)) FAIL("DM_TOUCH_LAYOUT '%s': rejected but not empty", v);
        for (int s = 0; s < DM_PAD_SET_N; s++) for (int c = 0; c < DM_PAD_C_N; c++)
            if (abs(l.dx[s][c]) > DM_PAD_STEP_MAX || abs(l.dy[s][c]) > DM_PAD_STEP_MAX) FAIL("DM_TOUCH_LAYOUT '%s': a step out of range", v);
    }
}

static BOOL geo_equal(const DmPadGeo *a, const DmPadGeo *b) {
    #define SAME_PT(p, q) (CGPointEqualToPoint((p), (q)))
    if (a->u != b->u || !SAME_PT(a->face, b->face) || !SAME_PT(a->stick, b->stick) || !SAME_PT(a->dpad, b->dpad) || !SAME_PT(a->swap, b->swap)) return NO;
    for (int i = 0; i < 4; i++) if (!SAME_PT(a->drop[i], b->drop[i]) || !SAME_PT(a->faceKey[i], b->faceKey[i]) || a->dropR[i] != b->dropR[i]) return NO;
    for (int i = 0; i < 2; i++) if (!SAME_PT(a->click[i], b->click[i]) || !CGRectEqualToRect(a->pill[i], b->pill[i])) return NO;
    return a->faceSplit == b->faceSplit && a->moved == b->moved && a->dropped == b->dropped && a->faceR == b->faceR && a->stickR == b->stickR;
    #undef SAME_PT
}

enum { DM_PAD_HIT_MENU = 100 };   // the menu button: dm_pad_menu_takes, not dm_pad_hit
// Which control a shape id belongs to, as dm_pad_hit names it.
static void shape_owner(int id, int *kind, int *key) {
    *key = -1;
    if (id < DM_PAD_SHAPE_STICK) *kind = DM_PAD_HIT_FACE;
    else if (id == DM_PAD_SHAPE_STICK) *kind = DM_PAD_HIT_STICK;
    else if (id == DM_PAD_SHAPE_DPAD) *kind = DM_PAD_HIT_DPAD;
    else if (id < DM_PAD_SHAPE_TIP) { *kind = DM_PAD_HIT_KEY; *key = DM_PAD_C_ZL + (id - DM_PAD_SHAPE_DROP); }
    else if (id < DM_PAD_SHAPE_CLICK) *kind = -1;   // a teardrop's tip: a point, no touch target of its own
    else if (id < DM_PAD_SHAPE_PILL) { *kind = DM_PAD_HIT_KEY; *key = DM_PAD_C_L3 + (id - DM_PAD_SHAPE_CLICK); }
    else if (id < DM_PAD_SHAPE_SWAP) { *kind = DM_PAD_HIT_KEY; *key = DM_PAD_C_MINUS + (id - DM_PAD_SHAPE_PILL); }
    else *kind = DM_PAD_HIT_MENU;
}

// Every rule of a geometry the gamepad may draw: every shape inside its rectangle and on the screen, no two overlapping, a moved control
// clear of every other by the gap and of the menu button's hit circle, and a touch well inside a drawn control taken by that control (the
// menu button's decision and the hit-test read the same geometry).
static void check_geo(const Screen *s, BOOL full, const DmPadGeo *g, const char *what) {
    DmLayout l = dm_layout(s->bounds, s->insets, s->partiallyOpen, s->division, DM_PICTURE_16_9);
    DmPadShape sh[20]; int n = dm_pad_shapes(g, full, sh);
    for (int i = 0; i < n; i++) {
        if (!dm_pad_shape_inside(&sh[i])) FAIL("%s %s %s: shape %d leaves its rectangle", s->name, full ? "3D" : "2D", what, sh[i].id);
        CGRect b = dm_pad_shape_box(&sh[i]);
        if (!CGRectContainsRect(CGRectInset(s->bounds, -0.5, -0.5), b)) FAIL("%s %s %s: shape %d is off the screen", s->name, full ? "3D" : "2D", what, sh[i].id);
        for (int j = i + 1; j < n; j++)
            if (!dm_pad_same_control(&sh[i], &sh[j]) && dm_pad_shapes_overlap(&sh[i], &sh[j]))
                FAIL("%s %s %s: shapes %d and %d overlap", s->name, full ? "3D" : "2D", what, sh[i].id, sh[j].id);
    }
    for (int c = 0; c < DM_PAD_C_N; c++)
        if ((g->moved & (1u << c)) && !dm_pad_control_fits(g, full, c)) FAIL("%s %s %s: moved control %s is too close to another", s->name, full ? "3D" : "2D", what, dm_pad_control_names[c]);
    if (g->moved & g->dropped) FAIL("%s %s: a control is both moved and dropped", s->name, what);
    // Touches: the centre of each control and points halfway to its edge (the D-pad on its arms, a pill along its length).
    for (int i = 0; i < n; i++) {
        int kind, key; shape_owner(sh[i].id, &kind, &key);
        if (kind < 0) continue;
        CGPoint pts[5]; int np = 0; pts[np++] = sh[i].isRect ? CGPointMake(CGRectGetMidX(sh[i].rect), CGRectGetMidY(sh[i].rect)) : sh[i].c;
        if (sh[i].isRect) { CGFloat w = sh[i].rect.size.width * 0.3; pts[np++] = CGPointMake(pts[0].x - w, pts[0].y); pts[np++] = CGPointMake(pts[0].x + w, pts[0].y); }
        else {
            CGFloat r = sh[i].id == DM_PAD_SHAPE_DPAD ? g->dpadR * 0.6 : sh[i].r * 0.5;
            for (int k = 0; k < 4; k++) pts[np++] = CGPointMake(sh[i].c.x + (k == 0 ? r : k == 1 ? -r : 0), sh[i].c.y + (k == 2 ? r : k == 3 ? -r : 0));
        }
        for (int k = 0; k < np; k++) {
            BOOL menu = dm_pad_menu_takes(g, full, l.separated, pts[k]);
            if (kind == DM_PAD_HIT_MENU) { if (!menu) FAIL("%s %s %s: a touch on the menu button at %.0f %.0f is not the menu's", s->name, full ? "3D" : "2D", what, pts[k].x, pts[k].y); continue; }
            if (menu) { FAIL("%s %s %s: the menu button takes a touch at %.0f %.0f inside shape %d (moved %#x)", s->name, full ? "3D" : "2D", what, pts[k].x, pts[k].y, sh[i].id, g->moved); continue; }
            DmPadHit h = dm_pad_hit(g, full, l.separated, NO, YES, pts[k]);
            if (h.kind != kind || (kind == DM_PAD_HIT_KEY && h.key != key))
                FAIL("%s %s %s: a touch at %.0f %.0f inside shape %d goes to %d/%d (moved %#x)", s->name, full ? "3D" : "2D", what, pts[k].x, pts[k].y, sh[i].id, h.kind, h.key, g->moved);
        }
    }
}

static uint32_t g_rng = 2026;
static uint32_t rnd(void) { g_rng ^= g_rng << 13; g_rng ^= g_rng >> 17; g_rng ^= g_rng << 5; return g_rng; }

static void check_arrangement(const Screen *screens, int nscreens) {
    // Reset: a layout of zeros, a value that names a control at 0 0, and a value for other layouts are the built-in geometry exactly,
    // the points the gamepad has always used (pinned above on the Pro Max).
    DmPadLayout zero, named, other; memset(&zero, 0, sizeof zero);
    dm_pad_layout_parse("1;2d/face:0,0/stick:0,0;3d/a:0,0/zl:0,0", &named);
    dm_pad_layout_parse("1;2s/face:3,-2/stick:2,-2;3s/a:-2,0", &other);   // only the split layouts
    for (int i = 0; i < nscreens; i++)
        for (int full = 0; full < 2; full++)
            for (int z = 0; z < 3; z++) {
                DmLayout l = dm_layout(screens[i].bounds, screens[i].insets, screens[i].partiallyOpen, screens[i].division, DM_PICTURE_16_9);
                DmPadOptions o = {dm_pad_size_scale(k_sizes[z]), 0, NULL};
                DmPadGeo none = dm_pad_geo(screens[i].bounds, screens[i].insets, l, full, o);
                o.layout = &zero; DmPadGeo a = dm_pad_geo(screens[i].bounds, screens[i].insets, l, full, o);
                o.layout = &named; DmPadGeo b = dm_pad_geo(screens[i].bounds, screens[i].insets, l, full, o);
                if (!geo_equal(&none, &a) || !geo_equal(&none, &b)) FAIL("%s %s %s: an arrangement of zeros is not the built-in layout", screens[i].name, full ? "3D" : "2D", k_sizes[z]);
                o.layout = &other; DmPadGeo c = dm_pad_geo(screens[i].bounds, screens[i].insets, l, full, o);
                if (!l.separated && !geo_equal(&none, &c)) FAIL("%s %s: the split layouts' arrangement moved the overlay layout", screens[i].name, full ? "3D" : "2D");
                check_geo(&screens[i], full, &none, k_sizes[z]);
            }
    {   // On the Pro Max: a move that fits lands where asked, a move onto another control is dropped, a move past the edge stops at it.
        const Screen *s = &screens[3];
        DmLayout l = dm_layout(s->bounds, s->insets, NO, CGRectNull, DM_PICTURE_16_9);
        DmPadLayout m; dm_pad_layout_parse("1;3d/face:-4,-4/stick:0,-3/minus:-2,2/b:0,1", &m);
        DmPadOptions o = {1, 0, &m};
        DmPadGeo base = dm_pad_geo(s->bounds, s->insets, l, YES, (DmPadOptions){1}), g = dm_pad_geo(s->bounds, s->insets, l, YES, o);
        CGFloat step = 13.5;   // a quarter of the 54-point face key
        if (!NEAR(g.face.x, base.face.x - 4 * step) || !NEAR(g.face.y, base.face.y - 4 * step)) FAIL("Pro Max: the diamond did not move by 4 4 steps");
        if (!NEAR(g.faceKey[0].x, base.faceKey[0].x - 4 * step) || !NEAR(g.faceKey[1].y, base.faceKey[1].y - 3 * step)) FAIL("Pro Max: the keys did not follow the diamond, B its own step");
        if (!NEAR(g.stick.x, base.stick.x) || !NEAR(g.stick.y, base.stick.y - 3 * step)) FAIL("Pro Max: the stick did not move");
        if (!NEAR(g.pill[DM_PAD_MINUS].origin.x, base.pill[DM_PAD_MINUS].origin.x - 2 * step) || !NEAR(g.pill[DM_PAD_MINUS].origin.y, base.pill[DM_PAD_MINUS].origin.y + 2 * step)) FAIL("Pro Max: minus did not move");
        if (g.dropped || !g.faceSplit) FAIL("Pro Max: a move that fits was dropped (%#x)", g.dropped);
        dm_pad_layout_parse("1;3d/stick:52,0/zl:0,-40/dpad:-30,0", &m);   // the stick onto the diamond, ZL past the top, the D-pad past the left edge
        g = dm_pad_geo(s->bounds, s->insets, l, YES, o);
        if (!CGPointEqualToPoint(g.stick, base.stick) || !(g.dropped & 1u << DM_PAD_C_STICK)) FAIL("Pro Max: the stick moved onto the diamond");
        if (!NEAR(g.drop[DM_PAD_ZL].y - g.dropR[DM_PAD_ZL] * DM_PAD_DROP_TIP * sin(M_PI_4), CGRectGetMinY(g.safe))) FAIL("Pro Max: ZL past the top does not stop at the edge (%.1f)", g.drop[DM_PAD_ZL].y);
        if (g.moved & 1u << DM_PAD_C_DPAD) {
            if (!NEAR(g.dpad.x - hypot(g.dpadR, g.armW), CGRectGetMinX(g.corner))) FAIL("Pro Max: the D-pad past the edge does not stop at it");
        }
        // A control can take the place another one left: the stick into the D-pad's place while the D-pad goes elsewhere (ordered after the stick).
        dm_pad_layout_parse("1;3d/stick:11,1/dpad:0,-12", &m);
        g = dm_pad_geo(s->bounds, s->insets, l, YES, o);
        if (g.dropped) FAIL("Pro Max: the stick could not take the D-pad's old place (%#x)", g.dropped);
        check_geo(s, YES, &g, "swap");
    }
    // The fuzz: seeded random arrangements on every screen, layout, size and stick place. Whatever is asked, the result keeps every rule.
    for (int i = 0; i < nscreens; i++)
        for (int full = 0; full < 2; full++)
            for (int z = 0; z < 3; z++)
                for (int p = 0; p < 3; p++)
                    for (int k = 0; k < 40; k++) {
                        DmPadLayout m; memset(&m, 0, sizeof m);
                        int moves = 1 + (int)(rnd() % 10);
                        for (int j = 0; j < moves; j++) {
                            int set = (int)(rnd() % DM_PAD_SET_N), c = (int)(rnd() % DM_PAD_C_N), wide = rnd() % 3 == 0;
                            int range = wide ? DM_PAD_STEP_MAX : 8;
                            m.dx[set][c] = (signed char)((int)(rnd() % (2 * range + 1)) - range);
                            m.dy[set][c] = (signed char)((int)(rnd() % (2 * range + 1)) - range);
                        }
                        DmLayout l = dm_layout(screens[i].bounds, screens[i].insets, screens[i].partiallyOpen, screens[i].division, DM_PICTURE_16_9);
                        DmPadGeo g = dm_pad_geo(screens[i].bounds, screens[i].insets, l, full, (DmPadOptions){dm_pad_size_scale(k_sizes[z]), p, &m});
                        char what[64]; snprintf(what, sizeof what, "%s stick %d fuzz %d", k_sizes[z], p, k);
                        check_geo(&screens[i], full, &g, what);
                        g_arranged++;
                    }
}

int main(void) {
    const Screen screens[] = {
        // iPhone landscape (the phone's only orientation): the Dynamic Island or notch on one side, the home indicator at the bottom.
        {"iPhone SE landscape", {{0, 0}, {667, 375}}, {0, 0, 0, 0}, NO, CGRectNull},
        {"iPhone mini landscape", {{0, 0}, {812, 375}}, {0, 50, 21, 50}, NO, CGRectNull},
        {"iPhone landscape", {{0, 0}, {852, 393}}, {0, 59, 21, 59}, NO, CGRectNull},
        {"iPhone Pro Max landscape", {{0, 0}, {932, 430}}, {0, 59, 21, 59}, NO, CGRectNull},
        {"iPhone 17 Pro Max landscape", {{0, 0}, {956, 440}}, {0, 62, 20, 62}, NO, CGRectNull},
        // iPad: every orientation; portrait splits the picture from the controls.
        {"iPad mini landscape", {{0, 0}, {1133, 744}}, {24, 0, 20, 0}, NO, CGRectNull},
        {"iPad Pro 13 landscape", {{0, 0}, {1376, 1032}}, {24, 0, 20, 0}, NO, CGRectNull},
        {"iPad mini portrait", {{0, 0}, {744, 1133}}, {24, 0, 20, 0}, NO, CGRectNull},
        {"iPad Pro 13 portrait", {{0, 0}, {1032, 1376}}, {24, 0, 20, 0}, NO, CGRectNull},
        // Split portrait windows the Duo harness uses, and iPhone Duo's inner display (patch 0061): portrait with the fold, tabletop half open.
        {"portrait 390x844", {{0, 0}, {390, 844}}, {59, 0, 34, 0}, NO, CGRectNull},
        {"portrait 320x568", {{0, 0}, {320, 568}}, {50, 0, 24, 0}, NO, CGRectNull},
        {"Duo inner portrait", {{0, 0}, {669, 951}}, {62, 0, 34, 0}, NO, {{0, 455.5}, {669, 40}}},
        {"Duo inner landscape", {{0, 0}, {951, 669}}, {0, 62, 20, 62}, NO, CGRectNull},
        {"Duo tabletop", {{0, 0}, {951, 669}}, {0, 62, 20, 62}, YES, {{0, 314.5}, {951, 40}}},
    };
    int nscreens = (int)(sizeof screens / sizeof *screens);

    // Option parsing.
    if (dm_pad_size_scale(NULL) != 1 || dm_pad_size_scale("") != 1 || dm_pad_size_scale("medium") != 1 || dm_pad_size_scale("huge") != 1) FAIL("DM_TOUCH_SIZE: medium is the default");
    if (!(dm_pad_size_scale("small") < 1) || !(dm_pad_size_scale("large") > 1)) FAIL("DM_TOUCH_SIZE: small is smaller and large larger");

    // The built-in size is the layout DmGamepad.m has always drawn: iPhone Pro Max landscape, centres in points.
    {
        DmPadGeo g = geo(&screens[3], YES, (DmPadOptions){1});
        if (!NEAR(g.u, 1)) FAIL("Pro Max: u %.3f, want 1", g.u);
        if (!NEAR(g.face.x, 932 - 29.5 - 81) || !NEAR(g.face.y, 430 - 21 - 82)) FAIL("Pro Max: diamond at %.1f %.1f", g.face.x, g.face.y);
        if (!NEAR(g.stick.x, 29.5 + 81) || !NEAR(g.stick.y, 430 - 21 - 82)) FAIL("Pro Max: stick at %.1f %.1f", g.stick.x, g.stick.y);
        if (!NEAR(g.dpad.x, 29.5 + 231) || !NEAR(g.dpad.y, 430 - 21 - 64)) FAIL("Pro Max: D-pad at %.1f %.1f", g.dpad.x, g.dpad.y);
        if (!NEAR(g.drop[DM_PAD_ZL].x, 59 + 44) || !NEAR(g.drop[DM_PAD_ZL].y, 40) || !NEAR(g.drop[DM_PAD_R].x, 932 - 59 - 44) || !NEAR(g.drop[DM_PAD_R].y, 108)) FAIL("Pro Max: shoulders moved");
        if (!NEAR(g.click[1].x, 932 - 59 - 102) || !NEAR(g.pill[DM_PAD_PLUS].origin.x, 466 + 52 - 25) || !NEAR(g.swap.x, 466) || !NEAR(g.swap.y, 22)) FAIL("Pro Max: top row moved");
        if (!NEAR(g.stickR, 77) || !NEAR(g.faceR, 27) || !NEAR(g.dpadR, 48)) FAIL("Pro Max: sizes changed");
        // Portrait split (the Duo harness's numbers): the thumbs' centres at 28 % and 72 % of the controls, 58 % down.
        DmLayout l = dm_layout(screens[9].bounds, screens[9].insets, NO, CGRectNull, DM_PICTURE_16_9);
        DmPadGeo p = dm_pad_geo(screens[9].bounds, screens[9].insets, l, NO, (DmPadOptions){1});
        CGRect s = p.safe;
        if (!p.portrait || !NEAR(p.face.x, CGRectGetMinX(s) + 0.72 * s.size.width) || !NEAR(p.stick.x, CGRectGetMinX(s) + 0.28 * s.size.width)) FAIL("portrait: thumbs moved");
    }

    // Every size and stick place on every screen, 2D and 3D: inside, and no overlap.
    static const char *places[] = {"corner", "higher", "inward"};
    if (dm_pad_stick_place(NULL) != DM_PAD_STICK_CORNER || dm_pad_stick_place("left") != DM_PAD_STICK_CORNER || dm_pad_stick_place("higher") != DM_PAD_STICK_HIGHER
        || dm_pad_stick_place("inward") != DM_PAD_STICK_INWARD) FAIL("DM_TOUCH_STICK: corner is the default");
    for (int i = 0; i < nscreens; i++)
        for (int full = 0; full < 2; full++)
            for (int z = 0; z < 3; z++)
                for (int p = 0; p < 3; p++) {
                    char what[64]; snprintf(what, sizeof what, "%s %s", k_sizes[z], places[p]);
                    check_fits(&screens[i], full, what, (DmPadOptions){dm_pad_size_scale(k_sizes[z]), dm_pad_stick_place(places[p])});
                }

    // The stick moves where asked on the phones, and nothing on the right moves with it.
    for (int i = 0; i <= 4; i++)
        for (int full = 0; full < 2; full++)
            for (int z = 0; z < 3; z++) {
                DmPadOptions o = {dm_pad_size_scale(k_sizes[z]), DM_PAD_STICK_CORNER};
                DmPadGeo c = geo(&screens[i], full, o);
                o.stick = DM_PAD_STICK_HIGHER; DmPadGeo h = geo(&screens[i], full, o);
                o.stick = DM_PAD_STICK_INWARD; DmPadGeo n = geo(&screens[i], full, o);
                if (!(c.stick.y - h.stick.y >= 30 * c.u) || h.stick.x != c.stick.x) FAIL("%s %s %s: higher lifts the stick only %.1f", screens[i].name, full ? "3D" : "2D", k_sizes[z], c.stick.y - h.stick.y);
                if (!(n.stick.x - c.stick.x >= 30 * c.u) || n.stick.y != c.stick.y) FAIL("%s %s %s: inward moves the stick only %.1f", screens[i].name, full ? "3D" : "2D", k_sizes[z], n.stick.x - c.stick.x);
                if (full && !NEAR(n.dpad.x - c.dpad.x, n.stick.x - c.stick.x)) FAIL("%s 3D %s: the D-pad does not move with the stick", screens[i].name, k_sizes[z]);
                if (!CGPointEqualToPoint(h.face, c.face) || !CGPointEqualToPoint(n.face, c.face) || !CGPointEqualToPoint(n.drop[DM_PAD_R], c.drop[DM_PAD_R])) FAIL("%s: the right side moved", screens[i].name);
            }

    // Picture Fill (DM_PICTURE_FIT) only makes the game rectangle larger: the controls keep the full view and their places.
    for (int i = 0; i < nscreens; i++) {
        DmLayout fit = dm_layout(screens[i].bounds, screens[i].insets, screens[i].partiallyOpen, screens[i].division, DM_PICTURE_16_9);
        DmLayout fill = dm_layout_picture(fit, screens[i].bounds, YES, DM_PICTURE_16_9);
        DmPadGeo a = dm_pad_geo(screens[i].bounds, screens[i].insets, fit, YES, (DmPadOptions){1.2}), b = dm_pad_geo(screens[i].bounds, screens[i].insets, fill, YES, (DmPadOptions){1.2});
        if (!CGPointEqualToPoint(a.face, b.face) || !CGPointEqualToPoint(a.stick, b.stick) || a.u != b.u) FAIL("%s: the picture fill moved the controls", screens[i].name);
    }

    // The sizes keep their order everywhere, and on a phone in landscape large really is larger and small smaller.
    for (int i = 0; i < nscreens; i++)
        for (int full = 0; full < 2; full++) {
            CGFloat us = geo(&screens[i], full, (DmPadOptions){0.8}).u, um = geo(&screens[i], full, (DmPadOptions){1}).u, ul = geo(&screens[i], full, (DmPadOptions){1.2}).u;
            if (!(us < um) || ul < um) FAIL("%s %s: sizes out of order (%.3f %.3f %.3f)", screens[i].name, full ? "3D" : "2D", us, um, ul);
            if (i <= 4 && !(ul > um * 1.15)) FAIL("%s %s: large is not larger (%.3f vs %.3f)", screens[i].name, full ? "3D" : "2D", ul, um);
        }

    // The 3D layout's right-stick hint: in the right third, inside the safe area, clear of every control; on every phone in landscape
    // and every size it has room for a short and a long wording.
    for (int i = 0; i < nscreens; i++)
        for (int z = 0; z < 3; z++)
            for (int w = 0; w < 2; w++) {
                DmLayout l = dm_layout(screens[i].bounds, screens[i].insets, screens[i].partiallyOpen, screens[i].division, DM_PICTURE_16_9);
                DmPadGeo g = dm_pad_geo(screens[i].bounds, screens[i].insets, l, YES, (DmPadOptions){dm_pad_size_scale(k_sizes[z]), 0});
                CGFloat areaMinX = CGRectGetMaxX(l.controls) - l.controls.size.width / 3;
                CGSize text = CGSizeMake(w ? fmax(300 * g.u, 280) : 150 * g.u, fmax(30 * g.u, 28));   // the long one: about 30 characters at the label's 13 to 20 points
                CGRect r = dm_pad_hint_rect(&g, areaMinX, text);
                if (CGRectIsNull(r)) { if (i <= 6 || i == 12) FAIL("%s %s: no room for the hint (%s)", screens[i].name, k_sizes[z], w ? "long" : "short"); continue; }
                if (CGRectGetMinX(r) < areaMinX - 0.5 && CGRectGetMaxX(r) < CGRectGetMaxX(g.safe) - 0.5) FAIL("%s %s: the hint is not at the right edge's area", screens[i].name, k_sizes[z]);
                if (!CGRectContainsRect(g.safe, r)) FAIL("%s %s: the hint leaves the safe area", screens[i].name, k_sizes[z]);
                DmPadShape sh[20]; int n = dm_pad_shapes(&g, YES, sh);
                DmPadShape me = {CGPointZero, 0, r, YES, g.safe, -1};
                for (int k = 0; k < n; k++) if (dm_pad_shapes_overlap(&me, &sh[k])) FAIL("%s %s: the hint covers shape %d", screens[i].name, k_sizes[z], sh[k].id);
            }

    check_layout_values();
    check_arrangement(screens, nscreens);

    if (!g_fail) printf("ok: %d screens, %d arrangements\n", nscreens, g_arranged);
    return g_fail > 100 ? 100 : g_fail;
}
