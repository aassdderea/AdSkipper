#import "NetworkBlocker.h"
#import "RuleEngine.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <netdb.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach-o/nlist.h>
#import <string.h>
#import <unistd.h>

static NSString *const kNBLogPrefix = @"[AdSkipper::Network]";

static int (*_original_getaddrinfo)(const char *hostname, const char *servname,
                                     const struct addrinfo *hints, struct addrinfo **res);
static int (*_original_getaddrinfo_darwin)(const char *hostname, const char *servname,
                                            const struct addrinfo *hints, struct addrinfo **res);

@interface NetworkBlocker ()
@property (nonatomic, strong) NSMutableSet<NSString *> *blockedDomains;
@property (nonatomic, strong) NSMutableSet<NSString *> *blockedWildcardDomains;
@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, assign) NSUInteger dnsBlockedCount;
@property (nonatomic, assign) NSUInteger httpBlockedCount;
@end

struct nb_rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

@implementation NetworkBlocker

+ (instancetype)sharedInstance {
    static NetworkBlocker *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[NetworkBlocker alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _blockedDomains = [NSMutableSet set];
        _blockedWildcardDomains = [NSMutableSet set];
        _lock = [[NSLock alloc] init];
        _dnsBlockedCount = 0;
        _httpBlockedCount = 0;
    }
    return self;
}

#pragma mark - Domain Blacklist Management

- (void)loadDomainBlacklist:(NSArray<NSString *> *)domains {
    [_lock lock];
    [_blockedDomains removeAllObjects];
    [_blockedWildcardDomains removeAllObjects];
    
    for (NSString *domain in domains) {
        NSString *trimmed = [domain stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length == 0 || [trimmed hasPrefix:@"#"]) continue;
        
        NSString *lower = [trimmed lowercaseString];
        if ([lower hasPrefix:@"*."]) {
            [_blockedWildcardDomains addObject:[lower substringFromIndex:1]];
        } else {
            [_blockedDomains addObject:lower];
        }
    }
    
    [_lock unlock];
    NSLog(@"%@ 已加载 %lu 个精确域名 + %lu 个通配域名",
          kNBLogPrefix,
          (unsigned long)_blockedDomains.count,
          (unsigned long)_blockedWildcardDomains.count);
}

- (void)loadDomainBlacklistFromFile:(NSString *)path {
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!content) {
        NSLog(@"%@ 域名黑名单文件不存在: %@", kNBLogPrefix, path);
        return;
    }
    
    NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    [self loadDomainBlacklist:lines];
    
    NSString *rulesPath = [[RuleEngine sharedInstance] rulesFilePath];
    NSData *jsonData = [NSData dataWithContentsOfFile:rulesPath];
    if (jsonData) {
        NSDictionary *root = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
        NSArray *blockedDomains = root[@"blockedDomains"];
        if ([blockedDomains isKindOfClass:[NSArray class]] && blockedDomains.count > 0) {
            [self loadDomainBlacklist:blockedDomains];
        }
    }
}

- (void)addDomainToBlacklist:(NSString *)domain {
    [_lock lock];
    [_blockedDomains addObject:[domain lowercaseString]];
    [_lock unlock];
}

- (void)removeDomainFromBlacklist:(NSString *)domain {
    [_lock lock];
    [_blockedDomains removeObject:[domain lowercaseString]];
    [_lock unlock];
}

- (BOOL)isDomainBlocked:(NSString *)host {
    if (!host || host.length == 0) return NO;
    
    [_lock lock];
    NSString *lower = [host lowercaseString];
    
    if ([_blockedDomains containsObject:lower]) {
        [_lock unlock];
        return YES;
    }
    
    for (NSString *wildcard in _blockedWildcardDomains) {
        if ([lower hasSuffix:wildcard] || [lower isEqualToString:[wildcard substringFromIndex:1]]) {
            [_lock unlock];
            return YES;
        }
    }
    
    [_lock unlock];
    return NO;
}

- (BOOL)isURLBlocked:(NSURL *)url {
    if (!url) return NO;
    return [self isDomainBlocked:url.host];
}

- (NSArray<NSString *> *)allBlockedDomains {
    [_lock lock];
    NSMutableArray *all = [NSMutableArray array];
    [all addObjectsFromArray:[_blockedDomains allObjects]];
    for (NSString *w in _blockedWildcardDomains) {
        [all addObject:[@"*" stringByAppendingString:w]];
    }
    [_lock unlock];
    return [all sortedArrayUsingSelector:@selector(compare:)];
}

- (NSUInteger)blockedRequestCount {
    return _dnsBlockedCount + _httpBlockedCount;
}

