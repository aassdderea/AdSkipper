#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NetworkBlocker : NSObject

+ (instancetype)sharedInstance;

- (void)loadDomainBlacklist:(NSArray<NSString *> *)domains;
- (void)loadDomainBlacklistFromFile:(NSString *)path;
- (void)addDomainToBlacklist:(NSString *)domain;
- (void)removeDomainFromBlacklist:(NSString *)domain;
- (BOOL)isDomainBlocked:(NSString *)host;
- (BOOL)isURLBlocked:(NSURL *)url;

- (void)installDNSHook;
- (void)installURLSessionHook;

- (NSArray<NSString *> *)allBlockedDomains;
- (NSUInteger)blockedRequestCount;
- (void)resetCounters;

@end

NS_ASSUME_NONNULL_END
