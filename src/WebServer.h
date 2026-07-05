#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WebServer : NSObject

+ (instancetype)sharedInstance;

- (BOOL)startOnPort:(uint16_t)port;
- (void)stop;
- (uint16_t)actualPort;
- (BOOL)isRunning;
- (NSString *)accessURL;

@end

NS_ASSUME_NONNULL_END
