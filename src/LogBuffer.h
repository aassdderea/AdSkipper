#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LogEntry : NSObject
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, copy) NSString *level;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *message;
- (NSDictionary *)toDictionary;
@end

@interface LogBuffer : NSObject

+ (instancetype)sharedInstance;

- (void)log:(NSString *)message level:(NSString *)level source:(NSString *)source;
- (void)info:(NSString *)format, ...;
- (void)block:(NSString *)format, ...;

- (NSArray<LogEntry *> *)allLogs;
- (NSArray<LogEntry *> *)recentLogs:(NSUInteger)count;
- (NSString *)allLogsJSON;
- (void)clear;

@property (nonatomic, readonly) NSUInteger totalDnsBlocked;
@property (nonatomic, readonly) NSUInteger totalHttpBlocked;
@property (nonatomic, readonly) NSUInteger totalUiBlocked;
- (void)incrementDns;
- (void)incrementHttp;
- (void)incrementUi;

@end

NS_ASSUME_NONNULL_END
