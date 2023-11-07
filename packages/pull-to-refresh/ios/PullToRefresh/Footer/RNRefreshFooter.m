#import "RNRefreshFooter.h"
#import "RNRefreshFooterLocalData.h"
#import "RNRefreshState.h"
#import "RNRefreshingEvent.h"
#import "RNRefreshOffsetChangedEvent.h"
#import "RNRefreshStateChangedEvent.h"

#import <React/RCTRefreshableProtocol.h>
#import <React/UIView+React.h>
#import <React/RCTRootContentView.h>
#import <React/RCTTouchHandler.h>
#import <React/RCTUIManager.h>
#import <React/RCTLog.h>
#import <React/RCTAssert.h>


@interface RNRefreshFooter () <RCTRefreshableProtocol>

@property(nonatomic, assign) RNRefreshState state;
@property(nonatomic, weak) RCTBridge *bridge;
@property(nonatomic, assign) CGFloat bottomInset;

@end

@implementation RNRefreshFooter {
    BOOL _hasObserver;
    __weak RCTRootContentView *_rootView;
}

- (instancetype)initWithBridge:(RCTBridge *)bridge {
    if (self = [super init]) {
        _bridge = bridge;
        _hasObserver = NO;
        _state = RNRefreshStateIdle;
        _noMoreData = NO;
        _manual = NO;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    if (self.backgroundColor == nil) {
        self.backgroundColor = [UIColor clearColor];
    }
}

- (void)reactSetFrame:(CGRect)frame {
    [super reactSetFrame:frame];
    self.hidden = ![self isFullScrollView];
    if (!self.manual) {
        // 和下拉刷新有冲突
        [self setScrollViewContentInset];
    }
}

- (void)setScrollViewContentInset {
    UIEdgeInsets insets = self.scrollView.contentInset;
    if (!self.hidden) {
        self.scrollView.contentInset = UIEdgeInsetsMake(insets.top, insets.left, self.frame.size.height, insets.right);
    } else {
        self.scrollView.contentInset = UIEdgeInsetsMake(insets.top, insets.left, 0, insets.right);
    }
}

- (void)setLocalData {
    if (self.scrollView) {
        CGSize contentSize = self.scrollView.contentSize;
        if (self.frame.origin.y != contentSize.height) {
            RNRefreshFooterLocalData *localData = [[RNRefreshFooterLocalData alloc] initWithScrollViewContentSize:contentSize];
            [self.bridge.uiManager setLocalData:localData forView:self];
        }
    }
}

- (void)setScrollView:(UIScrollView *)scrollView {
    [self removeObserver];
    _scrollView = scrollView;
    [self addObserver];
}

- (void)willMoveToWindow:(UIWindow *)newWindow {
    [super willMoveToWindow:newWindow];
    if (newWindow) {
        [self addObserver];
    } else {
        [self removeObserver];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self cacheRootView];
    }
}

- (void)addObserver {
    if (!_hasObserver && self.scrollView) {
        NSKeyValueObservingOptions options = NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld;
        [self.scrollView addObserver:self forKeyPath:@"contentOffset" options:options context:nil];
        [self.scrollView addObserver:self forKeyPath:@"contentSize" options:options context:nil];
        _hasObserver = YES;
    }
}

