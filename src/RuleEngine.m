#import "RuleEngine.h"
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

static NSString *const kRuleEngineLogPrefix = @"[AdSkipper::RuleEngine]";

@implementation ASRule
@end

@interface RuleEngine ()
@property (nonatomic, strong) NSMutableArray<ASRule *> *rules;
@property (nonatomic, strong) dispatch_source_t hotReloadTimer;
@property (nonatomic, copy) NSString *rulesPath;
@property (nonatomic, strong) NSDate *lastModifiedDate;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<ASRule *> *> *appRuleCache;
@end

@implementation RuleEngine

+ (instancetype)sharedInstance {
    static RuleEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RuleEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _rules = [NSMutableArray array];
        _appRuleCache = [NSMutableDictionary dictionary];
        _rulesPath = [self defaultRulesPath];
    }
    return self;
}

- (NSString *)defaultRulesPath {
    NSString *supportDir = @"/Library/Application Support/AdSkipper";
    NSString *path = [supportDir stringByAppendingPathComponent:@"rules.json"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        path = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
                stringByAppendingPathComponent:@"AdSkipper/rules.json"];
    }
    
    if (![fm fileExistsAtPath:path]) {
        NSString *dir = [path stringByDeletingLastPathComponent];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return path;
}

- (NSString *)rulesFilePath {
    return _rulesPath;
}

- (void)loadRulesFromFile:(NSString *)path {
    if (path) {
        _rulesPath = path;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:_rulesPath]) {
        NSLog(@"%@ 规则文件不存在: %@，加载内置默认规则", kRuleEngineLogPrefix, _rulesPath);
        [self loadBuiltinRules];
        [self saveRules];
        return;
    }
    
    _lastModifiedDate = [[fm attributesOfItemAtPath:_rulesPath error:nil] fileModificationDate];
    
    NSData *data = [NSData dataWithContentsOfFile:_rulesPath];
    if (!data) {
        NSLog(@"%@ 无法读取规则文件，加载内置默认规则", kRuleEngineLogPrefix);
        [self loadBuiltinRules];
        return;
    }
    
    [self loadRulesFromJSON:data];
    NSLog(@"%@ 已加载 %lu 条规则", kRuleEngineLogPrefix, (unsigned long)_rules.count);
}

