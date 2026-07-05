#import "WebServer.h"
#import "WebUI.h"
#import "RuleEngine.h"
#import "NetworkBlocker.h"
#import "LogBuffer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>

static NSString *const kWSLogPrefix = @"[WebServer]";

@interface WebServer ()
@property (nonatomic, assign) int listenSocket;
@property (nonatomic, strong) dispatch_source_t acceptSource;
@property (nonatomic, assign) uint16_t port;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, strong) NSMutableArray *clientSockets;
@property (nonatomic, strong) NSLock *socketLock;
@end

@implementation WebServer

+ (instancetype)sharedInstance {
    static WebServer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[WebServer alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _clientSockets = [NSMutableArray array];
        _socketLock = [[NSLock alloc] init];
    }
    return self;
}

- (BOOL)startOnPort:(uint16_t)port {
    if (_running) return YES;
    
    for (uint16_t tryPort = port; tryPort < port + 10; tryPort++) {
        if ([self tryStartOnPort:tryPort]) {
            _port = tryPort;
            _running = YES;
            [[LogBuffer sharedInstance] info:@"Web管理界面已启动 %@", [self accessURL]];
            return YES;
        }
    }
    [[LogBuffer sharedInstance] log:@"Web服务器启动失败(端口被占用)" level:@"error" source:@"WebServer"];
    return NO;
}

- (BOOL)tryStartOnPort:(uint16_t)port {
    _listenSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (_listenSocket < 0) return NO;
    
    int reuse = 1;
    setsockopt(_listenSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(port);
    
    if (bind(_listenSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(_listenSocket);
        return NO;
    }
    
    if (listen(_listenSocket, 5) < 0) {
        close(_listenSocket);
        return NO;
    }
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    _acceptSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)_listenSocket, 0, queue);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_acceptSource, ^{
        [weakSelf acceptConnection];
    });
    
    dispatch_source_set_cancel_handler(_acceptSource, ^{
        close(weakSelf.listenSocket);
    });
    
    dispatch_resume(_acceptSource);
    return YES;
}

- (void)acceptConnection {
    struct sockaddr_in clientAddr;
    socklen_t len = sizeof(clientAddr);
    int clientFd = accept(_listenSocket, (struct sockaddr *)&clientAddr, &len);
    if (clientFd < 0) return;
    
    int on = 1;
    setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    
    [_socketLock lock];
    [_clientSockets addObject:@(clientFd)];
    [_socketLock unlock];
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)clientFd, 0, queue);
    
    __weak typeof(self) weakSelf = self;
    __block NSMutableData *buffer = [NSMutableData data];
    
    dispatch_source_set_event_handler(readSource, ^{
        size_t estimated = dispatch_source_get_data(readSource);
        if (estimated == 0) {
            dispatch_source_cancel(readSource);
            return;
        }
        
        char buf[65536];
        ssize_t n = recv(clientFd, buf, sizeof(buf), 0);
        if (n <= 0) {
            dispatch_source_cancel(readSource);
            return;
        }
        
        [buffer appendBytes:buf length:n];
        
        NSString *raw = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
        if ([raw containsString:@"\r\n\r\n"] || [raw containsString:@"\n\n"]) {
            [weakSelf handleRequest:raw clientFd:clientFd];
            dispatch_source_cancel(readSource);
        }
    });
    
    dispatch_source_set_cancel_handler(readSource, ^{
        close(clientFd);
        [weakSelf.socketLock lock];
        [weakSelf.clientSockets removeObject:@(clientFd)];
        [weakSelf.socketLock unlock];
    });
    
    dispatch_resume(readSource);
}

