#import "TJEngine.h"
#import "TJInternal.h"
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

static __weak UIViewController *sTJThemeOwnerVC = nil;

UIViewController *tj_currentThemeOwnerVC(void) { return sTJThemeOwnerVC; }
void tj_setThemeOwnerVC(UIViewController *vc) { sTJThemeOwnerVC = vc; }

static UIImage *sLastTappedImage = nil;
static CFTimeInterval sLastTappedImageTime = 0;
static UIColor *sLastTappedDominantColorMemo = nil;

void tj_recordTappedArtworkImage(UIImage * _Nullable img) {
    sLastTappedImage = img;
    sLastTappedImageTime = CACurrentMediaTime();
    sLastTappedDominantColorMemo = nil;
}

UIColor * _Nullable tj_recentTappedDominantColor(void) {
    if (!sLastTappedImage) return nil;
    if (CACurrentMediaTime() - sLastTappedImageTime > 1.5) {
        sLastTappedImage = nil;
        sLastTappedDominantColorMemo = nil;
        return nil;
    }
    if (!sLastTappedDominantColorMemo) {
        CGFloat sat = prefFloat(@"albumSaturation", 1.52);
        CGFloat bri = prefFloat(@"albumBrightness", 0.75);
        sLastTappedDominantColorMemo = dominantColorFromImage(sLastTappedImage, sat, bri);
    }
    return sLastTappedDominantColorMemo;
}

UIImage * _Nullable tj_extractCatalogImageSync(id _Nullable component) {
    if (!component) return nil;
    UIImage *img = nil;
    if ([component respondsToSelector:@selector(imageWithSize:)]) {
        CGSize sz = CGSizeMake(200, 200);
        img = ((UIImage * (*)(id, SEL, CGSize)) objc_msgSend)(component, @selector(imageWithSize:), sz);
    }
    if (!img) {
        @try { img = [component valueForKey:@"image"]; } @catch (__unused id e) {}
    }
    if (!img) {
        @try { img = [component valueForKey:@"thumbnailImage"]; } @catch (__unused id e) {}
    }
    if (!img) {
        @try { img = [component valueForKey:@"artworkImage"]; } @catch (__unused id e) {}
    }
    if (!img) {
        id catalog = nil;
        @try { catalog = [component valueForKey:@"_internalImageCatalog"]; } @catch (__unused id e) {}
        if (!catalog) {
            @try { catalog = [component valueForKey:@"artworkCatalog"]; } @catch (__unused id e) {}
        }
        if (catalog) {
            if ([catalog respondsToSelector:@selector(bestImageFromDisk)]) {
                img = ((UIImage * (*)(id, SEL))objc_msgSend)(catalog, @selector(bestImageFromDisk));
            }
            if (!img && [catalog respondsToSelector:@selector(existingImageOfSize:)]) {
                CGSize sz = CGSizeMake(200, 200);
                img = ((UIImage * (*)(id, SEL, CGSize))objc_msgSend)(catalog, @selector(existingImageOfSize:), sz);
            }
        }
    }
    return img;
}

static UIImage * _Nullable tj_findSelectedArtworkInRootView(UIView *root) {
    if (!root) return nil;
    NSMutableArray *viewsToVisit = [NSMutableArray arrayWithObject:root];
    while (viewsToVisit.count > 0) {
        UIView *v = viewsToVisit.firstObject;
        [viewsToVisit removeObjectAtIndex:0];

        if ([v isKindOfClass:[UICollectionView class]]) {
            UICollectionView *cv = (UICollectionView *)v;
            for (NSIndexPath *ip in cv.indexPathsForSelectedItems) {
                UICollectionViewCell *cell = [cv cellForItemAtIndexPath:ip];
                if (cell) {
                    UIImage *img = firstImageInView(cell, 0);
                    if (img && img.size.width >= 40.f) return img;
                }
            }
            for (UICollectionViewCell *cell in cv.visibleCells) {
                if (cell.isHighlighted) {
                    UIImage *img = firstImageInView(cell, 0);
                    if (img && img.size.width >= 40.f) return img;
                }
            }
        } else if ([v isKindOfClass:[UITableView class]]) {
            UITableView *tv = (UITableView *)v;
            NSIndexPath *ip = tv.indexPathForSelectedRow;
            if (ip) {
                UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
                if (cell) {
                    UIImage *img = firstImageInView(cell, 0);
                    if (img && img.size.width >= 40.f) return img;
                }
            }
            for (UITableViewCell *cell in tv.visibleCells) {
                if (cell.isHighlighted) {
                    UIImage *img = firstImageInView(cell, 0);
                    if (img && img.size.width >= 40.f) return img;
                }
            }
        }

        for (UIView *sub in v.subviews) {
            [viewsToVisit addObject:sub];
        }
    }
    return nil;
}

