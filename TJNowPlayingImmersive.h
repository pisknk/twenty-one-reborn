#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "TJEngine.h"
#import "TJModelUtils.h"
#import "TJMotionArtworkResolver.h"

NS_ASSUME_NONNULL_BEGIN

UIView * _Nullable tj_getOrCreateFullBleedArtworkView(UIViewController *controlsVC);

void tj_updateFullBleedArtworkImage(UIImage * _Nullable image);

void tj_requestHighResArtworkForItem(id _Nullable playingItem);

void tj_layoutFullBleedArtwork(UIViewController *controlsVC);

void tj_setNowPlayingImmersiveVisible(BOOL visible);

BOOL tj_isNowPlayingLyricsOrQueueActiveWithView(UIView * _Nullable view, UIViewController * _Nullable controlsVC);

BOOL tj_isNowPlayingItemMusicVideo(id _Nullable playingItem, UIView * _Nullable contentView, UIViewController * _Nullable vc);

void tj_updateNowPlayingMotionArtwork(UIView *contentView, id _Nullable playingItem);

void tj_pauseMotionArtwork(UIView * _Nullable contentView);

void tj_pauseAllMotionArtwork(void);

void tj_resumeMotionArtwork(UIView * _Nullable contentView);

void tj_transitionToFullScreenMotionIfReady(void);

void tj_transitionToSquaredLayout(BOOL animated);

BOOL tj_isMotionArtworkReadyForDisplay(void);
BOOL tj_isFullScreenTransitionComplete(void);

BOOL tj_motionArtworkShouldPlay(UIView * _Nullable contentView);

void tj_setActiveNowPlayingContentView(UIView * _Nullable cv);
UIView * _Nullable tj_activeNowPlayingContentView(void);

NSString * _Nullable tj_currentActiveTrackIdentity(void);

void tj_setCurrentActiveTrackIdentity(NSString * _Nullable trackKey);

void tj_cleanupNowPlayingImmersive(UIView * _Nullable contentView);

BOOL tj_isNowPlayingLyricsOrQueueActive(UIViewController * _Nullable controlsVC);

UIView * _Nullable tj_activeNowPlayingArtworkContainer(void);

NS_ASSUME_NONNULL_END
