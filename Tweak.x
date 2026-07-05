#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "RuleEngine.h"
#import "AdDetector.h"
#import "TouchSimulator.h"
#import "NetworkBlocker.h"
#import "LogBuffer.h"
#import "WebConsole.h"

static BOOL _adSkipperInitialized = NO;
static BOOL _globalAdBlockEnabled = YES;
static NSInteger _totalAdsBlocked = 0;
static NSMutableDictionary<NSString *, NSNumber *> *_blockedClassStats;

static IMP _orig_UIView_addSubview = NULL;
static IMP _orig_UIView_didMoveToSuperview = NULL;
static IMP _orig_UIViewController_viewDidAppear = NULL;
static IMP _orig_UIViewController_presentVC = NULL;
static IMP _orig_UIWindow_makeKeyAndVisible = NULL;
static IMP _orig_UIWindow_motionEnded = NULL;

static void adskipper_hook_makeKeyAndVisible(id self, SEL _cmd) {
    if (_orig_UIWindow_makeKeyAndVisible) {
        ((void(*)(id, SEL))_orig_UIWindow_makeKeyAndVisible)(self, _cmd);
    }
    if (_adSkipperInitialized) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[AdDetector sharedInstance] scanViewHierarchy:(UIWindow *)self];
        });
    }
}

static void adskipper_hook_motionEnded(id self, SEL _cmd, UIEventSubtype motion, UIEvent *event) {
    if (motion == UIEventSubtypeMotionShake && _adSkipperInitialized) {
        static NSTimeInterval lastShake = 0;
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now - lastShake > 1.5) {
            lastShake = now;
            dispatch_async(dispatch_get_main_queue(), ^{
                WebConsole *wc = [WebConsole sharedInstance];
                if ([wc isVisible]) {
                    [wc hide];
                } else {
                    [wc show];
                }
            });
        }
    }
    if (_orig_UIWindow_motionEnded) {
        ((void(*)(id, SEL, UIEventSubtype, UIEvent *))_orig_UIWindow_motionEnded)(self, _cmd, motion, event);
    }
}
        NSString *className = NSStringFromClass([view class]);
        if ([[RuleEngine sharedInstance] shouldBlockClass:className]) {
            _totalAdsBlocked++;
            return;
        }
    }
    if (_orig_UIView_addSubview) {
        ((void(*)(id, SEL, UIView *))_orig_UIView_addSubview)(self, _cmd, view);
    }
}

static void adskipper_hook_didMoveToSuperview(id self, SEL _cmd) {
    if (_orig_UIView_didMoveToSuperview) {
        ((void(*)(id, SEL))_orig_UIView_didMoveToSuperview)(self, _cmd);
    }
    if (_adSkipperInitialized && [(UIView *)self superview]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[AdDetector sharedInstance] scanViewHierarchy:(UIView *)self];
        });
    }
}

static void adskipper_hook_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (_orig_UIViewController_viewDidAppear) {
        ((void(*)(id, SEL, BOOL))_orig_UIViewController_viewDidAppear)(self, _cmd, animated);
    }
    if (!_adSkipperInitialized) return;
    
    if (!_toastShown) {
        adskipper_showToastNow(@"AdSkipper 已激活", 0, 0, @"摇晃手机打开控制台");
    }
    
    NSString *vcClassName = NSStringFromClass([self class]);
    if ([[RuleEngine sharedInstance] shouldBlockClass:vcClassName]) {
        _totalAdsBlocked++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIViewController *vc = (UIViewController *)self;
            if (vc.presentingViewController) {
                [vc dismissViewControllerAnimated:NO completion:nil];
            } else if (vc.navigationController) {
                [vc.navigationController popViewControllerAnimated:NO];
            } else if (vc.view.superview) {
                [vc.view removeFromSuperview];
            }
        });
        return;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[AdDetector sharedInstance] scanViewHierarchy:[(UIViewController *)self view]];
    });
}

