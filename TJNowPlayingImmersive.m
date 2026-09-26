#import "TJNowPlayingImmersive.h"
#import "TJModelUtils.h"
#import "TJMotionArtworkResolver.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

static void *kTJNowPlayingPlayerLayerKey = &kTJNowPlayingPlayerLayerKey;
static void *kTJNowPlayingQueuePlayerKey = &kTJNowPlayingQueuePlayerKey;
static void *kTJNowPlayingCurrentAssetKey = &kTJNowPlayingCurrentAssetKey;
static void *kTJNowPlayingObserverRegisteredKey = &kTJNowPlayingObserverRegisteredKey;
static void *kTJNowPlayingCurrentLookupIDKey = &kTJNowPlayingCurrentLookupIDKey;
static void *kTJFullBleedArtworkViewKey = &kTJFullBleedArtworkViewKey;
static void *kTJInFlightFetchKey = &kTJInFlightFetchKey;
static void *kTJLastPlayingLookupIDKey = &kTJLastPlayingLookupIDKey;
static void *kTJPlayerLayerObserverKey = &kTJPlayerLayerObserverKey;
static void *kTJPlayToEndObserverKey = &kTJPlayToEndObserverKey;
static void *kTJStallObserverKey = &kTJStallObserverKey;
static void *kTJNowPlayingLooperKey = &kTJNowPlayingLooperKey;

static UIView *sActiveFullScreenArtworkContainer = nil;
static __weak UIView *sActiveNowPlayingContentView = nil;
static UIImage *sLatestArtworkImage = nil;
static NSString *sLatestArtworkAdamID = nil;
static NSString *sCurrentActiveTrackIdentity = nil;
static BOOL sIsMotionCanvasReadyForDisplay = NO;
static BOOL sIsFullScreenTransitionComplete = NO;
static BOOL sIsMusicPlayingForMotion = NO;
static BOOL sMotionPlaybackObserverRegistered = NO;
static NSMutableSet<NSString *> *sResolvedMasterURLs = nil;
static NSMutableSet<NSString *> *sResolvingMasterURLs = nil;
static NSMutableSet<NSString *> *sLooperFailedURLs = nil;

void tj_setActiveNowPlayingContentView(UIView * _Nullable cv) { sActiveNowPlayingContentView = cv; }
UIView * _Nullable tj_activeNowPlayingContentView(void) { return sActiveNowPlayingContentView; }
NSString * _Nullable tj_currentActiveTrackIdentity(void) { return sCurrentActiveTrackIdentity; }
void tj_setCurrentActiveTrackIdentity(NSString * _Nullable k) { sCurrentActiveTrackIdentity = [k copy]; }
BOOL tj_isMotionArtworkReadyForDisplay(void) { return sIsMotionCanvasReadyForDisplay; }
BOOL tj_isFullScreenTransitionComplete(void) { return sIsFullScreenTransitionComplete; }
UIView * _Nullable tj_activeNowPlayingArtworkContainer(void) { return sActiveFullScreenArtworkContainer; }

static BOOL tj_musicIsForeground(UIView * _Nullable container) {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) return NO;
    UIWindowScene *scene = container.window.windowScene;
    if (scene && scene.activationState != UISceneActivationStateForegroundActive) return NO;
    return YES;
}

BOOL tj_motionArtworkShouldPlay(UIView * _Nullable contentView) {
    if (!prefBool(@"enabled", YES) || !prefBool(@"immersiveMotionArtwork", YES)) return NO;
    if ([NSProcessInfo processInfo].isLowPowerModeEnabled) return NO;
    if (!sIsMusicPlayingForMotion) return NO;
    UIView *container = contentView ?: sActiveFullScreenArtworkContainer;
    if (!container || !container.window || container.isHidden || container.alpha <= 0.01f) return NO;
    if (!tj_musicIsForeground(container)) return NO;
    return YES;
}

static void tj_disableAudioTracks(AVPlayerItem * _Nullable item) {
    if (!item) return;
    for (AVPlayerItemTrack *t in item.tracks) {
        if ([t.assetTrack.mediaType isEqualToString:AVMediaTypeAudio] && t.enabled) t.enabled = NO;
    }
}

typedef void (*TJMRRegisterFunc)(dispatch_queue_t);

typedef void (*TJMRGetIsPlayingFunc)(dispatch_queue_t, void (^)(Boolean isPlaying));

static void tj_ensureMotionPlaybackObserverRegistered(void) {
    if (sMotionPlaybackObserverRegistered) return;
    sMotionPlaybackObserverRegistered = YES;

    TJMRRegisterFunc regFunc = (TJMRRegisterFunc)dlsym(RTLD_DEFAULT, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (regFunc) regFunc(dispatch_get_main_queue());

    TJMRGetIsPlayingFunc getIsPlaying = (TJMRGetIsPlayingFunc)dlsym(RTLD_DEFAULT, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if (getIsPlaying) {
        getIsPlaying(dispatch_get_main_queue(), ^(Boolean isPlaying) {
            sIsMusicPlayingForMotion = isPlaying;
            if (isPlaying) tj_resumeMotionArtwork(sActiveFullScreenArtworkContainer);
        });
    } else {
        sIsMusicPlayingForMotion = YES;
    }

    void (^onPauseLike)(void) = ^{
        if (!sIsMusicPlayingForMotion) {
            tj_pauseAllMotionArtwork();
        }
    };

    [[NSNotificationCenter defaultCenter] addObserverForName:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        NSNumber *val = note.userInfo[@"kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey"];
        if (val) { sIsMusicPlayingForMotion = val.boolValue; onPauseLike(); }
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:@"kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification"
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        NSNumber *stNum = note.userInfo[@"kMRMediaRemotePlaybackStateUserInfoKey"];
        if (stNum) { sIsMusicPlayingForMotion = (stNum.integerValue == 1); onPauseLike(); }
    }];
    for (NSString *name in @[UIApplicationWillResignActiveNotification, UIApplicationDidEnterBackgroundNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            UIView *views[2] = { sActiveFullScreenArtworkContainer, sActiveNowPlayingContentView };
            for (int i = 0; i < 2; i++) {
                if (!views[i]) continue;
                AVPlayer *ours = objc_getAssociatedObject(views[i], kTJNowPlayingQueuePlayerKey);
                if (ours.rate != 0.0f) [ours pause];
            }
        }];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                                                      object:nil queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if ([NSProcessInfo processInfo].isLowPowerModeEnabled) {
            tj_pauseAllMotionArtwork();
        }
    }];
}

