#import <UIKit/UIKit.h>
#import "TJEngine.h"
#import "TJNowPlayingImmersive.h"

NS_ASSUME_NONNULL_BEGIN

BOOL colorIsLight(UIColor *color);
double tj_colorLuminance(UIColor *c);
BOOL tj_safeColorRGBA(UIColor *c, CGFloat * _Nullable r, CGFloat * _Nullable g,
                      CGFloat * _Nullable b, CGFloat * _Nullable a);
UIColor *tj_detailHeaderSubtitleOnListSurface(UIColor *listSurface);
UIColor * _Nullable tj_detailHeaderSubtitleColorFromTextViewReference(UIView *detailHeader);
void tj_applyArtistSubtitleInkToLabel(UILabel *l, UIColor *ink);
void tj_fixDetailHeaderButtonLabels(UIView *v, UIColor *subtitleInk, int depth);
void tj_boostDetailHeaderCaptionLabels(UIView *v, UIColor *fg, int depth);
UIColor *tj_buttonFillFromDominant(UIColor *dominant);
void tj_styleDetailHeaderPrimaryActions(UIView *detailHeader, UIColor *dominant,
                                        UIColor *foreground, UIColor *listSurface);

void tj_tintListRowInteractables(UIView *v, UIColor *fg, int depth);
void flattenListRowOpaqueBases(UIView *v, int depth);
void tj_fixCellContentForScroll(UIView *cell);
BOOL tj_isAlbumTrackRowCell(UIView *cell);
void tj_clearShelfCardCell(UICollectionViewCell *cell);
void tj_cardCellPrepareForReuse(UICollectionViewCell *cell);

BOOL tj_cvContentLooksHorizontallyScrolled(UICollectionView *cv);

UIViewController * _Nullable tj_currentThemeOwnerVC(void);
void tj_setThemeOwnerVC(UIViewController * _Nullable vc);
void tj_detailSurfaceVCHandoffIfLeaving(UIViewController *vc);
void tj_detailSurfaceVCLayoutTickForced(UIViewController *vc);
void tj_detailSurfaceVCForceChromeTick(UIViewController *vc);
void tj_listScrollSurfaceDidAttach(UIScrollView *sv);
void tj_listScrollSurfaceLayoutEnsure(UIScrollView *sv);
void tj_paintDetailBodyNow(UIViewController *vc, UIColor *listSurface);

BOOL tj_collectionViewIsMainVerticalList(UICollectionView *cv);
void tj_recordTappedArtworkImage(UIImage * _Nullable img);
UIColor * _Nullable tj_recentTappedDominantColor(void);
UIImage * _Nullable tj_extractCatalogImageSync(id _Nullable component);
void tj_prepareDetailVCTintBeforePush(UINavigationController *nav, UIViewController *detailVC);
void tj_prepareDetailVCTintOnWillAppear(UIViewController *detailVC);
void tintVCViewTree(UIView *v, UIColor *color, int depth);
NSArray<UIScrollView *> *cachedListScrollViewsForVC(UIViewController *vc);
UIView * _Nullable tj_findDetailHeaderInView(UIView *root, int depth);

void tj_paintListScrollSurfaceLite(UIScrollView *sv, UIColor *listSurface);
void tj_paintListScrollSurface(UIScrollView *sv, UIColor *listSurface, UIColor *fg);
void tj_fallbackPaintBestListCollectionView(UIViewController *vc, UIColor *listSurface, UIColor *fg,
                                            BOOL useParallaxLiteList);

void tj_tintRadiosityShadow(UIView *detailHeader, UIColor *dominant);

void tj_applyForegroundToDetailsViewLabels(UIView *detailHeader, UIColor *fg,
                                            UIColor * _Nullable subtitleInk);

NS_ASSUME_NONNULL_END
