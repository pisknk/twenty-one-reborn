#import "TJLastFmManager.h"
#import "TJLastFmShared.h"
#import "TJPrefsStore.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/stat.h>

typedef void (*TJMRRegisterFunc)(dispatch_queue_t);
typedef void (*TJMRGetNowPlayingInfoFunc)(dispatch_queue_t, void (^)(NSDictionary * _Nullable information));

static TJMRGetNowPlayingInfoFunc sMRGetNowPlayingInfo = NULL;

static void TJOnFlushQueueDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void TJOnBlacklistArtistDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);
static void TJOnBlacklistAlbumDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo);

@interface TJLastFmManager () {
    dispatch_queue_t _ioQueue;
    dispatch_source_t _dueTimer;
    BOOL _isFlushingQueue;

    NSTimeInterval _activeListenedSeconds;
    NSTimeInterval _segmentStartWallClock;
    NSTimeInterval _targetScrobbleSeconds;
    BOOL _hasScrobbledCurrent;
    BOOL _isNowPlayingSent;
    time_t _playbackStartEpoch;
    NSString *_currentTrackKey;
}

- (void)migrateBlacklistFormatIfNeeded;
- (void)onPrefsChanged:(NSNotification *)note;
- (void)onMediaRemoteEvent:(NSNotification *)note;
- (BOOL)isMusicNowPlayingApp;
- (void)refreshNowPlayingInfo;
- (void)handleNowPlayingInfo:(NSDictionary * _Nullable)info;
- (void)beginTrackWithKey:(NSString *)key title:(NSString *)title artist:(NSString *)artist album:(NSString * _Nullable)album duration:(NSTimeInterval)duration;
- (void)recomputeTarget;
- (NSTimeInterval)currentActiveListenedSeconds;
- (void)setPlaying:(BOOL)isPlaying;
- (void)finalizeCurrentTrackIfDue;
- (void)scheduleDueTimer;
- (void)sendNowPlayingForCurrentTrack;
- (void)performScrobbleForCurrentTrack;
- (void)sendPostRequestWithParams:(NSDictionary<NSString *, NSString *> *)params completion:(void (^ _Nullable)(BOOL success, NSInteger lastfmErrorCode))completion;
- (void)writeQueueArray:(NSArray *)queue;
- (void)enqueueOfflineScrobble:(NSDictionary *)fields;
- (void)writeSharedStateFile;

@end

@implementation TJLastFmManager

+ (instancetype)sharedInstance {
    static TJLastFmManager *sManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sManager = [[TJLastFmManager alloc] init];
    });
    return sManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentState = TJScrobbleStateIdle;
        _ioQueue = dispatch_queue_create("com.twentyone.lastfm.io", DISPATCH_QUEUE_SERIAL);

        dispatch_async(_ioQueue, ^{
            [[NSFileManager defaultManager] removeItemAtPath:kTJLegacyOfflineQueueFile error:nil];
        });

        [self migrateBlacklistFormatIfNeeded];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onPrefsChanged:)
                                                     name:TJPrefsStoreChangedNotification
                                                   object:nil];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                        TJOnFlushQueueDarwinNotification, (__bridge CFStringRef)kTJFlushQueueDarwinNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                        TJOnBlacklistArtistDarwinNotification, (__bridge CFStringRef)kTJBlacklistArtistDarwinNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge const void *)self,
                                        TJOnBlacklistAlbumDarwinNotification, (__bridge CFStringRef)kTJBlacklistAlbumDarwinNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
    }
    return self;
}

#pragma mark - Darwin notification trampolines

static void TJOnFlushQueueDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[TJLastFmManager sharedInstance] flushOfflineQueue];
    });
}

static void TJOnBlacklistArtistDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TJLastFmManager *mgr = [TJLastFmManager sharedInstance];
        if (mgr.currentArtistName.length > 0) [mgr addArtistToBlacklist:mgr.currentArtistName];
    });
}

static void TJOnBlacklistAlbumDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TJLastFmManager *mgr = [TJLastFmManager sharedInstance];
        if (mgr.currentAlbumTitle.length > 0) [mgr addAlbumToBlacklist:mgr.currentAlbumTitle];
    });
}

#pragma mark - Startup