static CGRect tj_targetBounds(void) {
    CGSize sz = [UIScreen mainScreen].bounds.size;
    CGFloat w = sz.width > 0 ? sz.width : 390.0f;
    CGFloat h = ceil((sz.height > 0 ? sz.height : 844.0f) * 0.68f);
    return CGRectMake(0, 0, w, h);
}

static UIView * _Nullable tj_findContentView(UIView * _Nullable root) {
    if (!root) return nil;
    if ([NSStringFromClass(root.class) containsString:@"NowPlayingContentView"]) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = tj_findContentView(sub);
        if (found) return found;
    }
    return nil;
}

void tj_transitionToFullScreenMotionIfReady(void) {
    if (!sIsMotionCanvasReadyForDisplay || tj_isNowPlayingItemMusicVideo(nil, nil, nil)) return;
    UIView *container = sActiveFullScreenArtworkContainer;
    if (!container) return;
    UIView *cv = sActiveNowPlayingContentView ?: (container.superview ? tj_findContentView(container.superview) : nil);
    if (cv) sActiveNowPlayingContentView = cv;
    if (tj_isNowPlayingLyricsOrQueueActiveWithView(cv ?: container, nil)) return;
    if (sIsFullScreenTransitionComplete && container.alpha >= 0.99f && (!cv || cv.alpha <= 0.01f)) return;

    container.hidden = NO;
    if (cv) {
        cv.hidden = NO;
        if (cv.alpha < 0.1f) cv.alpha = 1.0f;
        cv.transform = CGAffineTransformIdentity;
        if (cv.superview) cv.superview.clipsToBounds = NO;
    }

    [UIView animateWithDuration:0.32 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        container.alpha = 1.0f;
        if (cv) {
            cv.alpha = 0.0f;
            cv.transform = CGAffineTransformMakeScale(1.18f, 1.18f);
        }
    } completion:^(BOOL finished) {
        if (finished) {
            sIsFullScreenTransitionComplete = YES;
            if (cv && cv.alpha <= 0.01f) {
                cv.transform = CGAffineTransformIdentity;
            }
        }
    }];
}

void tj_transitionToSquaredLayout(BOOL animated) {
    sIsMotionCanvasReadyForDisplay = NO;
    sIsFullScreenTransitionComplete = NO;
    UIView *container = sActiveFullScreenArtworkContainer;
    UIView *cv = sActiveNowPlayingContentView ?: (container.superview ? tj_findContentView(container.superview) : nil);
    if (cv) sActiveNowPlayingContentView = cv;

    if (!animated) {
        if (container) { container.alpha = 0.0f; container.hidden = YES; }
        if (cv) {
            [cv.layer removeAllAnimations];
            cv.hidden = NO;
            cv.alpha = 1.0f;
            cv.transform = CGAffineTransformIdentity;
        }
        return;
    }
    if (cv) {
        [cv.layer removeAllAnimations];
        cv.hidden = NO;
        cv.transform = CGAffineTransformMakeScale(1.10f, 1.10f);
        cv.alpha = 0.0f;
    }
    [UIView animateWithDuration:0.24 delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction animations:^{
        if (container) container.alpha = 0.0f;
        if (cv) {
            cv.alpha = 1.0f;
            cv.transform = CGAffineTransformIdentity;
        }
    } completion:^(BOOL finished) {
        if (finished && container && container.alpha == 0.0f) container.hidden = YES;
    }];
}

@interface TJPlayerLayerObserver : NSObject
@property (nonatomic, weak) AVPlayerLayer *playerLayer;
@property (nonatomic, weak) AVPlayer *player;
@property (nonatomic, weak) AVPlayerItem *playerItem;
@property (nonatomic, assign) BOOL isObserving;
@property (nonatomic, assign) BOOL isSeeking;
@property (nonatomic, strong) AVPlayerLooper *looper;
@property (nonatomic, copy) void (^onLooperFailed)(void);
- (void)startObservingLayer:(AVPlayerLayer *)layer player:(AVPlayer *)player item:(AVPlayerItem *)item;
- (void)observeLooper:(AVPlayerLooper *)looper;
- (void)stopObserving;
@end

@implementation TJPlayerLayerObserver
- (void)startObservingLayer:(AVPlayerLayer *)layer player:(AVPlayer *)player item:(AVPlayerItem *)item {
    if (_isObserving) return;
    _playerLayer = layer; _player = player; _playerItem = item;
    _isObserving = YES; _isSeeking = NO;
    @try { [layer addObserver:self forKeyPath:@"readyForDisplay" options:NSKeyValueObservingOptionNew context:nil]; } @catch (__unused id e) {}
    @try { [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil]; } @catch (__unused id e) {}
    @try { [player addObserver:self forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew context:nil]; } @catch (__unused id e) {}
}

- (void)observeLooper:(AVPlayerLooper *)looper {
    if (!_isObserving || !looper || _looper) return;
    _looper = looper;
    @try { [looper addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil]; } @catch (__unused id e) {}
}