- (void)removeObserver {
    if (_hasObserver && self.scrollView) {
        [self.scrollView removeObserver:self forKeyPath:@"contentOffset" context:nil];
        [self.scrollView removeObserver:self forKeyPath:@"contentSize" context:nil];
        _hasObserver = NO;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"contentSize"]) {
        [self setLocalData];
    }
    
    if ([keyPath isEqualToString:@"contentOffset"]) {
        
        // 马上可看见 footer
        CGFloat minRange = self.scrollView.contentSize.height - self.scrollView.frame.size.height;
        
        if (self.scrollView.contentOffset.y >= minRange) {
            CGFloat offset = self.scrollView.contentOffset.y - minRange;
            [self.bridge.eventDispatcher sendEvent:[[RNRefreshOffsetChangedEvent alloc] initWithViewTag:self.reactTag offset:offset]];
        }
        
        if (self.hidden || self.noMoreData) {
            return;
        }
        
        if (self.state == RNRefreshStateRefreshing) {
            return;
        }
        
        if (![self isFullScrollView]) { // 内容不满一屏
            return;
        }
        
        CGFloat offset = self.scrollView.contentOffset.y;
        
        if (self.scrollView.isDragging) {
            [self cancelRootViewTouches];
        }
        
        if (self.manual) {
            if (offset < minRange) {
                // 未到临界点，返回
                return;
            }
            
            // 完全可看见 footer
            CGFloat maxRange = minRange + self.bounds.size.height;
            
            if (self.scrollView.isDragging) {
                if (self.state == RNRefreshStateIdle && offset >= maxRange) {
                    self.state = RNRefreshStateComing;
                    
                } else
                if (self.state == RNRefreshStateComing && offset <= maxRange) {
                    self.state = RNRefreshStateIdle;
                }
                return;
            }
            
            if (self.state == RNRefreshStateComing) {
                // 松开手
                [self beginRefreshing];
                return;
            }
        } else {
            CGPoint new = [change[@"new"] CGPointValue];
            CGPoint old = [change[@"old"] CGPointValue];
            
            CGFloat range = self.scrollView.contentSize.height - self.scrollView.frame.size.height + self.frame.size.height * 0.3;
            if (new.y > old.y && offset >= range) {
                if (self.state == RNRefreshStateIdle) {
                    [self beginRefreshing];
                    return;
                }
            }
        }
    }
}

-(BOOL)isFullScrollView { // 内容是否能撑满 scrollView
    CGFloat range = self.scrollView.contentInset.top + self.scrollView.contentSize.height;
    CGFloat height = self.scrollView.frame.size.height;
    return range >= height;
}

@dynamic refreshing;

- (BOOL)isRefreshing {
    return self.state == RNRefreshStateRefreshing;
}

- (void)setRefreshing:(BOOL)refreshing {
    if (refreshing) {
        [self beginRefreshing];
    } else {
        [self endRefreshing];
    }
}

- (void)beginRefreshing {
    [self setState:RNRefreshStateRefreshing];
}

- (void)endRefreshing {
    [self setState:RNRefreshStateIdle];
}

- (void)setState:(RNRefreshState)state {
    if (_state == state || !self.scrollView) {
        return;
    }
    
    RNRefreshState old = _state;
    _state = state;

    [self.bridge.eventDispatcher sendEvent:[[RNRefreshStateChangedEvent alloc] initWithViewTag:self.reactTag refreshState:state]];
    
    if (state == RNRefreshStateIdle && old == RNRefreshStateRefreshing) {
        if (self.manual) {
            [self animateToIdleState];
        }
        return;
    }

    if (state == RNRefreshStateRefreshing) {
        if (self.manual) {
            [self animateToRefreshingState];
        }
        [self.bridge.eventDispatcher sendEvent:[[RNRefreshingEvent alloc] initWithViewTag:self.reactTag]];
        return;
    }
}

- (void)animateToIdleState {
    [UIView animateWithDuration:0.2 animations:^{
        UIScrollView *scrollView = self.scrollView;
        UIEdgeInsets insets = scrollView.contentInset;
        scrollView.contentInset = UIEdgeInsetsMake(insets.top, insets.left, self.bottomInset, insets.right);
    } completion:NULL];
}

- (void)animateToRefreshingState {
    [UIView animateWithDuration:0.2 animations:^{
        UIScrollView *scrollView = self.scrollView;
        CGFloat range = scrollView.contentSize.height - scrollView.frame.size.height + self.bounds.size.height;
        UIEdgeInsets insets = scrollView.contentInset;
        self.bottomInset = insets.bottom;
        [scrollView setContentInset:UIEdgeInsetsMake(insets.top, insets.left, self.frame.size.height, insets.right)];
        CGPoint offset = {scrollView.contentOffset.x, range};
        [scrollView setContentOffset:offset animated:NO];
    } completion:NULL];
}

- (void)cacheRootView {
  UIView *rootView = self;
  while (rootView.superview && ![rootView isReactRootView]) {
    rootView = rootView.superview;
  }
  _rootView = rootView;
}

- (void)cancelRootViewTouches {
    RCTRootContentView *rootView = (RCTRootContentView *)_rootView;
    [rootView.touchHandler cancel];
}

@end
