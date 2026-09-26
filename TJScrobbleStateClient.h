#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TJScrobbleState) {
    TJScrobbleStateIdle = 0,
    TJScrobbleStateCountingDown = 1,
    TJScrobbleStateScrobbled = 2,
    TJScrobbleStateBlacklisted = 3,
    TJScrobbleStateDisabled = 4
};

extern NSString *const kTJScrobbleStateChangedNotification;

@interface TJScrobbleStateClient : NSObject

+ (instancetype)sharedInstance;

@property(nonatomic, readonly) TJScrobbleState state;
@property(nonatomic, readonly, copy, nullable) NSString *trackTitle;
@property(nonatomic, readonly, copy, nullable) NSString *artistName;
@property(nonatomic, readonly, copy, nullable) NSString *albumTitle;
@property(nonatomic, readonly, copy, nullable) NSString *username;
@property(nonatomic, readonly) BOOL isLoggedIn;
@property(nonatomic, readonly) NSInteger remainingCountdownSeconds;

- (void)requestBlacklistCurrentArtist;
- (void)requestBlacklistCurrentAlbum;
- (void)requestFlushOfflineQueue;

@end

NS_ASSUME_NONNULL_END
