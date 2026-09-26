#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import "TJPrefsStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface _TtC16MusicApplication12DetailHeader : UIView
- (void)tj_recolourFromArtwork;
@end

@interface _TtCC16MusicApplication12DetailHeader11DetailsView : UIView
@property(nonatomic, readonly) UIColor *artworkProminentColor;
@property(nonatomic, readonly) UIColor *textColor;
@property(nonatomic, readonly) UIView *actionButton;
@property(nonatomic, readonly) UIView *moreButton;
@property(nonatomic, readonly) UIView *actionsContainerView;
@end

@interface _TtC16MusicApplication10DetailCell : UICollectionViewCell
@end

@interface _TtC16MusicApplication8SongCell : UICollectionViewCell
@end

@interface MusicArtworkComponentImageView : UIImageView
@end

@interface _TtC16MusicApplication21NowPlayingContentView : UIView
@end

@interface _TtC16MusicApplication24NowPlayingViewController : UIViewController
@property(nonatomic, strong, nullable) UIViewController *controlsViewController;
@property(nonatomic, strong, nullable) id playingItem;
@end

@interface MusicNowPlayingControlsViewController : UIViewController
- (nullable id)accessibilityNowPlayingResponse;
@end

@interface _TtC16MusicApplication24MiniPlayerViewController : UIViewController
@end

@interface _TtC16MusicApplication30NowPlayingLyricsViewController : UIViewController
@end

@interface MusicNowPlayingLyricsViewController : UIViewController
@end

@interface _TtC16MusicApplication29NowPlayingQueueViewController : UIViewController
@end

@interface NSObject (TJArtworkCatalogPrivate)
- (UIImage * _Nullable)bestImageFromDisk;
- (UIImage * _Nullable)existingImageOfSize:(CGSize)size;
@end

@interface NSObject (TJNowPlayingDynamicPrivate)
- (nullable id)artworkCatalog;
- (nullable id)metadataObject;
- (nullable id)album;
- (nullable id)musicVideo;
- (BOOL)isVideo;
- (nullable id)videoOutput;
- (nullable id)videoBackgroundArtworkCatalog;
- (nullable NSURL *)videoURL;
- (nullable id)accessibilityPlayerVideoLayer;
- (nullable id)accessibilityNowPlayingResponse;
- (nullable UIView *)titlesStackView;
- (nullable UIView *)timeControl;
- (nullable UIView *)transportControlsStackView;
- (nullable UIView *)bottomButtonsStackView;
- (nullable UIView *)artworkView;
- (nullable id)tracklist;
- (nullable id)playingItem;
- (nullable id)identifiers;
- (nullable id)universalStore;
- (long long)adamID;
- (BOOL)isPlaying;
- (NSInteger)state;
- (NSInteger)playbackState;
@end

extern UIColor *_albumDetailDominantColor;
extern UIColor *_albumDetailForegroundColor;
extern UIColor *_albumDetailListSurfaceColor;

extern void *kTJTintedKey;
extern void *kTJArtworkKey;
extern void *kTJCachedDominantKey;
extern void *kTJCachedCVsKey;
extern void *kTJLastSurfaceApplyKey;
extern void *kTJLastListPaintKey;
extern void *kTJLastHeavyListPaintKey;
extern void *kTJLastParallaxTreePassKey;
extern void *kTJHeaderLayoutThrottleKey;
extern void *kTJVCListLayoutCoalesceKey;
extern void *kTJListBootstrapScheduledKey;
extern void *kTJHeaderLayoutAsyncScheduledKey;
extern void *kTJSurfaceTintDepthKey;
extern void *kTJParallaxScanStampKey;
extern void *kTJDetailHeaderCacheKey;
extern void *kTJDetailHeaderStampKey;
extern void *kTJGrayArtKey;
extern void *kTJArtworkArmedStampKey;

UIColor *dominantColorFromImage(UIImage *image, CGFloat satMult, CGFloat briCap);
CGFloat tj_imageEdgeRatio(UIImage *image);
UIColor *tj_listSurfaceFromDominant(UIColor *dominant);
UIColor *tj_albumDetailForeground(UIColor *dominant, UIColor *listSurface);
UIColor *tj_rowFillColor(void);

UIViewController * _Nullable nearestVC(UIView * _Nullable v);
UIViewController *tj_albumSurfaceViewController(UIView *anchor);
BOOL tj_surfaceVCIsAlbumDetailFamily(UIViewController *vc);
BOOL tj_subtreeContainsParallaxView(UIView *root, int depth);
BOOL tj_cellOnAlbumOrPlaylistDetail(UIView *v);
BOOL tj_cellIsInMainListScrollSurface(UIView *cell);
BOOL tj_viewHasParallaxAncestor(UIView *v);

void tintAlbumDetailHierarchy(UIView *start, UIColor *color);
void applyAlbumSurfaceTint(UIViewController *vc, UIColor *dominant, UIColor *fg);
void tj_maybeScheduleListBootstrapRetries(UIViewController *vc);
void tj_detailSurfaceVCLayoutTick(UIViewController *vc);

UIImage * _Nullable firstImageInView(UIView *v, int depth);
void applyCellTint(UIView *v, int depth);

void tj_detailHeaderScheduleRecolour(_TtC16MusicApplication12DetailHeader *header);

UIColor * _Nullable tj_headerReadMusicDominantColor(UIView *detailHeader);
UIColor * _Nullable tj_headerReadMusicTextColor(UIView *detailHeader);

UIViewController * _Nullable tj_activeNowPlayingControlsViewController(void);
UIViewController * _Nullable tj_activeMiniPlayerViewController(void);

NS_ASSUME_NONNULL_END
