#import "TJScrobbleStateClient.h"
#import "TJLastFmShared.h"

NSString *const kTJScrobbleStateChangedNotification = @"TJScrobbleStateChangedNotification";

@interface TJScrobbleStateClient () {
    NSDictionary *_snapshot;
}
- (void)reload;
@end

@implementation TJScrobbleStateClient

+ (instancetype)sharedInstance {
    static TJScrobbleStateClient *sInstance = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{ sInstance = [[self alloc] init]; });
    return sInstance;
}

static void TJOnScrobbleStateChangedDarwin(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[TJScrobbleStateClient sharedInstance] reload];
    });
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                        TJOnScrobbleStateChangedDarwin,
                                        (__bridge CFStringRef)kTJScrobbleStateChangedDarwinNotification,
                                        NULL, CFNotificationSuspensionBehaviorCoalesce);
    }
    return self;
}

- (void)reload {
    _snapshot = [NSDictionary dictionaryWithContentsOfFile:kTJScrobbleStateFile];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTJScrobbleStateChangedNotification object:nil];
}

- (TJScrobbleState)state { return (TJScrobbleState)[_snapshot[@"state"] integerValue]; }

- (NSString * _Nullable)trackTitle {
    NSString *v = _snapshot[@"title"];
    return v.length > 0 ? v : nil;
}

- (NSString * _Nullable)artistName {
    NSString *v = _snapshot[@"artist"];
    return v.length > 0 ? v : nil;
}

- (NSString * _Nullable)albumTitle {
    NSString *v = _snapshot[@"album"];
    return v.length > 0 ? v : nil;
}

- (NSString * _Nullable)username {
    NSString *v = _snapshot[@"username"];
    return v.length > 0 ? v : nil;
}

- (BOOL)isLoggedIn { return [_snapshot[@"loggedIn"] boolValue]; }

- (NSInteger)remainingCountdownSeconds {
    if (self.state != TJScrobbleStateCountingDown) return 0;
    NSTimeInterval target = [_snapshot[@"target"] doubleValue];
    NSTimeInterval listenedSnapshot = [_snapshot[@"listenedSnapshot"] doubleValue];
    NSTimeInterval snapshotTime = [_snapshot[@"snapshotTime"] doubleValue];
    BOOL isPlaying = [_snapshot[@"isPlaying"] boolValue];

    NSTimeInterval listened = listenedSnapshot;
    if (isPlaying && snapshotTime > 0.0) {
        listened += ([[NSDate date] timeIntervalSince1970] - snapshotTime);
    }
    return MAX(0, (NSInteger)ceil(target - listened));
}

- (void)requestBlacklistCurrentArtist {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kTJBlacklistArtistDarwinNotification, NULL, NULL, YES);
}

- (void)requestBlacklistCurrentAlbum {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kTJBlacklistAlbumDarwinNotification, NULL, NULL, YES);
}

- (void)requestFlushOfflineQueue {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kTJFlushQueueDarwinNotification, NULL, NULL, YES);
}

@end