- (void)handleRequest:(NSString *)raw clientFd:(int)fd {
    NSArray *lines = [raw componentsSeparatedByString:@"\n"];
    if (lines.count == 0) { close(fd); return; }
    
    NSString *firstLine = [lines[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *parts = [firstLine componentsSeparatedByString:@" "];
    if (parts.count < 2) { close(fd); return; }
    
    NSString *method = parts[0];
    NSString *path = parts[1];
    
    NSString *body = nil;
    NSRange bodySep = [raw rangeOfString:@"\r\n\r\n"];
    if (bodySep.location == NSNotFound) bodySep = [raw rangeOfString:@"\n\n"];
    if (bodySep.location != NSNotFound) {
        body = [raw substringFromIndex:bodySep.location + bodySep.length];
    }
    
    NSString *response = [self routeRequest:method path:path body:body];
    NSData *data = [response dataUsingEncoding:NSUTF8StringEncoding];
    send(fd, data.bytes, data.length, 0);
}

- (NSString *)routeRequest:(NSString *)method path:(NSString *)path body:(NSString *)body {
    if ([path isEqualToString:@"/"]) {
        return [self httpResponse:kWebUIHTML contentType:@"text/html; charset=utf-8"];
    }
    
    if ([path isEqualToString:@"/api/status"]) {
        return [self jsonResponse:@{@"running": @YES, @"port": @(_port)}];
    }
    
    if ([path isEqualToString:@"/api/rules"]) {
        if ([method isEqualToString:@"POST"]) {
            return [self handleSaveRules:body];
        }
        return [self handleGetRules];
    }
    
    if ([path isEqualToString:@"/api/rules/delete"]) {
        return [self handleDeleteRule:body];
    }
    
    if ([path isEqualToString:@"/api/rules/toggle"]) {
        return [self handleToggleRule:body];
    }
    
    if ([path isEqualToString:@"/api/domains"]) {
        if ([method isEqualToString:@"POST"]) {
            return [self handleAddDomain:body];
        }
        return [self handleGetDomains];
    }
    
    if ([path isEqualToString:@"/api/domains/delete"]) {
        return [self handleDeleteDomain:body];
    }
    
    if ([path isEqualToString:@"/api/stats"]) {
        return [self handleGetStats];
    }
    
    if ([path isEqualToString:@"/api/logs"]) {
        return [self handleGetLogs];
    }
    
    if ([path isEqualToString:@"/api/logs/clear"]) {
        [[LogBuffer sharedInstance] clear];
        return [self jsonResponse:@{@"ok": @YES}];
    }
    
    return [self httpResponse:@"404 Not Found" contentType:@"text/plain"];
}

#pragma mark - Rule Handlers

- (NSString *)handleGetRules {
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
    return [self jsonResponse:@{@"rules": arr}];
}

- (NSString *)handleSaveRules:(NSString *)body {
    if (!body) return [self jsonResponse:@{@"error": @"empty body"}];
    NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (!dict) return [self jsonResponse:@{@"error": @"invalid json"}];
    
    RuleEngine *engine = [RuleEngine sharedInstance];
    NSMutableArray *allRules = [[engine allRules] mutableCopy];
    
    ASRule *rule = [[ASRule alloc] init];
    rule.ruleId = dict[@"id"] ?: [[NSUUID UUID] UUIDString];
    rule.appBundleId = dict[@"appBundleId"] == [NSNull null] ? nil : dict[@"appBundleId"];
    rule.targetType = [dict[@"targetType"] integerValue];
    rule.targetValue = dict[@"targetValue"] ?: @"";
    rule.actionType = [dict[@"actionType"] integerValue];
    rule.delayBeforeAction = [dict[@"delay"] doubleValue];
    rule.priority = [dict[@"priority"] integerValue];
    rule.enabled = [dict[@"enabled"] boolValue];
    rule.useRegex = [dict[@"useRegex"] boolValue];
    rule.skipButtonKeyword = dict[@"skipKeyword"] == [NSNull null] ? nil : dict[@"skipKeyword"];
    
    BOOL found = NO;
    for (NSUInteger i = 0; i < allRules.count; i++) {
        if ([[allRules[i] ruleId] isEqualToString:rule.ruleId]) {
            allRules[i] = rule;
            found = YES;
            break;
        }
    }
    if (!found) {
        [allRules addObject:rule];
    }
    
    [allRules sortUsingComparator:^NSComparisonResult(ASRule *r1, ASRule *r2) {
        return [@(r2.priority) compare:@(r1.priority)];
    }];
    
    NSMutableArray *dicts = [NSMutableArray array];
    for (ASRule *r in allRules) {
        [dicts addObject:@{
            @"id": r.ruleId, @"appBundleId": r.appBundleId ?: [NSNull null],
            @"targetType": @(r.targetType), @"targetValue": r.targetValue,
            @"actionType": @(r.actionType), @"delay": @(r.delayBeforeAction),
            @"priority": @(r.priority), @"enabled": @(r.enabled),
            @"useRegex": @(r.useRegex), @"skipKeyword": r.skipButtonKeyword ?: [NSNull null]
        }];
    }
    
    NSDictionary *root = @{@"rules": dicts, @"version": @"1.0", @"updatedAt": @([[NSDate date] timeIntervalSince1970])};
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[[RuleEngine sharedInstance] rulesFilePath] atomically:YES];
    
    [[RuleEngine sharedInstance] reloadRules];
    [[LogBuffer sharedInstance] block:@"规则已更新: %@", rule.ruleId];
    return [self jsonResponse:@{@"ok": @YES, @"id": rule.ruleId}];
}

- (NSString *)handleDeleteRule:(NSString *)body {
    if (!body) return [self jsonResponse:@{@"error": @"empty body"}];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSString *ruleId = dict[@"id"];
    if (!ruleId) return [self jsonResponse:@{@"error": @"missing id"}];
    
    RuleEngine *engine = [RuleEngine sharedInstance];
    NSMutableArray *all = [[engine allRules] mutableCopy];
    for (NSUInteger i = 0; i < all.count; i++) {
        if ([[all[i] ruleId] isEqualToString:ruleId]) {
            [all removeObjectAtIndex:i];
            [[LogBuffer sharedInstance] block:@"规则已删除: %@", ruleId];
            break;
        }
    }
    
    [self saveRulesArray:all];
    [[RuleEngine sharedInstance] reloadRules];
    return [self jsonResponse:@{@"ok": @YES}];
}

- (NSString *)handleToggleRule:(NSString *)body {
    if (!body) return [self jsonResponse:@{@"error": @"empty body"}];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSString *ruleId = dict[@"id"];
    if (!ruleId) return [self jsonResponse:@{@"error": @"missing id"}];
    
    RuleEngine *engine = [RuleEngine sharedInstance];
    NSMutableArray *all = [[engine allRules] mutableCopy];
    for (ASRule *r in all) {
        if ([r.ruleId isEqualToString:ruleId]) {
            r.enabled = !r.enabled;
            break;
        }
    }
    [self saveRulesArray:all];
    [[RuleEngine sharedInstance] reloadRules];
    return [self jsonResponse:@{@"ok": @YES}];
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
    NSDictionary *root = @{@"rules": dicts, @"version": @"1.0", @"updatedAt": @([[NSDate date] timeIntervalSince1970])};
    NSData *json = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:[[RuleEngine sharedInstance] rulesFilePath] atomically:YES];
}