- (void)stopObserving {
    if (!_isObserving) return;
    if (_playerLayer) { @try { [_playerLayer removeObserver:self forKeyPath:@"readyForDisplay"]; } @catch (__unused id e) {} }
    if (_playerItem) { @try { [_playerItem removeObserver:self forKeyPath:@"status"]; } @catch (__unused id e) {} }
    if (_player) { @try { [_player removeObserver:self forKeyPath:@"timeControlStatus"]; } @catch (__unused id e) {} }
    if (_looper) { @try { [_looper removeObserver:self forKeyPath:@"status"]; } @catch (__unused id e) {} }
    _isObserving = NO; _playerLayer = nil; _playerItem = nil; _player = nil; _looper = nil; _onLooperFailed = nil;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    AVPlayerLayer *layer = _playerLayer;
    AVPlayer *p = _player;
    if ([keyPath isEqualToString:@"readyForDisplay"] && layer && layer.isReadyForDisplay) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [CATransaction begin];
            [CATransaction setAnimationDuration:0.20];
            layer.opacity = 1.0f;
            [CATransaction commit];
            sIsMotionCanvasReadyForDisplay = YES;
            tj_transitionToFullScreenMotionIfReady();
            tj_disableAudioTracks(p.currentItem);
            if (p && p.rate == 0.0f && tj_motionArtworkShouldPlay(nil)) {
                [p play];
            }
        });
    } else if ([keyPath isEqualToString:@"status"] && object == _looper) {
        if (_looper.status == AVPlayerLooperStatusFailed && _onLooperFailed) {
            void (^cb)(void) = _onLooperFailed;
            _onLooperFailed = nil;
            dispatch_async(dispatch_get_main_queue(), cb);
        }
    } else if ([keyPath isEqualToString:@"status"]) {
        if (_playerItem && _playerItem.status == AVPlayerItemStatusReadyToPlay) {
            dispatch_async(dispatch_get_main_queue(), ^{
                tj_disableAudioTracks(p.currentItem);
                if (p && p.rate == 0.0f && tj_motionArtworkShouldPlay(nil)) {
                    [p play];
                }
            });
        }
    } else if ([keyPath isEqualToString:@"timeControlStatus"]) {
        if (p && p.timeControlStatus == AVPlayerTimeControlStatusPaused && layer && !layer.hidden && layer.opacity > 0.0f && tj_motionArtworkShouldPlay(nil)) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (p.timeControlStatus == AVPlayerTimeControlStatusPaused && tj_motionArtworkShouldPlay(nil)) {
                    tj_disableAudioTracks(p.currentItem);
                    [p play];
                }
            });
        }
    }
}
- (void)dealloc { [self stopObserving]; }
@end

#pragma mark - Helper: Lyrics and Queue State

static BOOL tj_isVCOnScreen(UIViewController * _Nullable vc) {
    if (!vc || ![vc isViewLoaded]) return NO;
    UIView *v = nil;
    @try { v = vc.view; } @catch (__unused id e) { return NO; }
    if (!v || !v.window || v.hidden || v.alpha < 0.1f) return NO;
    CGRect r = [v convertRect:v.bounds toView:nil];
    return (r.size.height > 150.0f && CGRectGetMidX(r) >= 0.0f && CGRectGetMidX(r) <= [UIScreen mainScreen].bounds.size.width);
}

static BOOL tj_checkHierarchyForLyricsOrQueue(UIViewController * _Nullable vc) {
    if (!vc) return NO;
    NSString *cls = NSStringFromClass(vc.class);
    if (([cls containsString:@"Lyrics"] || [cls containsString:@"Queue"]) && tj_isVCOnScreen(vc)) return YES;
    for (UIViewController *child in vc.childViewControllers) {
        if (tj_checkHierarchyForLyricsOrQueue(child)) return YES;
    }
    return vc.presentedViewController ? tj_checkHierarchyForLyricsOrQueue(vc.presentedViewController) : NO;
}

static UIViewController * _Nullable tj_searchVC(UIViewController * _Nullable root, NSString *name) {
    if (!root) return nil;
    if ([NSStringFromClass(root.class) containsString:name]) return root;
    for (UIViewController *child in root.childViewControllers) {
        UIViewController *f = tj_searchVC(child, name);
        if (f) return f;
    }
    return root.presentedViewController ? tj_searchVC(root.presentedViewController, name) : nil;
}

static BOOL tj_isToggleButtonSelected(UIView * _Nullable btn, NSString *id1, NSString *id2) {
    if (!btn || ![btn isKindOfClass:[UIView class]]) return NO;
    if ([btn respondsToSelector:@selector(isSelected)] && [(UIControl *)btn isSelected]) return YES;
    if (btn.accessibilityTraits & UIAccessibilityTraitSelected) return YES;
    NSString *ident = [btn accessibilityIdentifier];
    if (ident && ([ident containsString:id1] || [ident containsString:id2])) return YES;
    NSString *val = [btn accessibilityValue];
    if (val && ([val isEqualToString:@"1"] || [[val lowercaseString] containsString:@"selected"] || [[val lowercaseString] containsString:@"on"])) return YES;
    for (UIView *sub in btn.subviews) {
        if ([sub isKindOfClass:[UIImageView class]]) {
            NSString *desc = [[(UIImageView *)sub image] description];
            if ([desc containsString:id1] || [desc containsString:id2]) return YES;
        }
    }
    return NO;
}

BOOL tj_isNowPlayingLyricsOrQueueActiveWithView(UIView * _Nullable view, UIViewController * _Nullable controlsVC) {
    if (view && view.bounds.size.width > 0.0f && view.bounds.size.width < 160.0f) return YES;
    if (!controlsVC && view) {
        UIResponder *r = view.nextResponder;
        while (r && ![r isKindOfClass:[UIViewController class]]) r = r.nextResponder;
        controlsVC = (UIViewController *)r;
    }
    return tj_isNowPlayingLyricsOrQueueActive(controlsVC);
}

BOOL tj_isNowPlayingLyricsOrQueueActive(UIViewController * _Nullable controlsVC) {
    if (!controlsVC) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow || !controlsVC) controlsVC = w.rootViewController;
                    if (w.isKeyWindow) break;
                }
                if (controlsVC) break;
            }
        }
    }
    if (!controlsVC) return NO;

    UIViewController *npvc = controlsVC;
    while (npvc && ![NSStringFromClass(npvc.class) containsString:@"NowPlayingViewController"]) npvc = npvc.parentViewController;
    if (!npvc) npvc = tj_searchVC(controlsVC, @"NowPlayingViewController");

    if (npvc) {
        if (tj_checkHierarchyForLyricsOrQueue(npvc)) return YES;
        for (NSString *prop in @[@"lyricsViewController", @"queueViewController"]) {
            @try {
                id vc = [npvc valueForKey:prop];
                if (vc && [vc isKindOfClass:[UIViewController class]] && tj_isVCOnScreen((UIViewController *)vc)) return YES;
            } @catch (__unused id e) {}
        }
        for (NSString *k in @[@"nowPlayingSelectedMode", @"mode", @"layoutType", @"nowPlayingLayoutType"]) {
            @try {
                id m = [npvc valueForKey:k];
                if (m && ([[m description].lowercaseString containsString:@"lyric"] || [[m description].lowercaseString containsString:@"queue"])) return YES;
            } @catch (__unused id e) {}
        }
    }

    UIViewController *cvc = [NSStringFromClass(controlsVC.class) containsString:@"ControlsViewController"] ? controlsVC : nil;
    if (!cvc && npvc) {
        @try { cvc = [npvc valueForKey:@"controlsViewController"]; } @catch (__unused id e) {}
        if (!cvc) cvc = tj_searchVC(npvc, @"ControlsViewController");
    }
    if (!cvc) cvc = tj_searchVC(controlsVC, @"ControlsViewController");

    if (cvc) {
        @try { if (tj_isToggleButtonSelected([cvc valueForKey:@"lyricsButton"], @"LyricsOn", @"quote.bubble.fill")) return YES; } @catch (__unused id e) {}
        @try { if (tj_isToggleButtonSelected([cvc valueForKey:@"queueButton"], @"QueueOn", @"list.bullet.indent")) return YES; } @catch (__unused id e) {}
        @try {
            id colConstraints = [cvc valueForKey:@"artworkLayoutGuideCollapsedConstraints"];
            if ([colConstraints isKindOfClass:[NSArray class]] && [colConstraints count] > 0) {
                NSLayoutConstraint *c = (NSLayoutConstraint *)[colConstraints firstObject];
                if ([c respondsToSelector:@selector(isActive)] && [c isActive]) return YES;
            }
        } @catch (__unused id e) {}
    }
    return NO;
}