- (void)loadBuiltinRules {
    [_rules removeAllObjects];
    [_appRuleCache removeAllObjects];
    
    NSArray *builtin = @[
        @{@"id": @"buad_splash_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"BUSplashAdView", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.5), @"priority": @(100), @"skipKeyword": @"跳过"},
        @{@"id": @"buad_splash_skip", @"targetType": @(ASRuleTargetKeyword), @"targetValue": @"跳过", @"actionType": @(ASRuleActionClick), @"delay": @(0.3), @"priority": @(99), @"useRegex": @(NO)},
        @{@"id": @"buad_native_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"BUNativeExpressAdView", @"actionType": @(ASRuleActionRemove), @"delay": @(0.1), @"priority": @(90)},
        @{@"id": @"buad_reward_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"BURewardedVideoAd", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.5), @"priority": @(88)},
        @{@"id": @"buad_fullscreen_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"BUFullscreenVideoAd", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.5), @"priority": @(88)},
        @{@"id": @"gdt_splash_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"GDTSplashAd", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.5), @"priority": @(100), @"skipKeyword": @"跳过"},
        @{@"id": @"gdt_skip_btn", @"targetType": @(ASRuleTargetKeyword), @"targetValue": @"跳过", @"actionType": @(ASRuleActionClick), @"delay": @(0.3), @"priority": @(99)},
        @{@"id": @"gdt_native_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"GDTUnifiedNativeAdView", @"actionType": @(ASRuleActionRemove), @"delay": @(0.1), @"priority": @(90)},
        @{@"id": @"gdt_interstitial_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"GDTUnifiedInterstitialAd", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.3), @"priority": @(88)},
        @{@"id": @"admob_banner_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"GADBannerView", @"actionType": @(ASRuleActionRemove), @"delay": @(0.1), @"priority": @(90)},
        @{@"id": @"admob_interstitial_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"GADInterstitialAd", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.3), @"priority": @(88)},
        @{@"id": @"admob_reward_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"GADRewardedAd", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.5), @"priority": @(88)},
        @{@"id": @"admob_native_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"GADNativeAdView", @"actionType": @(ASRuleActionRemove), @"delay": @(0.1), @"priority": @(90)},
        @{@"id": @"admob_skip_btn", @"targetType": @(ASRuleTargetKeyword), @"targetValue": @"Skip|Close|关闭|跳过", @"actionType": @(ASRuleActionClick), @"delay": @(0.3), @"priority": @(95), @"useRegex": @(YES)},
        @{@"id": @"unity_ad_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"UADSWebViewAdView", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.5), @"priority": @(85)},
        @{@"id": @"vungle_ad_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"VungleAdView", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.5), @"priority": @(85)},
        @{@"id": @"transparent_overlay", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"UIWindow", @"actionType": @(ASRuleActionHide), @"delay": @(1.0), @"priority": @(70), @"parentClassName": @""},
        @{@"id": @"close_ad_button", @"targetType": @(ASRuleTargetKeyword), @"targetValue": @"关闭|Close|×|✕|关闭广告", @"actionType": @(ASRuleActionClick), @"delay": @(0.1), @"priority": @(97), @"useRegex": @(YES)},
        @{@"id": @"countdown_skip", @"targetType": @(ASRuleTargetKeyword), @"targetValue": @"\\d+s|跳过广告|skip ad", @"actionType": @(ASRuleActionClick), @"delay": @(0.2), @"priority": @(96), @"useRegex": @(YES)},
        @{@"id": @"ks_ad_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"KSAdSplashViewController", @"actionType": @(ASRuleActionDismiss), @"delay": @(0.5), @"priority": @(100), @"skipKeyword": @"跳过"},
        @{@"id": @"ks_native_block", @"targetType": @(ASRuleTargetClassName), @"targetValue": @"KSNativeAdView", @"actionType": @(ASRuleActionRemove), @"delay": @(0.1), @"priority": @(90)},
        @{@"id": @"toutiao_ad_page", @"targetType": @(ASRuleTargetKeyword), @"targetValue": @"广告", @"actionType": @(ASRuleActionClick), @"delay": @(0.2), @"priority": @(50), @"skipKeyword": @"关闭"},
        @{@"id": @"xiao_ad", @"targetType": @(ASRuleTargetKeyword), @"targetValue": @"×|✕", @"actionType": @(ASRuleActionClick), @"delay": @(0.3), @"priority": @(80), @"useRegex": @(YES)},
        @{@"id": @"generic_ad_close", @"targetType": @(ASRuleTargetAccessibility), @"targetValue": @"关闭广告", @"actionType": @(ASRuleActionClick), @"delay": @(0.2), @"priority": @(85)},
        @{@"id": @"generic_ad_close_en", @"targetType": @(ASRuleTargetAccessibility), @"targetValue": @"Close Advertisement", @"actionType": @(ASRuleActionClick), @"delay": @(0.2), @"priority": @(85)},
    ];
    
    for (NSDictionary *dict in builtin) {
        ASRule *rule = [[ASRule alloc] init];
        rule.ruleId = dict[@"id"];
        rule.targetType = [dict[@"targetType"] integerValue];
        rule.targetValue = dict[@"targetValue"];
        rule.actionType = [dict[@"actionType"] integerValue];
        rule.actionParam = dict[@"actionParam"];
        rule.delayBeforeAction = [dict[@"delay"] doubleValue];
        rule.priority = [dict[@"priority"] integerValue];
        rule.enabled = YES;
        rule.useRegex = [dict[@"useRegex"] boolValue];
        rule.skipButtonKeyword = dict[@"skipKeyword"];
        rule.parentClassName = dict[@"parentClassName"];
        [_rules addObject:rule];
    }
    
    [_rules sortUsingComparator:^NSComparisonResult(ASRule *r1, ASRule *r2) {
        return [@(r2.priority) compare:@(r1.priority)];
    }];
}

- (void)loadRulesFromJSON:(NSData *)jsonData {
    NSError *error = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    
    if (error || ![obj isKindOfClass:[NSDictionary class]]) {
        NSLog(@"%@ JSON解析失败: %@", kRuleEngineLogPrefix, error);
        return;
    }
    
    [_rules removeAllObjects];
    [_appRuleCache removeAllObjects];
    
    NSDictionary *root = (NSDictionary *)obj;
    NSArray *ruleDicts = root[@"rules"];
    
    if (![ruleDicts isKindOfClass:[NSArray class]]) {
        NSLog(@"%@ 规则格式错误，需要包含rules数组", kRuleEngineLogPrefix);
        return;
    }
    
    for (NSDictionary *dict in ruleDicts) {
        ASRule *rule = [[ASRule alloc] init];
        rule.ruleId = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
        rule.appBundleId = dict[@"appBundleId"];
        rule.targetType = [dict[@"targetType"] integerValue];
        rule.targetValue = dict[@"targetValue"];
        rule.actionType = [dict[@"actionType"] integerValue];
        rule.actionParam = dict[@"actionParam"];
        rule.delayBeforeAction = [dict[@"delay"] doubleValue];
        rule.priority = [dict[@"priority"] integerValue];
        rule.enabled = [dict[@"enabled"] boolValue];
        rule.useRegex = [dict[@"useRegex"] boolValue];
        rule.skipButtonKeyword = dict[@"skipKeyword"];
        rule.parentClassName = dict[@"parentClassName"];
        [_rules addObject:rule];
    }
    
    [_rules sortUsingComparator:^NSComparisonResult(ASRule *r1, ASRule *r2) {
        return [@(r2.priority) compare:@(r1.priority)];
    }];
    
    NSLog(@"%@ 成功加载 %lu 条规则", kRuleEngineLogPrefix, (unsigned long)_rules.count);
}

- (void)reloadRules {
    [self loadRulesFromFile:_rulesPath];
}

- (void)startHotReloadWithInterval:(NSTimeInterval)interval {
    [self stopHotReload];
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0);
    _hotReloadTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    
    uint64_t ns = (uint64_t)(interval * NSEC_PER_SEC);
    dispatch_source_set_timer(_hotReloadTimer, dispatch_time(DISPATCH_TIME_NOW, ns), ns, ns / 10);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_hotReloadTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDate *modDate = [[fm attributesOfItemAtPath:strongSelf->_rulesPath error:nil] fileModificationDate];
        
        if (modDate && ![modDate isEqualToDate:strongSelf->_lastModifiedDate]) {
            NSLog(@"%@ 检测到规则文件更新，重新加载", kRuleEngineLogPrefix);
            [strongSelf reloadRules];
        }
    });
    
    dispatch_resume(_hotReloadTimer);
    NSLog(@"%@ 已启动规则热重载，间隔 %.0f 秒", kRuleEngineLogPrefix, interval);
}

- (void)stopHotReload {
    if (_hotReloadTimer) {
        dispatch_source_cancel(_hotReloadTimer);
        _hotReloadTimer = nil;
    }
}

- (NSArray<ASRule *> *)rulesForApp:(NSString *)bundleId {
    if (!bundleId) return [self allRules];
    
    NSArray<ASRule *> *cached = _appRuleCache[bundleId];
    if (cached) return cached;
    
    NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(ASRule *rule, NSDictionary *bindings) {
        if (!rule.enabled) return NO;
        if (!rule.appBundleId) return YES;
        if (rule.useRegex) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rule.appBundleId options:0 error:nil];
            return [regex numberOfMatchesInString:bundleId options:0 range:NSMakeRange(0, bundleId.length)] > 0;
        }
        return [rule.appBundleId isEqualToString:bundleId] || [bundleId containsString:rule.appBundleId];
    }];
    
    NSArray *result = [_rules filteredArrayUsingPredicate:pred];
    _appRuleCache[bundleId] = result;
    return result;
}

- (NSArray<ASRule *> *)rulesForAction:(ASRuleActionType)action {
    NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(ASRule *rule, NSDictionary *bindings) {
        return rule.enabled && rule.actionType == action;
    }];
    return [_rules filteredArrayUsingPredicate:pred];
}

- (NSArray<ASRule *> *)allRules {
    NSPredicate *pred = [NSPredicate predicateWithBlock:^BOOL(ASRule *rule, NSDictionary *bindings) {
        return rule.enabled;
    }];
    return [_rules filteredArrayUsingPredicate:pred];
}

- (BOOL)shouldBlockClass:(NSString *)className {
    for (ASRule *rule in _rules) {
        if (!rule.enabled) continue;
        if (rule.targetType != ASRuleTargetClassName) continue;
        
        if (rule.useRegex) {
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rule.targetValue options:0 error:nil];
            if ([regex numberOfMatchesInString:className options:0 range:NSMakeRange(0, className.length)] > 0) {
                return YES;
            }
        } else {
            if ([className isEqualToString:rule.targetValue] || [className containsString:rule.targetValue]) {
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)shouldBlockView:(UIView *)view {
    return [self matchingRuleForView:view] != nil;
}

- (nullable ASRule *)matchingRuleForView:(UIView *)view {
    NSString *className = NSStringFromClass([view class]);
    
    NSArray *sorted = [_rules sortedArrayUsingComparator:^NSComparisonResult(ASRule *r1, ASRule *r2) {
        return [@(r2.priority) compare:@(r1.priority)];
    }];
    
    for (ASRule *rule in sorted) {
        if (!rule.enabled) continue;
        
        BOOL matches = NO;
        switch (rule.targetType) {
            case ASRuleTargetClassName: {
                if (rule.useRegex) {
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rule.targetValue options:0 error:nil];
                    matches = [regex numberOfMatchesInString:className options:0 range:NSMakeRange(0, className.length)] > 0;
                } else {
                    matches = [className isEqualToString:rule.targetValue] || [className containsString:rule.targetValue];
                }
                break;
            }
            case ASRuleTargetKeyword: {
                NSString *text = [self extractTextFromView:view];
                if (rule.useRegex) {
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rule.targetValue options:0 error:nil];
                    matches = [regex numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] > 0;
                } else {
                    matches = [text containsString:rule.targetValue];
                }
                break;
            }
            case ASRuleTargetAccessibility: {
                NSString *label = view.accessibilityLabel ?: @"";
                if (rule.useRegex) {
                    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rule.targetValue options:0 error:nil];
                    matches = [regex numberOfMatchesInString:label options:0 range:NSMakeRange(0, label.length)] > 0;
                } else {
                    matches = [label containsString:rule.targetValue];
                }
                break;
            }
            default:
                break;
        }
        
        if (matches) return rule;
    }
    
    return nil;
}

- (NSString *)extractTextFromView:(UIView *)view {
    NSMutableString *text = [NSMutableString string];
    
    if ([view isKindOfClass:[UILabel class]]) {
        [text appendString:[(UILabel *)view text] ?: @""];
    }
    if ([view isKindOfClass:[UIButton class]]) {
        NSString *title = [(UIButton *)view titleForState:UIControlStateNormal];
        if (title) [text appendString:title];
    }
    
    if (view.accessibilityLabel) [text appendString:view.accessibilityLabel];
    
    for (UIView *subview in view.subviews) {
        [text appendString:[self extractTextFromView:subview]];
    }
    
    return text;
}

- (void)saveRules {
    NSMutableArray *ruleDicts = [NSMutableArray array];
    for (ASRule *rule in _rules) {
        [ruleDicts addObject:@{
            @"id": rule.ruleId ?: @"",
            @"appBundleId": rule.appBundleId ?: [NSNull null],
            @"targetType": @(rule.targetType),
            @"targetValue": rule.targetValue ?: @"",
            @"actionType": @(rule.actionType),
            @"actionParam": rule.actionParam ?: [NSNull null],
            @"delay": @(rule.delayBeforeAction),
            @"priority": @(rule.priority),
            @"enabled": @(rule.enabled),
            @"useRegex": @(rule.useRegex),
            @"skipKeyword": rule.skipButtonKeyword ?: [NSNull null],
            @"parentClassName": rule.parentClassName ?: [NSNull null],
        }];
    }
    
    NSDictionary *root = @{@"rules": ruleDicts, @"version": @"1.0.0", @"updatedAt": @([[NSDate date] timeIntervalSince1970])};
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    
    if (jsonData) {
        NSString *dir = [_rulesPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [jsonData writeToFile:_rulesPath atomically:YES];
        NSLog(@"%@ 规则已保存到 %@", kRuleEngineLogPrefix, _rulesPath);
    }
}

@end
