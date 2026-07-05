#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void hello(void) {
    NSLog(@"[AdSkipper] ====== DYLIB 已加载！=======");
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        UIWindow *kw = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *w in [(UIWindowScene *)s windows]) {
                        if (!w.hidden && w.alpha > 0) { kw = w; break; }
                    }
                }
                if (kw) break;
            }
        }
        if (!kw) kw = [UIApplication sharedApplication].windows.firstObject;
        if (!kw) return;
        
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(0, 80, kw.bounds.size.width, 60)];
        lb.text = @"AdSkipper OK!";
        lb.textColor = [UIColor greenColor];
        lb.textAlignment = NSTextAlignmentCenter;
        lb.font = [UIFont boldSystemFontOfSize:28];
        lb.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
        [kw addSubview:lb];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ [lb removeFromSuperview]; });
    });
}
