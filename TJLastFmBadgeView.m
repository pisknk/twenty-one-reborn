#import "TJLastFmBadgeView.h"
#import "TJEngine.h"

@interface TJLastFmBadgeView () {
    UIImageView *_iconView;
    UILabel *_textLabel;
    TJScrobbleState _renderedState;
    NSInteger _lastSeconds;
    BOOL _compactMode;
}
@end

@implementation TJLastFmBadgeView

+ (instancetype)badgeView {
    return [[self alloc] initWithFrame:CGRectMake(0, 0, 56, 18)];
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _renderedState = TJScrobbleStateIdle;
        _lastSeconds = -1;

        self.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.14f];
        self.layer.cornerRadius = 4.5f;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;

        _iconView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 11, 11)];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.tintColor = [UIColor colorWithWhite:1.0f alpha:0.85f];
        [self addSubview:_iconView];

        _textLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _textLabel.font = [UIFont systemFontOfSize:11.0f weight:UIFontWeightMedium];
        _textLabel.textColor = [UIColor colorWithWhite:1.0f alpha:0.85f];
        _textLabel.textAlignment = NSTextAlignmentLeft;
        [self addSubview:_textLabel];

        if (@available(iOS 14.0, *)) {
            self.showsMenuAsPrimaryAction = YES;
        }

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onScrobbleStateChanged:)
                                                     name:kTJScrobbleStateChangedNotification
                                                   object:nil];

        [self refreshDisplayAnimated:NO];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)matchNativeTraitView:(UIView * _Nullable)traitView {
    if (traitView) {
        if (traitView.layer.cornerRadius > 0.0f) {
            self.layer.cornerRadius = traitView.layer.cornerRadius;
        } else {
            self.layer.cornerRadius = 4.5f;
        }
        if (traitView.backgroundColor && ![traitView.backgroundColor isEqual:[UIColor clearColor]]) {
            self.backgroundColor = traitView.backgroundColor;
        } else {
            self.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.14f];
        }
    } else {
        self.layer.cornerRadius = 4.5f;
        self.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.14f];
    }
    self.layer.cornerCurve = kCACornerCurveContinuous;
    [self setNeedsLayout];
}

- (BOOL)compactMode {
    return _compactMode;
}

- (void)setCompactMode:(BOOL)compactMode {
    if (_compactMode != compactMode) {
        _compactMode = compactMode;
        _textLabel.font = _compactMode ? [UIFont systemFontOfSize:9.5f weight:UIFontWeightMedium] : [UIFont systemFontOfSize:11.0f weight:UIFontWeightMedium];
        [self refreshDisplayAnimated:NO];
        [self setNeedsLayout];
    }
}

- (void)onScrobbleStateChanged:(NSNotification *)note {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL animate = ([TJScrobbleStateClient sharedInstance].state != self->_renderedState);
        [self refreshDisplayAnimated:animate];
    });
}

- (void)refreshDisplayAnimated:(BOOL)animated {
    TJScrobbleStateClient *mgr = [TJScrobbleStateClient sharedInstance];
    TJScrobbleState state = mgr.state;
    NSInteger seconds = mgr.remainingCountdownSeconds;

    if (!prefBool(@"lastFmEnabled", YES) || !prefBool(@"lastFmShowBadge", YES) || !mgr.isLoggedIn) {
        self.hidden = YES;
        return;
    }

    if (state == TJScrobbleStateIdle && seconds <= 0) {
        self.hidden = YES;
        return;
    }

    self.hidden = NO;

    NSString *symbolName = @"arrow.triangle.2.circlepath";
    NSString *displayText = @"";

    switch (state) {
        case TJScrobbleStateCountingDown: {
            symbolName = @"arrow.triangle.2.circlepath";
            displayText = [NSString stringWithFormat:@"%lds", (long)seconds];
            break;
        }
        case TJScrobbleStateScrobbled: {
            symbolName = @"checkmark";
            displayText = @"Scrobbled";
            break;
        }
        case TJScrobbleStateBlacklisted: {
            symbolName = @"slash.circle";
            displayText = @"Ignored";
            break;
        }
        case TJScrobbleStateDisabled:
        case TJScrobbleStateIdle:
        default: {
            self.hidden = YES;
            return;
        }
    }

    CGFloat iconPt = _compactMode ? 7.5f : 9.0f;
    UIImageConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:iconPt weight:UIImageSymbolWeightMedium];
    UIImage *img = [UIImage systemImageNamed:symbolName withConfiguration:config];

    BOOL stateChanged = (_renderedState != state);
    _renderedState = state;
    _lastSeconds = seconds;

    if (stateChanged && animated) {
        [UIView transitionWithView:self
                          duration:0.25
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
            self->_iconView.image = img;
            self->_textLabel.text = displayText;
            [self setNeedsLayout];
            [self layoutIfNeeded];
        } completion:nil];
    } else {
        _iconView.image = img;
        _textLabel.text = displayText;
        [self setNeedsLayout];
    }

    CGFloat oldW = self.bounds.size.width;
    CGFloat defaultH = _compactMode ? 15.0f : 18.0f;
    CGSize fit = [self sizeThatFits:CGSizeMake(0, self.bounds.size.height > 0.0f ? self.bounds.size.height : defaultH)];
    if (oldW > 0.0f && fabs(oldW - fit.width) > 1.0f && self.superview) {
        [self.superview setNeedsLayout];
    }

    if (@available(iOS 14.0, *)) {
        self.menu = [self buildContextMenu];
    }
}

