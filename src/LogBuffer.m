#import "LogBuffer.h"

#define MAX_LOG_ENTRIES 500

@implementation LogEntry

- (NSDictionary *)toDictionary {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
    return @{
        @"time": [fmt stringFromDate:self.timestamp],
        @"level": self.level ?: @"info",
        @"source": self.source ?: @"",
        @"message": self.message ?: @""
    };
}

@end

@interface LogBuffer ()
@property (nonatomic, strong) NSMutableArray<LogEntry *> *entries;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, assign) NSUInteger dnsBlocked;
@property (nonatomic, assign) NSUInteger httpBlocked;
@property (nonatomic, assign) NSUInteger uiBlocked;
@end

@implementation LogBuffer

+ (instancetype)sharedInstance {
    static LogBuffer *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[LogBuffer alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _entries = [NSMutableArray arrayWithCapacity:MAX_LOG_ENTRIES];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)log:(NSString *)message level:(NSString *)level source:(NSString *)source {
    LogEntry *entry = [[LogEntry alloc] init];
    entry.timestamp = [NSDate date];
    entry.level = level;
    entry.source = source;
    entry.message = message;
    
    [_lock lock];
    [_entries addObject:entry];
    if (_entries.count > MAX_LOG_ENTRIES) {
        [_entries removeObjectsInRange:NSMakeRange(0, _entries.count - MAX_LOG_ENTRIES)];
    }
    [_lock unlock];
    
    NSLog(@"[AdSkipper::%@] %@", source, message);
}

- (void)info:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:msg level:@"info" source:@"System"];
}

- (void)block:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self log:msg level:@"block" source:@"Block"];
}

- (NSArray<LogEntry *> *)allLogs {
    [_lock lock];
    NSArray *copy = [_entries copy];
    [_lock unlock];
    return copy;
}

- (NSArray<LogEntry *> *)recentLogs:(NSUInteger)count {
    [_lock lock];
    NSUInteger start = _entries.count > count ? _entries.count - count : 0;
    NSArray *copy = [_entries subarrayWithRange:NSMakeRange(start, _entries.count - start)];
    [_lock unlock];
    return copy;
}

- (NSString *)allLogsJSON {
    [_lock lock];
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:_entries.count];
    for (LogEntry *e in _entries) {
        [arr addObject:[e toDictionary]];
    }
    NSDictionary *root = @{
        @"logs": arr,
        @"stats": @{
            @"dns": @(_dnsBlocked),
            @"http": @(_httpBlocked),
            @"ui": @(_uiBlocked),
            @"total": @(_dnsBlocked + _httpBlocked + _uiBlocked)
        }
    };
    [_lock unlock];
    
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)clear {
    [_lock lock];
    [_entries removeAllObjects];
    _dnsBlocked = 0;
    _httpBlocked = 0;
    _uiBlocked = 0;
    [_lock unlock];
}

- (NSUInteger)totalDnsBlocked { return _dnsBlocked; }
- (NSUInteger)totalHttpBlocked { return _httpBlocked; }
- (NSUInteger)totalUiBlocked { return _uiBlocked; }

- (void)incrementDns {
    [_lock lock]; _dnsBlocked++; [_lock unlock];
}

- (void)incrementHttp {
    [_lock lock]; _httpBlocked++; [_lock unlock];
}

- (void)incrementUi {
    [_lock lock]; _uiBlocked++; [_lock unlock];
}

@end
