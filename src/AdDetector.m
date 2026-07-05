#import "AdDetector.h"
#import "RuleEngine.h"
#import "TouchSimulator.h"
#import <objc/runtime.h>

static NSString *const kAdDetectorLogPrefix = @"[AdSkipper::Detector]";

@interface AdDetector ()
@property (nonatomic, strong) NSTimer *scanTimer;
@property (nonatomic, strong) NSMutableSet<NSValue *> *processedViews;
@property (nonatomic, assign) NSUInteger scanCount;
@end

@implementation AdDetector

+ (instancetype)sharedInstance {
    static AdDetector *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AdDetector alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _processedViews = [NSMutableSet set];
    }
    return self;
}

- (void)startScanning {
    [self stopScanning];
    
    __weak typeof(self) weakSelf = self;
    _scanTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf performScan];
    }];
    
    [[NSRunLoop mainRunLoop] addTimer:_scanTimer forMode:NSRunLoopCommonModes];
    NSLog(@"%@ 广告扫描已启动", kAdDetectorLogPrefix);
}

- (void)stopScanning {
    if (_scanTimer) {
        [_scanTimer invalidate];
        _scanTimer = nil;
    }
}

- (void)performScan {
    @autoreleasepool {
        [self scanAllWindows];
    }
    
    _scanCount++;
    if (_scanCount % 200 == 0) {
        [_processedViews removeAllObjects];
    }
}

- (void)scanAllWindows {
    NSArray<UIWindow *> *windows = nil;
    
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [[UIApplication sharedApplication] connectedScenes];
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                windows = windowScene.windows;
            }
        }
    }
    
    if (!windows || windows.count == 0) {
        windows = [[UIApplication sharedApplication] windows];
    }
    
    for (UIWindow *window in windows) {
        [self scanViewHierarchy:window];
    }
}

- (void)scanViewHierarchy:(UIView *)rootView {
    if (!rootView) return;
    
    NSString *className = NSStringFromClass([rootView class]);
    
    if ([className hasPrefix:@"_"] && ![className containsString:@"Ad"]) {
        for (UIView *subview in rootView.subviews) {
            [self scanViewHierarchy:subview];
        }
        return;
    }
    
    ASRule *rule = [[RuleEngine sharedInstance] matchingRuleForView:rootView];
    
    if (rule) {
        NSValue *key = [NSValue valueWithNonretainedObject:rootView];
        if (![_processedViews containsObject:key]) {
            [_processedViews addObject:key];
            
            NSLog(@"%@ 检测到广告视图: %@ -> 规则: %@ (动作: %ld)",
                  kAdDetectorLogPrefix, className, rule.ruleId, (long)rule.actionType);
            
            if (rule.delayBeforeAction > 0) {
                [self scheduleDelayedActionForView:rootView rule:rule];
            } else {
                [self handleDetectedAdView:rootView withRule:rule];
            }
            return;
        }
    }
    
    for (UIView *subview in rootView.subviews) {
        [self scanViewHierarchy:subview];
    }
    
    if ([rootView isKindOfClass:[UIViewController class]]) {
        UIViewController *vc = (UIViewController *)rootView;
        [self scanViewHierarchy:vc.view];
    }
    
    if ([rootView respondsToSelector:@selector(presentedViewController)]) {
        UIViewController *vc = (UIViewController *)rootView;
        if (vc.presentedViewController) {
            [self scanViewHierarchy:vc.presentedViewController.view];
        }
    }
}

- (void)scheduleDelayedActionForView:(UIView *)view rule:(ASRule *)rule {
    __weak typeof(view) weakView = view;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(rule.delayBeforeAction * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakView) strongView = weakView;
        if (strongView && strongView.superview) {
            [[AdDetector sharedInstance] handleDetectedAdView:strongView withRule:rule];
        }
    });
}

- (void)handleDetectedAdView:(UIView *)adView withRule:(ASRule *)rule {
    if (!adView) return;
    
    switch (rule.actionType) {
        case ASRuleActionRemove:
            [self removeAdView:adView withRule:rule];
            break;
        case ASRuleActionHide:
            [self hideAdView:adView withRule:rule];
            break;
        case ASRuleActionDismiss:
            [self dismissAdView:adView withRule:rule];
            break;
        case ASRuleActionClick:
            [self clickSkipButton:adView withRule:rule];
            break;
        case ASRuleActionBlock:
            [self blockAdView:adView withRule:rule];
            break;
        default:
            break;
    }
}

- (void)removeAdView:(UIView *)adView withRule:(ASRule *)rule {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (adView.superview) {
            NSLog(@"%@ 移除广告视图: %@ (规则: %@)", kAdDetectorLogPrefix, NSStringFromClass([adView class]), rule.ruleId);
            [adView removeFromSuperview];
        }
    });
}