static void adskipper_hook_presentVC(id self, SEL _cmd, UIViewController *vc, BOOL animated, id completion) {
    if (_adSkipperInitialized) {
        NSString *vcClassName = NSStringFromClass([vc class]);
        if ([[RuleEngine sharedInstance] shouldBlockClass:vcClassName]) {
            _totalAdsBlocked++;
            return;
        }
    }
    if (_orig_UIViewController_presentVC) {
        ((void(*)(id, SEL, UIViewController *, BOOL, id))_orig_UIViewController_presentVC)(self, _cmd, vc, animated, completion);
    }
}

static void adskipper_hook_makeKeyAndVisible(id self, SEL _cmd) {
    if (_orig_UIWindow_makeKeyAndVisible) {
        ((void(*)(id, SEL))_orig_UIWindow_makeKeyAndVisible)(self, _cmd);
    }
    if (_adSkipperInitialized) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[AdDetector sharedInstance] scanViewHierarchy:(UIWindow *)self];
        });
    }
}

static void adskipper_swizzleInstanceMethod(Class cls, SEL originalSel, IMP newImp, IMP *origStore) {
    Method method = class_getInstanceMethod(cls, originalSel);
    if (!method) return;
    
    if (origStore) {
        *origStore = method_getImplementation(method);
    }
    method_setImplementation(method, newImp);
}

static void adskipper_installAllHooks(void) {
    adskipper_swizzleInstanceMethod([UIView class], @selector(addSubview:),
                                    (IMP)adskipper_hook_addSubview, &_orig_UIView_addSubview);
    
    adskipper_swizzleInstanceMethod([UIView class], @selector(didMoveToSuperview),
                                    (IMP)adskipper_hook_didMoveToSuperview, &_orig_UIView_didMoveToSuperview);
    
    adskipper_swizzleInstanceMethod([UIView class], @selector(didMoveToWindow),
                                    (IMP)adskipper_hook_didMoveToSuperview, NULL);
    
    adskipper_swizzleInstanceMethod([UIViewController class], @selector(viewDidAppear:),
                                    (IMP)adskipper_hook_viewDidAppear, &_orig_UIViewController_viewDidAppear);
    
    adskipper_swizzleInstanceMethod([UIViewController class],
                                    NSSelectorFromString(@"presentViewController:animated:completion:"),
                                    (IMP)adskipper_hook_presentVC, &_orig_UIViewController_presentVC);
    
    adskipper_swizzleInstanceMethod([UIWindow class], @selector(makeKeyAndVisible),
                                    (IMP)adskipper_hook_makeKeyAndVisible, &_orig_UIWindow_makeKeyAndVisible);
    
    adskipper_swizzleInstanceMethod([UIWindow class], @selector(motionEnded:withEvent:),
                                    (IMP)adskipper_hook_motionEnded, &_orig_UIWindow_motionEnded);
}

