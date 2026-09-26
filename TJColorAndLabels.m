#import "TJEngine.h"
#import "TJInternal.h"
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id tj_objectForKnownSelector(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

UIColor *dominantColorFromImage(UIImage *image, CGFloat satMult, CGFloat briCap) {
    if (!image) return nil;

    CGSize thumb = CGSizeMake(32, 32);
    UIGraphicsBeginImageContextWithOptions(thumb, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, thumb.width, thumb.height)];
    UIImage *small = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    CGImageRef cg = small.CGImage;
    if (!cg) return nil;

    NSUInteger w = CGImageGetWidth(cg), h = CGImageGetHeight(cg), n = w * h;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    unsigned char *px = (unsigned char *)calloc(n * 4, 1);
    if (!px) { CGColorSpaceRelease(space); return nil; }
    CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, w * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) { free(px); return nil; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);

    long r = 0, g = 0, b = 0;
    for (NSUInteger i = 0; i < n; i++) { r += px[i*4]; g += px[i*4+1]; b += px[i*4+2]; }
    free(px);

    UIColor *avg = [UIColor colorWithRed:(r/(CGFloat)n)/255.0
                                   green:(g/(CGFloat)n)/255.0
                                    blue:(b/(CGFloat)n)/255.0
                                   alpha:1.0];
    CGFloat hue, sat, bri, alpha;
    [avg getHue:&hue saturation:&sat brightness:&bri alpha:&alpha];
    sat = MIN(sat * satMult, 1.0);
    bri = MIN(MAX(bri, 0.15), briCap);
    return [UIColor colorWithHue:hue saturation:sat brightness:bri alpha:alpha];
}

CGFloat tj_imageEdgeRatio(UIImage *image) {
    if (!image) return 1.0f;

    CGSize thumb = CGSizeMake(32, 32);
    UIGraphicsBeginImageContextWithOptions(thumb, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, thumb.width, thumb.height)];
    UIImage *small = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    CGImageRef cg = small.CGImage;
    if (!cg) return 1.0f;

    NSUInteger w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    unsigned char *px = (unsigned char *)calloc(w * h * 4, 1);
    if (!px) { CGColorSpaceRelease(space); return 1.0f; }
    CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, w * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!ctx) { free(px); return 1.0f; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);

    NSUInteger edges = 0, pairs = 0;
    for (NSUInteger y = 0; y < h; y++) {
        for (NSUInteger x = 0; x + 1 < w; x++) {
            NSUInteger i = y * w + x, j = i + 1;
            CGFloat la = (0.2126f*px[i*4] + 0.7152f*px[i*4+1] + 0.0722f*px[i*4+2]) / 255.f;
            CGFloat lb = (0.2126f*px[j*4] + 0.7152f*px[j*4+1] + 0.0722f*px[j*4+2]) / 255.f;
            if (fabs(la - lb) > 0.08) edges++;
            pairs++;
        }
    }
    free(px);
    return pairs ? (CGFloat)edges / (CGFloat)pairs : 1.0f;
}

BOOL colorIsLight(UIColor *color) {
    if (!color) return NO;
    CGFloat r = 0.f, g = 0.f, b = 0.f;
    if (tj_safeColorRGBA(color, &r, &g, &b, NULL)) {
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.5;
    }
    return tj_colorLuminance(color) > 0.5;
}

double tj_colorLuminance(UIColor *c) {
    CGFloat r, g, b, a;
    if (!c || ![c getRed:&r green:&g blue:&b alpha:&a] || a < 0.15) return 0.5;
    return 0.299 * (double)r + 0.587 * (double)g + 0.114 * (double)b;
}

BOOL tj_safeColorRGBA(UIColor *c, CGFloat *outR, CGFloat *outG, CGFloat *outB, CGFloat *outA) {
    if (!c) return NO;
    CGFloat r = 0.f, g = 0.f, b = 0.f, a = 1.f;
    if ([c getRed:&r green:&g blue:&b alpha:&a]) {
        if (outR) *outR = r;
        if (outG) *outG = g;
        if (outB) *outB = b;
        if (outA) *outA = a;
        return YES;
    }
    CGFloat w = 0.f;
    a = 1.f;
    if ([c getWhite:&w alpha:&a]) {
        if (outR) *outR = w;
        if (outG) *outG = w;
        if (outB) *outB = w;
        if (outA) *outA = a;
        return YES;
    }
    return NO;
}

UIColor *tj_detailHeaderSubtitleOnListSurface(UIColor *listSurface) {
    double lum = tj_colorLuminance(listSurface);
    if (lum > 0.84)
        return [UIColor colorWithWhite:0.06 alpha:1];
    return [UIColor whiteColor];
}