- (void)start {
    TJMRRegisterFunc regFunc = (TJMRRegisterFunc)dlsym(RTLD_DEFAULT, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (regFunc) regFunc(dispatch_get_main_queue());

    sMRGetNowPlayingInfo = (TJMRGetNowPlayingInfoFunc)dlsym(RTLD_DEFAULT, "MRMediaRemoteGetNowPlayingInfo");

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onMediaRemoteEvent:)
                                                 name:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onMediaRemoteEvent:)
                                                 name:@"kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onMediaRemoteEvent:)
                                                 name:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onMediaRemoteEvent:)
                                                 name:@"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
                                               object:nil];

    [self refreshNowPlayingInfo];
    [self flushOfflineQueue];
}

- (void)onMediaRemoteEvent:(NSNotification *)note {
    [self refreshNowPlayingInfo];
}

#pragma mark - App identification

- (BOOL)isMusicNowPlayingApp {
    Class cls = NSClassFromString(@"SBMediaController");
    if (!cls || ![cls respondsToSelector:@selector(sharedInstance)]) return YES;
    id controller = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(sharedInstance));
    if (!controller || ![controller respondsToSelector:@selector(nowPlayingApplication)]) return YES;
    id app = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(nowPlayingApplication));
    if (!app || ![app respondsToSelector:@selector(bundleIdentifier)]) return YES;
    NSString *bid = ((id (*)(id, SEL))objc_msgSend)(app, @selector(bundleIdentifier));
    return !bid || [bid isEqualToString:@"com.apple.Music"];
}

#pragma mark - MediaRemote data pump

- (void)refreshNowPlayingInfo {
    if (!sMRGetNowPlayingInfo) return;
    if (![self isMusicNowPlayingApp]) {
        [self setPlaying:NO];
        return;
    }
    __weak typeof(self) weakSelf = self;
    sMRGetNowPlayingInfo(dispatch_get_main_queue(), ^(NSDictionary * _Nullable info) {
        [weakSelf handleNowPlayingInfo:info];
    });
}