BOOL tj_isNowPlayingItemMusicVideo(id _Nullable playingItem, UIView * _Nullable contentView, UIViewController * _Nullable vc) {
    if (playingItem) {
        id cur = playingItem;
        if ([cur respondsToSelector:@selector(metadataObject)]) cur = [cur metadataObject] ?: cur;
        if ([cur respondsToSelector:NSSelectorFromString(@"anyObject")]) {
            cur = ((id (*)(id, SEL))objc_msgSend)(cur, NSSelectorFromString(@"anyObject")) ?: cur;
        }
        if ([cur isKindOfClass:NSClassFromString(@"MPModelMusicVideo")]) return YES;
        for (NSString *sel in @[@"musicVideo", @"videoOutput"]) {
            SEL s = NSSelectorFromString(sel);
            if ([cur respondsToSelector:s] && ((id (*)(id, SEL))objc_msgSend)(cur, s) != nil) return YES;
        }
        if (cur) {
            SEL isVid = NSSelectorFromString(@"isVideo");
            if ([cur respondsToSelector:isVid] && ((BOOL (*)(id, SEL))objc_msgSend)(cur, isVid)) return YES;
        }
        if (playingItem && playingItem != cur) {
            SEL isVid = NSSelectorFromString(@"isVideo");
            if ([playingItem respondsToSelector:isVid] && ((BOOL (*)(id, SEL))objc_msgSend)(playingItem, isVid)) return YES;
        }
    }

    if (!contentView) contentView = sActiveNowPlayingContentView;
    if (contentView) {
        @try { if ([contentView valueForKey:@"videoContext"]) return YES; } @catch (__unused id e) {}
        if (contentView.bounds.size.width > contentView.bounds.size.height + 25.0f) return YES;
        for (UIView *sub in contentView.subviews) {
            NSString *cls = NSStringFromClass(sub.class);
            if ([cls containsString:@"VideoView"] || [cls containsString:@"PlayerView"]) return YES;
        }
    }

    if (vc) {
        UIViewController *npvc = vc;
        while (npvc && ![NSStringFromClass(npvc.class) containsString:@"NowPlayingViewController"]) npvc = npvc.parentViewController;
        if (!npvc && [NSStringFromClass(vc.class) containsString:@"NowPlayingViewController"]) npvc = vc;
        if (npvc) {
            @try { if ([npvc valueForKey:@"videoViewController"]) return YES; } @catch (__unused id e) {}
            for (NSString *k in @[@"nowPlayingSelectedMode", @"mode", @"layoutType"]) {
                @try {
                    id mode = [npvc valueForKey:k];
                    if (mode && [[mode description].lowercaseString containsString:@"video"]) return YES;
                } @catch (__unused id e) {}
            }
        }
    }
    return NO;
}

static void tj_ensureLifecycleObserversRegistered(UIView *contentView) {
    if (!contentView || objc_getAssociatedObject(contentView, kTJNowPlayingObserverRegisteredKey)) return;
    objc_setAssociatedObject(contentView, kTJNowPlayingObserverRegisteredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakCV = contentView;
    void (^resumeBlock)(NSNotification *) = ^(NSNotification *note) {
        UIView *cv = weakCV;
        if (cv) tj_resumeMotionArtwork(cv);
    };
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:resumeBlock];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:resumeBlock];
}

void tj_updateFullBleedArtworkImage(UIImage * _Nullable image) {
    if (!image) return;
    CGFloat newPx = image.size.width * image.scale * image.size.height * image.scale;
    if (sLatestArtworkImage) {
        CGFloat curPx = sLatestArtworkImage.size.width * sLatestArtworkImage.scale * sLatestArtworkImage.size.height * sLatestArtworkImage.scale;
        if (curPx > newPx && newPx < 400.0f * 400.0f) return;
    }
    sLatestArtworkImage = image;
    UIView *container = sActiveFullScreenArtworkContainer;
    if (!container) return;
    UIImageView *iv = (UIImageView *)[container viewWithTag:212102];
    if (!iv) {
        for (UIView *sub in container.subviews) {
            if ([sub isKindOfClass:[UIImageView class]]) { iv = (UIImageView *)sub; break; }
        }
    }
    if (iv && iv.image != image) {
        [UIView transitionWithView:iv duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{ iv.image = image; } completion:nil];
    }
}

