#import "TJLastFmManager.h"

__attribute__((constructor))
static void TJScrobblerInit(void) {
    @autoreleasepool {
        [[TJLastFmManager sharedInstance] start];
    }
}