- (void)handleNowPlayingInfo:(NSDictionary * _Nullable)info {
    if (![info isKindOfClass:[NSDictionary class]]) return;

    NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
    NSString *artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
    NSString *album = info[@"kMRMediaRemoteNowPlayingInfoAlbum"];
    NSNumber *durNum = info[@"kMRMediaRemoteNowPlayingInfoDuration"];
    NSNumber *elapsedNum = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
    NSNumber *rateNum = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
    id uid = info[@"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"] ?: info[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"];

    if (!title.length || !artist.length) return;

    NSString *trackKey = uid ? [NSString stringWithFormat:@"%@", uid] : [NSString stringWithFormat:@"%@ - %@", title, artist];
    NSTimeInterval duration = durNum ? durNum.doubleValue : 0.0;
    NSTimeInterval elapsed = elapsedNum ? elapsedNum.doubleValue : -1.0;
    BOOL isPlaying = rateNum ? (rateNum.doubleValue > 0.0) : _isPlaying;

    BOOL isDifferentTrack = !_currentTrackKey || ![trackKey isEqualToString:_currentTrackKey];
    BOOL isReplay = NO;
    if (!isDifferentTrack && _hasScrobbledCurrent && elapsed >= 0.0 && elapsed < 2.0) {
        isReplay = YES;
    }

    if (isDifferentTrack || isReplay) {
        [self finalizeCurrentTrackIfDue];
        [self beginTrackWithKey:trackKey title:title artist:artist album:album duration:duration];
    } else if (duration > 0.0 && fabs(duration - _currentTrackDuration) > 1.0) {
        _currentTrackDuration = duration;
        if (_currentState == TJScrobbleStateCountingDown) [self recomputeTarget];
    }

    [self setPlaying:isPlaying];
    [self scheduleDueTimer];
    [self writeSharedStateFile];
}

#pragma mark - Track lifecycle

- (void)beginTrackWithKey:(NSString *)key title:(NSString *)title artist:(NSString *)artist album:(NSString * _Nullable)album duration:(NSTimeInterval)duration {
    _currentTrackKey = key;
    _currentTrackTitle = [title copy];
    _currentArtistName = [artist copy];
    _currentAlbumTitle = album.length > 0 ? [album copy] : nil;
    _currentTrackDuration = duration;
    _activeListenedSeconds = 0.0;
    _segmentStartWallClock = 0.0;
    _hasScrobbledCurrent = NO;
    _isNowPlayingSent = NO;
    _playbackStartEpoch = (time_t)[[NSDate date] timeIntervalSince1970];

    if (!prefBool(@"lastFmEnabled", YES) || ![self isLoggedIn]) {
        _currentState = TJScrobbleStateDisabled;
    } else if ([self isArtistBlacklisted:artist] || (album.length > 0 && [self isAlbumBlacklisted:album])) {
        _currentState = TJScrobbleStateBlacklisted;
    } else if (duration > 0.0 && duration < 30.0) {
        _currentState = TJScrobbleStateIdle;
    } else {
        [self recomputeTarget];
        _currentState = TJScrobbleStateCountingDown;
        [self flushOfflineQueue];
    }
}

- (void)recomputeTarget {
    CGFloat userPct = prefFloat(@"lastFmThreshold", 0.50f);
    CGFloat effectivePct = MAX(0.20f, MIN(1.00f, userPct));
    NSTimeInterval base = _currentTrackDuration > 0.0 ? _currentTrackDuration : 180.0;
    _targetScrobbleSeconds = MIN(base * effectivePct, 240.0);
    if (_targetScrobbleSeconds < 1.0) _targetScrobbleSeconds = 15.0;
}

- (NSTimeInterval)currentActiveListenedSeconds {
    NSTimeInterval total = _activeListenedSeconds;
    if (_isPlaying && _segmentStartWallClock > 0.0) {
        total += (CFAbsoluteTimeGetCurrent() - _segmentStartWallClock);
    }
    return total;
}

- (void)setPlaying:(BOOL)isPlaying {
    if (_isPlaying == isPlaying) return;
    if (isPlaying) {
        _segmentStartWallClock = CFAbsoluteTimeGetCurrent();
        if (!_isNowPlayingSent && _currentState == TJScrobbleStateCountingDown) {
            [self sendNowPlayingForCurrentTrack];
        }
    } else if (_segmentStartWallClock > 0.0) {
        _activeListenedSeconds += (CFAbsoluteTimeGetCurrent() - _segmentStartWallClock);
        _segmentStartWallClock = 0.0;
    }
    _isPlaying = isPlaying;
}

- (void)finalizeCurrentTrackIfDue {
    if (_dueTimer) { dispatch_source_cancel(_dueTimer); _dueTimer = nil; }
    if (_isPlaying && _segmentStartWallClock > 0.0) {
        _activeListenedSeconds += (CFAbsoluteTimeGetCurrent() - _segmentStartWallClock);
        _segmentStartWallClock = _isPlaying ? CFAbsoluteTimeGetCurrent() : 0.0;
    }
    [self checkAndPerformScrobbleIfDue];
}

- (void)scheduleDueTimer {
    if (_dueTimer) { dispatch_source_cancel(_dueTimer); _dueTimer = nil; }
    if (_currentState != TJScrobbleStateCountingDown || !_isPlaying || _hasScrobbledCurrent) return;

    NSTimeInterval remaining = _targetScrobbleSeconds - [self currentActiveListenedSeconds];
    if (remaining <= 0.0) { [self checkAndPerformScrobbleIfDue]; return; }

    _dueTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_dueTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ceil(remaining) * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 1 * NSEC_PER_SEC);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_dueTimer, ^{
        [weakSelf checkAndPerformScrobbleIfDue];
        [weakSelf writeSharedStateFile];
    });
    dispatch_resume(_dueTimer);
}

- (void)checkAndPerformScrobbleIfDue {
    if (!prefBool(@"lastFmEnabled", YES) || ![self isLoggedIn]) return;
    if (_currentState != TJScrobbleStateCountingDown || _hasScrobbledCurrent) return;
    if (!_currentTrackTitle || !_currentArtistName) return;

    if ([self currentActiveListenedSeconds] >= _targetScrobbleSeconds) {
        [self performScrobbleForCurrentTrack];
    }
}

#pragma mark - Session

- (BOOL)isLoggedIn {
    NSString *sk = self.sessionKey;
    return sk.length > 0;
}

- (NSString *)sessionUsername { return prefString(@"lastFmUsername", nil); }
- (NSString *)sessionKey { return prefString(@"lastFmSessionKey", nil); }

- (void)setSessionKey:(NSString *)key username:(NSString *)username {
    prefSetObject(@"lastFmSessionKey", key);
    prefSetObject(@"lastFmUsername", username);
    [self reloadPreferencesAndResetIfNeeded];
}

- (void)logout {
    [self setSessionKey:nil username:nil];
}