static void tj_applyEarlyTintToVC(UIViewController *detailVC, UIColor *dom) {
    if (!detailVC || !dom) return;
    CGFloat domSat = 0;
    if ([dom getHue:NULL saturation:&domSat brightness:NULL alpha:NULL] && domSat < 0.06f) return;
    UIColor *listSurface = tj_listSurfaceFromDominant(dom);
    UIColor *fg = tj_albumDetailForeground(dom, listSurface);
    _albumDetailDominantColor = dom;
    _albumDetailForegroundColor = fg;
    _albumDetailListSurfaceColor = listSurface;
    tj_setThemeOwnerVC(detailVC);

    objc_setAssociatedObject(detailVC, kTJTintedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(detailVC, kTJCachedDominantKey, dom, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL jamShell = tj_colorLuminance(listSurface) < 0.74;
    detailVC.overrideUserInterfaceStyle =
        jamShell ? UIUserInterfaceStyleDark
                 : (colorIsLight(dom) ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark);

    if (detailVC.isViewLoaded && detailVC.view) {
        detailVC.view.backgroundColor = listSurface;
        tj_paintDetailBodyNow(detailVC, listSurface);
    }
}

void tj_prepareDetailVCTintBeforePush(UINavigationController *nav, UIViewController *detailVC) {
    if (!detailVC || !tj_surfaceVCIsAlbumDetailFamily(detailVC)) return;
    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;

    UIColor *dom = objc_getAssociatedObject(detailVC, kTJCachedDominantKey);
    if (!dom) {
        dom = tj_recentTappedDominantColor();
    }
    if (!dom && nav) {
        UIViewController *sourceVC = nav.topViewController;
        if (sourceVC && sourceVC.isViewLoaded) {
            UIImage *img = tj_findSelectedArtworkInRootView(sourceVC.view);
            if (img) {
                CGFloat sat = prefFloat(@"albumSaturation", 1.52);
                CGFloat bri = prefFloat(@"albumBrightness", 0.75);
                dom = dominantColorFromImage(img, sat, bri);
            }
        }
    }

    if (dom) {
        tj_applyEarlyTintToVC(detailVC, dom);
    }
}

void tj_prepareDetailVCTintOnWillAppear(UIViewController *detailVC) {
    if (!detailVC || !tj_surfaceVCIsAlbumDetailFamily(detailVC)) return;
    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;

    UIColor *dom = objc_getAssociatedObject(detailVC, kTJCachedDominantKey);
    if (!dom) {
        dom = tj_recentTappedDominantColor();
    }
    if (!dom) {
        UINavigationController *nav = detailVC.navigationController;
        if (nav) {
            UIViewController *prev = nil;
            NSArray *vcs = nav.viewControllers;
            UIViewController *onStack = detailVC;
            while (onStack && ![vcs containsObject:onStack]) onStack = onStack.parentViewController;
            NSUInteger idx = onStack ? [vcs indexOfObject:onStack] : NSNotFound;
            if (idx != NSNotFound && idx > 0) prev = vcs[idx - 1];
            if (prev && prev.isViewLoaded) {
                UIImage *img = tj_findSelectedArtworkInRootView(prev.view);
                if (img) {
                    CGFloat sat = prefFloat(@"albumSaturation", 1.52);
                    CGFloat bri = prefFloat(@"albumBrightness", 0.75);
                    dom = dominantColorFromImage(img, sat, bri);
                }
            }
        }
    }

    if (dom) {
        tj_applyEarlyTintToVC(detailVC, dom);
    } else {
        if (detailVC.isViewLoaded && detailVC.view) {
            detailVC.view.backgroundColor = [UIColor systemBackgroundColor];
        }
    }
}

void tj_detailSurfaceVCHandoffIfLeaving(UIViewController *vc) {
    if (!vc) return;
    if (!vc.isMovingFromParentViewController && !vc.isBeingDismissed) return;
    UINavigationController *nav = vc.navigationController;

    UIViewController *top = nav.topViewController;
    if (!top || top == vc) {
        UIViewController *pres = nav.presentingViewController ?: vc.presentingViewController;
        if ([pres isKindOfClass:[UINavigationController class]])
            pres = ((UINavigationController *)pres).topViewController;
        top = pres;
    }
    if (top && top != vc && tj_surfaceVCIsAlbumDetailFamily(top) &&
        top.isViewLoaded && top.view.window) {
        tj_detailSurfaceVCForceChromeTick(top);
    } else {
        UIViewController *owner = tj_currentThemeOwnerVC();
        if (!owner || owner == vc) {
            _albumDetailDominantColor = nil;
            _albumDetailForegroundColor = nil;
            _albumDetailListSurfaceColor = nil;
            tj_setThemeOwnerVC(nil);
        }
    }
    vc.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
}

UIView *tj_findDetailHeaderInView(UIView *root, int depth) {
    if (!root || depth > 28) return nil;
    NSString *c = NSStringFromClass(root.class);
    if ([c containsString:@"DetailHeader"])
        return root;
    for (UIView *s in root.subviews) {
        UIView *f = tj_findDetailHeaderInView(s, depth + 1);
        if (f) return f;
    }
    return nil;
}

UIView *tj_cachedDetailHeaderForVC(UIViewController *vc) {
    if (!vc || !vc.isViewLoaded || !vc.view) return nil;
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *ts = objc_getAssociatedObject(vc, kTJDetailHeaderStampKey);
    if (ts && now - ts.doubleValue < 1.0) {
        UIView *dh = objc_getAssociatedObject(vc, kTJDetailHeaderCacheKey);
        if (dh && dh.window && [dh isDescendantOfView:vc.view])
            return dh;
    }
    UIView *found = tj_findDetailHeaderInView(vc.view, 0);
    if (found) {
        objc_setAssociatedObject(vc, kTJDetailHeaderCacheKey, found, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(vc, kTJDetailHeaderStampKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return found;
}

void tj_detailSurfaceVCLayoutTickForced(UIViewController *vc) {
    if (!vc || !vc.view.window) return;
    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;
    [vc.view layoutIfNeeded];
    objc_setAssociatedObject(vc, kTJCachedCVsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *dh = tj_cachedDetailHeaderForVC(vc);
    if (dh && [dh respondsToSelector:@selector(tj_recolourFromArtwork)])
        [(id)dh performSelector:@selector(tj_recolourFromArtwork)];

}

void tj_detailSurfaceVCLayoutTick(UIViewController *vc) {
    if (!vc || !vc.view.window) return;
    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *last = objc_getAssociatedObject(vc, kTJVCListLayoutCoalesceKey);
    if (last && now - last.doubleValue < 0.055) return;
    objc_setAssociatedObject(vc, kTJVCListLayoutCoalesceKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIView *dh = tj_cachedDetailHeaderForVC(vc);
    if (dh && [dh respondsToSelector:@selector(tj_recolourFromArtwork)])
        [(id)dh performSelector:@selector(tj_recolourFromArtwork)];

}

void tj_detailSurfaceVCForceChromeTick(UIViewController *vc) {
    if (!vc) return;
    objc_setAssociatedObject(vc, kTJLastSurfaceApplyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(vc, kTJLastListPaintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    tj_detailSurfaceVCLayoutTickForced(vc);
}

void tj_listScrollSurfaceDidAttach(UIScrollView *sv) {
    if (!sv || !sv.window) return;
    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;
    if (tj_viewHasParallaxAncestor((UIView *)sv)) return;
    if (!tj_cellOnAlbumOrPlaylistDetail((UIView *)sv)) return;
    if ([sv isKindOfClass:[UICollectionView class]] &&
        !tj_collectionViewIsMainVerticalList((UICollectionView *)sv))
        return;
    UIColor *fill = tj_rowFillColor();
    if (fill) {
        UIColor *fg = _albumDetailForegroundColor ?: [UIColor whiteColor];
        tj_paintListScrollSurface(sv, fill, fg);
    } else {

    }

    UIViewController *svc = tj_albumSurfaceViewController((UIView *)sv);
    if (svc)
        objc_setAssociatedObject(svc, kTJCachedCVsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void clearSwiftUIHostingSurfaces(UIView *v, int depth) {
    if (!v || depth > 18) return;
    NSString *cls = NSStringFromClass(v.class);
    if ([cls containsString:@"UIHosting"] ||
        [cls containsString:@"HostingContent"] ||
        [cls containsString:@"SwiftUI"]) {
        v.backgroundColor = [UIColor clearColor];
        v.opaque = NO;
    } else if ([cls containsString:@"UIListContent"]) {
        UIColor *f = tj_rowFillColor();
        if (f) {
            v.backgroundColor = f;
            v.opaque = YES;
        } else {
            v.backgroundColor = [UIColor clearColor];
            v.opaque = NO;
        }
    }
    for (UIView *sub in v.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"ParallaxView"])
            continue;
        clearSwiftUIHostingSurfaces(sub, depth + 1);
    }
}

static void tj_fixLabelContrastForSurface(UILabel *l, UIColor *fg) {
    if (!l || !fg) return;
    UIColor *surface = _albumDetailListSurfaceColor;
    if (!surface) return;
    UIColor *t = l.textColor;
    if (!t) {
        l.textColor = fg;
        return;
    }
    CGFloat tr = 0.f, tg = 0.f, tb = 0.f, ta = 1.f;
    BOOL rgbaOK = tj_safeColorRGBA(t, &tr, &tg, &tb, &ta);
    CGFloat sat = 0.f;
    BOOL hsbOK = [t getHue:NULL saturation:&sat brightness:NULL alpha:NULL];
    if (!rgbaOK && !hsbOK) return;
    if (hsbOK && sat > 0.35f) return;
    if (rgbaOK && ta < 0.4f) {
        l.textColor = [fg colorWithAlphaComponent:MAX(0.55f, ta)];
        return;
    }
    double lumT = rgbaOK ? (0.299 * (double)tr + 0.587 * (double)tg + 0.114 * (double)tb)
                         : tj_colorLuminance(t);
    double lumS = tj_colorLuminance(surface);
    if (fabs(lumT - lumS) < 0.22) {
        CGFloat a = (l.font.pointSize < 14.f) ? 0.78f : 1.f;
        l.textColor = [fg colorWithAlphaComponent:a];
    }
}

static void tj_cellScrollInWalk(UIView *v, int depth, UIColor *fill, UIColor *fg) {
    if (!v || depth > 14) return;
    NSString *cls = NSStringFromClass(v.class);
    if ([cls containsString:@"SymbolButton"]) {
        if (fg) {
            v.backgroundColor = [UIColor clearColor];
            v.tintColor = fg;
            if ([v isKindOfClass:[UIButton class]]) {
                UIButton *b = (UIButton *)v;
                [b setTitleColor:fg forState:UIControlStateNormal];
                [b setTitleColor:fg forState:UIControlStateHighlighted];
                b.imageView.backgroundColor = [UIColor clearColor];
                b.imageView.opaque = NO;
                if (b.titleLabel) b.titleLabel.backgroundColor = [UIColor clearColor];
                if (@available(iOS 15.0, *)) {
                    UIButtonConfiguration *cfg = b.configuration;
                    if (cfg) {
                        UIButtonConfiguration *c = [cfg copy];
                        c.baseForegroundColor = fg;
                        b.configuration = c;
                    }
                }
            }
            for (UIView *s in v.subviews) {
                if ([s isKindOfClass:[UIImageView class]])
                    ((UIImageView *)s).tintColor = fg;
                if ([s isKindOfClass:[UILabel class]])
                    ((UILabel *)s).textColor = fg;
            }
        }
        return;
    }
    if ([cls containsString:@"UIHosting"] || [cls containsString:@"HostingContent"] ||
        [cls containsString:@"SwiftUI"]) {
        v.backgroundColor = [UIColor clearColor];
        v.opaque = NO;
    } else if ([cls containsString:@"UIListContent"]) {
        v.backgroundColor = fill;
        v.opaque = YES;
    }
    if ([v isKindOfClass:[UILabel class]] && ![cls containsString:@"ButtonLabel"])
        tj_fixLabelContrastForSurface((UILabel *)v, fg);
    for (UIView *sub in v.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"ParallaxView"])
            continue;
        tj_cellScrollInWalk(sub, depth + 1, fill, fg);
    }
}

void tj_fixCellContentForScroll(UIView *cell) {
    if (!cell) return;
    UIColor *fill = tj_rowFillColor();
    if (!fill) return;
    tj_cellScrollInWalk(cell, 0, fill, _albumDetailForegroundColor);
}

void fixLabelContrastInView(UIView *v, UIColor *dominant, UIColor *fg, int depth,
                                   UIColor *headerSubtitleInk) {
    (void)dominant;
    if (!v || depth > 16) return;
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        NSString *lcn = NSStringFromClass(l.class);
        if ([lcn containsString:@"ButtonLabel"]) {
            UIColor *ink = headerSubtitleInk;
            if (!ink && _albumDetailListSurfaceColor)
                ink = tj_detailHeaderSubtitleOnListSurface(_albumDetailListSurfaceColor);
            tj_applyArtistSubtitleInkToLabel(l, ink);
        } else {
            tj_fixLabelContrastForSurface(l, fg);
        }
    }
    for (UIView *sub in v.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"ParallaxView"])
            continue;
        fixLabelContrastInView(sub, dominant, fg, depth + 1, headerSubtitleInk);
    }
}

static void *kTJPrimaryActionRestorerKey = (void *)"tj.asso.primaryActionRestorer";

static id tj_detailHeaderProperty(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static UIConfigurationColorTransformer tj_constantColorTransformer(UIColor *color) {
    return ^UIColor *(UIColor *input) {
        (void)input;
        return color;
    };
}

static void tj_configurePrimaryActionButton(UIButton *button, UIColor *fill, UIColor *ink);
static void *kTJPrimaryActionLastFillInkKey = (void *)"tj.asso.primaryActionLastFillInk";

@interface TJPrimaryActionStateRestorer : NSObject
@property(nonatomic, weak) UIButton *button;
@property(nonatomic, strong) UIColor *fill;
@property(nonatomic, strong) UIColor *ink;
@end

@implementation TJPrimaryActionStateRestorer

- (void)restoreNormalAppearance:(__unused id)sender {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        TJPrimaryActionStateRestorer *selfRef = weakSelf;
        if (selfRef.button) {
            objc_setAssociatedObject(selfRef.button, kTJPrimaryActionLastFillInkKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            tj_configurePrimaryActionButton(selfRef.button, selfRef.fill, selfRef.ink);
        }
    });
}

@end

static void tj_configurePrimaryActionButton(UIButton *button, UIColor *fill, UIColor *ink) {
    if (!button || !fill || !ink) return;

    NSArray<UIColor *> *lastFillInk = objc_getAssociatedObject(button, kTJPrimaryActionLastFillInkKey);
    if (lastFillInk.count == 2 && [lastFillInk[0] isEqual:fill] && [lastFillInk[1] isEqual:ink]) return;
    objc_setAssociatedObject(button, kTJPrimaryActionLastFillInkKey, @[fill, ink], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGFloat effW = MAX(CGRectGetWidth(button.bounds), CGRectGetWidth(button.frame));
    CGFloat effH = MAX(CGRectGetHeight(button.bounds), CGRectGetHeight(button.frame));
    CGFloat side = MIN(MAX(effW, 1.f), MAX(effH, 1.f));
    CGFloat radius = MIN(14.f, side * 0.34f);
    button.backgroundColor = [UIColor clearColor];
    button.clipsToBounds = YES;
    button.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) button.layer.cornerCurve = kCACornerCurveContinuous;
    button.tintColor = ink;

    [button setTitleColor:ink forState:UIControlStateNormal];
    [button setTitleColor:ink forState:UIControlStateHighlighted];
    [button setTitleColor:ink forState:UIControlStateSelected];
    [button setTitleColor:ink forState:UIControlStateDisabled];

    if (button.titleLabel) {
        button.titleLabel.textColor = ink;
        if (button.titleLabel.attributedText.length > 0) {
            NSMutableAttributedString *attr = [button.titleLabel.attributedText mutableCopy];
            [attr addAttribute:NSForegroundColorAttributeName value:ink range:NSMakeRange(0, attr.length)];
            button.titleLabel.attributedText = attr;
        }
    }
    if (button.imageView) {
        button.imageView.tintColor = ink;
        if (button.imageView.image) {
            button.imageView.image = [button.imageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    }

    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *configuration = button.configuration;
        if (configuration) {
            UIButtonConfiguration *copy = [configuration copy];
            copy.baseForegroundColor = ink;

            copy.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
                NSMutableDictionary *dict = [incoming mutableCopy] ?: [NSMutableDictionary dictionary];
                dict[NSForegroundColorAttributeName] = ink;
                return dict;
            };

            copy.imageColorTransformer = ^UIColor *(UIColor *input) {
                (void)input;
                return ink;
            };

            if (copy.attributedTitle) {
                NSMutableAttributedString *attr = [copy.attributedTitle mutableCopy];
                [attr addAttribute:NSForegroundColorAttributeName value:ink range:NSMakeRange(0, attr.length)];
                copy.attributedTitle = attr;
            }

            if (copy.image) {
                copy.image = [copy.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            }

            UIBackgroundConfiguration *background = [configuration.background copy] ?:
                                                 [UIBackgroundConfiguration clearConfiguration];
            background.backgroundColor = fill;
            background.backgroundColorTransformer = tj_constantColorTransformer(fill);
            background.cornerRadius = radius;
            copy.background = background;
            button.configuration = copy;

            button.configurationUpdateHandler = ^(UIButton *btn) {
                UIButtonConfiguration *c = [btn.configuration copy];
                if (c) {
                    c.baseForegroundColor = ink;
                    c.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *incoming) {
                        NSMutableDictionary *d = [incoming mutableCopy] ?: [NSMutableDictionary dictionary];
                        d[NSForegroundColorAttributeName] = ink;
                        return d;
                    };
                    c.imageColorTransformer = ^UIColor *(UIColor *input) {
                        (void)input;
                        return ink;
                    };
                    if (c.attributedTitle) {
                        NSMutableAttributedString *a = [c.attributedTitle mutableCopy];
                        [a addAttribute:NSForegroundColorAttributeName value:ink range:NSMakeRange(0, a.length)];
                        c.attributedTitle = a;
                    }
                    UIBackgroundConfiguration *bg = [c.background copy] ?: [UIBackgroundConfiguration clearConfiguration];
                    bg.backgroundColor = fill;
                    bg.backgroundColorTransformer = tj_constantColorTransformer(fill);
                    bg.cornerRadius = radius;
                    c.background = bg;
                    btn.configuration = c;
                }
            };
        } else {
            button.backgroundColor = fill;
        }
    }

    TJPrimaryActionStateRestorer *restorer = objc_getAssociatedObject(button, kTJPrimaryActionRestorerKey);
    if (!restorer) {
        restorer = [TJPrimaryActionStateRestorer new];
        restorer.button = button;
        objc_setAssociatedObject(button, kTJPrimaryActionRestorerKey, restorer,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button addTarget:restorer action:@selector(restoreNormalAppearance:)
          forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside |
                           UIControlEventTouchCancel];
    }
    restorer.fill = fill;
    restorer.ink = ink;
}

static BOOL tj_isPrimaryDetailActionView(UIView *view) {
    CGFloat width = MAX(CGRectGetWidth(view.bounds), CGRectGetWidth(view.frame));
    CGFloat height = MAX(CGRectGetHeight(view.bounds), CGRectGetHeight(view.frame));
    if (width < 96.f || height < 36.f) return NO;
    return [view isKindOfClass:[UIButton class]] ||
           [NSStringFromClass(view.class) containsString:@"SymbolButton"];
}

static void tj_tintPrimaryActionContents(UIView *view, UIColor *fill, UIColor *ink, int depth) {
    if (!view || !ink || depth > 8) return;

    if ([view isKindOfClass:[UIButton class]]) {
        tj_configurePrimaryActionButton((UIButton *)view, fill, ink);
    }

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        label.textColor = ink;
        if (label.attributedText.length > 0) {
            NSMutableAttributedString *attr = [label.attributedText mutableCopy];
            [attr addAttribute:NSForegroundColorAttributeName value:ink range:NSMakeRange(0, attr.length)];
            label.attributedText = attr;
        }
    } else if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *iv = (UIImageView *)view;
        iv.tintColor = ink;
        if (iv.image) {
            iv.image = [iv.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    }

    if ([view respondsToSelector:@selector(setTintColor:)]) {
        view.tintColor = ink;
    }

    for (UIView *subview in view.subviews)
        tj_tintPrimaryActionContents(subview, fill, ink, depth + 1);
}

static void tj_configurePrimaryActionView(UIView *view, UIColor *fill, UIColor *ink) {
    if ([view isKindOfClass:[UIButton class]]) {
        tj_configurePrimaryActionButton((UIButton *)view, fill, ink);
    } else {
        CGFloat effW = MAX(CGRectGetWidth(view.bounds), CGRectGetWidth(view.frame));
        CGFloat effH = MAX(CGRectGetHeight(view.bounds), CGRectGetHeight(view.frame));
        CGFloat side = MIN(MAX(effW, 1.f), MAX(effH, 1.f));
        view.backgroundColor = fill;
        view.clipsToBounds = YES;
        view.layer.cornerRadius = MIN(14.f, side * 0.34f);
        if (@available(iOS 13.0, *)) view.layer.cornerCurve = kCACornerCurveContinuous;
    }
    tj_tintPrimaryActionContents(view, fill, ink, 0);
}

static void tj_stylePrimaryActionButtonsInView(UIView *view, UIColor *fill, UIColor *ink, int depth) {
    if (!view || depth > 8) return;
    if (tj_isPrimaryDetailActionView(view)) {
        tj_configurePrimaryActionView(view, fill, ink);
        return;
    }
    for (UIView *subview in view.subviews)
        tj_stylePrimaryActionButtonsInView(subview, fill, ink, depth + 1);
}

void tj_styleDetailHeaderPrimaryActions(UIView *detailHeader, UIColor *dominant,
                                        UIColor *foreground, UIColor *listSurface) {
    if (!detailHeader || !dominant || !foreground || !listSurface) return;
    id detailsView = tj_detailHeaderProperty(detailHeader, @selector(detailsView));
    UIView *actionsContainer = tj_detailHeaderProperty(detailsView, @selector(actionsContainerView));
    UIView *targetContainer = [actionsContainer isKindOfClass:[UIView class]] ? actionsContainer : (UIView *)detailsView;
    if (![targetContainer isKindOfClass:[UIView class]]) targetContainer = detailHeader;

    BOOL darkSurface = tj_colorLuminance(listSurface) < 0.74;
    UIColor *fill = [tj_buttonFillFromDominant(dominant)
                     colorWithAlphaComponent:darkSurface ? 0.48f : 0.42f];
    UIColor *actionInk = [UIColor whiteColor];
    if (fill && tj_colorLuminance(fill) >= 0.75) {
        actionInk = [UIColor colorWithWhite:0.10 alpha:1.f];
    }
    tj_stylePrimaryActionButtonsInView(targetContainer, fill, actionInk, 0);
}

void tj_paintListScrollSurfaceLite(UIScrollView *sv, UIColor *listSurface) {
    if (!sv || !listSurface) return;
    sv.backgroundColor = listSurface;
    UIView *p = sv.superview;
    for (int i = 0; p && i < 8; i++, p = p.superview) {
        NSString *pc = NSStringFromClass(p.class);
        if ([pc containsString:@"TintColorObserving"]) {
            if (!tj_subtreeContainsParallaxView(p, 0))
                p.backgroundColor = listSurface;
        }
    }
    if ([sv isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)sv;
        if (cv.backgroundView) {
            cv.backgroundView.hidden = YES;
            cv.backgroundView.alpha = 0.0f;
            cv.backgroundView = nil;
        }
        for (UICollectionViewCell *cell in cv.visibleCells) {
            if (!tj_isAlbumTrackRowCell(cell)) {
                tj_clearShelfCardCell(cell);
                continue;
            }
            cell.backgroundColor = listSurface;
            cell.contentView.backgroundColor = listSurface;
        }
        for (UIView *sub in cv.subviews) {
            if (tj_viewHasParallaxAncestor(sub)) continue;
            if ([sub isKindOfClass:[UICollectionReusableView class]] &&
                ![sub isKindOfClass:[UICollectionViewCell class]]) {
                if (![NSStringFromClass(sub.class) containsString:@"DetailHeader"]) {
                    sub.backgroundColor = [UIColor clearColor];
                    sub.opaque = NO;
                }
            } else if ([sub isKindOfClass:[UIScrollView class]] && sub != cv) {
                sub.backgroundColor = [UIColor clearColor];
                sub.opaque = NO;
            }
        }
    } else if ([sv isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)sv;
        tv.backgroundView = nil;
        for (UITableViewCell *cell in tv.visibleCells) {
            cell.backgroundColor = listSurface;
            cell.contentView.backgroundColor = listSurface;
        }
    }
}

void tj_listScrollSurfaceLayoutEnsure(UIScrollView *sv) {
    if (!sv || !sv.window) return;
    UIColor *fill = tj_rowFillColor();
    if (fill) {
        UIViewController *owner = tj_currentThemeOwnerVC();
        if (owner && owner.isViewLoaded && owner.view && ![sv isDescendantOfView:owner.view]) return;
        if (tj_viewHasParallaxAncestor((UIView *)sv)) return;
        BOOL isHorizontalCV = [sv isKindOfClass:[UICollectionView class]] &&
                              tj_cvContentLooksHorizontallyScrolled((UICollectionView *)sv);
        if (isHorizontalCV) {
            sv.backgroundColor = [UIColor clearColor];
            sv.opaque = NO;
        } else if (![sv.backgroundColor isEqual:fill]) {
            sv.backgroundColor = fill;
        }
        if ([sv isKindOfClass:[UICollectionView class]]) {
            UICollectionView *cv = (UICollectionView *)sv;
            if (cv.backgroundView) {
                cv.backgroundView.hidden = YES;
                cv.backgroundView.alpha = 0.0f;
                cv.backgroundView = nil;
            }
            for (UIView *sub in cv.subviews) {
                if (tj_viewHasParallaxAncestor(sub)) continue;
                if ([sub isKindOfClass:[UIScrollView class]]) {
                    sub.backgroundColor = [UIColor clearColor];
                    sub.opaque = NO;
                    if ([sub isKindOfClass:[UICollectionView class]]) {
                        UICollectionView *subCv = (UICollectionView *)sub;
                        subCv.backgroundColor = [UIColor clearColor];
                        subCv.opaque = NO;
                        if (subCv.backgroundView) {
                            subCv.backgroundView.hidden = YES;
                            subCv.backgroundView.alpha = 0.0f;
                            subCv.backgroundView = nil;
                        }
                    }
                    for (UIView *c in sub.subviews) {
                        NSString *cCls = NSStringFromClass(c.class);
                        if ([cCls containsString:@"_UISystemBackgroundView"] ||
                            [cCls containsString:@"SectionBackground"] ||
                            [cCls containsString:@"DecorationView"]) {
                            c.backgroundColor = [UIColor clearColor];
                            c.opaque = NO;
                        }
                    }
                } else if ([sub isKindOfClass:[UICollectionReusableView class]] &&
                           ![sub isKindOfClass:[UICollectionViewCell class]]) {
                    if (![NSStringFromClass(sub.class) containsString:@"DetailHeader"]) {
                        sub.backgroundColor = [UIColor clearColor];
                        sub.opaque = NO;
                        for (UIView *c in sub.subviews) {
                            NSString *cCls = NSStringFromClass(c.class);
                            if ([cCls containsString:@"_UISystemBackgroundView"] ||
                                [cCls containsString:@"SectionBackground"] ||
                                [cCls containsString:@"DecorationView"]) {
                                c.backgroundColor = [UIColor clearColor];
                                c.opaque = NO;
                            }
                        }
                    }
                }
            }
        }
        return;
    }

}

static void tj_paintBodyTreeNow(UIView *v, UIColor *color, int depth) {
    if (!v || depth > 18) return;
    NSString *cls = NSStringFromClass(v.class);
    if ([cls containsString:@"ParallaxView"]) return;
    if ([v isKindOfClass:[UICollectionView class]]) {
        if (!tj_cvContentLooksHorizontallyScrolled((UICollectionView *)v)) {
            v.backgroundColor = color;
            UICollectionView *cv = (UICollectionView *)v;
            if (cv.backgroundView) {
                cv.backgroundView.hidden = YES;
                cv.backgroundView.alpha = 0.0f;
                cv.backgroundView = nil;
            }
        }
    } else if ([v isKindOfClass:[UITableView class]]) {
        v.backgroundColor = color;
        ((UITableView *)v).backgroundView = nil;
    } else if ([cls containsString:@"TintColorObserving"] ||
               [cls containsString:@"VerticalStack"] ||
               [cls containsString:@"AlbumDetail"] ||
               [cls containsString:@"ContainerDetail"] ||
               [cls containsString:@"PlaylistDetail"] ||
               [cls containsString:@"JSVertical"]) {
        if (!tj_subtreeContainsParallaxView(v, 0))
            v.backgroundColor = color;
    }
    for (UIView *s in v.subviews)
        tj_paintBodyTreeNow(s, color, depth + 1);
}

void tj_paintDetailBodyNow(UIViewController *vc, UIColor *listSurface) {
    if (!vc || !vc.isViewLoaded || !vc.view || !listSurface) return;
    vc.view.backgroundColor = listSurface;
    tj_paintBodyTreeNow(vc.view, listSurface, 0);
}

void tj_paintListScrollSurface(UIScrollView *sv, UIColor *listSurface, UIColor *fg) {
    if (!sv || !listSurface) return;
    sv.backgroundColor = listSurface;
    UIView *p = sv.superview;
    for (int i = 0; p && i < 8; i++, p = p.superview) {
        NSString *pc = NSStringFromClass(p.class);
        if ([pc containsString:@"TintColorObserving"]) {
            if (!tj_subtreeContainsParallaxView(p, 0))
                p.backgroundColor = listSurface;
        }
    }
    if ([sv isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)sv;
        if (cv.backgroundView) {
            cv.backgroundView.hidden = YES;
            cv.backgroundView.alpha = 0.0f;
            cv.backgroundView = nil;
        }
        for (UICollectionViewCell *cell in cv.visibleCells) {
            if (!tj_isAlbumTrackRowCell(cell)) {
                tj_clearShelfCardCell(cell);
                continue;
            }
            cell.backgroundColor = listSurface;
            cell.contentView.backgroundColor = listSurface;
            applyCellTint(cell, 0);
            flattenListRowOpaqueBases(cell, 0);
            if (fg) tj_tintListRowInteractables(cell, fg, 0);
        }
        for (UIView *sub in cv.subviews) {
            if (tj_viewHasParallaxAncestor(sub)) continue;
            if ([sub isKindOfClass:[UICollectionReusableView class]] &&
                ![sub isKindOfClass:[UICollectionViewCell class]]) {
                if (![NSStringFromClass(sub.class) containsString:@"DetailHeader"]) {
                    sub.backgroundColor = [UIColor clearColor];
                    sub.opaque = NO;
                    for (UIView *c in sub.subviews) {
                        NSString *cCls = NSStringFromClass(c.class);
                        if ([cCls containsString:@"_UISystemBackgroundView"] ||
                            [cCls containsString:@"SectionBackground"] ||
                            [cCls containsString:@"DecorationView"]) {
                            c.backgroundColor = [UIColor clearColor];
                            c.opaque = NO;
                        }
                    }
                }
            } else if ([sub isKindOfClass:[UIScrollView class]] && sub != cv) {
                sub.backgroundColor = [UIColor clearColor];
                sub.opaque = NO;
            }
        }
    } else if ([sv isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)sv;
        tv.backgroundView = nil;
        for (UITableViewCell *cell in tv.visibleCells) {
            cell.backgroundColor = listSurface;
            cell.contentView.backgroundColor = listSurface;
            applyCellTint(cell, 0);
            flattenListRowOpaqueBases(cell, 0);
            if (fg) tj_tintListRowInteractables(cell, fg, 0);
        }
    }
}

void tj_walkFallbackListCandidates(UIView *v, int depth, CGFloat winW, UICollectionView **outBest,
                                        CGFloat *outScore) {
    if (!v || depth > 22 || !outBest || !outScore) return;
    if ([NSStringFromClass(v.class) containsString:@"ParallaxView"]) return;
    if ([v isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)v;
        if (!tj_viewHasParallaxAncestor(cv) && !tj_cvContentLooksHorizontallyScrolled(cv)) {
            CGFloat bw = CGRectGetWidth(cv.bounds);
            CGFloat eh = MAX(CGRectGetHeight(cv.bounds), CGRectGetHeight(cv.frame));
            if (bw >= winW * 0.78f && eh >= 160.f) {
                UICollectionViewLayout *lay = cv.collectionViewLayout;
                CGSize cs = lay ? lay.collectionViewContentSize : CGSizeZero;
                if (!(cs.width > 24.f && cs.height > 24.f && cs.width > cs.height * 1.08f)) {
                    CGFloat score = eh * 1e6f + MIN(cs.height, 500000.f);
                    if (score > *outScore) {
                        *outScore = score;
                        *outBest = cv;
                    }
                }
            }
        }
    }
    for (UIView *s in v.subviews)
        tj_walkFallbackListCandidates(s, depth + 1, winW, outBest, outScore);
}

void tj_fallbackPaintBestListCollectionView(UIViewController *vc, UIColor *listSurface, UIColor *fg,
                                                  BOOL useParallaxLiteList) {
    if (!vc || !vc.view || !listSurface) return;
    if (cachedListScrollViewsForVC(vc).count > 0) return;
    UIWindow *win = vc.view.window;
    CGFloat winW = win ? CGRectGetWidth(win.bounds) : 390.f;
    UICollectionView *best = nil;
    CGFloat bestScore = -1.f;
    tj_walkFallbackListCandidates(vc.view, 0, winW, &best, &bestScore);
    if (!best) return;
    if (useParallaxLiteList)
        tj_paintListScrollSurfaceLite((UIScrollView *)best, listSurface);
    else
        tj_paintListScrollSurface((UIScrollView *)best, listSurface, fg);
}

void tj_maybeScheduleListBootstrapRetries(UIViewController *vc) {
    if (!vc || !vc.view.window) return;
    if (cachedListScrollViewsForVC(vc).count > 0) return;
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *lm = objc_getAssociatedObject(vc, kTJListBootstrapScheduledKey);
    if (lm && now - lm.doubleValue < 0.16) return;
    objc_setAssociatedObject(vc, kTJListBootstrapScheduledKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIViewController *wvc = vc;
    for (NSNumber *d in @[@0.0, @0.055, @0.11]) {
        CGFloat delay = d.doubleValue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *s = wvc;
            if (!s || !s.view.window) return;
            if (cachedListScrollViewsForVC(s).count > 0) return;
            objc_setAssociatedObject(s, kTJCachedCVsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            tj_detailSurfaceVCLayoutTickForced(s);
        });
    }
}

void applyAlbumSurfaceTint(UIViewController *vc, UIColor *dominant, UIColor *fg) {
    if (!vc || !dominant) return;

    NSNumber *depthN = objc_getAssociatedObject(vc, kTJSurfaceTintDepthKey);
    int depth = depthN ? depthN.intValue : 0;
    if (depth > 0)
        return;
    objc_setAssociatedObject(vc, kTJSurfaceTintDepthKey, @(depth + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    @try {

    UIColor *listSurface = tj_listSurfaceFromDominant(dominant);
    _albumDetailListSurfaceColor = listSurface;
    objc_setAssociatedObject(vc, kTJTintedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL jamShell = tj_colorLuminance(listSurface) < 0.74;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL pageParallax = tj_subtreeContainsParallaxView(vc.view, 0);

    CFTimeInterval fullChromeGap = pageParallax ? 0.56 : 0.2;
    NSNumber *lastFullN = objc_getAssociatedObject(vc, kTJLastSurfaceApplyKey);
    BOOL doFullChrome = !lastFullN || (now - lastFullN.doubleValue >= fullChromeGap);

    if (!doFullChrome && vc.transitionCoordinator)
        doFullChrome = YES;
    if (doFullChrome)
        objc_setAssociatedObject(vc, kTJLastSurfaceApplyKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL runListPaint = doFullChrome;
    if (!pageParallax && !runListPaint) {
        static const CGFloat kNonParallaxListPaintHz = 30.f;
        NSNumber *lp = objc_getAssociatedObject(vc, kTJLastListPaintKey);
        if (!lp || (now - lp.doubleValue >= (1.0 / kNonParallaxListPaintHz))) {
            runListPaint = YES;
        }
    } else if (pageParallax && !runListPaint) {

        static const CGFloat kParallaxListLiteHz = 8.f;
        NSNumber *lp = objc_getAssociatedObject(vc, kTJLastListPaintKey);
        if (!lp || (now - lp.doubleValue >= (1.0 / kParallaxListLiteHz)))
            runListPaint = YES;
    }
    if (runListPaint)
        objc_setAssociatedObject(vc, kTJLastListPaintKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    BOOL runHeavyListCells = NO;
    if (pageParallax && doFullChrome && runListPaint) {
        static const CFTimeInterval kParallaxHeavyListMin = 1.2;
        NSNumber *lh = objc_getAssociatedObject(vc, kTJLastHeavyListPaintKey);
        if (!lh || (now - lh.doubleValue >= kParallaxHeavyListMin)) {
            runHeavyListCells = YES;
            objc_setAssociatedObject(vc, kTJLastHeavyListPaintKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    BOOL runTintTreePass = doFullChrome;
    if (pageParallax && doFullChrome) {
        if (runHeavyListCells) {
            objc_setAssociatedObject(vc, kTJLastParallaxTreePassKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else {
            static const CFTimeInterval kParallaxTintTreeMin = 0.95;
            NSNumber *ltr = objc_getAssociatedObject(vc, kTJLastParallaxTreePassKey);
            if (ltr && (now - ltr.doubleValue < kParallaxTintTreeMin))
                runTintTreePass = NO;
            else
                objc_setAssociatedObject(vc, kTJLastParallaxTreePassKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    if (pageParallax && !doFullChrome && !runListPaint)
        return;

    vc.overrideUserInterfaceStyle =
        jamShell ? UIUserInterfaceStyleDark
                 : (colorIsLight(dominant) ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark);
    if (![vc.view.backgroundColor isEqual:listSurface]) {
        vc.view.backgroundColor = listSurface;
    }

    if (runTintTreePass)
        tintVCViewTree(vc.view, listSurface, 0);

    UIView *dhEarly = nil;
    UIColor *headerSubtitleInk = fg;
    if (doFullChrome) {
        dhEarly = tj_cachedDetailHeaderForVC(vc);
        headerSubtitleInk = tj_detailHeaderSubtitleColorFromTextViewReference(dhEarly);
        if (!headerSubtitleInk)
            headerSubtitleInk = fg;
        if (!headerSubtitleInk)
            headerSubtitleInk = tj_detailHeaderSubtitleOnListSurface(listSurface);
    }

    if (runTintTreePass)
        fixLabelContrastInView(vc.view, dominant, fg, 0, headerSubtitleInk);

    if (runListPaint) {
        BOOL parallaxLiteList = pageParallax && !runHeavyListCells;
        for (UIScrollView *sv in cachedListScrollViewsForVC(vc)) {
            if ([sv isKindOfClass:[UICollectionView class]] &&
                !tj_collectionViewIsMainVerticalList((UICollectionView *)sv))
                continue;
            if (parallaxLiteList)
                tj_paintListScrollSurfaceLite(sv, listSurface);
            else
                tj_paintListScrollSurface(sv, listSurface, fg);
        }

        tj_fallbackPaintBestListCollectionView(vc, listSurface, fg, parallaxLiteList);
    }

    if (runTintTreePass)
        clearSwiftUIHostingSurfaces(vc.view, 0);

    if (doFullChrome) {
        UIView *detailHeader = dhEarly ?: tj_cachedDetailHeaderForVC(vc);
        if (detailHeader && dominant && fg) {
            tj_fixDetailHeaderButtonLabels(detailHeader, headerSubtitleInk, 0);
            tj_boostDetailHeaderCaptionLabels(detailHeader, fg, 0);

            tj_applyForegroundToDetailsViewLabels(detailHeader, fg, headerSubtitleInk);

            tj_tintRadiosityShadow(detailHeader, dominant);
            tj_styleDetailHeaderPrimaryActions(detailHeader, dominant, fg, listSurface);
        }
    }

    } @catch (__unused id e) {
    } @finally {
        objc_setAssociatedObject(vc, kTJSurfaceTintDepthKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
