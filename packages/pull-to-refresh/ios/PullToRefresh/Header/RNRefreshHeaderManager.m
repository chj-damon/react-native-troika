#import "RNRefreshHeaderManager.h"
#import "RNRefreshHeader.h"
#import "RNRefreshHeaderShadowView.h"

#import <React/RCTRefreshableProtocol.h>
#import <React/RCTUIManager.h>

@implementation RNRefreshHeaderManager

RCT_EXPORT_MODULE(RefreshHeader)

- (UIView *)view {
    return [[RNRefreshHeader alloc] initWithBridge:self.bridge];
}

- (RCTShadowView *)shadowView {
    return [RNRefreshHeaderShadowView new];
}

RCT_EXPORT_VIEW_PROPERTY(onRefresh, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onStateChanged, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onOffsetChanged, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(refreshing, BOOL)

RCT_EXPORT_METHOD(setNativeRefreshing : (nonnull NSNumber *)viewTag toRefreshing : (BOOL)refreshing) {
  [self.bridge.uiManager addUIBlock:^(RCTUIManager *uiManager, NSDictionary<NSNumber *, UIView *> *viewRegistry) {
    UIView *view = viewRegistry[viewTag];

    if ([view conformsToProtocol:@protocol(RCTRefreshableProtocol)]) {
        [(id<RCTRefreshableProtocol>)view setRefreshing:refreshing];
    } else {
        RCTLogError(@"view must conform to protocol RCTRefreshableProtocol");
    }
  }];
}

@end