void tj_walkTextViewsForSubtitleInk(UIView *v, int depth, UIColor **bestOut, CGFloat *scoreOut) {
    if (!v || depth > 28 || !bestOut || !scoreOut) return;
    if ([v isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)v;
        UIColor *tc = tv.textColor;
        if (tc) {
            CGFloat a = 1.f;
            if (![tc getRed:nil green:nil blue:nil alpha:&a]) a = 1.f;
            if (a < 0.04f) return;
            CGFloat fs = tv.font ? tv.font.pointSize : 14.f;
            CGFloat area = CGRectGetWidth(tv.bounds) * CGRectGetHeight(tv.bounds);
            CGFloat score = fs * 1000.f + area * 1e-6f;
            if (score > *scoreOut) {
                *scoreOut = score;
                *bestOut = tc;
            }
        }
    }
    NSString *cn = NSStringFromClass(v.class);
    if ([cn containsString:@"UITextViewCanvasView"]) {
        UIView *p = v.superview;
        while (p) {
            if ([p isKindOfClass:[UITextView class]]) {
                UITextView *tv = (UITextView *)p;
                UIColor *tc = tv.textColor;
                if (tc) {
                    CGFloat a = 1.f;
                    if (![tc getRed:nil green:nil blue:nil alpha:&a]) a = 1.f;
                    if (a >= 0.04f) {
                        CGFloat fs = tv.font ? tv.font.pointSize : 14.f;
                        CGFloat area = CGRectGetWidth(tv.bounds) * CGRectGetHeight(tv.bounds);
                        CGFloat score = fs * 1000.f + area * 1e-6f + 1e6f;
                        if (score > *scoreOut) {
                            *scoreOut = score;
                            *bestOut = tc;
                        }
                    }
                }
                break;
            }
            p = p.superview;
        }
    }
    for (UIView *s in v.subviews)
        tj_walkTextViewsForSubtitleInk(s, depth + 1, bestOut, scoreOut);
}

UIColor *tj_detailHeaderSubtitleColorFromTextViewReference(UIView *detailHeader) {
    UIColor *best = nil;
    CGFloat score = 0;
    if (detailHeader)
        tj_walkTextViewsForSubtitleInk(detailHeader, 0, &best, &score);
    return best;
}

UIButton *tj_nearestUIButtonAncestor(UIView *v) {
    for (UIView *x = v.superview; x; x = x.superview) {
        if ([x isKindOfClass:[UIButton class]])
            return (UIButton *)x;
    }
    return nil;
}

static void *kTJArtistSubtitleLastInkKey = (void *)"tj.asso.artistSubtitleLastInk";

void tj_applyArtistSubtitleInkToLabel(UILabel *l, UIColor *ink) {
    if (!l || !ink) return;
    NSString *lcn = NSStringFromClass(l.class);
    if (![lcn containsString:@"ButtonLabel"]) return;
    UIColor *lastInk = objc_getAssociatedObject(l, kTJArtistSubtitleLastInkKey);
    if ([lastInk isEqual:ink]) return;
    objc_setAssociatedObject(l, kTJArtistSubtitleLastInkKey, ink, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    l.textColor = ink;
    l.backgroundColor = [UIColor clearColor];
    UIButton *btn = tj_nearestUIButtonAncestor(l);
    if (!btn) return;
    [btn setTitleColor:ink forState:UIControlStateNormal];
    [btn setTitleColor:ink forState:UIControlStateHighlighted];
    [btn setTitleColor:ink forState:UIControlStateSelected];
    [btn setTitleColor:ink forState:UIControlStateDisabled];
    btn.tintColor = ink;
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfg = btn.configuration;
        if (cfg) {
            UIButtonConfiguration *c = [cfg copy];
            c.baseForegroundColor = ink;
            btn.configuration = c;
        }
    }
}

void tj_boostDetailHeaderCaptionLabels(UIView *v, UIColor *fg, int depth) {
    if (!v || depth > 22 || !fg) return;
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        NSString *lcn = NSStringFromClass(l.class);
        if (![lcn containsString:@"ButtonLabel"]) {
            UIColor *t = l.textColor;
            if (t && l.font.pointSize <= 14.5f) {
                CGFloat sat = 0, al = 0;
                [t getHue:NULL saturation:&sat brightness:NULL alpha:&al];
                if (sat <= 0.22f && al >= 0.35f)
                    l.textColor = [fg colorWithAlphaComponent:0.9f];
            }
        }
    }
    for (UIView *s in v.subviews)
        tj_boostDetailHeaderCaptionLabels(s, fg, depth + 1);
}

void tj_fixDetailHeaderButtonLabels(UIView *v, UIColor *subtitleInk, int depth) {
    if (!v || depth > 22) return;
    if ([v isKindOfClass:[UILabel class]])
        tj_applyArtistSubtitleInkToLabel((UILabel *)v, subtitleInk);
    for (UIView *s in v.subviews)
        tj_fixDetailHeaderButtonLabels(s, subtitleInk, depth + 1);
}

UIColor *tj_buttonFillFromDominant(UIColor *dominant) {
    CGFloat h, s, b, a;
    if (![dominant getHue:&h saturation:&s brightness:&b alpha:&a])
        return [dominant colorWithAlphaComponent:0.9];
    CGFloat nb = MAX(0.1f, MIN(b * 0.48f, b - 0.06f));
    CGFloat ns = MIN(s * 1.06f, 1.f);
    return [UIColor colorWithHue:h saturation:ns brightness:nb alpha:0.94f];
}

