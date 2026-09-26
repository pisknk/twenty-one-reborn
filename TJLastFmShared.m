#import "TJLastFmShared.h"
#import <CommonCrypto/CommonDigest.h>

NSString *const kTJLastFmAPIKey = @"4e7055dc7eda8fba6de538417cc275b6";
NSString *const kTJLastFmAPISecret = @"9290a8184b5a0075815f74b11ebddf48";
NSString *const kTJLastFmAPIBaseURL = @"https://ws.audioscrobbler.com/2.0/";

NSString *const kTJSharedDir = @"/var/mobile/Media/TwentyOne";
NSString *const kTJOfflineQueueFile = @"/var/mobile/Media/TwentyOne/scrobbles.plist";
NSString *const kTJScrobbleStateFile = @"/var/mobile/Media/TwentyOne/scrobble_state.plist";
NSString *const kTJLegacyOfflineQueueFile = @"/var/mobile/Library/Caches/com.pisknk.twentyone/scrobbles.plist";

NSString *const kTJScrobbleStateChangedDarwinNotification = @"com.pisknk.twentyone.scrobbleState";
NSString *const kTJFlushQueueDarwinNotification = @"com.pisknk.twentyone.flushQueue";
NSString *const kTJBlacklistArtistDarwinNotification = @"com.pisknk.twentyone.blacklistArtist";
NSString *const kTJBlacklistAlbumDarwinNotification = @"com.pisknk.twentyone.blacklistAlbum";

NSString *tj_md5(NSString *input) {
    const char *cstr = [input UTF8String];
    if (!cstr) return @"";
    unsigned char result[CC_MD5_DIGEST_LENGTH];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CC_MD5(cstr, (CC_LONG)strlen(cstr), result);
#pragma clang diagnostic pop
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", result[i]];
    }
    return [hex copy];
}

NSString *tj_urlEncode(NSString *str) {
    if (!str) return @"";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~"];
    return [str stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

NSString *tj_lastfm_signature(NSDictionary<NSString *, NSString *> *params, NSString *secret) {
    NSArray<NSString *> *sortedKeys = [params.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString *sigBase = [NSMutableString string];
    for (NSString *k in sortedKeys) {
        if ([k isEqualToString:@"format"] || [k isEqualToString:@"callback"]) continue;
        [sigBase appendString:k];
        [sigBase appendString:params[k] ?: @""];
    }
    [sigBase appendString:secret];
    return tj_md5(sigBase);
}

NSArray<NSString *> *tj_blacklistEntries(NSString *raw) {
    if (!raw || raw.length == 0) return @[];
    NSArray<NSString *> *lines = [raw componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray<NSString *> *cleaned = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSString *line in lines) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length > 0) [cleaned addObject:t];
    }
    return cleaned;
}

BOOL tj_blacklistContains(NSString *raw, NSString *target) {
    if (!target || target.length == 0) return NO;
    NSString *needle = [[target stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (needle.length == 0) return NO;
    for (NSString *entry in tj_blacklistEntries(raw)) {
        if ([[entry lowercaseString] isEqualToString:needle]) return YES;
    }
    return NO;
}

NSString *tj_blacklistByAdding(NSString *raw, NSString *newItem) {
    NSString *trimmedNew = [newItem stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmedNew.length == 0) return raw ?: @"";
    NSMutableArray<NSString *> *entries = [tj_blacklistEntries(raw) mutableCopy];
    if (tj_blacklistContains(raw, trimmedNew)) return [entries componentsJoinedByString:@"\n"];
    [entries addObject:trimmedNew];
    return [entries componentsJoinedByString:@"\n"];
}

NSString *tj_blacklistMigrateLegacyFormat(NSString *raw) {
    if (!raw || raw.length == 0) return raw ?: @"";
    NSArray<NSString *> *items = [raw componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",\n\r"]];
    NSMutableArray<NSString *> *cleaned = [NSMutableArray arrayWithCapacity:items.count];
    for (NSString *item in items) {
        NSString *t = [item stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length > 0 && ![cleaned containsObject:t]) [cleaned addObject:t];
    }
    return [cleaned componentsJoinedByString:@"\n"];
}
