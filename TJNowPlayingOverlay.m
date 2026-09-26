#import "TJEngine.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

void tj_detailHeaderScheduleRecolour(_TtC16MusicApplication12DetailHeader *header) {
    if (!header) return;
    if (objc_getAssociatedObject(header, kTJHeaderLayoutAsyncScheduledKey))
        return;
    objc_setAssociatedObject(header, kTJHeaderLayoutAsyncScheduledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *wh = header;
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(wh, kTJHeaderLayoutAsyncScheduledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIView *v = wh;
        if (!v) return;
        if ([v respondsToSelector:@selector(tj_recolourFromArtwork)])
            [(_TtC16MusicApplication12DetailHeader *)v tj_recolourFromArtwork];
    });
}