static void adskipper_hookAdSDKClasses(void) {
    NSArray *sdkInitMethods = @[
        @"setAppID:", @"setAppId:", @"registerAppId:", @"registerAppID:",
        @"startWithAppId:", @"startWithAppID:", @"initializeWithAppId:",
        @"sharedInstance", @"sharedSDK", @"manager", @"defaultManager",
        @"loadAdData", @"loadAdDataWithCount:", @"showAdFromRootViewController:",
        @"showAd", @"presentAd", @"showInterstitial", @"loadInterstitialAd",
    ];
    
    NSArray *sdkClasses = @[
        @"BUAdSDKManager", @"BUNativeExpressAdManager", @"BUSplashAd",
        @"BURewardedVideoAd", @"BUFullscreenVideoAd", @"BUNativeAd",
        @"GDTSDKConfig", @"GDTSplashAd", @"GDTUnifiedNativeAd",
        @"GDTUnifiedInterstitialAd", @"GDTUnifiedBannerView", @"GDTUnifiedRewardAd",
        @"GADMobileAds", @"GADRewardBasedVideoAd", @"GADInterstitial",
        @"GADBannerView", @"GADNativeExpressAdView", @"GADRewardedAd",
        @"UnityAds", @"UADSWebViewShowOperation",
        @"KSAdSplashManager", @"KSRewardVideoAd", @"KSNativeAdsManager",
        @"VungleSDK", @"VungleAdSDK", @"AdColony", @"IronSource",
        @"AppLovinSdk", @"ALSdk", @"ALInterstitialAd",
        @"FBAudienceNetworkAds", @"FBAdView", @"FBInterstitialAd",
        @"Mintegral", @"MTGSDK", @"SigmobAd", @"SigmobSplashAd",
    ];
    
    for (NSString *className in sdkClasses) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        for (unsigned int i = 0; i < methodCount; i++) {
            SEL sel = method_getName(methods[i]);
            NSString *selName = NSStringFromSelector(sel);
            for (NSString *initSel in sdkInitMethods) {
                if ([selName hasPrefix:[initSel stringByReplacingOccurrencesOfString:@":" withString:@""]] ||
                    [selName rangeOfString:initSel].location != NSNotFound) {
                    IMP orig = method_getImplementation(methods[i]);
                    IMP block = imp_implementationWithBlock(^(id s) {
                        _totalAdsBlocked++;
                        return orig ? ((id(*)(id, SEL))orig)(s, sel) : nil;
                    });
                    method_setImplementation(methods[i], block);
                    break;
                }
            }
        }
        free(methods);
        
        Class metaCls = object_getClass(cls);
        unsigned int metaCount = 0;
        Method *metaMethods = class_copyMethodList(metaCls, &metaCount);
        for (unsigned int i = 0; i < metaCount; i++) {
            SEL sel = method_getName(metaMethods[i]);
            NSString *selName = NSStringFromSelector(sel);
            for (NSString *initSel in sdkInitMethods) {
                if ([selName rangeOfString:[initSel stringByReplacingOccurrencesOfString:@":" withString:@""]].location != NSNotFound) {
                    IMP orig = method_getImplementation(metaMethods[i]);
                    method_setImplementation(metaMethods[i], imp_implementationWithBlock(^{
                        _totalAdsBlocked++;
                    }));
                    break;
                }
            }
        }
        free(metaMethods);
    }
}

static BOOL _toastShown = NO;

static UIWindow *adskipper_getKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in [(UIWindowScene *)scene windows]) {
                    if (!w.hidden && w.alpha > 0 && w.bounds.size.width > 0) return w;
                }
            }
        }
    }
    for (UIWindow *w in [[UIApplication sharedApplication] windows]) {
        if (!w.hidden && w.alpha > 0 && w.bounds.size.width > 0) return w;
    }
    return nil;
}

static void adskipper_showToastNow(NSString *message, NSInteger ruleCount, NSInteger domainCount, NSString *hint) {
    if (_toastShown) return;
    
    UIWindow *keyWindow = adskipper_getKeyWindow();
    if (!keyWindow) return;
    
    _toastShown = YES;
    
    CGFloat sw = keyWindow.bounds.size.width;
    UIView *toast = [[UIView alloc] initWithFrame:CGRectMake(16, 80, sw - 32, 72)];
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.88];
    toast.layer.cornerRadius = 14;
    toast.clipsToBounds = YES;
    toast.alpha = 0;
    toast.tag = 0xAD51;
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, toast.bounds.size.width - 24, 18)];
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont boldSystemFontOfSize:13];
    label.textAlignment = NSTextAlignmentCenter;
    [toast addSubview:label];
    
    UILabel *detail = [[UILabel alloc] initWithFrame:CGRectMake(12, 28, toast.bounds.size.width - 24, 16)];
    detail.text = [NSString stringWithFormat:@"%ld 规则  %ld 域名", (long)ruleCount, (long)domainCount];
    detail.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
    detail.font = [UIFont systemFontOfSize:11];
    detail.textAlignment = NSTextAlignmentCenter;
    [toast addSubview:detail];
    
    UILabel *hintLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 48, toast.bounds.size.width - 24, 16)];
    hintLabel.text = hint;
    hintLabel.textColor = [UIColor colorWithRed:0.49 green:1.0 blue:0.42 alpha:0.9];
    hintLabel.font = [UIFont systemFontOfSize:10];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    [toast addSubview:hintLabel];
    
    [keyWindow addSubview:toast];
    
    [UIView animateWithDuration:0.3 animations:^{ toast.alpha = 1; }
                     completion:^(BOOL f) {
        [UIView animateWithDuration:0.4 delay:4.0 options:0 animations:^{ toast.alpha = 0; }
                         completion:^(BOOL f) { [toast removeFromSuperview]; }];
    }];
}

