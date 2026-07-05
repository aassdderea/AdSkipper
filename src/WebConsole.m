#import "WebConsole.h"
#import "WebUI.h"
#import "RuleEngine.h"
#import "NetworkBlocker.h"
#import "LogBuffer.h"

@interface WebConsole ()
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) BOOL visible;
@end

@implementation WebConsole

+ (instancetype)sharedInstance {
    static WebConsole *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WebConsole alloc] init];
    });
    return instance;
}

- (instancetype)init {
    UIWindowScene *scene = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in [[UIApplication sharedApplication] connectedScenes]) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                scene = (UIWindowScene *)s;
                if (s.activationState == UISceneActivationStateForegroundActive) break;
            }
        }
    }
    
    if (scene) {
        self = [super initWithWindowScene:scene];
    } else {
        self = [super initWithFrame:[UIScreen mainScreen].bounds];
    }
    
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = YES;
        
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        WKUserContentController *cc = [[WKUserContentController alloc] init];
        [cc addScriptMessageHandler:self name:@"adskipper"];
        config.userContentController = cc;
        
        _webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:config];
        _webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _webView.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.05 alpha:1];
        _webView.scrollView.bounces = NO;
        if (@available(iOS 11.0, *)) {
            _webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        }
        
        UIButton *closeBtn = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
        closeBtn.translatesAutoresizingMaskIntoConstraints = NO;
        closeBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.15 alpha:0.9];
        closeBtn.layer.cornerRadius = 22;
        closeBtn.clipsToBounds = YES;
        [closeBtn setTitle:@"×" forState:UIControlStateNormal];
        [closeBtn setTitleColor:[UIColor colorWithRed:0.49 green:1.0 blue:0.42 alpha:1] forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
        [closeBtn addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
        
        [self addSubview:_webView];
        [self addSubview:closeBtn];
        
        [NSLayoutConstraint activateConstraints:@[
            [closeBtn.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:8],
            [closeBtn.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [closeBtn.widthAnchor constraintEqualToConstant:44],
            [closeBtn.heightAnchor constraintEqualToConstant:44]
        ]];
    }
    return self;
}

- (void)show {
    if (_visible) return;
    
    if (![WKWebView class]) {
        [[LogBuffer sharedInstance] log:@"WebKit不可用，控制台无法启动" level:@"error" source:@"Console"];
        return;
    }
    
    _visible = YES;
    self.hidden = NO;
    self.frame = [UIScreen mainScreen].bounds;
    _webView.frame = self.bounds;
    
    NSString *html = kWebUIHTML;
    [_webView loadHTMLString:html baseURL:nil];
    
    [[LogBuffer sharedInstance] info:@"控制台已打开"];
}

- (void)hide {
    if (!_visible) return;
    _visible = NO;
    self.hidden = YES;
}

- (BOOL)isVisible {
    return _visible;
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"adskipper"]) return;
    
    NSDictionary *body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) return;
    
    NSString *action = body[@"action"];
    NSDictionary *params = body[@"params"] ?: @{};
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *result = [self handleAction:action params:params];
        [self sendResult:result callbackId:body[@"cbId"]];
    });
}

- (NSDictionary *)handleAction:(NSString *)action params:(NSDictionary *)params {
    if ([action isEqualToString:@"getRules"]) {
        return [self getRules];
    }
    if ([action isEqualToString:@"saveRule"]) {
        return [self saveRule:params];
    }
    if ([action isEqualToString:@"deleteRule"]) {
        return [self deleteRule:params];
    }
    if ([action isEqualToString:@"toggleRule"]) {
        return [self toggleRule:params];
    }
    if ([action isEqualToString:@"getDomains"]) {
        return [self getDomains];
    }
    if ([action isEqualToString:@"addDomain"]) {
        return [self addDomain:params];
    }
    if ([action isEqualToString:@"deleteDomain"]) {
        return [self deleteDomain:params];
    }
    if ([action isEqualToString:@"getLogs"]) {
        return [self getLogs];
    }
    if ([action isEqualToString:@"clearLogs"]) {
        [[LogBuffer sharedInstance] clear];
        return @{@"ok": @YES};
    }
    if ([action isEqualToString:@"getStats"]) {
        return [self getStats];
    }
    return @{@"error": @"unknown action"};
}

#pragma mark - Rule Actions

- (NSDictionary *)getRules {
    NSArray *rules = [[RuleEngine sharedInstance] allRules];
    NSMutableArray *arr = [NSMutableArray array];
    for (ASRule *rule in rules) {
        [arr addObject:@{
            @"id": rule.ruleId ?: @"",
            @"appBundleId": rule.appBundleId ?: [NSNull null],
            @"targetType": @(rule.targetType),
            @"targetValue": rule.targetValue ?: @"",
            @"actionType": @(rule.actionType),
            @"delay": @(rule.delayBeforeAction),
            @"priority": @(rule.priority),
            @"enabled": @(rule.enabled),
            @"useRegex": @(rule.useRegex),
            @"skipKeyword": rule.skipButtonKeyword ?: [NSNull null]
        }];
    }
    return @{@"rules": arr};
}

