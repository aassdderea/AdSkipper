#import "TouchSimulator.h"
#import <objc/runtime.h>

static NSString *const kTouchSimLogPrefix = @"[AdSkipper::Touch]";

@implementation TouchSimulator

+ (instancetype)sharedInstance {
    static TouchSimulator *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TouchSimulator alloc] init];
    });
    return instance;
}

- (void)simulateTapOnView:(UIView *)view {
    if (!view || view.hidden || view.alpha < 0.01) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self executeSimulatedTapOnView:view];
    });
}

- (void)simulateTapAtPoint:(CGPoint)point inView:(UIView *)view {
    if (!view) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *hitView = [view hitTest:point withEvent:nil];
        if (hitView) {
            [self executeSimulatedTapOnView:hitView];
        }
    });
}

- (void)executeSimulatedTapOnView:(UIView *)view {
    NSLog(@"%@ 模拟点击视图: %@", kTouchSimLogPrefix, NSStringFromClass([view class]));
    
    [self invokeAllTargetActions:view withEvent:nil];
    
    if ([view respondsToSelector:@selector(sendActionsForControlEvents:)]) {
        UIControl *control = (UIControl *)view;
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        [control sendActionsForControlEvents:UIControlEventTouchDown];
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    }
    
    if ([view.gestureRecognizers count] > 0) {
        for (UIGestureRecognizer *gr in view.gestureRecognizers) {
            if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
                [self fireGestureRecognizer:gr onView:view];
            }
        }
    }
    
    if ([view respondsToSelector:@selector(touchesBegan:withEvent:)]) {
        [self simulateTouchesOnView:view];
    }
    
    if ([view canBecomeFirstResponder]) {
        [view becomeFirstResponder];
    }
    
    [self notifyAccessibilityActivate:view];
}

- (void)invokeAllTargetActions:(UIView *)view withEvent:(UIEvent *)event {
    if (![view isKindOfClass:[UIControl class]]) {
        [self tryInvokeParentControl:view event:event];
        return;
    }
    
    UIControl *control = (UIControl *)view;
    NSSet *targets = [control allTargets];
    
    for (id target in targets) {
        NSArray *actions = [control actionsForTarget:target forControlEvent:UIControlEventTouchUpInside];
        if (!actions) {
            actions = [control actionsForTarget:target forControlEvent:UIControlEventTouchDown];
        }
        if (!actions) {
            actions = [control actionsForTarget:target forControlEvent:UIControlEventPrimaryActionTriggered];
        }
        
        for (NSString *action in actions) {
            SEL sel = NSSelectorFromString(action);
            if ([target respondsToSelector:sel]) {
                NSLog(@"%@ 触发动作: %@ -> %@", kTouchSimLogPrefix, NSStringFromClass([target class]), action);
                
                NSMethodSignature *sig = [target methodSignatureForSelector:sel];
                if (sig) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:target];
                    [inv setSelector:sel];
                    
                    if ([action containsString:@":"]) {
                        id param = control;
                        [inv setArgument:&param atIndex:2];
                    }
                    [inv invoke];
                }
            }
        }
    }
}

- (void)tryInvokeParentControl:(UIView *)view event:(UIEvent *)event {
    UIView *parent = view.superview;
    while (parent) {
        if ([parent isKindOfClass:[UIControl class]]) {
            [self invokeAllTargetActions:parent withEvent:event];
            return;
        }
        parent = parent.superview;
    }
}

- (void)fireGestureRecognizer:(UIGestureRecognizer *)gr onView:(UIView *)view {
    if ([gr respondsToSelector:@selector(ignoreTouch:forEvent:)]) {
        [gr performSelector:@selector(reset)];
    }
    
    if ([gr.delegate respondsToSelector:@selector(gestureRecognizer:shouldReceiveTouch:)]) {
        [gr setState:UIGestureRecognizerStateBegan];
        [gr setState:UIGestureRecognizerStateEnded];
        
        if ([gr respondsToSelector:@selector(touchesBegan:withEvent:)]) {
            [gr performSelector:@selector(touchesBegan:withEvent:) withObject:nil withObject:nil];
        }
        if ([gr respondsToSelector:@selector(touchesEnded:withEvent:)]) {
            [gr performSelector:@selector(touchesEnded:withEvent:) withObject:nil withObject:nil];
        }
    }
}

