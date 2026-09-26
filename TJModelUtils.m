#import "TJModelUtils.h"
#import <objc/runtime.h>
#import <objc/message.h>

BOOL tj_isNumericAdamID(NSString * _Nullable s) {
    if (!s || s.length == 0) return NO;
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([s rangeOfCharacterFromSet:nonDigits].location != NSNotFound) return NO;
    return [s longLongValue] > 0;
}

id _Nullable tj_unwrapSongFromPlayingItem(id _Nullable item) {
    if (!item) return nil;
    id current = item;

    if ([current respondsToSelector:@selector(metadataObject)]) {
        id meta = ((id (*)(id, SEL))objc_msgSend)(current, @selector(metadataObject));
        if (meta) current = meta;
    }

    if ([current respondsToSelector:NSSelectorFromString(@"anyObject")]) {
        id any = ((id (*)(id, SEL))objc_msgSend)(current, NSSelectorFromString(@"anyObject"));
        if (any) current = any;
    }

    if ([current respondsToSelector:NSSelectorFromString(@"playlistEntry")]) {
        id pe = ((id (*)(id, SEL))objc_msgSend)(current, NSSelectorFromString(@"playlistEntry"));
        if (pe) current = pe;
    }

    if ([current respondsToSelector:NSSelectorFromString(@"song")]) {
        id s = ((id (*)(id, SEL))objc_msgSend)(current, NSSelectorFromString(@"song"));
        if (s) return s;
    }

    for (NSString *kp in @[@"song", @"playlistEntry.song", @"metadataObject.song", @"metadataObject.playlistEntry.song"]) {
        @try {
            id s = [item valueForKeyPath:kp];
            if (s) return s;
        } @catch (__unused id e) {}
    }

    if ([current respondsToSelector:NSSelectorFromString(@"album")]) {
        return current;
    }

    return current;
}

id _Nullable tj_unwrapAlbumFromPlayingItem(id _Nullable item) {
    if (!item) return nil;

    id song = tj_unwrapSongFromPlayingItem(item);
    if (song && [song respondsToSelector:NSSelectorFromString(@"album")]) {
        id alb = ((id (*)(id, SEL))objc_msgSend)(song, NSSelectorFromString(@"album"));
        if (alb) return alb;
    }

    if ([item respondsToSelector:NSSelectorFromString(@"album")]) {
        id alb = ((id (*)(id, SEL))objc_msgSend)(item, NSSelectorFromString(@"album"));
        if (alb) return alb;
    }

    for (NSString *kp in @[@"song.album", @"album", @"playlistEntry.song.album", @"metadataObject.song.album", @"metadataObject.playlistEntry.song.album"]) {
        @try {
            id alb = [item valueForKeyPath:kp];
            if (alb) return alb;
        } @catch (__unused id e) {}
    }

    return nil;
}

