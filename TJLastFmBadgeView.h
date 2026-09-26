#import <UIKit/UIKit.h>
#import "TJScrobbleStateClient.h"

NS_ASSUME_NONNULL_BEGIN

@interface TJLastFmBadgeView : UIButton

+ (instancetype)badgeView;

@property (nonatomic, assign) BOOL compactMode;

- (void)refreshDisplayAnimated:(BOOL)animated;
- (void)matchNativeTraitView:(nullable UIView *)traitView;

@end

NS_ASSUME_NONNULL_END