- (void)hideAdView:(UIView *)adView withRule:(ASRule *)rule {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (adView.alpha > 0.01) {
            NSLog(@"%@ 隐藏广告视图: %@ (规则: %@)", kAdDetectorLogPrefix, NSStringFromClass([adView class]), rule.ruleId);
            adView.hidden = YES;
            adView.alpha = 0.0;
            adView.userInteractionEnabled = NO;
        }
    });
}

- (void)dismissAdView:(UIView *)adView withRule:(ASRule *)rule {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *className = NSStringFromClass([adView class]);
        
        NSLog(@"%@ 尝试关闭广告: %@ (规则: %@)", kAdDetectorLogPrefix, className, rule.ruleId);
        
        if (rule.skipButtonKeyword) {
            UIView *skipBtn = [self findSkipButtonInView:adView withKeyword:rule.skipButtonKeyword];
            if (skipBtn) {
                NSLog(@"%@ 找到跳过按钮，模拟点击", kAdDetectorLogPrefix);
                [[TouchSimulator sharedInstance] simulateTapOnView:skipBtn];
                return;
            }
        }
        
        UIView *skipBtn = [self findSkipButtonInView:adView withKeyword:@"跳过"];
        if (skipBtn) {
            [[TouchSimulator sharedInstance] simulateTapOnView:skipBtn];
            return;
        }
        
        skipBtn = [self findSkipButtonInView:adView withKeyword:@"关闭"];
        if (skipBtn) {
            [[TouchSimulator sharedInstance] simulateTapOnView:skipBtn];
            return;
        }
        
        if ([adView respondsToSelector:@selector(dismiss)]) {
            [adView performSelector:@selector(dismiss)];
        } else if ([adView respondsToSelector:@selector(close)]) {
            [adView performSelector:@selector(close)];
        } else if ([adView respondsToSelector:@selector(removeFromSuperview)]) {
            [adView removeFromSuperview];
        } else if ([adView isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)adView;
            if (vc.presentingViewController) {
                [vc dismissViewControllerAnimated:NO completion:nil];
            } else if (vc.navigationController) {
                [vc.navigationController popViewControllerAnimated:NO];
            }
        } else if (adView.superview) {
            [adView removeFromSuperview];
        }
    });
}

- (void)blockAdView:(UIView *)adView withRule:(ASRule *)rule {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"%@ 屏蔽广告视图: %@", kAdDetectorLogPrefix, NSStringFromClass([adView class]));
        adView.hidden = YES;
        adView.alpha = 0.0;
        adView.userInteractionEnabled = NO;
        
        for (UIView *subview in adView.subviews) {
            subview.hidden = YES;
            subview.alpha = 0.0;
            subview.userInteractionEnabled = NO;
        }
    });
}

- (void)clickSkipButton:(UIView *)targetView withRule:(ASRule *)rule {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *clickTarget = targetView;
        
        if ([targetView isKindOfClass:[UILabel class]] && targetView.superview) {
            clickTarget = targetView.superview;
        }
        
        if (clickTarget.isAccessibilityElement || 
            [clickTarget isKindOfClass:[UIButton class]] ||
            [clickTarget isKindOfClass:[UIControl class]]) {
            NSLog(@"%@ 模拟点击: %@ (规则: %@)", kAdDetectorLogPrefix, NSStringFromClass([clickTarget class]), rule.ruleId);
            [[TouchSimulator sharedInstance] simulateTapOnView:clickTarget];
        } else if (clickTarget.superview && 
                   ([clickTarget.superview isKindOfClass:[UIButton class]] || 
                    [clickTarget.superview isKindOfClass:[UIControl class]])) {
            NSLog(@"%@ 模拟点击父视图: %@", kAdDetectorLogPrefix, NSStringFromClass([clickTarget.superview class]));
            [[TouchSimulator sharedInstance] simulateTapOnView:clickTarget.superview];
        }
    });
}

- (UIView *)findSkipButtonInView:(UIView *)view withKeyword:(NSString *)keyword {
    if (!view || !keyword) return nil;
    
    if ([self viewContainsKeyword:view keyword:keyword]) {
        return view;
    }
    
    for (UIView *subview in view.subviews) {
        UIView *found = [self findSkipButtonInView:subview withKeyword:keyword];
        if (found) return found;
    }
    
    return nil;
}

- (BOOL)viewContainsKeyword:(UIView *)view keyword:(NSString *)keyword {
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        NSString *title = [btn titleForState:UIControlStateNormal];
        if ([title containsString:keyword]) return YES;
    }
    
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if ([label.text containsString:keyword]) return YES;
    }
    
    if (view.accessibilityLabel && [view.accessibilityLabel containsString:keyword]) return YES;
    
    if (view.accessibilityIdentifier && [view.accessibilityIdentifier containsString:keyword]) return YES;
    
    return NO;
}

@end
