#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchSimulator : NSObject

+ (instancetype)sharedInstance;

- (void)simulateTapOnView:(UIView *)view;
- (void)simulateTapAtPoint:(CGPoint)point inView:(UIView *)view;
- (void)simulateSwipeInView:(UIView *)view direction:(UISwipeGestureRecognizerDirection)direction;
- (void)sendSystemEventForView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
