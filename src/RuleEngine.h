#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ASRuleActionType) {
    ASRuleActionBlock = 0,
    ASRuleActionRemove,
    ASRuleActionClick,
    ASRuleActionDismiss,
    ASRuleActionHide
};

typedef NS_ENUM(NSInteger, ASRuleTargetType) {
    ASRuleTargetClassName = 0,
    ASRuleTargetKeyword,
    ASRuleTargetAccessibility,
    ASRuleTargetSDKMethod
};

@interface ASRule : NSObject

@property (nonatomic, copy) NSString *ruleId;
@property (nonatomic, copy, nullable) NSString *appBundleId;
@property (nonatomic, assign) ASRuleTargetType targetType;
@property (nonatomic, copy) NSString *targetValue;
@property (nonatomic, assign) ASRuleActionType actionType;
@property (nonatomic, copy, nullable) NSString *actionParam;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) NSTimeInterval delayBeforeAction;
@property (nonatomic, assign) NSInteger priority;
@property (nonatomic, assign) BOOL useRegex;
@property (nonatomic, copy, nullable) NSString *skipButtonKeyword;
@property (nonatomic, copy, nullable) NSString *parentClassName;

@end

@interface RuleEngine : NSObject

+ (instancetype)sharedInstance;

- (void)loadRulesFromFile:(NSString *)path;
- (void)loadRulesFromJSON:(NSData *)jsonData;
- (void)reloadRules;
- (void)startHotReloadWithInterval:(NSTimeInterval)interval;
- (void)stopHotReload;

- (NSArray<ASRule *> *)rulesForApp:(NSString *)bundleId;
- (NSArray<ASRule *> *)rulesForAction:(ASRuleActionType)action;
- (NSArray<ASRule *> *)allRules;

- (BOOL)shouldBlockClass:(NSString *)className;
- (BOOL)shouldBlockView:(UIView *)view;
- (nullable ASRule *)matchingRuleForView:(UIView *)view;

- (NSString *)rulesFilePath;
- (void)saveRules;

@end

NS_ASSUME_NONNULL_END
