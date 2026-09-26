#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TJScrobbleState) {
    TJScrobbleStateIdle = 0,
    TJScrobbleStateCountingDown = 1,
    TJScrobbleStateScrobbled = 2,
    TJScrobbleStateBlacklisted = 3,
    TJScrobbleStateDisabled = 4
};

@interface TJLastFmManager : NSObject

+ (instancetype)sharedInstance;

@property(nonatomic, readonly, copy, nullable) NSString *currentTrackTitle;
@property(nonatomic, readonly, copy, nullable) NSString *currentArtistName;
@property(nonatomic, readonly, copy, nullable) NSString *currentAlbumTitle;
@property(nonatomic, readonly) NSTimeInterval currentTrackDuration;
@property(nonatomic, readonly) TJScrobbleState currentState;
@property(nonatomic, readonly) BOOL isLoggedIn;
@property(nonatomic, readonly, copy, nullable) NSString *sessionUsername;
@property(nonatomic, readonly, copy, nullable) NSString *sessionKey;
@property(nonatomic, readonly) BOOL isPlaying;

- (void)start;

- (void)setSessionKey:(nullable NSString *)key username:(nullable NSString *)username;
- (void)logout;
- (void)reloadPreferencesAndResetIfNeeded;

- (void)checkAndPerformScrobbleIfDue;

- (BOOL)isArtistBlacklisted:(NSString *)artist;
- (BOOL)isAlbumBlacklisted:(NSString *)album;
- (void)addArtistToBlacklist:(NSString *)artist;
- (void)addAlbumToBlacklist:(NSString *)album;

- (void)flushOfflineQueue;
- (NSUInteger)offlineQueueCount;

@end

NS_ASSUME_NONNULL_END