- (void)onPrefsChanged:(NSNotification *)note {
    [self reloadPreferencesAndResetIfNeeded];
}

- (void)reloadPreferencesAndResetIfNeeded {
    if (prefBool(@"lastFmEnabled", YES) && [self isLoggedIn]) {
        if (_currentTrackTitle && _currentArtistName) {
            BOOL blacklisted = [self isArtistBlacklisted:_currentArtistName] ||
                               (_currentAlbumTitle.length > 0 && [self isAlbumBlacklisted:_currentAlbumTitle]);
            if (blacklisted) {
                _currentState = TJScrobbleStateBlacklisted;
            } else if (_currentState == TJScrobbleStateDisabled || _currentState == TJScrobbleStateBlacklisted) {
                [self recomputeTarget];
                _currentState = TJScrobbleStateCountingDown;
                [self sendNowPlayingForCurrentTrack];
            }
        }
        [self flushOfflineQueue];
    } else {
        _currentState = TJScrobbleStateDisabled;
    }
    [self scheduleDueTimer];
    [self writeSharedStateFile];
}

#pragma mark - Blacklist

- (void)migrateBlacklistFormatIfNeeded {
    NSNumber *fmt = prefValue(@"blacklistFormat");
    if (fmt.integerValue >= 2) return;
    NSString *artists = prefString(@"lastFmBlacklistedArtists", nil);
    NSString *albums = prefString(@"lastFmBlacklistedAlbums", nil);
    if (artists.length > 0) prefSetObject(@"lastFmBlacklistedArtists", tj_blacklistMigrateLegacyFormat(artists));
    if (albums.length > 0) prefSetObject(@"lastFmBlacklistedAlbums", tj_blacklistMigrateLegacyFormat(albums));
    prefSetObject(@"blacklistFormat", @2);
}

- (BOOL)isArtistBlacklisted:(NSString *)artist {
    return tj_blacklistContains(prefString(@"lastFmBlacklistedArtists", nil), artist);
}

- (BOOL)isAlbumBlacklisted:(NSString *)album {
    return tj_blacklistContains(prefString(@"lastFmBlacklistedAlbums", nil), album);
}

- (void)addArtistToBlacklist:(NSString *)artist {
    if (!artist.length) return;
    prefSetObject(@"lastFmBlacklistedArtists", tj_blacklistByAdding(prefString(@"lastFmBlacklistedArtists", nil), artist));
    if ([artist isEqualToString:_currentArtistName] && _currentState != TJScrobbleStateBlacklisted) {
        if (_dueTimer) { dispatch_source_cancel(_dueTimer); _dueTimer = nil; }
        _currentState = TJScrobbleStateBlacklisted;
        [self writeSharedStateFile];
    }
}

- (void)addAlbumToBlacklist:(NSString *)album {
    if (!album.length) return;
    prefSetObject(@"lastFmBlacklistedAlbums", tj_blacklistByAdding(prefString(@"lastFmBlacklistedAlbums", nil), album));
    if ([album isEqualToString:_currentAlbumTitle] && _currentState != TJScrobbleStateBlacklisted) {
        if (_dueTimer) { dispatch_source_cancel(_dueTimer); _dueTimer = nil; }
        _currentState = TJScrobbleStateBlacklisted;
        [self writeSharedStateFile];
    }
}

#pragma mark - Network

- (void)sendNowPlayingForCurrentTrack {
    if (!prefBool(@"lastFmNowPlayingEnabled", YES)) return;
    if (_isNowPlayingSent || !_currentTrackTitle || !_currentArtistName) return;
    NSString *sk = self.sessionKey;
    if (!sk.length) return;

    _isNowPlayingSent = YES;

    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    params[@"method"] = @"track.updateNowPlaying";
    params[@"api_key"] = kTJLastFmAPIKey;
    params[@"sk"] = sk;
    params[@"artist"] = _currentArtistName;
    params[@"track"] = _currentTrackTitle;
    if (_currentAlbumTitle.length > 0) params[@"album"] = _currentAlbumTitle;
    if (_currentTrackDuration > 0.0) params[@"duration"] = [NSString stringWithFormat:@"%ld", (long)_currentTrackDuration];
    params[@"api_sig"] = tj_lastfm_signature(params, kTJLastFmAPISecret);
    params[@"format"] = @"json";

    [self sendPostRequestWithParams:params completion:nil];
}