static void adskipper_retryToast(NSString *message, NSInteger ruleCount, NSInteger domainCount, NSString *hint, int attempt) {
    if (_toastShown || attempt > 10) return;
    
    __weak void(^weakRetry)(int) = nil;
    
    void(^tryShow)(void) = ^{
        if (_toastShown) return;
        adskipper_showToastNow(message, ruleCount, domainCount, hint);
        if (!_toastShown) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(attempt * 0.8 * NSEC_PER_SEC)),
                          dispatch_get_main_queue(), ^{
                adskipper_retryToast(message, ruleCount, domainCount, hint, attempt + 1);
            });
        }
    };
    
    dispatch_async(dispatch_get_main_queue(), tryShow);
}

static void adskipper_init(void) {
    if (_adSkipperInitialized) return;
    _adSkipperInitialized = YES;
    _blockedClassStats = [NSMutableDictionary dictionary];
    
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSLog(@"[AdSkipper] ========================================");
    NSLog(@"[AdSkipper] 广告跳过插件 v1.0 初始化");
    NSLog(@"[AdSkipper] App: %@ | iOS: %@", bundleId, [[UIDevice currentDevice] systemVersion]);
    
    adskipper_installAllHooks();
    
    RuleEngine *engine = [RuleEngine sharedInstance];
    [engine loadRulesFromFile:nil];
    [engine startHotReloadWithInterval:10.0];
    
    adskipper_hookAdSDKClasses();
    
    NetworkBlocker *nb = [NetworkBlocker sharedInstance];
    [nb installDNSHook];
    [nb installURLSessionHook];
    
    NSString *domainPath = @"/Library/Application Support/AdSkipper/domain_blacklist.txt";
    if (![[NSFileManager defaultManager] fileExistsAtPath:domainPath]) {
        domainPath = [[NSBundle mainBundle] pathForResource:@"domain_blacklist" ofType:@"txt"];
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:domainPath]) {
        NSString *rulesDir = [[engine rulesFilePath] stringByDeletingLastPathComponent];
        domainPath = [rulesDir stringByAppendingPathComponent:@"domain_blacklist.txt"];
    }
    [nb loadDomainBlacklistFromFile:domainPath];
    
    [[AdDetector sharedInstance] startScanning];
    
    NSLog(@"[AdSkipper] 已加载 %lu 条UI规则 | %lu 个拦截域名",
          (unsigned long)[engine allRules].count,
          (unsigned long)[nb allBlockedDomains].count);
    NSLog(@"[AdSkipper] 拦截层: DNS | HTTP | UI 三层防护");
    NSLog(@"[AdSkipper] 初始化完成！========================================");
    
    NSUInteger ruleCount = [engine allRules].count;
    NSUInteger domainCount = [nb allBlockedDomains].count;
    adskipper_retryToast(@"AdSkipper 已激活", (NSInteger)ruleCount, (NSInteger)domainCount, @"摇晃手机打开控制台", 1);
}

static void __attribute__((constructor)) adskipper_dylib_load(void) {
    NSLog(@"[AdSkipper] dylib loaded into process");
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            adskipper_init();
        });
    }
}

#ifdef THEOS
%ctor {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            adskipper_init();
        });
    }
}
#endif
