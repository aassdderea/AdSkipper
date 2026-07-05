#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WebConsole : UIWindow <WKScriptMessageHandler>

+ (instancetype)sharedInstance;
- (void)show;
- (void)hide;
- (BOOL)isVisible;

@end

NS_ASSUME_NONNULL_END