#pragma mark - Domain Handlers

- (NSString *)handleGetDomains {
    NSArray *domains = [[NetworkBlocker sharedInstance] allBlockedDomains];
    return [self jsonResponse:@{@"domains": domains}];
}

- (NSString *)handleAddDomain:(NSString *)body {
    if (!body) return [self jsonResponse:@{@"error": @"empty body"}];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSString *domain = dict[@"domain"];
    if (!domain) return [self jsonResponse:@{@"error": @"missing domain"}];
    
    [[NetworkBlocker sharedInstance] addDomainToBlacklist:domain];
    [[LogBuffer sharedInstance] block:@"域名已添加: %@", domain];
    return [self jsonResponse:@{@"ok": @YES}];
}

- (NSString *)handleDeleteDomain:(NSString *)body {
    if (!body) return [self jsonResponse:@{@"error": @"empty body"}];
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:[body dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSString *domain = dict[@"domain"];
    if (!domain) return [self jsonResponse:@{@"error": @"missing domain"}];
    
    [[NetworkBlocker sharedInstance] removeDomainFromBlacklist:domain];
    [[LogBuffer sharedInstance] block:@"域名已删除: %@", domain];
    return [self jsonResponse:@{@"ok": @YES}];
}

#pragma mark - Stats & Logs

- (NSString *)handleGetStats {
    LogBuffer *lb = [LogBuffer sharedInstance];
    NetworkBlocker *nb = [NetworkBlocker sharedInstance];
    RuleEngine *re = [RuleEngine sharedInstance];
    return [self jsonResponse:@{
        @"dnsBlocked": @(lb.totalDnsBlocked),
        @"httpBlocked": @(lb.totalHttpBlocked),
        @"uiBlocked": @(lb.totalUiBlocked),
        @"total": @(lb.totalDnsBlocked + lb.totalHttpBlocked + lb.totalUiBlocked),
        @"rules": @([re allRules].count),
        @"domains": @([nb allBlockedDomains].count)
    }];
}

- (NSString *)handleGetLogs {
    return [[LogBuffer sharedInstance] allLogsJSON];
}

#pragma mark - HTTP Helpers

- (NSString *)httpResponse:(NSString *)body contentType:(NSString *)ct {
    return [NSString stringWithFormat:
        @"HTTP/1.1 200 OK\r\n"
        @"Content-Type: %@\r\n"
        @"Content-Length: %lu\r\n"
        @"Access-Control-Allow-Origin: *\r\n"
        @"Connection: close\r\n"
        @"\r\n%@", ct, (unsigned long)body.length, body];
}

- (NSString *)jsonResponse:(NSDictionary *)dict {
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [self httpResponse:json ?: @"{}" contentType:@"application/json; charset=utf-8"];
}

- (void)stop {
    if (!_running) return;
    _running = NO;
    
    if (_acceptSource) {
        dispatch_source_cancel(_acceptSource);
        _acceptSource = nil;
    }
    
    [_socketLock lock];
    for (NSNumber *fdNum in _clientSockets) {
        close([fdNum intValue]);
    }
    [_clientSockets removeAllObjects];
    [_socketLock unlock];
    
    close(_listenSocket);
}

- (uint16_t)actualPort {
    return _port;
}

- (BOOL)isRunning {
    return _running;
}

- (NSString *)accessURL {
    return [NSString stringWithFormat:@"http://127.0.0.1:%d", _port];
}

@end