void tj_requestHighResArtworkForItem(id _Nullable playingItem) {
    if (!playingItem) return;
    NSString *newID = tj_extractAdamID(playingItem);
    if (newID && sLatestArtworkAdamID && ![newID isEqualToString:sLatestArtworkAdamID]) sLatestArtworkImage = nil;
    if (newID) sLatestArtworkAdamID = newID;

    id catalog = nil;
    if ([playingItem respondsToSelector:@selector(artworkCatalog)]) {
        catalog = ((id (*)(id, SEL))objc_msgSend)(playingItem, @selector(artworkCatalog));
    }
    if (!catalog && [playingItem respondsToSelector:@selector(metadataObject)]) {
        id meta = ((id (*)(id, SEL))objc_msgSend)(playingItem, @selector(metadataObject));
        if (meta) {
            for (NSString *k in @[@"artworkCatalog", @"album.artworkCatalog", @"song.artworkCatalog"]) {
                @try { id c = [meta valueForKeyPath:k]; if (c) { catalog = c; break; } } @catch (__unused id e) {}
            }
        }
    }
    if (!catalog) return;

    CGFloat scale = [UIScreen mainScreen].scale ?: 3.0f;
    CGRect fitBounds = tj_targetBounds();
    CGFloat maxSide = MAX(fitBounds.size.width, fitBounds.size.height);
    CGSize targetSize = CGSizeMake(maxSide, maxSide);
    if ([catalog respondsToSelector:@selector(setFittingSize:)]) ((void (*)(id, SEL, CGSize))objc_msgSend)(catalog, @selector(setFittingSize:), targetSize);
    if ([catalog respondsToSelector:@selector(setDestinationScale:)]) ((void (*)(id, SEL, CGFloat))objc_msgSend)(catalog, @selector(setDestinationScale:), scale);

    if ([catalog respondsToSelector:@selector(bestImageFromDisk)]) {
        UIImage *diskImg = ((UIImage * (*)(id, SEL))objc_msgSend)(catalog, @selector(bestImageFromDisk));
        if (diskImg && diskImg.size.width * diskImg.scale >= 400.0f) tj_updateFullBleedArtworkImage(diskImg);
    }
    if ([catalog respondsToSelector:@selector(requestImageWithCompletion:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(catalog, @selector(requestImageWithCompletion:), ^(UIImage * _Nullable hiResImg) {
            if (hiResImg && hiResImg.size.width * hiResImg.scale >= 400.0f) {
                dispatch_async(dispatch_get_main_queue(), ^{ tj_updateFullBleedArtworkImage(hiResImg); });
            }
        });
    }
}

UIView * _Nullable tj_getOrCreateFullBleedArtworkView(UIViewController *controlsVC) {
    if (!controlsVC) return sActiveFullScreenArtworkContainer;
    if (!controlsVC.isViewLoaded) return nil;
    tj_ensureMotionPlaybackObserverRegistered();
    CGRect bounds = tj_targetBounds();

    UIView *existing = objc_getAssociatedObject(controlsVC, kTJFullBleedArtworkViewKey);
    if (existing && existing.superview == controlsVC.view) {
        sActiveFullScreenArtworkContainer = existing;
        if (sIsMotionCanvasReadyForDisplay) { existing.hidden = NO; existing.alpha = 1.0f; tj_resumeMotionArtwork(existing); }
        return existing;
    }

    if (sActiveFullScreenArtworkContainer) {
        UIView *c = sActiveFullScreenArtworkContainer;
        [c removeFromSuperview];
        c.frame = bounds; c.bounds = bounds;
        if (c.layer.mask) c.layer.mask.frame = bounds;
        for (UIView *sub in c.subviews) sub.frame = bounds;
        AVPlayerLayer *pl = objc_getAssociatedObject(c, kTJNowPlayingPlayerLayerKey);
        if (pl) { pl.frame = bounds; pl.videoGravity = AVLayerVideoGravityResizeAspectFill; }
        controlsVC.view.clipsToBounds = NO;
        if (controlsVC.view.superview) controlsVC.view.superview.clipsToBounds = NO;
        [controlsVC.view insertSubview:c atIndex:0];
        objc_setAssociatedObject(controlsVC, kTJFullBleedArtworkViewKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (sIsMotionCanvasReadyForDisplay) { c.alpha = 1.0f; c.hidden = NO; tj_resumeMotionArtwork(c); }
        return c;
    }

    UIView *container = [[UIView alloc] initWithFrame:bounds];
    container.backgroundColor = [UIColor clearColor];
    container.userInteractionEnabled = NO;
    container.clipsToBounds = YES;
    container.alpha = (sIsMotionCanvasReadyForDisplay && sIsFullScreenTransitionComplete) ? 1.0f : 0.0f;
    container.hidden = (container.alpha == 0.0f);

    UIImageView *iv = [[UIImageView alloc] initWithFrame:bounds];
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.clipsToBounds = YES;
    iv.tag = 212102;
    iv.backgroundColor = [UIColor clearColor];
    if (sLatestArtworkImage && sLatestArtworkImage.size.width * sLatestArtworkImage.scale >= 300.0f) iv.image = sLatestArtworkImage;
    [container addSubview:iv];

    CAGradientLayer *mask = [CAGradientLayer layer];
    mask.frame = bounds;
    mask.colors = @[(id)[UIColor whiteColor].CGColor, (id)[UIColor whiteColor].CGColor, (id)[[UIColor whiteColor] colorWithAlphaComponent:0.5f].CGColor, (id)[UIColor clearColor].CGColor];
    mask.locations = @[@0.0f, @0.72f, @0.90f, @1.0f];
    mask.startPoint = CGPointMake(0.5f, 0.0f); mask.endPoint = CGPointMake(0.5f, 1.0f);
    container.layer.mask = mask;

    controlsVC.view.clipsToBounds = NO;
    if (controlsVC.view.superview) controlsVC.view.superview.clipsToBounds = NO;
    [controlsVC.view insertSubview:container atIndex:0];
    objc_setAssociatedObject(controlsVC, kTJFullBleedArtworkViewKey, container, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    sActiveFullScreenArtworkContainer = container;
    tj_ensureLifecycleObserversRegistered(container);
    return container;
}

void tj_setNowPlayingImmersiveVisible(BOOL visible) {
    UIView *c = sActiveFullScreenArtworkContainer;
    if (!c) return;
    if (visible && (c.hidden || c.alpha < 1.0f)) {
        c.hidden = NO; c.alpha = 1.0f; tj_resumeMotionArtwork(c);
    } else if (!visible && (!c.hidden || c.alpha > 0.0f)) {
        c.hidden = YES; c.alpha = 0.0f;
    }
}

void tj_layoutFullBleedArtwork(UIViewController *controlsVC) {
    if (!controlsVC || !controlsVC.isViewLoaded) return;
    BOOL disabled = !prefBool(@"enabled", YES) || !prefBool(@"immersiveNowPlaying", YES);
    BOOL isLyrics = tj_isNowPlayingLyricsOrQueueActive(controlsVC);
    BOOL isVid = tj_isNowPlayingItemMusicVideo(nil, nil, controlsVC);
    if (disabled || isLyrics || isVid) {
        UIView *existing = objc_getAssociatedObject(controlsVC, kTJFullBleedArtworkViewKey);
        if (existing) {
            existing.hidden = YES; existing.alpha = 0.0f;
            if (disabled || isVid) tj_pauseMotionArtwork(existing);
        }
        if (isVid) tj_setNowPlayingImmersiveVisible(NO);
        return;
    }

    UIView *container = tj_getOrCreateFullBleedArtworkView(controlsVC);
    if (!container) return;
    CGRect bounds = tj_targetBounds();
    if (!CGRectEqualToRect(container.frame, bounds)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        container.frame = bounds; container.bounds = bounds;
        if (container.layer.mask) container.layer.mask.frame = bounds;
        for (UIView *sub in container.subviews) sub.frame = bounds;
        AVPlayerLayer *pl = objc_getAssociatedObject(container, kTJNowPlayingPlayerLayerKey);
        if (pl) { pl.frame = bounds; pl.videoGravity = AVLayerVideoGravityResizeAspectFill; }
        [CATransaction commit];
    }
}

void tj_updateNowPlayingMotionArtwork(UIView *contentView, id _Nullable playingItem) {
    if (!contentView) return;
    @try {
        if (!playingItem) {
            playingItem = tj_extractPlayingItem(contentView) ?: tj_extractPlayingItem(tj_activeNowPlayingContentView());
        }
        if (!playingItem || tj_isNowPlayingItemMusicVideo(playingItem, contentView, nil) || !prefBool(@"enabled", YES) || !prefBool(@"immersiveMotionArtwork", YES)) {
            tj_cleanupNowPlayingImmersive(contentView);
            return;
        }

    id unwrappedSong = tj_unwrapSongFromPlayingItem(playingItem);
    id unwrappedAlbum = tj_unwrapAlbumFromPlayingItem(playingItem);
    NSString *albumID = tj_extractAlbumAdamID(playingItem);
    NSString *songID = tj_extractAdamID(playingItem);
    NSString *albumTitle = tj_extractAlbumTitle(playingItem);
    NSString *songTitle = nil;
    NSString *artistName = nil;

    NSMutableArray *srcs = [NSMutableArray arrayWithCapacity:2];
    if (unwrappedSong) [srcs addObject:unwrappedSong];
    if (playingItem && playingItem != unwrappedSong) [srcs addObject:playingItem];

    for (id src in srcs) {
        if (!songTitle) {
            for (NSString *k in @[@"title", @"song.title", @"metadataObject.title", @"metadataObject.song.title", @"metadataObject.playlistEntry.song.title"]) {
                @try { id v = [src valueForKeyPath:k]; if ([v isKindOfClass:[NSString class]] && [v length] > 0) { songTitle = v; break; } } @catch (__unused id e) {}
            }
        }
        if (!artistName) {
            for (NSString *k in @[@"artistName", @"artist.name", @"song.artistName", @"song.artist.name", @"metadataObject.artistName", @"metadataObject.song.artistName"]) {
                @try { id v = [src valueForKeyPath:k]; if ([v isKindOfClass:[NSString class]] && [v length] > 0) { artistName = v; break; } } @catch (__unused id e) {}
            }
        }
    }

    NSString *lookupID = albumID ?: songID ?: albumTitle ?: (songTitle ? [NSString stringWithFormat:@"%@ - %@", songTitle, artistName ?: @""] : nil);
    if (!lookupID) lookupID = [NSString stringWithFormat:@"%p", playingItem];
    objc_setAssociatedObject(contentView, kTJNowPlayingCurrentLookupIDKey, lookupID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *artistKey = tj_normalizedKey(artistName);
    NSString *albumCompoundKey = (artistKey && tj_normalizedKey(albumTitle)) ?
        [NSString stringWithFormat:@"album:%@|%@", artistKey, tj_normalizedKey(albumTitle)] : nil;
    NSString *songCompoundKey = (artistKey && tj_normalizedKey(songTitle)) ?
        [NSString stringWithFormat:@"song:%@|%@", artistKey, tj_normalizedKey(songTitle)] : nil;

    NSURL *videoURL = nil;
    if (albumID.length > 0) videoURL = tj_cachedAlbumMotionVideoURL(albumID);
    if (!videoURL && songID.length > 0) videoURL = tj_cachedAlbumMotionVideoURL(songID);
    if (!videoURL && albumCompoundKey) videoURL = tj_cachedAlbumMotionVideoURL(albumCompoundKey);
    if (!videoURL && songCompoundKey) videoURL = tj_cachedAlbumMotionVideoURL(songCompoundKey);

    NSURL *latestURL = tj_latestActiveAlbumMotionVideoURL();
    NSString *latestAID = tj_latestActiveAlbumAdamID();
    NSString *latestTitle = tj_latestActiveAlbumTitle();
    if (!videoURL && latestURL) {
        if ((albumID && latestAID && [albumID isEqualToString:latestAID]) || (albumTitle && latestTitle && tj_albumTitlesMatch(albumTitle, latestTitle))) {
            videoURL = latestURL;
        }
    }

    if (!videoURL) {
        UIView *npcv = tj_activeNowPlayingContentView();
        id metaObj = [playingItem respondsToSelector:@selector(metadataObject)] ? [playingItem metadataObject] : nil;
        id itemCat = [playingItem respondsToSelector:@selector(artworkCatalog)] ? ((id (*)(id, SEL))objc_msgSend)(playingItem, @selector(artworkCatalog)) : nil;
        id songCat = [unwrappedSong respondsToSelector:@selector(artworkCatalog)] ? ((id (*)(id, SEL))objc_msgSend)(unwrappedSong, @selector(artworkCatalog)) : nil;
        id albCat = [unwrappedAlbum respondsToSelector:@selector(artworkCatalog)] ? ((id (*)(id, SEL))objc_msgSend)(unwrappedAlbum, @selector(artworkCatalog)) : nil;
        NSMutableArray *targets = [NSMutableArray arrayWithCapacity:8];
        if (unwrappedAlbum) [targets addObject:unwrappedAlbum];
        if (unwrappedSong) [targets addObject:unwrappedSong];
        if (metaObj) [targets addObject:metaObj];
        if (playingItem) [targets addObject:playingItem];
        if (npcv) [targets addObject:npcv];
        if (itemCat) [targets addObject:itemCat];
        if (songCat) [targets addObject:songCat];
        if (albCat) [targets addObject:albCat];
        for (id target in targets) {
            for (NSString *prop in @[@"tallVideoArtwork", @"videoBackgroundArtworkCatalog", @"_internalVideoCatalog", @"videoArtwork", @"editorialVideo", @"videoCatalog"]) {
                id cat = nil;
                @try { cat = [target valueForKey:prop]; } @catch (__unused id e) {}
                if (cat) {
                    NSURL *u = tj_extractVideoURLFromObject(cat);
                    if (u) {
                        videoURL = u;
                        if (albumID.length > 0) tj_recordAlbumMotionVideoURL(albumID, videoURL);
                        if (songID.length > 0) tj_recordAlbumMotionVideoURL(songID, videoURL);
                        if (albumCompoundKey) tj_recordAlbumMotionVideoURL(albumCompoundKey, videoURL);
                        if (songCompoundKey) tj_recordAlbumMotionVideoURL(songCompoundKey, videoURL);
                        break;
                    }
                }
            }
            if (videoURL) break;
        }
    }

    if (!videoURL) {
        NSString *lastPlaying = objc_getAssociatedObject(contentView, kTJLastPlayingLookupIDKey);
        if (!lastPlaying || (lookupID && ![lastPlaying isEqualToString:lookupID])) {
            tj_cleanupNowPlayingImmersive(contentView);
        }
        if (lookupID && [lookupID isEqualToString:objc_getAssociatedObject(contentView, kTJInFlightFetchKey)]) return;

        if (lookupID) {
            objc_setAssociatedObject(contentView, kTJInFlightFetchKey, lookupID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            __weak UIView *weakCV = contentView;
            __weak id weakItem = playingItem;
            NSString *expectedID = lookupID;
            tj_fetchMotionVideoForSongAndAlbum(songID, albumID, albumTitle, artistName, songTitle, ^(NSURL * _Nullable fetchedURL) {
                UIView *cv = weakCV;
                if (cv) {
                    objc_setAssociatedObject(cv, kTJInFlightFetchKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    if (fetchedURL && [expectedID isEqualToString:objc_getAssociatedObject(cv, kTJNowPlayingCurrentLookupIDKey)]) {
                        tj_updateNowPlayingMotionArtwork(cv, weakItem);
                    }
                }
            });
        }
        return;
    }

    if (lookupID) objc_setAssociatedObject(contentView, kTJLastPlayingLookupIDKey, lookupID, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSURL *currentURL = objc_getAssociatedObject(contentView, kTJNowPlayingCurrentAssetKey);

    NSString *videoURLStr = videoURL.absoluteString;
    if (([videoURLStr containsString:@"_default.m3u8"] || [videoURLStr containsString:@"master.m3u8"]) &&
        ![sResolvedMasterURLs containsObject:videoURLStr]) {
        if (currentURL && ![currentURL isEqual:videoURL]) tj_cleanupNowPlayingImmersive(contentView);
        if (!sResolvingMasterURLs) sResolvingMasterURLs = [NSMutableSet set];
        if ([sResolvingMasterURLs containsObject:videoURLStr]) return;
        [sResolvingMasterURLs addObject:videoURLStr];

        NSMutableArray<NSString *> *keys = [NSMutableArray arrayWithCapacity:4];
        if (albumID.length > 0) [keys addObject:albumID];
        if (songID.length > 0) [keys addObject:songID];
        if (albumCompoundKey) [keys addObject:albumCompoundKey];
        if (songCompoundKey) [keys addObject:songCompoundKey];
        __weak UIView *weakCV = contentView;
        __weak id weakItem = playingItem;
        NSString *expectedID = lookupID;
        NSURL *masterURL = videoURL;
        tj_resolveOptimalVariantURL(masterURL, ^(NSURL * _Nullable fastURL) {
            [sResolvingMasterURLs removeObject:videoURLStr];
            if (!sResolvedMasterURLs) sResolvedMasterURLs = [NSMutableSet set];
            [sResolvedMasterURLs addObject:videoURLStr];
            if (fastURL && ![fastURL isEqual:masterURL]) {
                for (NSString *k in keys) tj_recordAlbumMotionVideoURL(k, fastURL);
            }
            UIView *cv = weakCV;
            if (cv && [expectedID isEqualToString:objc_getAssociatedObject(cv, kTJNowPlayingCurrentLookupIDKey)]) {
                tj_updateNowPlayingMotionArtwork(cv, weakItem);
            }
        });
        return;
    }

    if (currentURL && [currentURL isEqual:videoURL]) {
        AVPlayerLayer *pl = objc_getAssociatedObject(contentView, kTJNowPlayingPlayerLayerKey);
        if (pl) { pl.hidden = NO; pl.opacity = 1.0f; }
        tj_resumeMotionArtwork(contentView);
        return;
    }

    tj_cleanupNowPlayingImmersive(contentView);

    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:videoURL];
        if ([playerItem respondsToSelector:@selector(setPreferredPeakBitRate:)]) playerItem.preferredPeakBitRate = 4000000;
        if ([playerItem respondsToSelector:@selector(setPreferredMaximumResolution:)]) playerItem.preferredMaximumResolution = CGSizeMake(1080.0f, 1440.0f);

        NSString *urlKey = videoURL.absoluteString ?: @"";
        BOOL useLooper = ![sLooperFailedURLs containsObject:urlKey];
        AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[]];
        AVPlayerLooper *looper = nil;
        if (useLooper) {
            @try { looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:playerItem]; } @catch (__unused id e) { looper = nil; }
        }
        if (!looper) {
            useLooper = NO;
            [player insertItem:playerItem afterItem:nil];
            player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        }
        player.muted = YES;
        player.volume = 0.0f;
        player.preventsDisplaySleepDuringVideoPlayback = NO;
        if ([player respondsToSelector:@selector(setAutomaticallyWaitsToMinimizeStalling:)]) {
            player.automaticallyWaitsToMinimizeStalling = NO;
        }

        AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
        playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        CGFloat screenScale = [UIScreen mainScreen].scale ?: 3.0f;
        playerLayer.contentsScale = screenScale;
        playerLayer.rasterizationScale = screenScale;
        playerLayer.frame = (contentView.bounds.size.width > 0 && contentView.bounds.size.height > 0) ? contentView.bounds : tj_targetBounds();
        playerLayer.masksToBounds = YES;
        playerLayer.cornerRadius = 0.0f;
        playerLayer.opacity = playerLayer.isReadyForDisplay ? 1.0f : 0.0f;
        [contentView.layer addSublayer:playerLayer];

        TJPlayerLayerObserver *layerObs = [[TJPlayerLayerObserver alloc] init];
        [layerObs startObservingLayer:playerLayer player:player item:(useLooper ? nil : playerItem)];
        objc_setAssociatedObject(contentView, kTJPlayerLayerObserverKey, layerObs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        __weak AVPlayer *weakPlayer = player;
        __weak UIView *weakCV = contentView;
        if (useLooper) {
            objc_setAssociatedObject(contentView, kTJNowPlayingLooperKey, looper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            layerObs.onLooperFailed = ^{
                if (!sLooperFailedURLs) sLooperFailedURLs = [NSMutableSet set];
                [sLooperFailedURLs addObject:urlKey];
                UIView *cv = weakCV;
                if (cv && [videoURL isEqual:objc_getAssociatedObject(cv, kTJNowPlayingCurrentAssetKey)]) {
                    tj_cleanupNowPlayingImmersive(cv);
                    tj_updateNowPlayingMotionArtwork(cv, nil);
                }
            };
            [layerObs observeLooper:looper];
        } else {
            __weak TJPlayerLayerObserver *weakObs = layerObs;
            id endObs = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:playerItem queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
                AVPlayer *p = weakPlayer;
                TJPlayerLayerObserver *obs = weakObs;
                if (p && obs && !obs.isSeeking) {
                    obs.isSeeking = YES;
                    [p seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                        obs.isSeeking = NO;
                        if (finished && p.rate == 0.0f) [p play];
                    }];
                }
            }];
            objc_setAssociatedObject(contentView, kTJPlayToEndObserverKey, endObs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        id stallObs = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemPlaybackStalledNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
            AVPlayer *p = weakPlayer;
            if (!p || note.object != p.currentItem) return;
            if (p.rate == 0.0f && tj_motionArtworkShouldPlay(nil)) {
                [p play];
            }
        }];
        objc_setAssociatedObject(contentView, kTJStallObserverKey, stallObs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        objc_setAssociatedObject(contentView, kTJNowPlayingPlayerLayerKey, playerLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(contentView, kTJNowPlayingQueuePlayerKey, player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(contentView, kTJNowPlayingCurrentAssetKey, videoURL, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        if (tj_musicIsForeground(contentView)) [player play];
    } @catch (__unused id e) {
        tj_cleanupNowPlayingImmersive(contentView);
    }
}

void tj_pauseAllMotionArtwork(void) {
    tj_pauseMotionArtwork(sActiveFullScreenArtworkContainer);
    tj_pauseMotionArtwork(sActiveNowPlayingContentView);
}

void tj_pauseMotionArtwork(UIView * _Nullable contentView) {
    if (!contentView) return;
    if ([contentView respondsToSelector:@selector(accessibilityPlayerVideoLayer)]) {
        id natObj = [contentView accessibilityPlayerVideoLayer];
        if (natObj && [natObj isKindOfClass:[AVPlayerLayer class]] && ((AVPlayerLayer *)natObj).player) {
            [((AVPlayerLayer *)natObj).player pause];
        }
    }
    AVPlayer *player = objc_getAssociatedObject(contentView, kTJNowPlayingQueuePlayerKey);
    if (player) [player pause];
}

void tj_resumeMotionArtwork(UIView * _Nullable contentView) {
    if (!contentView) return;
    if (!tj_motionArtworkShouldPlay(contentView)) return;
    AVPlayer *player = objc_getAssociatedObject(contentView, kTJNowPlayingQueuePlayerKey);
    if (player && player.rate == 0.0f) {
        tj_disableAudioTracks(player.currentItem);
        [player play];
    }
}

void tj_cleanupNowPlayingImmersive(UIView * _Nullable contentView) {
    if (!contentView) return;
    sIsMotionCanvasReadyForDisplay = NO;
    sIsFullScreenTransitionComplete = NO;
    tj_transitionToSquaredLayout(NO);

    TJPlayerLayerObserver *layerObs = objc_getAssociatedObject(contentView, kTJPlayerLayerObserverKey);
    if (layerObs) {
        [layerObs stopObserving];
        objc_setAssociatedObject(contentView, kTJPlayerLayerObserverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    const void *obsKeys[] = { kTJPlayToEndObserverKey, kTJStallObserverKey };
    for (size_t i = 0; i < sizeof(obsKeys) / sizeof(obsKeys[0]); i++) {
        id obs = objc_getAssociatedObject(contentView, obsKeys[i]);
        if (obs) {
            [[NSNotificationCenter defaultCenter] removeObserver:obs];
            objc_setAssociatedObject(contentView, obsKeys[i], nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    AVPlayerLooper *looper = objc_getAssociatedObject(contentView, kTJNowPlayingLooperKey);
    if (looper) {
        [looper disableLooping];
        objc_setAssociatedObject(contentView, kTJNowPlayingLooperKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    AVPlayer *player = objc_getAssociatedObject(contentView, kTJNowPlayingQueuePlayerKey);
    if (player) {
        [player pause];
        if ([player isKindOfClass:[AVQueuePlayer class]]) [(AVQueuePlayer *)player removeAllItems];
        else [player replaceCurrentItemWithPlayerItem:nil];
    }
    AVPlayerLayer *playerLayer = objc_getAssociatedObject(contentView, kTJNowPlayingPlayerLayerKey);
    if (playerLayer) [playerLayer removeFromSuperlayer];

    objc_setAssociatedObject(contentView, kTJNowPlayingPlayerLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(contentView, kTJNowPlayingQueuePlayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(contentView, kTJNowPlayingCurrentAssetKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(contentView, kTJLastPlayingLookupIDKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
