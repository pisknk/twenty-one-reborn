#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "TJPrefsStore.h"


static void *kTJHomeTabItemKey = &kTJHomeTabItemKey;

static NSString *const kTJHomeTabTitle = @"Home";

static NSString *tj_listenNowTabTitle(void) {
    static NSString *title = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.apple.MusicApplication"];
        NSString *s = [bundle localizedStringForKey:@"LISTEN_NOW_TAB_TITLE" value:nil table:@"Music"];
        title = (s.length > 0 && ![s isEqualToString:@"LISTEN_NOW_TAB_TITLE"]) ? [s copy] : @"Listen Now";
    });
    return title;
}

static BOOL tj_homeTabEnabled(void) {
    return prefBool(@"enabled", YES);
}

static BOOL tj_isListenNowTitle(NSString *title) {
    return title.length > 0 && ([title isEqualToString:tj_listenNowTabTitle()] || [title isEqualToString:@"Listen Now"]);
}

static UIImage *tj_homeTabImage(void) {
    static UIImage *img = nil;
    if (!img) img = [UIImage systemImageNamed:@"house.fill"];
    return img;
}

static BOOL tj_isHomeTabItem(UITabBarItem *item) {
    return [objc_getAssociatedObject(item, kTJHomeTabItemKey) boolValue];
}

%hook UITabBarItem

- (void)setTitle:(NSString *)title {
    if (tj_homeTabEnabled() && tj_isListenNowTitle(title)) {
        objc_setAssociatedObject(self, kTJHomeTabItemKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        %orig(kTJHomeTabTitle);
        UIImage *home = tj_homeTabImage();
        if (home) {
            if (self.image != home) [self setImage:home];
            if (self.selectedImage != home) [self setSelectedImage:home];
        }
        return;
    }
    %orig;
}

- (void)setImage:(UIImage *)image {
    UIImage *home = tj_homeTabImage();
    if (home && tj_homeTabEnabled() && tj_isHomeTabItem(self)) {
        %orig(home);
        return;
    }
    %orig;
}

- (void)setSelectedImage:(UIImage *)image {
    UIImage *home = tj_homeTabImage();
    if (home && tj_homeTabEnabled() && tj_isHomeTabItem(self)) {
        %orig(home);
        return;
    }
    %orig;
}

%end

%hook UITabBarController

- (void)viewDidLayoutSubviews {
    %orig;
    if (!tj_homeTabEnabled()) return;
    UIImage *home = tj_homeTabImage();
    for (UITabBarItem *item in self.tabBar.items) {
        BOOL marked = tj_isHomeTabItem(item);
        if (!marked && !tj_isListenNowTitle(item.title)) continue;
        if (![item.title isEqualToString:kTJHomeTabTitle]) item.title = kTJHomeTabTitle;
        objc_setAssociatedObject(item, kTJHomeTabItemKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (home && item.image != home) item.image = home;
        if (home && item.selectedImage != home) item.selectedImage = home;
    }
}

%end
