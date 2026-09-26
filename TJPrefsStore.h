#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kTJPrefsDomain;
extern NSString *const kTJPrefsChangedDarwinNotification;

extern NSString *const TJPrefsStoreChangedNotification;

BOOL prefBool(NSString *key, BOOL def);
CGFloat prefFloat(NSString *key, CGFloat def);
NSString * _Nullable prefString(NSString *key, NSString * _Nullable def);
id _Nullable prefValue(NSString *key);
void prefSetObject(NSString *key, id _Nullable value);

NS_ASSUME_NONNULL_END
