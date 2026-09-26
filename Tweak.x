#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "TJEngine.h"
#import "TJInternal.h"
#import "TJNowPlayingImmersive.h"
#import "TJModelUtils.h"
#import "TJMotionArtworkResolver.h"
#import "TJLastFmBadgeView.h"

static void *kTJLastFmBadgeKey = &kTJLastFmBadgeKey;

static __weak UIViewController *sActiveNowPlayingControlsVC = nil;
static __weak UIViewController *sActiveMiniPlayerVC = nil;

UIViewController * _Nullable tj_activeNowPlayingControlsViewController(void) {
    return sActiveNowPlayingControlsVC;
}

UIViewController * _Nullable tj_activeMiniPlayerViewController(void) {
    return sActiveMiniPlayerVC;
}

typedef NS_ENUM(NSInteger, TJKeyProbeState) { TJKeyProbeUnknown = 0, TJKeyProbeValid, TJKeyProbeInvalid };

static id tj_probedValueForKey(id obj, NSString *key, TJKeyProbeState *probe) {
    if (*probe == TJKeyProbeInvalid) return nil;
    if (*probe == TJKeyProbeValid) return [obj valueForKey:key];
    @try {
        id v = [obj valueForKey:key];
        *probe = TJKeyProbeValid;
        return v;
    } @catch (__unused id e) {
        *probe = TJKeyProbeInvalid;
        return nil;
    }
}

static TJKeyProbeState sTimeControlProbe = TJKeyProbeUnknown;
static TJKeyProbeState sSubtitleButtonProbe = TJKeyProbeUnknown;
static TJKeyProbeState sTitleLabelProbe = TJKeyProbeUnknown;
static TJKeyProbeState sAudioTraitButtonProbe = TJKeyProbeUnknown;
static TJKeyProbeState sContextButtonProbe = TJKeyProbeUnknown;

%hook _TtC16MusicApplication12DetailHeader