- (NSDictionary *)saveRule:(NSDictionary *)params {
    RuleEngine *engine = [RuleEngine sharedInstance];
    NSMutableArray *all = [[engine allRules] mutableCopy];
    
    ASRule *rule = [[ASRule alloc] init];
    rule.ruleId = params[@"id"] ?: [[NSUUID UUID] UUIDString];
    rule.appBundleId = params[@"appBundleId"] == [NSNull null] ? nil : params[@"appBundleId"];
    rule.targetType = [params[@"targetType"] integerValue];
    rule.targetValue = params[@"targetValue"] ?: @"";
    rule.actionType = [params[@"actionType"] integerValue];
    rule.delayBeforeAction = [params[@"delay"] doubleValue];
    rule.priority = [params[@"priority"] integerValue];
    rule.enabled = [params[@"enabled"] boolValue];
    rule.useRegex = [params[@"useRegex"] boolValue];
    rule.skipButtonKeyword = params[@"skipKeyword"] == [NSNull null] ? nil : params[@"skipKeyword"];
    
    BOOL found = NO;
    for (NSUInteger i = 0; i < all.count; i++) {
        if ([[all[i] ruleId] isEqualToString:rule.ruleId]) {
            all[i] = rule;
            found = YES;
            break;
        }
    }
    if (!found) [all addObject:rule];
    
    [all sortUsingComparator:^NSComparisonResult(ASRule *r1, ASRule *r2) {
        return [@(r2.priority) compare:@(r1.priority)];
    }];
    
    [self saveRulesArray:all];
    [engine reloadRules];
    [[LogBuffer sharedInstance] block:@"规则已更新: %@", rule.ruleId];
    return @{@"ok": @YES, @"id": rule.ruleId};
}

- (NSDictionary *)deleteRule:(NSDictionary *)params {
    NSString *ruleId = params[@"id"];
    if (!ruleId) return @{@"error": @"missing id"};
    
    RuleEngine *engine = [RuleEngine sharedInstance];
    NSMutableArray *all = [[engine allRules] mutableCopy];
    for (NSUInteger i = 0; i < all.count; i++) {
        if ([[all[i] ruleId] isEqualToString:ruleId]) {
            [all removeObjectAtIndex:i];
            break;
        }
    }
    [self saveRulesArray:all];
    [engine reloadRules];
    return @{@"ok": @YES};
}

- (NSDictionary *)toggleRule:(NSDictionary *)params {
    NSString *ruleId = params[@"id"];
    if (!ruleId) return @{@"error": @"missing id"};
    
    RuleEngine *engine = [RuleEngine sharedInstance];
    NSMutableArray *all = [[engine allRules] mutableCopy];
    for (ASRule *r in all) {
        if ([r.ruleId isEqualToString:ruleId]) {
            r.enabled = !r.enabled;
            break;
        }
    }
    [self saveRulesArray:all];
    [engine reloadRules];
    return @{@"ok": @YES};
}

- (void)saveRulesArray:(NSArray<ASRule *> *)rules {
    NSMutableArray *dicts = [NSMutableArray array];
    for (ASRule *r in rules) {
        [dicts addObject:@{
            @"id": r.ruleId, @"appBundleId": r.appBundleId ?: [NSNull null],
            @"targetType": @(r.targetType), @"targetValue": r.targetValue,
            @"actionType": @(r.actionType), @"delay": @(r.delayBeforeAction),
            @"priority": @(r.priority), @"enabled": @(r.enabled),
            @"useRegex": @(r.useRegex), @"skipKeyword": r.skipButtonKeyword ?: [NSNull null]
        }];
    }
    NSDictionary *root = @{@"rules": dicts, @"version": @"1.0"};
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[[RuleEngine sharedInstance] rulesFilePath] atomically:YES];
}

#pragma mark - Domain Actions

- (NSDictionary *)getDomains {
    NSArray *domains = [[NetworkBlocker sharedInstance] allBlockedDomains];
    return @{@"domains": domains};
}

- (NSDictionary *)addDomain:(NSDictionary *)params {
    NSString *domain = params[@"domain"];
    if (!domain) return @{@"error": @"missing domain"};
    [[NetworkBlocker sharedInstance] addDomainToBlacklist:domain];
    [[LogBuffer sharedInstance] block:@"域名已添加: %@", domain];
    return @{@"ok": @YES};
}

- (NSDictionary *)deleteDomain:(NSDictionary *)params {
    NSString *domain = params[@"domain"];
    if (!domain) return @{@"error": @"missing domain"};
    [[NetworkBlocker sharedInstance] removeDomainFromBlacklist:domain];
    [[LogBuffer sharedInstance] block:@"域名已删除: %@", domain];
    return @{@"ok": @YES};
}

#pragma mark - Logs & Stats

- (NSDictionary *)getLogs {
    return [NSJSONSerialization JSONObjectWithData:[[[LogBuffer sharedInstance] allLogsJSON] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] ?: @{@"logs": @[]};
}

- (NSDictionary *)getStats {
    LogBuffer *lb = [LogBuffer sharedInstance];
    NetworkBlocker *nb = [NetworkBlocker sharedInstance];
    RuleEngine *re = [RuleEngine sharedInstance];
    return @{
        @"dnsBlocked": @(lb.totalDnsBlocked),
        @"httpBlocked": @(lb.totalHttpBlocked),
        @"uiBlocked": @(lb.totalUiBlocked),
        @"total": @(lb.totalDnsBlocked + lb.totalHttpBlocked + lb.totalUiBlocked),
        @"rules": @([re allRules].count),
        @"domains": @([nb allBlockedDomains].count)
    };
}

- (void)sendResult:(NSDictionary *)result callbackId:(NSString *)cbId {
    if (!cbId) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:result ?: @{} options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *js = [NSString stringWithFormat:@"_cb(%@, %@)", cbId, json ?: @"{}"];
    [_webView evaluateJavaScript:js completionHandler:nil];
}

@end