- (CGSize)sizeThatFits:(CGSize)size {
    [_textLabel sizeToFit];
    CGFloat labelWidth = _textLabel.frame.size.width;
    CGFloat iconW = _compactMode ? 9.0f : 11.0f;
    CGFloat gap = _compactMode ? 3.0f : 4.0f;
    CGFloat pad = _compactMode ? 5.0f : 6.5f;
    CGFloat width = pad + iconW + gap + labelWidth + pad;
    CGFloat minW = _compactMode ? 28.0f : 36.0f;
    CGFloat defaultH = _compactMode ? 15.0f : 18.0f;
    CGFloat h = size.height > 0.0f ? size.height : defaultH;
    return CGSizeMake(MAX(width, minW), h);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.layer.cornerRadius <= 0.0f || self.layer.cornerRadius > 8.0f) {
        self.layer.cornerRadius = _compactMode ? 3.5f : 4.5f;
    }
    self.layer.cornerCurve = kCACornerCurveContinuous;

    [_textLabel sizeToFit];
    CGFloat labelWidth = _textLabel.frame.size.width;
    CGFloat iconSize = _compactMode ? 9.0f : 11.0f;
    CGFloat gap = _compactMode ? 3.0f : 4.0f;
    CGFloat contentWidth = iconSize + gap + labelWidth;
    CGFloat startX = (self.bounds.size.width - contentWidth) / 2.0f;

    _iconView.frame = CGRectMake(startX, (self.bounds.size.height - iconSize) / 2.0f, iconSize, iconSize);
    _textLabel.frame = CGRectMake(startX + iconSize + gap, (self.bounds.size.height - _textLabel.frame.size.height) / 2.0f, labelWidth, _textLabel.frame.size.height);
}

- (UIMenu *)buildContextMenu API_AVAILABLE(ios(14.0)) {
    TJScrobbleStateClient *mgr = [TJScrobbleStateClient sharedInstance];
    NSString *user = mgr.username ?: @"";
    NSString *track = mgr.trackTitle ?: @"Current Song";
    NSString *artist = mgr.artistName ?: @"Unknown Artist";
    NSString *album = mgr.albumTitle ?: @"";

    NSString *header = nil;
    if (mgr.state == TJScrobbleStateScrobbled) {
        header = [NSString stringWithFormat:@"Scrobbled as @%@", user];
    } else if (mgr.state == TJScrobbleStateCountingDown) {
        header = [NSString stringWithFormat:@"Scrobbling in %lds", (long)mgr.remainingCountdownSeconds];
    } else if (mgr.state == TJScrobbleStateBlacklisted) {
        header = @"Scrobbling disabled for this track";
    } else {
        header = @"Last.fm";
    }

    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];

    UIAction *statusAction = [UIAction actionWithTitle:header
                                                 image:[UIImage systemImageNamed:@"info.circle"]
                                            identifier:nil
                                               handler:^(__unused UIAction *action) {}];
    statusAction.attributes = UIMenuElementAttributesDisabled;
    [actions addObject:statusAction];

    if (artist && artist.length > 0) {
        NSString *title = [NSString stringWithFormat:@"Blacklist Artist: %@", artist];
        UIAction *blArtist = [UIAction actionWithTitle:title
                                                 image:[UIImage systemImageNamed:@"person.crop.circle.badge.xmark"]
                                            identifier:nil
                                               handler:^(UIAction *action) {
            [[TJScrobbleStateClient sharedInstance] requestBlacklistCurrentArtist];
        }];
        [actions addObject:blArtist];
    }

    if (album && album.length > 0) {
        NSString *title = [NSString stringWithFormat:@"Blacklist Album: %@", album];
        UIAction *blAlbum = [UIAction actionWithTitle:title
                                                image:[UIImage systemImageNamed:@"opticaldisc"]
                                           identifier:nil
                                              handler:^(UIAction *action) {
            [[TJScrobbleStateClient sharedInstance] requestBlacklistCurrentAlbum];
        }];
        [actions addObject:blAlbum];
    }

    if (user && user.length > 0) {
        UIAction *openProfile = [UIAction actionWithTitle:@"Open Last.fm Profile"
                                                    image:[UIImage systemImageNamed:@"safari"]
                                               identifier:nil
                                                  handler:^(UIAction *action) {
            NSString *urlStr = [NSString stringWithFormat:@"https://www.last.fm/user/%@", user];
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlStr] options:@{} completionHandler:nil];
        }];
        [actions addObject:openProfile];
    }

    return [UIMenu menuWithTitle:track children:actions];
}

@end