- (void)setArtworkComponent:(id)component {
    %orig;
    UIViewController *surfaceGate = tj_albumSurfaceViewController(self);
    if (component) {
        objc_setAssociatedObject(self, kTJArtworkKey, component, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kTJArtworkArmedStampKey, @(CACurrentMediaTime()),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tj_inspectAndCacheComponentMotionVideo(component);

        NSString *title = surfaceGate.title ?: surfaceGate.navigationItem.title;
        if (!title && surfaceGate.parentViewController) {
            title = surfaceGate.parentViewController.title ?: surfaceGate.parentViewController.navigationItem.title;
        }
        if (title && title.length > 0) {
            tj_setLatestActiveAlbumTitle(title);
            if (tj_latestActiveAlbumMotionVideoURL()) {
                tj_recordAlbumMotionVideoURL(title, tj_latestActiveAlbumMotionVideoURL());
            }
        }

        if (surfaceGate) {
            id albumObj = nil;
            @try { albumObj = [(id)surfaceGate valueForKey:@"album"]; } @catch (__unused id e) {}
            if (!albumObj && surfaceGate.parentViewController) {
                @try { albumObj = [(id)surfaceGate.parentViewController valueForKey:@"album"]; } @catch (__unused id e) {}
            }
            if (albumObj) {
                NSString *aid = tj_extractAdamID(albumObj);
                if (aid) {
                    tj_setLatestActiveAlbumAdamID(aid);
                    if (tj_latestActiveAlbumMotionVideoURL()) {
                        tj_recordAlbumMotionVideoURL(aid, tj_latestActiveAlbumMotionVideoURL());
                    }
                }
            }
        }
    }
    if (!tj_surfaceVCIsAlbumDetailFamily(surfaceGate))
        return;

    UIViewController *owner = tj_currentThemeOwnerVC();
    if (owner && surfaceGate && owner != surfaceGate) {
        _albumDetailDominantColor = nil;
        _albumDetailForegroundColor = nil;
        _albumDetailListSurfaceColor = nil;
        tj_setThemeOwnerVC(nil);
    }
    objc_setAssociatedObject(self, kTJTintedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kTJCachedDominantKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kTJGrayArtKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, kTJHeaderLayoutThrottleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIViewController *vc = tj_albumSurfaceViewController(self);
    if (vc) {
        objc_setAssociatedObject(vc, kTJCachedCVsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(vc, kTJLastSurfaceApplyKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(vc, kTJLastListPaintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(vc, kTJLastHeavyListPaintKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(vc, kTJLastParallaxTreePassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(vc, kTJListBootstrapScheduledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [self tj_recolourFromArtwork];

    __weak typeof(self) ws = self;
    for (NSNumber *delay in @[@0.4, @1.0, @2.0, @3.5, @5.5, @8.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!ws) return;

            if (objc_getAssociatedObject(ws, kTJTintedKey)) {
                NSNumber *grayLatch = objc_getAssociatedObject(ws, kTJGrayArtKey);
                if (!grayLatch.boolValue) return;
                objc_setAssociatedObject(ws, kTJTintedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(ws, kTJCachedDominantKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            [ws tj_recolourFromArtwork];
        });
    }
}

- (void)layoutSubviews {
    %orig;
    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;
    UIViewController *surfaceVC = tj_albumSurfaceViewController(self);
    if (!tj_surfaceVCIsAlbumDetailFamily(surfaceVC)) return;
    BOOL immersivePage = surfaceVC && surfaceVC.view &&
                         tj_subtreeContainsParallaxView(surfaceVC.view, 0);
    CFTimeInterval headerLayoutHz = immersivePage ? 6.0 : 8.0;
    if (objc_getAssociatedObject(self, kTJTintedKey)) {
        CFTimeInterval t = CACurrentMediaTime();
        NSNumber *n = objc_getAssociatedObject(self, kTJHeaderLayoutThrottleKey);
        if (n && t - n.doubleValue < (1.0 / headerLayoutHz)) return;
        objc_setAssociatedObject(self, kTJHeaderLayoutThrottleKey, @(t), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    tj_detailHeaderScheduleRecolour(self);
}

- (void)didMoveToWindow {
    %orig;
    if (!self.window) {
        objc_setAssociatedObject(self, kTJTintedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kTJHeaderLayoutThrottleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, kTJHeaderLayoutAsyncScheduledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (prefBool(@"enabled", YES) && prefBool(@"albumDetailEnabled", YES)) {
        if (tj_surfaceVCIsAlbumDetailFamily(tj_albumSurfaceViewController(self)))
            tj_detailHeaderScheduleRecolour(self);
    }
}

%new
- (void)tj_recolourFromArtwork {
    if (!NSThread.isMainThread) return;
    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;

    UIViewController *surfaceVCForTint = tj_albumSurfaceViewController(self);
    if (!tj_surfaceVCIsAlbumDetailFamily(surfaceVCForTint))
        return;

    id locked = objc_getAssociatedObject(self, kTJTintedKey);
    UIColor *cachedDom = objc_getAssociatedObject(self, kTJCachedDominantKey);
    if (!locked) {
        UIColor *earlyDom = objc_getAssociatedObject(surfaceVCForTint, kTJCachedDominantKey);
        if ([earlyDom isKindOfClass:[UIColor class]]) {
            cachedDom = earlyDom;
            locked = @YES;
            objc_setAssociatedObject(self, kTJTintedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, kTJCachedDominantKey, earlyDom, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if (locked && [cachedDom isKindOfClass:[UIColor class]]) {
        UIColor *listSurface = tj_listSurfaceFromDominant(cachedDom);

        UIColor *musicFg = tj_headerReadMusicTextColor(self);
        UIColor *cfg = musicFg ?: tj_albumDetailForeground(cachedDom, listSurface);
        _albumDetailDominantColor = cachedDom;
        _albumDetailForegroundColor = cfg;
        _albumDetailListSurfaceColor = listSurface;
        tj_setThemeOwnerVC(surfaceVCForTint);
        tintAlbumDetailHierarchy(self, listSurface);
        UIViewController *vc = surfaceVCForTint;
        if (vc) {

            tj_paintDetailBodyNow(vc, listSurface);
            applyAlbumSurfaceTint(vc, cachedDom, cfg);
            tj_maybeScheduleListBootstrapRetries(vc);
        }
        return;
    }

    UIColor *dominant = tj_headerReadMusicDominantColor(self);
    BOOL fromMusicPipeline = (dominant != nil);

    if (!dominant) {

        CGFloat sat = prefFloat(@"albumSaturation", 1.52);
        CGFloat bri = prefFloat(@"albumBrightness", 0.75);

        id component = objc_getAssociatedObject(self, kTJArtworkKey);
        UIImage *img = nil;
        if (component) {
            if ([component respondsToSelector:@selector(imageWithSize:)]) {
                CGSize sz = CGSizeMake(200, 200);
                img = ((UIImage * (*)(id, SEL, CGSize)) objc_msgSend)(component,
                                                                      @selector(imageWithSize:),
                                                                      sz);
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
        }
        if (!img) img = tj_extractCatalogImageSync(component);
        if (!img) img = firstImageInView(self, 0);
        if (!img) return;

        dominant = dominantColorFromImage(img, sat, bri);
        if (!dominant) return;

        CGFloat domSat = 0;
        [dominant getHue:nil saturation:&domSat brightness:nil alpha:nil];

        BOOL isRealColor = (domSat > 0.10);
        if (!isRealColor && tj_imageEdgeRatio(img) < 0.06f) {
            NSNumber *armed = objc_getAssociatedObject(self, kTJArtworkArmedStampKey);
            if (!armed) {
                armed = @(CACurrentMediaTime());
                objc_setAssociatedObject(self, kTJArtworkArmedStampKey, armed,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (CACurrentMediaTime() - armed.doubleValue < 5.4) {

                __weak typeof(self) wsg = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (!wsg || objc_getAssociatedObject(wsg, kTJTintedKey)) return;
                    [wsg tj_recolourFromArtwork];
                });
                return;
            }
        }
    }

    UIColor *listSurface = tj_listSurfaceFromDominant(dominant);

    UIColor *musicFg = tj_headerReadMusicTextColor(self);
    UIColor *fg = musicFg ?: tj_albumDetailForeground(dominant, listSurface);
    _albumDetailDominantColor = dominant;
    _albumDetailForegroundColor = fg;

    _albumDetailListSurfaceColor = listSurface;
    tj_setThemeOwnerVC(surfaceVCForTint);

    self.backgroundColor = [UIColor clearColor];
    tintAlbumDetailHierarchy(self, listSurface);

    objc_setAssociatedObject(self, kTJCachedDominantKey, dominant, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIViewController *vc = surfaceVCForTint;
    if (vc) {
        tj_paintDetailBodyNow(vc, listSurface);
        applyAlbumSurfaceTint(vc, dominant, fg);
        tj_maybeScheduleListBootstrapRetries(vc);
    }

    objc_setAssociatedObject(self, kTJTintedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (fromMusicPipeline) {
        objc_setAssociatedObject(self, kTJGrayArtKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        CGFloat finalDomSat = 0;
        [dominant getHue:nil saturation:&finalDomSat brightness:nil alpha:nil];
        objc_setAssociatedObject(self, kTJGrayArtKey, @(finalDomSat <= 0.10),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%end

%hook MusicArtworkComponentImageView

- (void)setImage:(UIImage *)image {
    %orig;
    if (!image) return;
    if (prefBool(@"enabled", YES) && prefBool(@"immersiveNowPlaying", YES)) {
        UIView *p = ((UIView *)self).superview;
        BOOL isNPCV = NO;
        for (int i = 0; i < 4 && p; i++, p = p.superview) {
            if ([NSStringFromClass(p.class) containsString:@"NowPlayingContentView"]) {
                isNPCV = YES;
                break;
            }
        }
        if (isNPCV && !tj_isMiniPlayerSubtree((UIView *)self)) {
            tj_updateFullBleedArtworkImage(image);

            UIResponder *r = ((UIView *)self).nextResponder;
            UIViewController *controlsVC = nil;
            while (r) {
                if ([r isKindOfClass:[UIViewController class]]) {
                    UIViewController *vc = (UIViewController *)r;
                    if ([NSStringFromClass(vc.class) containsString:@"ControlsViewController"] ||
                        [NSStringFromClass(vc.class) containsString:@"NowPlayingViewController"]) {
                        controlsVC = vc;
                        break;
                    }
                }
                r = r.nextResponder;
            }
            if (controlsVC) {
                id playingItem = tj_extractPlayingItem(controlsVC);
                if (playingItem) {
                    if (tj_isNowPlayingItemMusicVideo(playingItem, nil, controlsVC)) {
                        tj_setNowPlayingImmersiveVisible(NO);
                        return;
                    }
                    UIView *container = tj_getOrCreateFullBleedArtworkView(controlsVC);
                    if (container) {
                        NSString *curTrack = tj_itemTrackKey(playingItem);
                        NSString *activeTrack = tj_currentActiveTrackIdentity();
                        BOOL trackChanged = (!activeTrack || (curTrack && ![curTrack isEqualToString:activeTrack]));
                        if (trackChanged) {
                            tj_setCurrentActiveTrackIdentity(curTrack);
                            tj_transitionToSquaredLayout(NO);
                            tj_requestHighResArtworkForItem(playingItem);
                            tj_updateNowPlayingMotionArtwork(container, playingItem);
                        } else {
                            if (tj_isMotionArtworkReadyForDisplay()) {
                                tj_setNowPlayingImmersiveVisible(YES);
                                UIView *cv = tj_activeNowPlayingContentView();
                                if (cv && cv.bounds.size.width >= 160.0f && tj_isFullScreenTransitionComplete()) {
                                    cv.alpha = 0.0f;
                                }
                            }
                        }
                        tj_resumeMotionArtwork(container);
                    }
                }
            }
        }
    }
    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;

    UIView *h = (UIView *)self;
    BOOL isDetailHeader = NO;
    for (int i = 0; i < 10 && h; i++, h = h.superview) {
        if ([NSStringFromClass(h.class) containsString:@"DetailHeader"]) {
            isDetailHeader = YES;
            break;
        }
    }
    if (!isDetailHeader || !h) return;
    UIViewController *vc = tj_albumSurfaceViewController(h);
    if (!tj_surfaceVCIsAlbumDetailFamily(vc)) return;
    tj_detailHeaderScheduleRecolour((_TtC16MusicApplication12DetailHeader *)h);
}

- (void)didMoveToSuperview {
    %orig;

    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;
    UIView *h = ((UIView *)self).superview;
    for (int i = 0; i < 10 && h; i++, h = h.superview) {
        if ([NSStringFromClass(h.class) containsString:@"DetailHeader"]) {

            if (!objc_getAssociatedObject(h, kTJArtworkArmedStampKey))
                objc_setAssociatedObject(h, kTJArtworkArmedStampKey,
                                         @(CACurrentMediaTime()),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            break;
        }
    }
}

%end

static void tj_detailVCViewWillAppear(UIViewController *vc) {
    tj_prepareDetailVCTintOnWillAppear(vc);
}
static void tj_detailVCViewDidLayoutSubviews(UIViewController *vc) {
    tj_detailSurfaceVCLayoutTick(vc);
    tj_maybeScheduleListBootstrapRetries(vc);
}
static void tj_detailVCViewDidAppear(UIViewController *vc) {
    tj_detailSurfaceVCForceChromeTick(vc);
}
static void tj_detailVCViewDidDisappear(UIViewController *vc) {
    tj_detailSurfaceVCHandoffIfLeaving(vc);
}

%hook _TtC16MusicApplication25AlbumDetailViewController
- (void)viewWillAppear:(BOOL)animated {
    tj_detailVCViewWillAppear((UIViewController *)self);
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    tj_detailVCViewDidLayoutSubviews((UIViewController *)self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    tj_detailVCViewDidAppear((UIViewController *)self);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    tj_detailVCViewDidDisappear((UIViewController *)self);
}
%end

%hook _TtC16MusicApplication28PlaylistDetailViewController
- (void)viewWillAppear:(BOOL)animated {
    tj_detailVCViewWillAppear((UIViewController *)self);
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    tj_detailVCViewDidLayoutSubviews((UIViewController *)self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    tj_detailVCViewDidAppear((UIViewController *)self);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    tj_detailVCViewDidDisappear((UIViewController *)self);
}
%end

%hook _TtC16MusicApplication29ContainerDetailViewController
- (void)viewWillAppear:(BOOL)animated {
    tj_detailVCViewWillAppear((UIViewController *)self);
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    tj_detailVCViewDidLayoutSubviews((UIViewController *)self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    tj_detailVCViewDidAppear((UIViewController *)self);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    tj_detailVCViewDidDisappear((UIViewController *)self);
}
%end

%hook _TtC16MusicApplication33ContainerDetailHeaderReusableView

- (void)layoutSubviews {
    %orig;
    if (!prefBool(@"enabled", YES) || !prefBool(@"albumDetailEnabled", YES)) return;
    @try {
        id hv = [(id)self valueForKey:@"headerView"];
        if (hv && [hv respondsToSelector:@selector(tj_recolourFromArtwork)])
            [(id)hv performSelector:@selector(tj_recolourFromArtwork)];
    } @catch (__unused id e) {}
}

%end

%hook _TtC16MusicApplication30MusicVideoDetailViewController

- (void)viewWillAppear:(BOOL)animated {
    tj_detailVCViewWillAppear((UIViewController *)self);
    %orig;
}
- (void)viewDidLayoutSubviews {
    %orig;
    tj_detailVCViewDidLayoutSubviews((UIViewController *)self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    tj_detailVCViewDidAppear((UIViewController *)self);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    tj_detailVCViewDidDisappear((UIViewController *)self);
}

%end

%hook UICollectionReusableView

- (void)layoutSubviews {
    %orig;
    if (!tj_currentThemeOwnerVC()) return;
    if (tj_viewHasParallaxAncestor(self)) return;
    if ([self isKindOfClass:[UICollectionViewCell class]]) return;
    if ([NSStringFromClass(self.class) containsString:@"DetailHeader"]) return;
    if (!tj_cellOnAlbumOrPlaylistDetail(self)) return;

    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    for (UIView *sub in self.subviews) {
        NSString *subCls = NSStringFromClass(sub.class);
        if ([subCls containsString:@"_UISystemBackgroundView"] ||
            [subCls containsString:@"SectionBackground"] ||
            [subCls containsString:@"DecorationView"] ||
            [subCls containsString:@"Background"]) {
            sub.backgroundColor = [UIColor clearColor];
            sub.opaque = NO;
            sub.hidden = YES;
            sub.alpha = 0.0f;
            if (sub.layer.backgroundColor) {
                sub.layer.backgroundColor = [UIColor clearColor].CGColor;
            }
        }
    }
}

%end

%hook UICollectionViewCell

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    %orig;
    if (prefBool(@"enabled", YES) && prefBool(@"albumDetailEnabled", YES)) {
        if (!tj_cellOnAlbumOrPlaylistDetail(self)) {
            UIImage *img = firstImageInView(self, 0);
            tj_recordTappedArtworkImage((img && img.size.width >= 80.f) ? img : nil);
        }
    }
}

- (void)willMoveToSuperview:(UIView *)newSuperview {
    %orig;
    if (!newSuperview || !tj_currentThemeOwnerVC()) return;
    if (tj_viewHasParallaxAncestor(self)) return;
    if (!tj_cellOnAlbumOrPlaylistDetail(newSuperview)) return;
    if (tj_isAlbumTrackRowCell(self)) return;
    if ([NSStringFromClass(self.class) containsString:@"DetailHeader"]) return;
    tj_clearShelfCardCell(self);
}

- (void)layoutSubviews {
    %orig;
    if (!tj_currentThemeOwnerVC()) return;
    if (tj_viewHasParallaxAncestor(self)) return;
    if (!tj_cellOnAlbumOrPlaylistDetail(self)) return;
    if (tj_isAlbumTrackRowCell(self)) return;
    if ([NSStringFromClass(self.class) containsString:@"DetailHeader"]) return;
    tj_clearShelfCardCell(self);
}

- (void)prepareForReuse {
    %orig;
    tj_cardCellPrepareForReuse(self);
}

%end

static void tj_paintRowCellWillMoveToSuperview(UIView *cell, UIView *contentView, UIView *newSuperview,
                                               UIView * _Nullable selectedBackgroundView) {
    if (tj_viewHasParallaxAncestor(cell)) return;
    UIColor *fill = tj_rowFillColor();
    if (!fill || !newSuperview || !tj_cellOnAlbumOrPlaylistDetail(newSuperview) ||
        !tj_cellIsInMainListScrollSurface(newSuperview))
        return;
    cell.backgroundColor = fill;
    contentView.backgroundColor = fill;
    applyCellTint(cell, 0);
    if (selectedBackgroundView) {
        selectedBackgroundView.backgroundColor = [_albumDetailDominantColor colorWithAlphaComponent:0.85];
    }
}

static void tj_paintRowCellLayoutSubviews(UIView *cell, UIView *contentView) {
    if (tj_viewHasParallaxAncestor(cell)) return;
    UIColor *fill = tj_rowFillColor();
    if (!fill || !tj_cellOnAlbumOrPlaylistDetail(cell) || !tj_cellIsInMainListScrollSurface(cell)) return;
    cell.backgroundColor = fill;
    contentView.backgroundColor = fill;
    applyCellTint(cell, 0);
    tj_fixCellContentForScroll(cell);
}

%hook _TtC16MusicApplication10DetailCell

- (void)willMoveToSuperview:(UIView *)newSuperview {
    %orig;
    tj_paintRowCellWillMoveToSuperview(self, self.contentView, newSuperview, self.selectedBackgroundView);
}

- (void)layoutSubviews {
    %orig;
    tj_paintRowCellLayoutSubviews(self, self.contentView);
}

%end

%hook _TtC16MusicApplication8SongCell

- (void)willMoveToSuperview:(UIView *)newSuperview {
    %orig;
    tj_paintRowCellWillMoveToSuperview(self, self.contentView, newSuperview, self.selectedBackgroundView);
}

- (void)layoutSubviews {
    %orig;
    tj_paintRowCellLayoutSubviews(self, self.contentView);
}

%end

%hook UICollectionViewListCell

- (void)willMoveToSuperview:(UIView *)newSuperview {
    %orig;
    tj_paintRowCellWillMoveToSuperview(self, self.contentView, newSuperview, nil);
}

- (void)layoutSubviews {
    %orig;
    tj_paintRowCellLayoutSubviews(self, self.contentView);
}

%end

%hook UITableViewCell

- (void)willMoveToSuperview:(UIView *)newSuperview {
    %orig;
    tj_paintRowCellWillMoveToSuperview(self, self.contentView, newSuperview, nil);
}

- (void)layoutSubviews {
    %orig;
    tj_paintRowCellLayoutSubviews(self, self.contentView);
}

%end

%hook UICollectionView

- (void)didMoveToWindow {
    %orig;
    if (self.window)
        tj_listScrollSurfaceDidAttach(self);
}

- (void)layoutSubviews {
    %orig;
    tj_listScrollSurfaceLayoutEnsure(self);
}

- (void)selectItemAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated scrollPosition:(UICollectionViewScrollPosition)scrollPosition {
    %orig;
    if (indexPath && prefBool(@"enabled", YES) && prefBool(@"albumDetailEnabled", YES)) {
        UICollectionViewCell *cell = [self cellForItemAtIndexPath:indexPath];
        UIImage *img = cell ? firstImageInView(cell, 0) : nil;
        tj_recordTappedArtworkImage((img && img.size.width >= 40.f) ? img : nil);
    }
}

- (void)setBackgroundColor:(UIColor *)color {
    UIColor *fill = tj_rowFillColor();
    if (fill && tj_cellOnAlbumOrPlaylistDetail(self) && !tj_viewHasParallaxAncestor(self)) {
        %orig(fill);
        return;
    }
    %orig(color);
}

- (void)setBackgroundView:(UIView *)bgView {
    if (tj_currentThemeOwnerVC() && tj_cellOnAlbumOrPlaylistDetail(self) && !tj_viewHasParallaxAncestor(self)) {
        if (bgView) {
            bgView.hidden = YES;
            bgView.alpha = 0.0f;
        }
        %orig(nil);
        UIColor *fill = tj_rowFillColor();
        if (fill) self.backgroundColor = fill;
        return;
    }
    %orig(bgView);
}

%end

%hook UINavigationController

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (viewController && prefBool(@"enabled", YES) && prefBool(@"albumDetailEnabled", YES) &&
        tj_surfaceVCIsAlbumDetailFamily(viewController)) {
        tj_prepareDetailVCTintBeforePush(self, viewController);
    }
    %orig;
}

%end

%hook UITableView

- (void)didMoveToWindow {
    %orig;
    if (self.window)
        tj_listScrollSurfaceDidAttach(self);
}

- (void)layoutSubviews {
    %orig;
    tj_listScrollSurfaceLayoutEnsure(self);
}

%end

static UIView * _Nullable tj_findNowPlayingContentView(UIView * _Nullable root) {
    if (!root) return nil;
    if ([NSStringFromClass(root.class) containsString:@"NowPlayingContentView"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = tj_findNowPlayingContentView(sub);
        if (found) return found;
    }
    return nil;
}

%hook _TtC16MusicApplication21NowPlayingContentView

- (void)willMoveToSuperview:(UIView *)newSuperview {
    %orig;
    if (prefBool(@"enabled", YES) && prefBool(@"immersiveNowPlaying", YES)) {
        if (newSuperview && !tj_isMiniPlayerSubtree(newSuperview)) {
            tj_setActiveNowPlayingContentView((UIView *)self);
            if (tj_isNowPlayingItemMusicVideo(nil, (UIView *)self, nil)) {
                self.alpha = 1.0f;
                self.hidden = NO;
                tj_setNowPlayingImmersiveVisible(NO);
                return;
            }
            if (tj_isNowPlayingLyricsOrQueueActiveWithView(newSuperview, nil)) {
                self.alpha = 1.0f;
                self.hidden = NO;
                tj_setNowPlayingImmersiveVisible(NO);
            } else if (tj_isMotionArtworkReadyForDisplay()) {
                if (tj_isFullScreenTransitionComplete()) self.alpha = 0.0f;
                tj_setNowPlayingImmersiveVisible(YES);
            } else {
                self.alpha = 1.0f;
                self.transform = CGAffineTransformIdentity;
                self.hidden = NO;
                tj_setNowPlayingImmersiveVisible(NO);
            }
        }
    }
}

- (void)didMoveToWindow {
    %orig;
    if (prefBool(@"enabled", YES) && prefBool(@"immersiveNowPlaying", YES)) {
        if (self.window && !tj_isMiniPlayerSubtree((UIView *)self)) {
            tj_setActiveNowPlayingContentView((UIView *)self);
            if (tj_isNowPlayingItemMusicVideo(nil, (UIView *)self, nil)) {
                self.alpha = 1.0f;
                self.hidden = NO;
                tj_setNowPlayingImmersiveVisible(NO);
                return;
            }
            if (tj_isNowPlayingLyricsOrQueueActiveWithView((UIView *)self, nil)) {
                self.alpha = 1.0f;
                self.hidden = NO;
                tj_setNowPlayingImmersiveVisible(NO);
            } else if (tj_isMotionArtworkReadyForDisplay()) {
                if (tj_isFullScreenTransitionComplete()) self.alpha = 0.0f;
                tj_setNowPlayingImmersiveVisible(YES);
            } else {
                self.alpha = 1.0f;
                self.transform = CGAffineTransformIdentity;
                self.hidden = NO;
                tj_setNowPlayingImmersiveVisible(NO);
            }
        }
    }
}

- (void)layoutSubviews {
    %orig;
    if (prefBool(@"enabled", YES) && prefBool(@"immersiveNowPlaying", YES)) {
        if (tj_isMiniPlayerSubtree((UIView *)self)) return;
        tj_setActiveNowPlayingContentView((UIView *)self);

        if (tj_isNowPlayingItemMusicVideo(nil, (UIView *)self, nil)) {
            self.alpha = 1.0f;
            self.hidden = NO;
            tj_setNowPlayingImmersiveVisible(NO);
            return;
        }

        BOOL isCollapsed = NO;
        if (self.bounds.size.width > 0.0f && self.bounds.size.width < 160.0f) {
            isCollapsed = YES;
        }
        if (!isCollapsed && tj_isNowPlayingLyricsOrQueueActiveWithView((UIView *)self, nil)) {
            isCollapsed = YES;
        }

        if (isCollapsed) {
            self.alpha = 1.0f;
            self.hidden = NO;
            tj_setNowPlayingImmersiveVisible(NO);
        } else if (self.bounds.size.width >= 160.0f) {
            if (tj_isMotionArtworkReadyForDisplay()) {
                if (tj_isFullScreenTransitionComplete()) self.alpha = 0.0f;
                tj_setNowPlayingImmersiveVisible(YES);
            } else {
                self.alpha = 1.0f;
                self.transform = CGAffineTransformIdentity;
                self.hidden = NO;
                tj_setNowPlayingImmersiveVisible(NO);
            }
        }
    }
}

%end

%hook _TtC16MusicApplication24NowPlayingViewController

- (void)viewDidLayoutSubviews {
    %orig;
    @try {
        UIViewController *ctrl = [self valueForKey:@"controlsViewController"];
        if (ctrl) {
            sActiveNowPlayingControlsVC = ctrl;
        }
    } @catch (__unused id e) {}
    id playingItem = tj_extractPlayingItem(self);
    if (prefBool(@"enabled", YES) && prefBool(@"immersiveNowPlaying", YES)) {
        BOOL isCollapsed = tj_isNowPlayingLyricsOrQueueActiveWithView(self.view, (UIViewController *)self);
        UIView *cv = tj_findNowPlayingContentView(self.view);
        if (cv) tj_setActiveNowPlayingContentView(cv);

        if (tj_isNowPlayingItemMusicVideo(playingItem, cv, (UIViewController *)self)) {
            tj_setNowPlayingImmersiveVisible(NO);
            if (cv) {
                cv.alpha = 1.0f;
                cv.hidden = NO;
            }
            return;
        }

        if (isCollapsed) {
            tj_setNowPlayingImmersiveVisible(NO);
            if (cv) {
                cv.alpha = 1.0f;
                cv.hidden = NO;
            }
        } else {
            UIView *container = tj_activeNowPlayingArtworkContainer();
            if (container) {
                if (playingItem) {
                    NSString *curTrack = tj_itemTrackKey(playingItem);
                    NSString *activeTrack = tj_currentActiveTrackIdentity();
                    BOOL trackChanged = (!activeTrack || (curTrack && ![curTrack isEqualToString:activeTrack]));
                    if (trackChanged) {
                        tj_setCurrentActiveTrackIdentity(curTrack);
                        tj_transitionToSquaredLayout(NO);
                        tj_requestHighResArtworkForItem(playingItem);
                        tj_updateNowPlayingMotionArtwork(container, playingItem);
                    } else {
                        if (tj_isMotionArtworkReadyForDisplay()) {
                            tj_setNowPlayingImmersiveVisible(YES);
                            if (cv && cv.bounds.size.width >= 160.0f && tj_isFullScreenTransitionComplete()) {
                                cv.alpha = 0.0f;
                            }
                        }
                    }
                    tj_resumeMotionArtwork(container);
                }
            }
        }
    }
}

%end

static BOOL tj_isViewExcludedTrait(UIView * _Nullable v) {
    if (!v) return YES;
    if ([v isKindOfClass:[TJLastFmBadgeView class]]) return YES;
    NSString *cls = NSStringFromClass(v.class);
    if ([cls containsString:@"TJLastFm"]) return YES;
    if ([cls containsString:@"Slider"] || [v isKindOfClass:[UISlider class]]) return YES;
    return NO;
}

static UIView * _Nullable tj_searchHierarchyForTrait(UIView * _Nullable root, int depth) {
    if (!root || depth > 4) return nil;
    for (UIView *sub in root.subviews) {
        if (sub.hidden || sub.alpha < 0.05f) continue;
        if (tj_isViewExcludedTrait(sub)) continue;

        NSString *cls = NSStringFromClass(sub.class);
        if ([cls containsString:@"Trait"] || [cls containsString:@"Quality"] || [cls containsString:@"AudioBadge"] || [cls containsString:@"FormatIndicator"]) {
            return sub;
        }
        if ([cls containsString:@"Badge"] && ![cls containsString:@"TJLastFm"]) {
            return sub;
        }

        if ([sub isKindOfClass:[UIButton class]] || [sub isKindOfClass:[UIControl class]]) {
            if (![cls containsString:@"Chevron"] && ![cls containsString:@"Route"] && ![cls containsString:@"Transport"] && ![cls containsString:@"Volume"] && ![cls containsString:@"Button"]) {
                CGFloat w = sub.bounds.size.width;
                CGFloat h = sub.bounds.size.height;
                if (w >= 20.0f && w <= 180.0f && h >= 12.0f && h <= 32.0f) {
                    return sub;
                }
            }
        }

        UIView *found = tj_searchHierarchyForTrait(sub, depth + 1);
        if (found) return found;
    }
    return nil;
}

static UIView * _Nullable tj_findAudioTraitView(UIViewController * _Nullable vc) {
    if (!vc || !vc.isViewLoaded) return nil;

    for (NSString *k in @[@"audioTraitButton", @"playingItemAudioTraitButton", @"traitButton", @"audioQualityButton", @"audioTraitsButton", @"badgeButton"]) {
        @try {
            id v = [vc valueForKey:k];
            if ([v isKindOfClass:[UIView class]] && !tj_isViewExcludedTrait((UIView *)v) && [(UIView *)v superview] && ![(UIView *)v isHidden] && [(UIView *)v alpha] > 0.05f) {
                return (UIView *)v;
            }
        } @catch (__unused id e) {}
    }

    UIView *timeControl = nil;
    timeControl = tj_probedValueForKey(vc, @"timeControl", &sTimeControlProbe);
    if (timeControl) {
        for (NSString *k in @[@"audioTraitButton", @"playingItemAudioTraitButton", @"traitButton", @"audioQualityButton", @"audioTraitsButton", @"badgeButton", @"traitControl", @"badgeView"]) {
            @try {
                id v = [timeControl valueForKey:k];
                if ([v isKindOfClass:[UIView class]] && !tj_isViewExcludedTrait((UIView *)v) && [(UIView *)v superview] && ![(UIView *)v isHidden] && [(UIView *)v alpha] > 0.05f) {
                    return (UIView *)v;
                }
            } @catch (__unused id e) {}
        }

        UIView *foundInTimeControl = tj_searchHierarchyForTrait(timeControl, 0);
        if (foundInTimeControl) return foundInTimeControl;

        for (UIView *sub in timeControl.subviews) {
            if (sub.hidden || sub.alpha < 0.05f || tj_isViewExcludedTrait(sub)) continue;
            if ([sub isKindOfClass:[UILabel class]]) {
                UILabel *lbl = (UILabel *)sub;
                if (lbl.text && ([lbl.text containsString:@":"] || [lbl.text containsString:@"-"])) continue;
            }
            CGFloat w = sub.bounds.size.width;
            CGFloat h = sub.bounds.size.height;
            if (w >= 20.0f && w <= 180.0f && h >= 12.0f && h <= 32.0f) {
                return sub;
            }
        }
    }

    UIView *foundInVC = tj_searchHierarchyForTrait(vc.view, 0);
    if (foundInVC) return foundInVC;

    return nil;
}

%hook MusicNowPlayingControlsViewController

- (void)viewDidLoad {
    %orig;
    if (prefBool(@"enabled", YES) && prefBool(@"immersiveNowPlaying", YES)) {
        tj_getOrCreateFullBleedArtworkView((UIViewController *)self);
    }
    if (prefBool(@"enabled", YES) && prefBool(@"lastFmEnabled", YES) && prefBool(@"lastFmShowBadge", YES)) {
        TJLastFmBadgeView *badge = [TJLastFmBadgeView badgeView];
        badge.hidden = YES;
        objc_setAssociatedObject(self, kTJLastFmBadgeKey, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sActiveNowPlayingControlsVC = self;
    id playingItem = tj_extractPlayingItem(self);
    if (prefBool(@"enabled", YES) && prefBool(@"immersiveNowPlaying", YES)) {
        BOOL isCollapsed = tj_isNowPlayingLyricsOrQueueActiveWithView(self.view, (UIViewController *)self);
        UIView *contentView = tj_findNowPlayingContentView(self.view);
        if (!contentView && [self respondsToSelector:@selector(parentViewController)]) {
            UIViewController *p = [self parentViewController];
            if (p && p.isViewLoaded) {
                contentView = tj_findNowPlayingContentView(p.view);
            }
        }
        if (!contentView) {
            contentView = tj_activeNowPlayingContentView();
        }
        if (contentView) tj_setActiveNowPlayingContentView(contentView);

        if (tj_isNowPlayingItemMusicVideo(playingItem, contentView, (UIViewController *)self)) {
            tj_setNowPlayingImmersiveVisible(NO);
            if (contentView) {
                contentView.alpha = 1.0f;
                contentView.hidden = NO;
            }
            return;
        }

        if (isCollapsed) {
            tj_setNowPlayingImmersiveVisible(NO);
            if (contentView) {
                contentView.alpha = 1.0f;
                contentView.hidden = NO;
            }
        } else {
            tj_layoutFullBleedArtwork((UIViewController *)self);
            UIView *container = tj_getOrCreateFullBleedArtworkView((UIViewController *)self);

            if (playingItem) {
                NSString *curTrack = tj_itemTrackKey(playingItem);
                NSString *activeTrack = tj_currentActiveTrackIdentity();
                BOOL trackChanged = (!activeTrack || (curTrack && ![curTrack isEqualToString:activeTrack]));
                if (trackChanged) {
                    tj_setCurrentActiveTrackIdentity(curTrack);
                    tj_transitionToSquaredLayout(NO);
                    tj_requestHighResArtworkForItem(playingItem);
                    if (container) tj_updateNowPlayingMotionArtwork(container, playingItem);
                } else {
                    if (tj_isMotionArtworkReadyForDisplay()) {
                        tj_setNowPlayingImmersiveVisible(YES);
                        if (contentView && contentView.bounds.size.width >= 160.0f) {
                            contentView.alpha = 0.0f;
                        }
                    }
                    if (container) {
                        tj_resumeMotionArtwork(container);
                    }
                }
            }

            if (tj_isMotionArtworkReadyForDisplay()) {
                if (contentView && contentView.bounds.size.width >= 160.0f) {
                    contentView.alpha = 0.0f;
                }
                tj_setNowPlayingImmersiveVisible(YES);
            } else {
                if (contentView) {
                    contentView.alpha = 1.0f;
                    contentView.hidden = NO;
                }
                tj_setNowPlayingImmersiveVisible(NO);
            }
            if (container) {
                tj_resumeMotionArtwork(container);
            }
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sActiveNowPlayingControlsVC = self;
    if (prefBool(@"enabled", YES) && prefBool(@"immersiveNowPlaying", YES) && tj_isMotionArtworkReadyForDisplay()) {
        tj_resumeMotionArtwork(tj_activeNowPlayingArtworkContainer());
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    sActiveNowPlayingControlsVC = self;
    id playingItem = tj_extractPlayingItem(self);
    if (prefBool(@"enabled", YES) && prefBool(@"immersiveNowPlaying", YES)) {
        BOOL isCollapsed = tj_isNowPlayingLyricsOrQueueActiveWithView(self.view, (UIViewController *)self);
        UIView *contentView = tj_findNowPlayingContentView(self.view);
        if (!contentView && [self respondsToSelector:@selector(parentViewController)]) {
            UIViewController *p = [self parentViewController];
            if (p && p.isViewLoaded) {
                contentView = tj_findNowPlayingContentView(p.view);
            }
        }
        if (!contentView) {
            contentView = tj_activeNowPlayingContentView();
        }
        if (contentView) tj_setActiveNowPlayingContentView(contentView);

        if (tj_isNowPlayingItemMusicVideo(playingItem, contentView, (UIViewController *)self)) {
            tj_setNowPlayingImmersiveVisible(NO);
            if (contentView) {
                contentView.alpha = 1.0f;
                contentView.hidden = NO;
            }
            return;
        }

        if (isCollapsed) {
            tj_setNowPlayingImmersiveVisible(NO);
            if (contentView) {
                contentView.alpha = 1.0f;
                contentView.hidden = NO;
            }
        } else {
            tj_layoutFullBleedArtwork((UIViewController *)self);
            UIView *container = tj_getOrCreateFullBleedArtworkView((UIViewController *)self);

            if (playingItem) {
                NSString *curTrack = tj_itemTrackKey(playingItem);
                NSString *activeTrack = tj_currentActiveTrackIdentity();
                BOOL trackChanged = (!activeTrack || (curTrack && ![curTrack isEqualToString:activeTrack]));
                if (trackChanged) {
                    tj_setCurrentActiveTrackIdentity(curTrack);
                    tj_transitionToSquaredLayout(NO);
                    tj_requestHighResArtworkForItem(playingItem);
                    if (container) tj_updateNowPlayingMotionArtwork(container, playingItem);
                } else {
                    if (tj_isMotionArtworkReadyForDisplay()) {
                        tj_setNowPlayingImmersiveVisible(YES);
                        if (contentView && contentView.bounds.size.width >= 160.0f) {
                            contentView.alpha = 0.0f;
                        }
                    }
                    if (container) {
                        tj_resumeMotionArtwork(container);
                    }
                }
            }

            if (tj_isMotionArtworkReadyForDisplay()) {
                if (contentView && contentView.bounds.size.width >= 160.0f) {
                    contentView.alpha = 0.0f;
                }
                tj_setNowPlayingImmersiveVisible(YES);
            } else {
                if (contentView) {
                    contentView.alpha = 1.0f;
                    contentView.hidden = NO;
                }
                tj_setNowPlayingImmersiveVisible(NO);
            }
            if (container) {
                tj_resumeMotionArtwork(container);
            }
        }
    }

    if (prefBool(@"enabled", YES) && prefBool(@"lastFmEnabled", YES) && prefBool(@"lastFmShowBadge", YES)) {
        TJLastFmBadgeView *badge = objc_getAssociatedObject(self, kTJLastFmBadgeKey);
        if (!badge) {
            badge = [TJLastFmBadgeView badgeView];
            objc_setAssociatedObject(self, kTJLastFmBadgeKey, badge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        [badge refreshDisplayAnimated:NO];

        UIButton *artistButton = nil;
        artistButton = tj_probedValueForKey(self, @"subtitleButton", &sSubtitleButtonProbe);

        UIView *artistMarquee = nil;
        @try {
            Ivar subIv = class_getInstanceVariable([self class], "subtitleMarqueeView");
            if (subIv) artistMarquee = object_getIvar(self, subIv);
        } @catch (__unused id e) {}
        if (!artistMarquee && artistButton && artistButton.superview && artistButton.superview != self.view) {
            artistMarquee = artistButton.superview;
        }

        UIView *titleView = nil;
        @try {
            Ivar titleIv = class_getInstanceVariable([self class], "titleMarqueeView");
            if (titleIv) titleView = object_getIvar(self, titleIv);
        } @catch (__unused id e) {}
        if (!titleView) {
            @try { titleView = [self valueForKey:@"titleMarqueeView"]; } @catch (__unused id e) {}
        }
        if (!titleView) {
            titleView = tj_probedValueForKey(self, @"titleLabel", &sTitleLabelProbe);
        }

        UIView *topContainer = nil;
        @try {
            Ivar topIv = class_getInstanceVariable([self class], "topContainerView");
            if (topIv) topContainer = object_getIvar(self, topIv);
        } @catch (__unused id e) {}
        if (!topContainer && artistMarquee && artistMarquee.superview) {
            topContainer = artistMarquee.superview;
        }
        if (!topContainer && titleView && titleView.superview) {
            topContainer = titleView.superview;
        }
        if (!topContainer && artistButton && artistButton.superview) {
            topContainer = artistButton.superview;
        }
        if (!topContainer) {
            topContainer = self.view;
        }

        UIView *artistContainer = (artistMarquee && artistMarquee != topContainer) ? artistMarquee : (artistButton ?: artistMarquee);

        if (topContainer && badge.superview != topContainer) {
            [badge removeFromSuperview];
            [topContainer addSubview:badge];
        }

        if (artistButton) {
            artistButton.transform = CGAffineTransformIdentity;
        }
        if (artistContainer) {
            artistContainer.transform = CGAffineTransformIdentity;
        }

        UIView *traitView = nil;
        traitView = tj_probedValueForKey(self, @"playingItemAudioTraitButton", &sAudioTraitButtonProbe);
        if (!traitView) {
            traitView = tj_findAudioTraitView((UIViewController *)self);
        }
        if (traitView) {
            traitView.transform = CGAffineTransformIdentity;
            [badge matchNativeTraitView:traitView];
        }

        BOOL isCollapsed = tj_isNowPlayingLyricsOrQueueActiveWithView(self.view, (UIViewController *)self);
        if (!isCollapsed && artistButton && artistButton.titleLabel.font.pointSize > 0.0f && artistButton.titleLabel.font.pointSize < 16.0f) {
            isCollapsed = YES;
        }
        if (!isCollapsed && artistContainer && artistContainer.frame.size.height > 0.0f && artistContainer.frame.size.height < 20.0f) {
            isCollapsed = YES;
        }

        if (isCollapsed) {
            badge.compactMode = YES;
            if (artistContainer && topContainer && !badge.hidden) {
                CGFloat badgeH = 15.0f;
                CGSize badgeSize = [badge sizeThatFits:CGSizeMake(0, badgeH)];
                CGFloat badgeW = badgeSize.width;
                if (badgeW < 28.0f) badgeW = 36.0f;
                CGFloat gap = 7.0f;

                CGFloat textLeadingX = 0.0f;
                UILabel *tl = nil;
                tl = tj_probedValueForKey(self, @"titleLabel", &sTitleLabelProbe);
                if (tl && topContainer) {
                    @try {
                        CGRect r = [tl convertRect:tl.bounds toView:topContainer];
                        if (r.origin.x > 0.0f && r.origin.x < topContainer.bounds.size.width) {
                            textLeadingX = r.origin.x;
                        }
                    } @catch (__unused id e) {}
                }
                if (textLeadingX <= 0.0f && titleView && topContainer) {
                    @try {
                        CGRect r = [titleView convertRect:titleView.bounds toView:topContainer];
                        if (r.origin.x > 0.0f && r.origin.x < topContainer.bounds.size.width) {
                            textLeadingX = r.origin.x;
                        }
                    } @catch (__unused id e) {}
                }
                if (textLeadingX < 14.0f) {
                    textLeadingX = 14.0f;
                }

                CGFloat leadingX = textLeadingX;

                CGFloat origY = artistContainer.frame.origin.y;
                CGFloat origH = artistContainer.frame.size.height > 0.0f ? artistContainer.frame.size.height : 16.0f;
                if (origY <= 0.0f && titleView && titleView.frame.origin.y > 0.0f) {
                    origY = titleView.frame.origin.y + titleView.frame.size.height + 2.0f;
                }
                CGFloat badgeY = origY + (origH - badgeH) / 2.0f;

                badge.transform = CGAffineTransformIdentity;
                badge.frame = CGRectMake(leadingX, badgeY, badgeW, badgeH);

                CGFloat shift = badgeW + gap;
                artistContainer.transform = CGAffineTransformMakeTranslation(shift, 0.0f);

                [topContainer bringSubviewToFront:badge];
                UIView *ctxBtn = nil;
                ctxBtn = tj_probedValueForKey(self, @"contextButton", &sContextButtonProbe);
                if (ctxBtn) {
                    [topContainer bringSubviewToFront:ctxBtn];
                }
            } else {
                if (artistContainer) {
                    artistContainer.transform = CGAffineTransformIdentity;
                }
            }
        } else {
            badge.compactMode = NO;
            if (artistContainer && topContainer && !badge.hidden) {
                CGFloat badgeH = 18.0f;
                CGSize badgeSize = [badge sizeThatFits:CGSizeMake(0, badgeH)];
                CGFloat badgeW = badgeSize.width;
                if (badgeW < 36.0f) badgeW = 48.0f;
                CGFloat gap = 6.0f;

                CGFloat leadingX = 24.0f;
                if (artistContainer.superview == topContainer && artistContainer.frame.origin.x > 0.0f) {
                    leadingX = artistContainer.frame.origin.x;
                } else if (titleView && titleView.superview == topContainer && titleView.frame.origin.x > 0.0f) {
                    leadingX = titleView.frame.origin.x;
                }

                CGFloat origY = artistContainer.frame.origin.y;
                CGFloat origH = artistContainer.frame.size.height > 0.0f ? artistContainer.frame.size.height : 24.0f;
                if (origY <= 0.0f && titleView && titleView.frame.origin.y > 0.0f) {
                    origY = titleView.frame.origin.y + titleView.frame.size.height + 4.0f;
                }
                CGFloat badgeY = origY + (origH - badgeH) / 2.0f;

                badge.transform = CGAffineTransformIdentity;
                badge.frame = CGRectMake(leadingX, badgeY, badgeW, badgeH);

                CGFloat shift = badgeW + gap;
                artistContainer.transform = CGAffineTransformMakeTranslation(shift, 0.0f);

                [topContainer bringSubviewToFront:badge];
                UIView *ctxBtn = nil;
                ctxBtn = tj_probedValueForKey(self, @"contextButton", &sContextButtonProbe);
                if (ctxBtn) {
                    [topContainer bringSubviewToFront:ctxBtn];
                }
            } else {
                if (artistContainer) {
                    artistContainer.transform = CGAffineTransformIdentity;
                }
            }
        }
    } else {
        TJLastFmBadgeView *badge = objc_getAssociatedObject(self, kTJLastFmBadgeKey);
        if (badge) {
            badge.hidden = YES;
        }
        UIButton *artistButton = nil;
        artistButton = tj_probedValueForKey(self, @"subtitleButton", &sSubtitleButtonProbe);
        if (artistButton) {
            artistButton.transform = CGAffineTransformIdentity;
            if (artistButton.superview) {
                artistButton.superview.transform = CGAffineTransformIdentity;
            }
        }
        UIView *artistMarquee = nil;
        @try {
            Ivar subIv = class_getInstanceVariable([self class], "subtitleMarqueeView");
            if (subIv) artistMarquee = object_getIvar(self, subIv);
        } @catch (__unused id e) {}
        if (artistMarquee) {
            artistMarquee.transform = CGAffineTransformIdentity;
        }
        UIView *traitView = nil;
        traitView = tj_probedValueForKey(self, @"playingItemAudioTraitButton", &sAudioTraitButtonProbe);
        if (!traitView) {
            traitView = tj_findAudioTraitView((UIViewController *)self);
        }
        if (traitView) {
            traitView.transform = CGAffineTransformIdentity;
        }
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    TJLastFmBadgeView *badge = objc_getAssociatedObject(self, kTJLastFmBadgeKey);
    if (badge) {
        badge.hidden = YES;
    }
    UIButton *artistButton = nil;
    artistButton = tj_probedValueForKey(self, @"subtitleButton", &sSubtitleButtonProbe);
    if (artistButton) {
        artistButton.transform = CGAffineTransformIdentity;
        if (artistButton.superview) {
            artistButton.superview.transform = CGAffineTransformIdentity;
        }
    }
    UIView *artistMarquee = nil;
    @try {
        Ivar subIv = class_getInstanceVariable([self class], "subtitleMarqueeView");
        if (subIv) artistMarquee = object_getIvar(self, subIv);
    } @catch (__unused id e) {}
    if (artistMarquee) {
        artistMarquee.transform = CGAffineTransformIdentity;
    }
    UIView *traitView = nil;
    traitView = tj_probedValueForKey(self, @"playingItemAudioTraitButton", &sAudioTraitButtonProbe);
    if (traitView) {
        traitView.transform = CGAffineTransformIdentity;
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    tj_pauseAllMotionArtwork();
}

%end

%hook _TtC16MusicApplication24MiniPlayerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sActiveMiniPlayerVC = (UIViewController *)self;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    sActiveMiniPlayerVC = (UIViewController *)self;
}

- (void)viewDidLayoutSubviews {
    %orig;
    sActiveMiniPlayerVC = (UIViewController *)self;
}

%end