NSString * _Nullable tj_extractAdamID(id _Nullable obj) {
    if (!obj) return nil;

    id song = tj_unwrapSongFromPlayingItem(obj);
    NSArray *candidates = (song && song != obj) ? @[song, obj] : @[obj];

    for (id target in candidates) {
        for (NSString *selName in @[@"subscriptionAdamID", @"adamID", @"purchasedAdamID", @"storeSubscriptionAdamID", @"storePurchasedAdamID", @"storeAdamID"]) {
            SEL s = NSSelectorFromString(selName);
            if ([target respondsToSelector:s]) {
                @try {
                    NSMethodSignature *sig = [target methodSignatureForSelector:s];
                    if (sig && (strcmp([sig methodReturnType], @encode(long long)) == 0 || strcmp([sig methodReturnType], "q") == 0)) {
                        long long val = ((long long (*)(id, SEL))objc_msgSend)(target, s);
                        if (val > 0) return [NSString stringWithFormat:@"%lld", val];
                    } else if (sig && sig.methodReturnType && sig.methodReturnType[0] == '@') {
                        id v = ((id (*)(id, SEL))objc_msgSend)(target, s);
                        if ([v isKindOfClass:[NSNumber class]] && [v longLongValue] > 0) {
                            return [NSString stringWithFormat:@"%lld", [v longLongValue]];
                        }
                        if ([v isKindOfClass:[NSString class]] && tj_isNumericAdamID((NSString *)v)) {
                            return (NSString *)v;
                        }
                    }
                } @catch (__unused id e) {}
            }
        }

        SEL identsSel = NSSelectorFromString(@"identifiers");
        if ([target respondsToSelector:identsSel]) {
            NSMethodSignature *isig = [target methodSignatureForSelector:identsSel];
            id idents = (isig && isig.methodReturnType && isig.methodReturnType[0] == '@') ? ((id (*)(id, SEL))objc_msgSend)(target, identsSel) : nil;
            if (idents) {
                for (NSString *storeSelName in @[@"universalStore", @"store", @"personalStore", @"personalizedStore"]) {
                    SEL usSel = NSSelectorFromString(storeSelName);
                    if ([idents respondsToSelector:usSel]) {
                        NSMethodSignature *ussig = [idents methodSignatureForSelector:usSel];
                        id us = (ussig && ussig.methodReturnType && ussig.methodReturnType[0] == '@') ? ((id (*)(id, SEL))objc_msgSend)(idents, usSel) : nil;
                        if (us) {
                            for (NSString *adamSelName in @[@"subscriptionAdamID", @"adamID", @"purchasedAdamID", @"storeSubscriptionAdamID", @"storePurchasedAdamID", @"storeAdamID"]) {
                                SEL adamSel = NSSelectorFromString(adamSelName);
                                if ([us respondsToSelector:adamSel]) {
                                    @try {
                                        NSMethodSignature *sig = [us methodSignatureForSelector:adamSel];
                                        if (sig && (strcmp([sig methodReturnType], @encode(long long)) == 0 || strcmp([sig methodReturnType], "q") == 0)) {
                                            long long aid = ((long long (*)(id, SEL))objc_msgSend)(us, adamSel);
                                            if (aid > 0) return [NSString stringWithFormat:@"%lld", aid];
                                        } else if (sig && sig.methodReturnType && sig.methodReturnType[0] == '@') {
                                            id aidObj = ((id (*)(id, SEL))objc_msgSend)(us, adamSel);
                                            if ([aidObj isKindOfClass:[NSNumber class]] && [aidObj longLongValue] > 0) {
                                                return [NSString stringWithFormat:@"%lld", [aidObj longLongValue]];
                                            }
                                            if ([aidObj isKindOfClass:[NSString class]] && tj_isNumericAdamID((NSString *)aidObj)) {
                                                return (NSString *)aidObj;
                                            }
                                        }
                                    } @catch (__unused id e) {}
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return nil;
}

NSString * _Nullable tj_extractAlbumAdamID(id _Nullable playingItem) {
    if (!playingItem) return nil;

    id album = tj_unwrapAlbumFromPlayingItem(playingItem);
    if (album) {
        NSString *aid = tj_extractAdamID(album);
        if (aid) return aid;
    }

    for (NSString *kp in @[@"song.album", @"album", @"playlistEntry.song.album", @"metadataObject.song.album", @"metadataObject.playlistEntry.song.album"]) {
        @try {
            id alb = [playingItem valueForKeyPath:kp];
            if (alb) {
                NSString *aid = tj_extractAdamID(alb);
                if (aid) return aid;
            }
        } @catch (__unused id e) {}
    }

    return nil;
}

BOOL tj_albumTitlesMatch(NSString * _Nullable t1, NSString * _Nullable t2) {
    if (!t1 || !t2) return NO;
    NSString *clean1 = [[t1 lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *clean2 = [[t2 lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return clean1.length > 0 && [clean1 isEqualToString:clean2];
}

NSString * _Nullable tj_normalizedKey(NSString * _Nullable s) {
    if (!s) return nil;
    NSString *t = [[s lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return t.length > 0 ? t : nil;
}

NSString * _Nullable tj_extractAlbumTitle(id _Nullable playingItem) {
    if (!playingItem) return nil;

    id album = tj_unwrapAlbumFromPlayingItem(playingItem);
    if (album) {
        for (NSString *key in @[@"title", @"albumTitle", @"name"]) {
            SEL s = NSSelectorFromString(key);
            if ([album respondsToSelector:s]) {
                id res = ((id (*)(id, SEL))objc_msgSend)(album, s);
                if ([res isKindOfClass:[NSString class]] && [res length] > 0) return res;
            }
            @try {
                id res = [album valueForKey:key];
                if ([res isKindOfClass:[NSString class]] && [res length] > 0) return res;
            } @catch (__unused id e) {}
        }
    }

    for (NSString *kp in @[@"albumTitle", @"containerTitle", @"albumName", @"song.album.title", @"metadataObject.song.album.title", @"metadataObject.playlistEntry.song.album.title"]) {
        @try {
            id res = [playingItem valueForKeyPath:kp];
            if ([res isKindOfClass:[NSString class]] && [res length] > 0) return res;
        } @catch (__unused id e) {}
    }

    return nil;
}

id _Nullable tj_extractNowPlayingResponse(id _Nullable target) {
    if (!target) return nil;
    for (NSString *selName in @[@"nowPlayingResponse", @"accessibilityNowPlayingResponse", @"response"]) {
        SEL sel = NSSelectorFromString(selName);
        if ([target respondsToSelector:sel]) {
            return ((id (*)(id, SEL))objc_msgSend)(target, sel);
        }
    }
    return nil;
}

id _Nullable tj_extractPlayingItem(id _Nullable target) {
    if (!target) return nil;

    id pi = nil;
    @try { pi = [target valueForKey:@"playingItem"]; } @catch (__unused id e) {}
    if (pi) return pi;

    if ([target respondsToSelector:NSSelectorFromString(@"controlsViewController")]) {
        @try {
            UIViewController *ctrl = ((id (*)(id, SEL))objc_msgSend)(target, NSSelectorFromString(@"controlsViewController"));
            if (ctrl) {
                id cpi = tj_extractPlayingItem(ctrl);
                if (cpi) return cpi;
            }
        } @catch (__unused id e) {}
    }

    if ([target isKindOfClass:[UIViewController class]]) {
        UIViewController *tvc = (UIViewController *)target;
        for (UIViewController *child in tvc.childViewControllers) {
            id cpi = nil;
            @try { cpi = [child valueForKey:@"playingItem"]; } @catch (__unused id e) {}
            if (cpi) return cpi;

            id resp = tj_extractNowPlayingResponse(child);
            if (resp) {
                id tracklist = nil;
                if ([resp respondsToSelector:@selector(tracklist)]) {
                    tracklist = ((id (*)(id, SEL))objc_msgSend)(resp, @selector(tracklist));
                }
                if (tracklist && [tracklist respondsToSelector:@selector(playingItem)]) {
                    return ((id (*)(id, SEL))objc_msgSend)(tracklist, @selector(playingItem));
                }
            }
        }
    }

    if ([target respondsToSelector:@selector(parentViewController)]) {
        UIViewController *parent = [target parentViewController];
        if (parent) {
            id ppi = tj_extractPlayingItem(parent);
            if (ppi) return ppi;
        }
    }

    id response = tj_extractNowPlayingResponse(target);
    if (response) {
        id tracklist = nil;
        if ([response respondsToSelector:@selector(tracklist)]) {
            tracklist = ((id (*)(id, SEL))objc_msgSend)(response, @selector(tracklist));
        }
        if (tracklist && [tracklist respondsToSelector:@selector(playingItem)]) {
            return ((id (*)(id, SEL))objc_msgSend)(tracklist, @selector(playingItem));
        }
        if ([response respondsToSelector:@selector(playingItem)]) {
            return ((id (*)(id, SEL))objc_msgSend)(response, @selector(playingItem));
        }
    }

    if ([target isKindOfClass:[UIView class]]) {
        UIResponder *r = ((UIView *)target).nextResponder;
        while (r) {
            if ([r isKindOfClass:[UIViewController class]]) {
                id rpi = tj_extractPlayingItem(r);
                if (rpi) return rpi;
            }
            r = r.nextResponder;
        }
    }

    return nil;
}

NSString * _Nullable tj_itemTrackKey(id _Nullable item) {
    if (!item) return nil;
    NSString *sid = tj_extractAdamID(item);
    if (sid && sid.length > 0) return sid;

    id song = tj_unwrapSongFromPlayingItem(item);
    NSString *sTitle = nil;
    NSString *sArtist = nil;
    if (song) {
        for (NSString *k in @[@"title", @"name"]) {
            @try { id v = [song valueForKey:k]; if ([v isKindOfClass:[NSString class]] && [v length] > 0) { sTitle = v; break; } } @catch (__unused id e) {}
        }
        for (NSString *k in @[@"artistName", @"artist.name"]) {
            @try { id v = [song valueForKeyPath:k]; if ([v isKindOfClass:[NSString class]] && [v length] > 0) { sArtist = v; break; } } @catch (__unused id e) {}
        }
    }
    if (!sTitle) {
        for (NSString *kp in @[@"title", @"song.title", @"metadataObject.title", @"metadataObject.song.title", @"metadataObject.playlistEntry.song.title"]) {
            @try { id v = [item valueForKeyPath:kp]; if ([v isKindOfClass:[NSString class]] && [v length] > 0) { sTitle = v; break; } } @catch (__unused id e) {}
        }
    }
    if (!sArtist) {
        for (NSString *kp in @[@"artistName", @"artist.name", @"song.artistName", @"song.artist.name", @"metadataObject.artistName", @"metadataObject.song.artistName", @"metadataObject.playlistEntry.song.artistName"]) {
            @try { id v = [item valueForKeyPath:kp]; if ([v isKindOfClass:[NSString class]] && [v length] > 0) { sArtist = v; break; } } @catch (__unused id e) {}
        }
    }
    if (sTitle && sTitle.length > 0) {
        return sArtist ? [NSString stringWithFormat:@"%@ - %@", sTitle, sArtist] : sTitle;
    }

    NSString *aid = tj_extractAlbumAdamID(item);
    if (aid && aid.length > 0) return aid;
    NSString *title = tj_extractAlbumTitle(item);
    if (title && title.length > 0) return title;

    return [NSString stringWithFormat:@"%p", item];
}

BOOL tj_isMiniPlayerSubtree(UIView * _Nullable view) {
    if (!view) return NO;
    UIView *p = view;
    for (int i = 0; i < 6 && p; i++, p = p.superview) {
        if ([NSStringFromClass(p.class) containsString:@"MiniPlayer"]) return YES;
    }
    return NO;
}