- (void)performScrobbleForCurrentTrack {
    if (_hasScrobbledCurrent || !_currentTrackTitle || !_currentArtistName) return;
    NSString *sk = self.sessionKey;
    if (!sk.length) return;

    _hasScrobbledCurrent = YES;
    _currentState = TJScrobbleStateScrobbled;
    if (_dueTimer) { dispatch_source_cancel(_dueTimer); _dueTimer = nil; }
    [self writeSharedStateFile];

    NSDictionary *fields = @{
        @"artist": _currentArtistName,
        @"track": _currentTrackTitle,
        @"album": _currentAlbumTitle ?: @"",
        @"duration": @(_currentTrackDuration),
        @"timestamp": @((double)_playbackStartEpoch),
    };

    NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
    params[@"method"] = @"track.scrobble";
    params[@"api_key"] = kTJLastFmAPIKey;
    params[@"sk"] = sk;
    params[@"artist"] = _currentArtistName;
    params[@"track"] = _currentTrackTitle;
    params[@"timestamp"] = [NSString stringWithFormat:@"%ld", (long)_playbackStartEpoch];
    if (_currentAlbumTitle.length > 0) params[@"album"] = _currentAlbumTitle;
    if (_currentTrackDuration > 0.0) params[@"duration"] = [NSString stringWithFormat:@"%ld", (long)_currentTrackDuration];
    params[@"api_sig"] = tj_lastfm_signature(params, kTJLastFmAPISecret);
    params[@"format"] = @"json";

    __weak typeof(self) weakSelf = self;
    [self sendPostRequestWithParams:params completion:^(BOOL success, NSInteger lastfmErrorCode) {
        if (!success) {
            [weakSelf enqueueOfflineScrobble:fields];
        }
    }];
}

- (void)sendPostRequestWithParams:(NSDictionary<NSString *, NSString *> *)params completion:(void (^ _Nullable)(BOOL success, NSInteger lastfmErrorCode))completion {
    NSMutableString *bodyStr = [NSMutableString string];
    BOOL first = YES;
    for (NSString *k in params) {
        if (!first) [bodyStr appendString:@"&"];
        [bodyStr appendFormat:@"%@=%@", tj_urlEncode(k), tj_urlEncode(params[k])];
        first = NO;
    }

    NSData *bodyData = [bodyStr dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kTJLastFmAPIBaseURL]
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:15.0];
    req.HTTPMethod = @"POST";
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = bodyData;

    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        BOOL ok = NO;
        NSInteger errCode = 0;
        if (!err && resp && [resp isKindOfClass:[NSHTTPURLResponse class]] && data) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
            @try {
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                id errVal = json[@"error"];
                if (errVal) {
                    errCode = [errVal integerValue];
                } else if (http.statusCode == 200) {
                    ok = YES;
                }
            } @catch (__unused id e) {
                if (http.statusCode == 200) ok = YES;
            }
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(ok, errCode); });
    }] resume];
}

#pragma mark - Offline queue

- (void)writeQueueArray:(NSArray *)queue {
    [[NSFileManager defaultManager] createDirectoryAtPath:kTJSharedDir
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0777}
                                                    error:nil];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:queue
                                                              format:NSPropertyListXMLFormat_v1_0
                                                             options:0
                                                               error:nil];
    if (data) {
        [data writeToFile:kTJOfflineQueueFile options:NSDataWritingAtomic error:nil];
        chmod([kTJOfflineQueueFile UTF8String], 0666);
    }
}

- (void)enqueueOfflineScrobble:(NSDictionary *)fields {
    dispatch_async(_ioQueue, ^{
        NSMutableArray *queue = [NSMutableArray arrayWithContentsOfFile:kTJOfflineQueueFile] ?: [NSMutableArray array];
        [queue addObject:fields];
        [self writeQueueArray:queue];
    });
}

