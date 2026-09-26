#import "TJEngine.h"
#import "TJInternal.h"
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

UIColor *tj_rowFillColor(void) {
    if (!tj_currentThemeOwnerVC()) return nil;
    if (_albumDetailListSurfaceColor) return _albumDetailListSurfaceColor;
    if (_albumDetailDominantColor) return tj_listSurfaceFromDominant(_albumDetailDominantColor);
    return nil;
}

static BOOL tj_isTrackRowActionControl(UIView *v) {
    for (UIView *x = v; x; x = x.superview) {
        NSString *c = NSStringFromClass(x.class);
        if ([c containsString:@"SongCell"] || [c containsString:@"DetailCell"] ||
            [c containsString:@"UITableViewCellContentView"] ||
            [c containsString:@"UICollectionViewListCell"])
            return YES;
    }
    return NO;
}

BOOL tj_isAlbumTrackRowCell(UIView *v) {
    if (!v) return NO;
    if ([v isKindOfClass:[UICollectionViewListCell class]]) return YES;
    if ([v isKindOfClass:[UITableViewCell class]]) return YES;
    NSString *cls = NSStringFromClass(v.class);
    if ([cls containsString:@"SongCell"] ||
        [cls containsString:@"DetailCell"] ||
        [cls containsString:@"ListCell"] ||
        [cls containsString:@"TracklistCell"]) {
        return YES;
    }
    return NO;
}

static const char * const kTJCardClearedKey = "kTJCardClearedKey";

