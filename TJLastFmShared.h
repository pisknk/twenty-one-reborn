#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kTJLastFmAPIKey;
extern NSString *const kTJLastFmAPISecret;
extern NSString *const kTJLastFmAPIBaseURL;

extern NSString *const kTJSharedDir;
extern NSString *const kTJOfflineQueueFile;
extern NSString *const kTJScrobbleStateFile;
extern NSString *const kTJLegacyOfflineQueueFile;

extern NSString *const kTJScrobbleStateChangedDarwinNotification;
extern NSString *const kTJFlushQueueDarwinNotification;
extern NSString *const kTJBlacklistArtistDarwinNotification;
extern NSString *const kTJBlacklistAlbumDarwinNotification;

NSString *tj_md5(NSString *input);
NSString *tj_urlEncode(NSString * _Nullable str);

NSString *tj_lastfm_signature(NSDictionary<NSString *, NSString *> *params, NSString *secret);

NSArray<NSString *> *tj_blacklistEntries(NSString * _Nullable raw);
BOOL tj_blacklistContains(NSString * _Nullable raw, NSString * _Nullable target);
NSString *tj_blacklistByAdding(NSString * _Nullable raw, NSString *newItem);

NSString *tj_blacklistMigrateLegacyFormat(NSString * _Nullable raw);

NS_ASSUME_NONNULL_END