- (void)simulateTouchesOnView:(UIView *)view {
    Class UITouchClass = NSClassFromString(@"UITouch");
    Class UIEventClass = NSClassFromString(@"UIEvent");
    
    if (!UITouchClass || !UIEventClass) return;
    
    UITouch *touch = [[UITouchClass alloc] init];
    [touch setValue:view forKey:@"view"];
    [touch setValue:view.window forKey:@"window"];
    [touch setValue:@(UITouchPhaseBegan) forKey:@"phase"];
    [touch setValue:@(0) forKey:@"tapCount"];
    
    CGPoint center = CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds));
    center = [view.window convertPoint:center fromView:view];
    [touch setValue:[NSValue valueWithCGPoint:center] forKey:@"locationInWindow"];
    
    NSSet *touches = [NSSet setWithObject:touch];
    
    UIEvent *event = [[UIEventClass alloc] init];
    SEL eventTouchesSelector = NSSelectorFromString(@"_initWithEvent:timestamp:");
    if ([event respondsToSelector:eventTouchesSelector]) {
        [event performSelector:eventTouchesSelector withObject:nil withObject:nil];
    }
    
    [touch setValue:@(UITouchPhaseBegan) forKey:@"phase"];
    [view touchesBegan:touches withEvent:event];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [touch setValue:@(UITouchPhaseEnded) forKey:@"phase"];
        [view touchesEnded:touches withEvent:event];
    });
}

- (void)notifyAccessibilityActivate:(UIView *)view {
    if (!view.isAccessibilityElement) return;
    
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"");
    
    SEL activateSelector = NSSelectorFromString(@"accessibilityActivate");
    if ([view respondsToSelector:activateSelector]) {
        [view performSelector:activateSelector];
    }
}

- (void)simulateSwipeInView:(UIView *)view direction:(UISwipeGestureRecognizerDirection)direction {
    dispatch_async(dispatch_get_main_queue(), ^{
        CGFloat dx = 0, dy = 0;
        switch (direction) {
            case UISwipeGestureRecognizerDirectionRight: dx = view.bounds.size.width * 0.8; break;
            case UISwipeGestureRecognizerDirectionLeft:  dx = -view.bounds.size.width * 0.8; break;
            case UISwipeGestureRecognizerDirectionDown:  dy = view.bounds.size.height * 0.8; break;
            case UISwipeGestureRecognizerDirectionUp:    dy = -view.bounds.size.height * 0.8; break;
            default: break;
        }
        
        CGPoint start = CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds));
        CGPoint end = CGPointMake(start.x + dx, start.y + dy);
        
        [self simulateSwipeFromPoint:start toPoint:end inView:view];
    });
}

- (void)simulateSwipeFromPoint:(CGPoint)fromPoint toPoint:(CGPoint)toPoint inView:(UIView *)view {
    UIView *startView = [view hitTest:fromPoint withEvent:nil];
    UIView *endView = [view hitTest:toPoint withEvent:nil];
    
    if (startView) {
        [self simulateTouchesOnView:startView];
    }
    if (endView && endView != startView) {
        [self simulateTouchesOnView:endView];
    }
}

- (void)sendSystemEventForView:(UIView *)view {
    if (!view) return;
    
    SEL hitTestSelector = NSSelectorFromString(@"hitTest:withEvent:");
    CGPoint center = CGPointMake(CGRectGetMidX(view.bounds), CGRectGetMidY(view.bounds));
    UIView *hitView = [view hitTest:center withEvent:nil];
    
    if (hitView && [hitView isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)hitView;
        [control sendAction:control.actionsForTarget ? nil : @selector(touchesBegan:withEvent:)
                          to:control.allTargets.anyObject
                    forEvent:nil];
    }
}

@end