- (void)resetCounters {
    _dnsBlockedCount = 0;
    _httpBlockedCount = 0;
}

#pragma mark - DNS Hook (getaddrinfo)

static int hooked_getaddrinfo(const char *hostname, const char *servname,
                               const struct addrinfo *hints, struct addrinfo **res) {
    if (hostname && strlen(hostname) > 0) {
        NSString *hostStr = [NSString stringWithUTF8String:hostname];
        if ([[NetworkBlocker sharedInstance] isDomainBlocked:hostStr]) {
            NetworkBlocker *nb = [NetworkBlocker sharedInstance];
            nb->_dnsBlockedCount++;
            
            if (nb->_dnsBlockedCount % 50 == 1) {
                NSLog(@"%@ DNS拦截: %@ (累计: %lu)", kNBLogPrefix, hostStr, (unsigned long)nb->_dnsBlockedCount);
            }
            
            struct addrinfo *fakeResult = calloc(1, sizeof(struct addrinfo));
            if (fakeResult) {
                fakeResult->ai_family = AF_INET;
                fakeResult->ai_socktype = SOCK_STREAM;
                fakeResult->ai_addrlen = sizeof(struct sockaddr_in);
                fakeResult->ai_addr = calloc(1, sizeof(struct sockaddr_in));
                if (fakeResult->ai_addr) {
                    struct sockaddr_in *sin = (struct sockaddr_in *)fakeResult->ai_addr;
                    sin->sin_family = AF_INET;
                    inet_pton(AF_INET, "127.0.0.1", &sin->sin_addr);
                }
                *res = fakeResult;
            }
            return 0;
        }
    }
    
    if (_original_getaddrinfo) {
        return _original_getaddrinfo(hostname, servname, hints, res);
    }
    return EAI_FAIL;
}

static void install_getaddrinfo_hook(void) {
    uint32_t imageCount = _dyld_image_count();
    
    for (uint32_t i = 0; i < imageCount; i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (!imageName) continue;
        
        if (strstr(imageName, "libsystem_info") || strstr(imageName, "libc")) {
            const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
            if (!header) continue;
            
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            
            struct nb_rebinding rebindings[] = {
                {"getaddrinfo", hooked_getaddrinfo, (void **)&_original_getaddrinfo},
            };
            
            [NetworkBlocker rebindSymbols:rebindings count:1 imageHeader:header slide:slide];
            
            if (_original_getaddrinfo) {
                NSLog(@"%@ getaddrinfo DNS拦截已安装", kNBLogPrefix);
            }
            return;
        }
    }
    
    _original_getaddrinfo = dlsym(RTLD_DEFAULT, "getaddrinfo");
    if (_original_getaddrinfo) {
        NSLog(@"%@ getaddrinfo DNS拦截已安装 (dlsym方式)", kNBLogPrefix);
    }
}

- (void)installDNSHook {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        install_getaddrinfo_hook();
    });
}

#pragma mark - NSURLSession Hook

static id hooked_dataTaskWithRequest(id self, SEL _cmd, NSURLRequest *request, id completionHandler) {
    if (request.URL && [[NetworkBlocker sharedInstance] isURLBlocked:request.URL]) {
        NetworkBlocker *nb = [NetworkBlocker sharedInstance];
        nb->_httpBlockedCount++;
        NSLog(@"%@ HTTP拦截: %@ (累计: %lu)", kNBLogPrefix, request.URL.host, (unsigned long)nb->_httpBlockedCount);
        
        if ([self respondsToSelector:@selector(dataTaskWithURL:completionHandler:)]) {
            NSURL *fakeURL = [NSURL URLWithString:@"about:blank"];
            return [self dataTaskWithURL:fakeURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (completionHandler) {
                    ((void(^)(NSData *, NSURLResponse *, NSError *))completionHandler)(nil, nil, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
                }
            }];
        }
        return nil;
    }
    
    return ((id(*)(id, SEL, NSURLRequest *, id))objc_msgSend)(self, @selector(ads_nb_original_dataTaskWithRequest:completionHandler:), request, completionHandler);
}

