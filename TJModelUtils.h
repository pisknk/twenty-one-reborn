#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "TJEngine.h"

NS_ASSUME_NONNULL_BEGIN

BOOL tj_isNumericAdamID(NSString * _Nullable s);

NSString * _Nullable tj_extractAdamID(id _Nullable obj);

id _Nullable tj_unwrapSongFromPlayingItem(id _Nullable item);

id _Nullable tj_unwrapAlbumFromPlayingItem(id _Nullable item);

NSString * _Nullable tj_extractAlbumAdamID(id _Nullable playingItem);

BOOL tj_albumTitlesMatch(NSString * _Nullable t1, NSString * _Nullable t2);

NSString * _Nullable tj_normalizedKey(NSString * _Nullable s);

NSString * _Nullable tj_extractAlbumTitle(id _Nullable playingItem);

id _Nullable tj_extractNowPlayingResponse(id _Nullable target);

id _Nullable tj_extractPlayingItem(id _Nullable target);

NSString * _Nullable tj_itemTrackKey(id _Nullable item);

BOOL tj_isMiniPlayerSubtree(UIView * _Nullable view);

NS_ASSUME_NONNULL_END
