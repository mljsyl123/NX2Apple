// The few UIKit names DmLayout.h and DmPadGeometry.h use, so their pure geometry builds and runs on the Mac (test_pad_geometry.py).
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
typedef struct { CGFloat top, left, bottom, right; } UIEdgeInsets;
static const UIEdgeInsets UIEdgeInsetsZero = {0, 0, 0, 0};
static inline UIEdgeInsets UIEdgeInsetsMake(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return (UIEdgeInsets){t, l, b, r}; }
static inline CGRect UIEdgeInsetsInsetRect(CGRect r, UIEdgeInsets i) {
    r.origin.x += i.left; r.origin.y += i.top; r.size.width -= i.left + i.right; r.size.height -= i.top + i.bottom; return r;
}
@class UIView;
