#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class ASRule;

NS_ASSUME_NONNULL_BEGIN

@interface AdDetector : NSObject

+ (instancetype)sharedInstance;

- (void)startScanning;
- (void)stopScanning;
- (void)scanViewHierarchy:(UIView *)rootView;
- (void)scanAllWindows;
- (UIView * _Nullable)findSkipButtonInView:(UIView *)view withKeyword:(NSString *)keyword;
- (void)handleDetectedAdView:(UIView *)adView withRule:(ASRule *)rule;
- (void)scheduleDelayedActionForView:(UIView *)view rule:(ASRule *)rule;

@end

NS_ASSUME_NONNULL_END