void tj_cardCellPrepareForReuse(UICollectionViewCell *cell) {
    if (!cell) return;
    objc_setAssociatedObject(cell, kTJCardClearedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void tj_clearShelfCardCell(UICollectionViewCell *cell) {
    if (!cell) return;
    if (tj_viewHasParallaxAncestor(cell)) return;

    if (objc_getAssociatedObject(cell, kTJCardClearedKey)) return;
    objc_setAssociatedObject(cell, kTJCardClearedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    cell.backgroundColor = [UIColor clearColor];
    cell.opaque = NO;
    if (cell.layer.backgroundColor) {
        cell.layer.backgroundColor = [UIColor clearColor].CGColor;
    }

    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.contentView.opaque = NO;
    if (cell.contentView.layer.backgroundColor) {
        cell.contentView.layer.backgroundColor = [UIColor clearColor].CGColor;
    }

    if (cell.backgroundView) {
        cell.backgroundView.hidden = YES;
        cell.backgroundView.alpha = 0.0f;
        cell.backgroundView.backgroundColor = [UIColor clearColor];
    }

    if (cell.selectedBackgroundView) {
        cell.selectedBackgroundView.backgroundColor = [UIColor clearColor];
    }

    for (UIView *sub in cell.subviews) {
        if (sub == cell.contentView) continue;
        NSString *cls = NSStringFromClass(sub.class);
        if ([cls containsString:@"Background"] || [cls containsString:@"Decoration"] ||
            [cls containsString:@"_UISystemBackgroundView"]) {
            sub.hidden = YES;
            sub.alpha = 0.0f;
            sub.backgroundColor = [UIColor clearColor];
            if (sub.layer.backgroundColor) {
                sub.layer.backgroundColor = [UIColor clearColor].CGColor;
            }
        }
    }

    for (UIView *sub in cell.contentView.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) continue;
        if ([sub isKindOfClass:[UILabel class]]) {
            sub.backgroundColor = [UIColor clearColor];
            sub.opaque = NO;
            if (sub.layer.backgroundColor) {
                sub.layer.backgroundColor = [UIColor clearColor].CGColor;
            }
            continue;
        }

        NSString *cls = NSStringFromClass(sub.class);
        if ([cls containsString:@"Artwork"] || [cls containsString:@"Video"] ||
            [cls containsString:@"Thumbnail"] || [cls containsString:@"Image"] ||
            [cls containsString:@"Cover"] || [cls containsString:@"Badge"] ||
            [cls containsString:@"Glyph"] || [cls containsString:@"Symbol"] ||
            [sub isKindOfClass:[UIButton class]]) {
            continue;
        }

        sub.backgroundColor = [UIColor clearColor];
        sub.opaque = NO;
        if (sub.layer.backgroundColor) {
            sub.layer.backgroundColor = [UIColor clearColor].CGColor;
        }

        for (UIView *nested in sub.subviews) {
            if ([nested isKindOfClass:[UIImageView class]]) continue;
            if ([nested isKindOfClass:[UILabel class]]) {
                nested.backgroundColor = [UIColor clearColor];
                nested.opaque = NO;
                if (nested.layer.backgroundColor) {
                    nested.layer.backgroundColor = [UIColor clearColor].CGColor;
                }
                continue;
            }

            NSString *nCls = NSStringFromClass(nested.class);
            if ([nCls containsString:@"Artwork"] || [nCls containsString:@"Video"] ||
                [nCls containsString:@"Thumbnail"] || [nCls containsString:@"Image"] ||
                [nCls containsString:@"Cover"] || [nCls containsString:@"Badge"] ||
                [nCls containsString:@"Glyph"] || [nCls containsString:@"Symbol"] ||
                [nested isKindOfClass:[UIButton class]]) {
                continue;
            }

            if ([nCls containsString:@"Background"] || [nCls containsString:@"Plate"] ||
                [nCls containsString:@"Card"] || [nCls containsString:@"Decoration"] ||
                [nCls containsString:@"_UISystemBackgroundView"]) {
                nested.hidden = YES;
                nested.alpha = 0.0f;
                nested.backgroundColor = [UIColor clearColor];
                if (nested.layer.backgroundColor) {
                    nested.layer.backgroundColor = [UIColor clearColor].CGColor;
                }
            } else {
                nested.backgroundColor = [UIColor clearColor];
                nested.opaque = NO;
                if (nested.layer.backgroundColor) {
                    nested.layer.backgroundColor = [UIColor clearColor].CGColor;
                }
            }
        }
    }
}

BOOL tj_cellOnAlbumOrPlaylistDetail(UIView *v) {
    if (!v) return NO;
    if (tj_viewHasParallaxAncestor(v)) return NO;
    UIViewController *owner = tj_currentThemeOwnerVC();
    UIResponder *r = v;
    for (int hops = 0; r && hops < 48; hops++, r = r.nextResponder) {
        if (![r isKindOfClass:[UIViewController class]]) continue;
        UIViewController *vc = (UIViewController *)r;
        if (owner && vc == owner) return YES;
        if (tj_surfaceVCIsAlbumDetailFamily(vc)) return YES;
    }
    return NO;
}

BOOL tj_surfaceVCIsAlbumDetailFamily(UIViewController *vc) {
    if (!vc) return NO;
    NSString *n = NSStringFromClass(vc.class);
    if ([n containsString:@"NowPlaying"]) return NO;
    if ([n containsString:@"ExpandedPlayer"]) return NO;
    if ([n containsString:@"MiniPlayer"]) return NO;
    return [n containsString:@"AlbumDetail"] || [n containsString:@"PlaylistDetail"] ||
           [n containsString:@"ContainerDetail"] || [n containsString:@"MusicAlbum"] ||
           [n containsString:@"MusicVideoDetail"];
}

UIViewController *nearestVC(UIView *v) {
    UIResponder *r = v;
    while ((r = r.nextResponder))
        if ([r isKindOfClass:[UIViewController class]]) return (UIViewController *)r;
    return nil;
}

UIViewController *tj_albumSurfaceViewController(UIView *anchor) {
    UIViewController *vc = nearestVC(anchor);
    if (!vc || !anchor) return vc;
    for (;;) {
        UIViewController *par = vc.parentViewController;
        if (!par || !par.isViewLoaded || !par.view) break;
        if ([par isKindOfClass:[UITabBarController class]] ||
            [par isKindOfClass:[UISplitViewController class]])
            break;
        if (![anchor isDescendantOfView:par.view]) break;
        vc = par;
    }
    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *asNav = (UINavigationController *)vc;
        UIViewController *top = asNav.topViewController;
        if (top && top.view && [anchor isDescendantOfView:top.view])
            vc = top;
    } else {
        UINavigationController *nav = vc.navigationController;
        if (nav && nav.topViewController && nav.topViewController.view &&
            [anchor isDescendantOfView:nav.topViewController.view])
            vc = nav.topViewController;
    }
    return vc;
}

BOOL tj_collectionViewIsMainVerticalList(UICollectionView *cv);
BOOL tj_subtreeContainsParallaxView(UIView *root, int depth);

void tintAlbumDetailHierarchy(UIView *start, UIColor *color) {
    UIView *v = start.superview;
    while (v) {
        if (tj_subtreeContainsParallaxView(v, 0)) {
            v = v.superview;
            continue;
        }
        NSString *cls = NSStringFromClass(v.class);
        if ([cls containsString:@"TintColorObserving"])
            v.backgroundColor = color;
        else if ([cls containsString:@"VerticalStack"] ||
                 [cls containsString:@"AlbumDetail"] ||
                 [cls containsString:@"ContainerDetail"] ||
                 [cls containsString:@"PlaylistDetail"])
            v.backgroundColor = color;
        else if ([v isKindOfClass:[UICollectionView class]] &&
                 tj_collectionViewIsMainVerticalList((UICollectionView *)v))
            v.backgroundColor = color;
        v = v.superview;
    }
}

UIImage *firstImageInView(UIView *v, int depth) {
    if (!v || depth > 8) return nil;
    if ([v isKindOfClass:[UIImageView class]]) {
        UIImage *img = ((UIImageView *)v).image;
        if (img && img.size.width >= 80 && img.size.height >= 80) return img;
    }
    for (UIView *sub in v.subviews) {
        UIImage *found = firstImageInView(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

void tj_tintListRowInteractables(UIView *v, UIColor *fg, int depth) {
    if (!v || !fg || depth > 18) return;
    NSString *cls = NSStringFromClass(v.class);

    BOOL musicOwnsState = tj_isTrackRowActionControl(v);
    if ([v isKindOfClass:[UIButton class]] && !musicOwnsState) {
        UIButton *b = (UIButton *)v;
        b.tintColor = fg;
        [b setTitleColor:fg forState:UIControlStateNormal];
    } else if ([v isKindOfClass:[UIControl class]] && !musicOwnsState) {
        UIControl *c = (UIControl *)v;
        CGFloat w = CGRectGetWidth(c.bounds), h = CGRectGetHeight(c.bounds);
        if (w > 0 && w <= 46.f && h > 0 && h <= 46.f)
            c.tintColor = fg;
    } else if ([v isKindOfClass:[UIImageView class]] && !musicOwnsState) {
        UIImageView *iv = (UIImageView *)v;
        CGFloat w = CGRectGetWidth(iv.bounds), h = CGRectGetHeight(iv.bounds);
        if (w > 0 && w < 40.f && h > 0 && h < 40.f)
            iv.tintColor = fg;
    } else if ([cls containsString:@"SymbolButton"] ||
               [cls containsString:@"ListAccessory"] ||
               [cls containsString:@"AccessoryView"] ||
               [cls containsString:@"UIAccessory"]) {
        if (!musicOwnsState && [v respondsToSelector:@selector(setTintColor:)])
            v.tintColor = fg;
    }
    for (UIView *s in v.subviews)
        tj_tintListRowInteractables(s, fg, depth + 1);
}

void flattenListRowOpaqueBases(UIView *v, int depth) {
    if (!v || depth > 14) return;
    UIColor *fill = tj_rowFillColor();
    NSString *cls = NSStringFromClass(v.class);
    if ([cls containsString:@"TableViewCellContentView"] ||
        [cls containsString:@"CellContentView"] ||
        [cls containsString:@"ListRow"] ||
        [cls containsString:@"_UIList"]) {
        if (fill) {
            v.backgroundColor = fill;
            v.opaque = YES;
        } else {
            v.backgroundColor = [UIColor clearColor];
            v.opaque = NO;
        }
    }
    for (UIView *sub in v.subviews)
        flattenListRowOpaqueBases(sub, depth + 1);
}

void applyCellTint(UIView *v, int depth) {
    if (!v || depth > 6) return;
    NSString *cls = NSStringFromClass(v.class);
    if ([cls containsString:@"_UISystemBackgroundView"] ||
        [cls containsString:@"SectionBackground"] ||
        [cls containsString:@"DecorationView"]) {
        v.backgroundColor = [UIColor clearColor];
        v.opaque = NO;
    } else if ([cls containsString:@"UITableViewCollectionCell"]) {
        UIColor *f = tj_rowFillColor();
        if (f) {
            v.backgroundColor = f;
            v.opaque = YES;
        } else {
            v.backgroundColor = [UIColor clearColor];
        }
    }
    for (UIView *sub in v.subviews)
        applyCellTint(sub, depth + 1);
    if (depth == 0) {
        flattenListRowOpaqueBases(v, 0);
        if (_albumDetailForegroundColor)
            tj_tintListRowInteractables(v, _albumDetailForegroundColor, 0);
    }
}

BOOL tj_viewHasParallaxAncestor(UIView *v) {
    for (UIView *p = v.superview; p; p = p.superview) {
        if ([NSStringFromClass(p.class) containsString:@"ParallaxView"])
            return YES;
    }
    return NO;
}

static BOOL tj_subtreeContainsParallaxViewScan(UIView *root, int depth) {
    if (!root || depth > 20) return NO;
    if ([NSStringFromClass(root.class) containsString:@"ParallaxView"])
        return YES;
    for (UIView *s in root.subviews) {
        if (tj_subtreeContainsParallaxViewScan(s, depth + 1))
            return YES;
    }
    return NO;
}

BOOL tj_subtreeContainsParallaxView(UIView *root, int depth) {
    if (!root) return NO;
    if (depth > 0)
        return tj_subtreeContainsParallaxViewScan(root, depth);
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *stamp = objc_getAssociatedObject(root, kTJParallaxScanStampKey);
    if (stamp) {
        double v = stamp.doubleValue;
        double issued = v < 0.0 ? -v : v;
        if (issued > 0.5 && now - issued < 1.0)
            return v > 0.0;
    }
    BOOL found = tj_subtreeContainsParallaxViewScan(root, 0);
    objc_setAssociatedObject(root, kTJParallaxScanStampKey, @(found ? now : -now),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return found;
}

BOOL tj_cvContentLooksHorizontallyScrolled(UICollectionView *cv) {
    if (!cv) return NO;
    UICollectionViewLayout *layout = cv.collectionViewLayout;
    CGSize cs = layout ? layout.collectionViewContentSize : CGSizeZero;
    if (cs.width < 28.f || cs.height < 28.f) return NO;
    return cs.width > cs.height * 1.08f;
}

BOOL tj_collectionViewIsMainVerticalList(UICollectionView *cv) {
    if (!cv) return NO;
    if (tj_viewHasParallaxAncestor(cv)) return NO;
    if (tj_cvContentLooksHorizontallyScrolled(cv)) return NO;
    CGFloat h = CGRectGetHeight(cv.bounds);
    CGFloat hFrame = CGRectGetHeight(cv.frame);
    CGFloat effH = MAX(h, hFrame);
    if (effH < 120.f) {

        UICollectionViewLayout *bootLayout = cv.collectionViewLayout;
        CGSize bootCs = bootLayout ? bootLayout.collectionViewContentSize : CGSizeZero;
        return bootCs.width < 2.f && bootCs.height < 2.f;
    }
    UIWindow *win = cv.window;
    CGFloat winH = win ? CGRectGetHeight(win.bounds) : 812.f;
    CGFloat winW = win ? CGRectGetWidth(win.bounds) : 390.f;
    CGFloat minH = MAX(440.f, winH * 0.52f);
    if (effH >= minH) {
        UICollectionViewLayout *layout = cv.collectionViewLayout;
        CGSize cs = layout ? layout.collectionViewContentSize : CGSizeZero;
        if (cs.width > 24.f && cs.height > 24.f) {
            if (cs.width > cs.height * 1.08f) return NO;
            if (cs.height >= cs.width * 0.48f) return YES;
        } else {
            return YES;
        }
    }
    UICollectionViewLayout *layout = cv.collectionViewLayout;
    CGSize cs = layout ? layout.collectionViewContentSize : CGSizeZero;
    CGFloat w = CGRectGetWidth(cv.bounds);
    BOOL wide = w >= winW * 0.78f;
    BOOL tallScrollContent = cs.height >= winH * 0.38f;
    BOOL verticalScrollContent =
        cs.height > 2.f && cs.height >= cs.width * 0.55f;
    if (wide && tallScrollContent && verticalScrollContent && effH >= 160.f)
        return YES;
    CGFloat csMaxBoot = MAX(cs.width, cs.height);
    if (wide && effH >= 220.f && csMaxBoot < 80.f)
        return YES;
    return NO;
}

BOOL tj_cellIsInMainListScrollSurface(UIView *cell) {
    if (!cell) return NO;
    if (tj_viewHasParallaxAncestor(cell)) return NO;

    for (UIView *x = cell; x; x = x.superview) {
        if ([x isKindOfClass:[UICollectionView class]])
            return tj_collectionViewIsMainVerticalList((UICollectionView *)x);
        if ([x isKindOfClass:[UITableView class]])
            return !tj_viewHasParallaxAncestor(x);
    }
    return NO;
}

BOOL tj_subtreeContainsMainListScrollSurface(UIView *root, int depth) {
    if (!root || depth > 24) return NO;
    if ([root isKindOfClass:[UICollectionView class]] &&
        tj_collectionViewIsMainVerticalList((UICollectionView *)root))
        return YES;
    if ([root isKindOfClass:[UITableView class]])
        return !tj_viewHasParallaxAncestor(root);
    for (UIView *s in root.subviews) {
        if ([NSStringFromClass(s.class) containsString:@"ParallaxView"])
            continue;
        if (tj_subtreeContainsMainListScrollSurface(s, depth + 1))
            return YES;
    }
    return NO;
}

void tj_scanForListCollectionViews(UIView *v, int depth, BOOL *sawMain, BOOL *sawShort) {
    if (!v || depth > 12 || !sawMain || !sawShort) return;
    if ([v isKindOfClass:[UICollectionView class]]) {
        if (tj_collectionViewIsMainVerticalList((UICollectionView *)v))
            *sawMain = YES;
        else
            *sawShort = YES;
    }
    for (UIView *s in v.subviews) {
        if ([NSStringFromClass(s.class) containsString:@"ParallaxView"])
            continue;
        tj_scanForListCollectionViews(s, depth + 1, sawMain, sawShort);
    }
}

BOOL tj_tintColorObservingShouldReceiveSurfaceTint(UIView *v) {
    if (tj_subtreeContainsParallaxView(v, 0))
        return NO;
    BOOL sawMain = NO, sawShort = NO;
    tj_scanForListCollectionViews(v, 0, &sawMain, &sawShort);
    if (sawShort && !sawMain)
        return NO;
    return YES;
}

BOOL tj_viewShouldReceiveSurfaceTint(UIView *v) {
    NSString *cls = NSStringFromClass(v.class);
    if ([cls containsString:@"ParallaxView"])
        return NO;
    if ([v isKindOfClass:[UICollectionView class]])
        return tj_collectionViewIsMainVerticalList((UICollectionView *)v);
    if ([v isKindOfClass:[UITableView class]])
        return !tj_viewHasParallaxAncestor(v);
    if ([cls containsString:@"VerticalStack"] ||
        [cls containsString:@"AlbumDetail"] ||
        [cls containsString:@"ContainerDetail"] ||
        [cls containsString:@"PlaylistDetail"])
        return !tj_subtreeContainsParallaxView(v, 0);
    if ([cls containsString:@"JSVertical"])
        return tj_subtreeContainsMainListScrollSurface(v, 0) &&
               !tj_subtreeContainsParallaxView(v, 0);
    if ([cls containsString:@"TintColorObserving"])
        return tj_tintColorObservingShouldReceiveSurfaceTint(v);
    return NO;
}

void tintVCViewTree(UIView *v, UIColor *color, int depth) {
    if (!v || depth > 14) return;
    if (tj_viewShouldReceiveSurfaceTint(v)) {
        v.backgroundColor = color;
        if ([v isKindOfClass:[UICollectionView class]]) {
            UICollectionView *cv = (UICollectionView *)v;
            if (cv.backgroundView) {
                cv.backgroundView.hidden = YES;
                cv.backgroundView.alpha = 0.0f;
                cv.backgroundView = nil;
            }
        }
    }
    for (UIView *sub in v.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"ParallaxView"])
            continue;
        tintVCViewTree(sub, color, depth + 1);
    }
}

void forEachListScrollViewUnderView(UIView *root, void (^block)(UIScrollView *sv)) {
    if (!root || !block) return;
    if ([root isKindOfClass:[UITableView class]]) {
        if (!tj_viewHasParallaxAncestor((UIView *)root))
            block((UIScrollView *)root);
    } else if ([root isKindOfClass:[UICollectionView class]]) {
        if (tj_collectionViewIsMainVerticalList((UICollectionView *)root))
            block((UIScrollView *)root);
    }
    for (UIView *sub in root.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"ParallaxView"])
            continue;
        forEachListScrollViewUnderView(sub, block);
    }
}

NSArray<UIScrollView *> *cachedListScrollViewsForVC(UIViewController *vc) {
    if (!vc) return @[];
    NSArray<UIScrollView *> *cached = objc_getAssociatedObject(vc, kTJCachedCVsKey);
    if (cached) {
        BOOL stale = NO;
        for (UIScrollView *sv in cached) {
            if ([sv isKindOfClass:[UICollectionView class]]) {
                if (!tj_collectionViewIsMainVerticalList((UICollectionView *)sv)) {
                    stale = YES;
                    break;
                }
            } else if ([sv isKindOfClass:[UITableView class]]) {
                if (tj_viewHasParallaxAncestor((UIView *)sv)) {
                    stale = YES;
                    break;
                }
            }
        }
        if (!stale) return cached;
        objc_setAssociatedObject(vc, kTJCachedCVsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSMutableArray<UIScrollView *> *lists = [NSMutableArray array];
    forEachListScrollViewUnderView(vc.view, ^(UIScrollView *sv) {
        if (sv) [lists addObject:sv];
    });
    if (lists.count == 0) return @[];
    cached = [lists copy];
    objc_setAssociatedObject(vc, kTJCachedCVsKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cached;
}