UIColor *tj_listSurfaceFromDominant(UIColor *dominant) {
    CGFloat h, s, b, a;
    if (![dominant getHue:&h saturation:&s brightness:&b alpha:&a])
        return dominant;
    CGFloat ns = (s < 0.06f) ? s : MIN(MAX(s, 0.12f) * 1.38f + 0.06f, 1.f);
    CGFloat nb;
    if (b < 0.18f)
        nb = MIN(b * 1.42f, 0.52f);
    else if (b > 0.92f)
        nb = MAX(b * 0.94f, 0.76f);
    else
        nb = b * 0.99f;
    nb = MAX(0.24f, MIN(nb, 0.93f));
    return [UIColor colorWithHue:h saturation:ns brightness:nb alpha:1.f];
}

UIColor *tj_albumDetailForeground(UIColor *dominant, UIColor *listSurface) {
    (void)dominant;
    double lum = tj_colorLuminance(listSurface);
    if (lum < 0.68)
        return [UIColor whiteColor];
    if (lum > 0.86)
        return [UIColor blackColor];
    return colorIsLight(listSurface) ? [UIColor blackColor] : [UIColor whiteColor];
}

UIColor *tj_headerReadMusicDominantColor(UIView *detailHeader) {
    if (!detailHeader) return nil;
    id detailsView = tj_objectForKnownSelector(detailHeader, @selector(detailsView));
    id color = tj_objectForKnownSelector(detailsView, @selector(artworkProminentColor));
    return [color isKindOfClass:[UIColor class]] ? color : nil;
}

UIColor *tj_headerReadMusicTextColor(UIView *detailHeader) {
    if (!detailHeader) return nil;
    id color = tj_objectForKnownSelector(detailHeader, @selector(textColor));
    return [color isKindOfClass:[UIColor class]] ? color : nil;
}

void tj_tintRadiosityShadow(UIView *detailHeader, UIColor *dominant) {
    if (!detailHeader || !dominant) return;
    id shadow = tj_objectForKnownSelector(detailHeader, @selector(radiosityShadow));
    if ([shadow isKindOfClass:[UIView class]]) {
        UIView *sv = (UIView *)shadow;
        CGFloat h, s, b, a;
        if ([dominant getHue:&h saturation:&s brightness:&b alpha:&a]) {
            sv.backgroundColor = [UIColor colorWithHue:h
                                            saturation:MIN(s * 0.65f, 0.55f)
                                            brightness:MIN(b * 0.70f, 0.60f)
                                                 alpha:0.55f];
        }
    }
}

static void *kTJDetailsLabelsLastColorsKey = (void *)"tj.asso.detailsLabelsLastColors";

void tj_applyForegroundToDetailsViewLabels(UIView *detailHeader, UIColor *fg,
                                            UIColor *subtitleInk) {
    if (!detailHeader || !fg) return;

    NSArray<id> *lastColors = objc_getAssociatedObject(detailHeader, kTJDetailsLabelsLastColorsKey);
    id lastSubtitle = subtitleInk ?: [NSNull null];
    if (lastColors.count == 2 && [lastColors[0] isEqual:fg] && [lastColors[1] isEqual:lastSubtitle]) return;
    objc_setAssociatedObject(detailHeader, kTJDetailsLabelsLastColorsKey, @[fg, lastSubtitle], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    id detailsView = tj_objectForKnownSelector(detailHeader, @selector(detailsView));
    if (!detailsView) return;

    id titleField = tj_objectForKnownSelector(detailsView, @selector(titleField));
    if ([titleField isKindOfClass:[UIView class]])
        ((UIView *)titleField).tintColor = fg;

    id detailLabel = tj_objectForKnownSelector(detailsView, @selector(detailLabel));
    if ([detailLabel isKindOfClass:[UILabel class]])
        ((UILabel *)detailLabel).textColor = [fg colorWithAlphaComponent:0.78f];

    id descriptionLabel = tj_objectForKnownSelector(detailsView, @selector(descriptionLabel));
    if ([descriptionLabel isKindOfClass:[UILabel class]])
        ((UILabel *)descriptionLabel).textColor = [fg colorWithAlphaComponent:0.78f];

    id actionButton = tj_objectForKnownSelector(detailsView, @selector(actionButton));
    if ([actionButton isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)actionButton;
        UIColor *ink = subtitleInk ?: fg;
        [btn setTitleColor:ink forState:UIControlStateNormal];
        [btn setTitleColor:ink forState:UIControlStateHighlighted];
        [btn setTitleColor:ink forState:UIControlStateSelected];
        btn.tintColor = ink;
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *cfg = btn.configuration;
            if (cfg) {
                UIButtonConfiguration *c = [cfg copy];
                c.baseForegroundColor = ink;
                btn.configuration = c;
            }
        }
    }
}