- (void)flushOfflineQueue {
    dispatch_async(_ioQueue, ^{
        if (self->_isFlushingQueue) return;
        self->_isFlushingQueue = YES;

        NSMutableArray *queue = [NSMutableArray arrayWithContentsOfFile:kTJOfflineQueueFile] ?: [NSMutableArray array];
        NSString *sk = self.sessionKey;
        if (queue.count == 0 || !sk.length) {
            self->_isFlushingQueue = NO;
            return;
        }

        NSTimeInterval cutoff = [[NSDate date] timeIntervalSince1970] - (14.0 * 24.0 * 3600.0);
        NSMutableArray *fresh = [NSMutableArray array];
        for (NSDictionary *entry in queue) {
            if ([entry[@"timestamp"] doubleValue] >= cutoff) [fresh addObject:entry];
        }

        NSArray *batch = [fresh subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)50, fresh.count))];
        if (batch.count == 0) {
            [self writeQueueArray:fresh];
            self->_isFlushingQueue = NO;
            return;
        }

        NSMutableDictionary<NSString *, NSString *> *params = [NSMutableDictionary dictionary];
        params[@"method"] = @"track.scrobble";
        params[@"api_key"] = kTJLastFmAPIKey;
        params[@"sk"] = sk;
        [batch enumerateObjectsUsingBlock:^(NSDictionary *entry, NSUInteger i, BOOL *stop) {
            params[[NSString stringWithFormat:@"artist[%lu]", (unsigned long)i]] = entry[@"artist"] ?: @"";
            params[[NSString stringWithFormat:@"track[%lu]", (unsigned long)i]] = entry[@"track"] ?: @"";
            if ([entry[@"album"] length] > 0) params[[NSString stringWithFormat:@"album[%lu]", (unsigned long)i]] = entry[@"album"];
            NSTimeInterval dur = [entry[@"duration"] doubleValue];
            if (dur > 0.0) params[[NSString stringWithFormat:@"duration[%lu]", (unsigned long)i]] = [NSString stringWithFormat:@"%ld", (long)dur];
            params[[NSString stringWithFormat:@"timestamp[%lu]", (unsigned long)i]] = [NSString stringWithFormat:@"%ld", (long)[entry[@"timestamp"] doubleValue]];
        }];
        params[@"api_sig"] = tj_lastfm_signature(params, kTJLastFmAPISecret);
        params[@"format"] = @"json";

        [self sendPostRequestWithParams:params completion:^(BOOL success, NSInteger lastfmErrorCode) {
            dispatch_async(self->_ioQueue, ^{
                NSMutableArray *remaining = [fresh mutableCopy];
                BOOL sessionInvalid = (lastfmErrorCode == 9);
                BOOL permanentFailure = !success && lastfmErrorCode != 0 && lastfmErrorCode != 11 && lastfmErrorCode != 16 && lastfmErrorCode != 9;
                if (success || permanentFailure) {
                    [remaining removeObjectsInArray:batch];
                }
                [self writeQueueArray:remaining];
                self->_isFlushingQueue = NO;

                if (sessionInvalid) return;
                if (success && remaining.count > 0) {
                    [self flushOfflineQueue];
                } else if (!success && !permanentFailure && remaining.count > 0) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), self->_ioQueue, ^{
                        [self flushOfflineQueue];
                    });
                }
            });
        }];
    });
}

- (NSUInteger)offlineQueueCount {
    NSArray *arr = [NSArray arrayWithContentsOfFile:kTJOfflineQueueFile];
    return arr.count;
}

#pragma mark - Shared state file (consumed by TJScrobbleStateClient in Music.app/Settings)

- (void)writeSharedStateFile {
    NSDictionary *state = @{
        @"state": @(_currentState),
        @"title": _currentTrackTitle ?: @"",
        @"artist": _currentArtistName ?: @"",
        @"album": _currentAlbumTitle ?: @"",
        @"target": @(_targetScrobbleSeconds),
        @"listenedSnapshot": @([self currentActiveListenedSeconds]),
        @"snapshotTime": @([[NSDate date] timeIntervalSince1970]),
        @"isPlaying": @(_isPlaying),
        @"loggedIn": @(self.isLoggedIn),
        @"username": self.sessionUsername ?: @"",
    };
    dispatch_async(_ioQueue, ^{
        [[NSFileManager defaultManager] createDirectoryAtPath:kTJSharedDir
                                  withIntermediateDirectories:YES
                                                   attributes:@{NSFilePosixPermissions: @0777}
                                                        error:nil];
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:state
                                                                  format:NSPropertyListXMLFormat_v1_0
                                                                 options:0
                                                                   error:nil];
        if (data) {
            [data writeToFile:kTJScrobbleStateFile options:NSDataWritingAtomic error:nil];
            chmod([kTJScrobbleStateFile UTF8String], 0666);
        }
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             (__bridge CFStringRef)kTJScrobbleStateChangedDarwinNotification,
                                             NULL, NULL, YES);
    });
}

@end