- (void)installURLSessionHook {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [NSURLSession class];
    SEL origSel = @selector(dataTaskWithRequest:completionHandler:);
    SEL hookSel = @selector(ads_nb_original_dataTaskWithRequest:completionHandler:);
        
        Method origMethod = class_getInstanceMethod(cls, origSel);
        if (!origMethod) {
            NSLog(@"%@ NSURLSession hook失败: 找不到dataTaskWithRequest:", kNBLogPrefix);
            return;
        }
        
        IMP origImp = method_getImplementation(origMethod);
        const char *types = method_getTypeEncoding(origMethod);
        
        class_addMethod(cls, hookSel, origImp, types);
        
        IMP hookImp = imp_implementationWithBlock(^(id self, NSURLRequest *request, id completion) {
            if (request.URL && [[NetworkBlocker sharedInstance] isURLBlocked:request.URL]) {
                NetworkBlocker *nb = [NetworkBlocker sharedInstance];
                nb->_httpBlockedCount++;
                if (nb->_httpBlockedCount % 20 == 1) {
                    NSLog(@"%@ HTTP拦截: %@ (累计: %lu)", kNBLogPrefix, request.URL.host, (unsigned long)nb->_httpBlockedCount);
                }
                
                NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:@{
                    NSLocalizedDescriptionKey: @"广告请求已被拦截"
                }];
                if (completion) {
                    ((void(^)(NSData *, NSURLResponse *, NSError *))completion)(nil, nil, error);
                }
                return (id)nil;
            }
            
            IMP orig = class_getMethodImplementation(cls, hookSel);
            if (orig) {
                return ((id(*)(id, SEL, NSURLRequest *, id))orig)(self, hookSel, request, completion);
            }
            return (id)nil;
        });
        
        method_setImplementation(origMethod, hookImp);
        NSLog(@"%@ NSURLSession HTTP拦截已安装", kNBLogPrefix);
    });
}

#pragma mark - Fishhook-style symbol rebinding

+ (void)rebindSymbols:(struct nb_rebinding *)rebindings
                count:(size_t)count
          imageHeader:(const struct mach_header_64 *)header
                slide:(intptr_t)slide {
    if (!header || !rebindings || count == 0) return;
    
    struct segment_command_64 *linkEdit = NULL;
    struct symtab_command *symtabCmd = NULL;
    struct dysymtab_command *dysymtabCmd = NULL;
    
    uintptr_t cur = (uintptr_t)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cur;
        
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            if (strcmp(seg->segname, SEG_LINKEDIT) == 0) {
                linkEdit = seg;
            }
        } else if (lc->cmd == LC_SYMTAB) {
            symtabCmd = (struct symtab_command *)lc;
        } else if (lc->cmd == LC_DYSYMTAB) {
            dysymtabCmd = (struct dysymtab_command *)lc;
        }
        
        cur += lc->cmdsize;
    }
    
    if (!linkEdit || !symtabCmd || !dysymtabCmd) return;
    
    uintptr_t baseAddr = slide - linkEdit->vmaddr;
    char *strtab = (char *)(baseAddr + symtabCmd->stroff);
    struct nlist_64 *symtab = (struct nlist_64 *)(baseAddr + symtabCmd->symoff);
    
    cur = (uintptr_t)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cur;
        
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            
            uint32_t *indirectTable = (uint32_t *)(baseAddr + dysymtabCmd->indirectsymoff);
            
            struct section_64 *sect = (struct section_64 *)((uintptr_t)(seg + 1));
            for (uint32_t j = 0; j < seg->nsects; j++, sect++) {
                if ((strcmp(sect->sectname, "__la_symbol_ptr") != 0 &&
                     strcmp(sect->sectname, "__got") != 0) ||
                    strncmp(sect->segname, "__DATA", 6) != 0) {
                    continue;
                }
                
                uint32_t *entries = (uint32_t *)(baseAddr + sect->addr);
                for (uint32_t k = 0; k < sect->size / sizeof(void *); k++) {
                    uint32_t symIndex = indirectTable[sect->reserved1 + k];
                    if (symIndex >= symtabCmd->nsyms) continue;
                    
                    char *name = strtab + symtab[symIndex].n_un.n_strx;
                    
                    for (size_t r = 0; r < count; r++) {
                        if (strcmp(name, rebindings[r].name) == 0) {
                            void **ptr = (void **)&entries[k];
                            if (rebindings[r].replaced) {
                                *rebindings[r].replaced = *ptr;
                            }
                            
                            kern_return_t kr = vm_protect(mach_task_self(), (vm_address_t)ptr, sizeof(void *), FALSE, VM_PROT_READ | VM_PROT_WRITE);
                            if (kr == KERN_SUCCESS) {
                                *ptr = rebindings[r].replacement;
                                vm_protect(mach_task_self(), (vm_address_t)ptr, sizeof(void *), FALSE, VM_PROT_READ);
                            }
                            goto next_entry;
                        }
                    }
                next_entry:;
                }
            }
        }
        
        cur += lc->cmdsize;
    }
}

@end
