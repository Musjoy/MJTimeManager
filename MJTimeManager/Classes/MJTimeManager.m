//
//  MJTimeManager.m
//  Common
//
//  Created by 黄磊 on 15/6/27.
//  Copyright © 2015年 OkNanRen. All rights reserved.
//

#import "MJTimeManager.h"

#ifdef __has_include(<AFHTTPSessionManager.h>)
#define MODULE_AFHTTPSessionManager
#import <AFHTTPSessionManager.h>
#endif

#ifdef MODULE_WEB_SERVICE
#import "MJWebService.h"
#endif

#define kLastServerTime @"lastServerTime"
#define kLastLocalTime @"lastLocalTime"

#define kLastSyncTime @"lasySyncTime"

static MJTimeManager *s_timeManager = nil;

@interface MJTimeManager ()

@property (nonatomic, strong) NSDate *lastServerTime;
@property (nonatomic, strong) NSDate *lastLocalTime;

@end


@implementation MJTimeManager

+ (MJTimeManager *)shareInstance
{
    static dispatch_once_t once_patch;
    dispatch_once(&once_patch, ^() {
        s_timeManager = [[self alloc] init];
    });
    
    return s_timeManager;
}

- (id)init
{
    self = [super init];
    if (self) {
        
        // 读取保存在userDefault里面的数据
        NSDictionary *dicTime = [[NSUserDefaults standardUserDefaults] objectForKey:kLastSyncTime];
        if (dicTime) {
            NSDate *lastServerTime = [dicTime objectForKey:kLastServerTime];
            NSDate *lastLocalTime = [dicTime objectForKey:kLastLocalTime];
            if (lastLocalTime) {
                self.lastServerTime = lastServerTime;
                self.lastLocalTime = lastLocalTime;
            }
        }
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStatusActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
#ifdef MODULE_WEB_SERVICE
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStatusActive:) name:kNoticGetNetwork object:nil];
#endif
    }
    return self;
}

#pragma mark - Notification Receive

- (void)appStatusActive:(NSNotification *)aNotic {
    
    [self syncTime];
}

#pragma mark - Public

+ (NSDate *)curServerTime
{
    return [[self shareInstance] curServerTime];
}

#pragma mark - Private

- (NSDate *)curServerTime
{
    NSDate *curDate = [NSDate date];
    if (_lastLocalTime == nil) {
        return curDate;
    }
    NSTimeInterval dTime = [curDate timeIntervalSince1970] - [_lastLocalTime timeIntervalSince1970];
    
    if (dTime < 0) {
        dTime = 0;
    }
    
    NSDate *curServerDate = [_lastServerTime dateByAddingTimeInterval:dTime];
    
    return curServerDate;
}

- (void)saveData
{
    NSDictionary *aDic = @{kLastServerTime:_lastServerTime,
                           kLastLocalTime:_lastLocalTime};
    [[NSUserDefaults standardUserDefaults] setObject:aDic forKey:kLastSyncTime];
}

#pragma mark -

- (void)syncTime {
    
#ifdef MODULE_AFHTTPSessionManager
    NSDate *dateBefore = [NSDate date];
    // 获取网络请求的时间
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    
    manager.requestSerializer = [AFHTTPRequestSerializer serializer];
    manager.responseSerializer = [AFJSONResponseSerializer serializer];
    [manager.requestSerializer setTimeoutInterval:0];
    [manager GET:[kServerUrl stringByAppendingString:@"/time.json"] parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        // 请求成功
        LogDebug(@"...>>>...receiveData = %@", responseObject);
        NSDictionary *allHeaderFields = [task.response valueForKey:@"allHeaderFields"];
        if (allHeaderFields) {
            NSString *serverTimeStr = allHeaderFields[@"Date"];
            NSDate *serverTime = [NSDate dateFromRFC822String:serverTimeStr];
            if (serverTime) {
                NSDate *dateAfter = [NSDate date];
                NSDate *localTime = [dateBefore dateByAddingTimeInterval:[dateAfter timeIntervalSinceDate:dateBefore] / 2];
                _lastServerTime = serverTime;
                _lastLocalTime = localTime;
                [self saveData];
                
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTICE_TIME_SYNC_SUCCEED object:nil];
            }
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        // 请求失败
        LogError(@"...>>>...Network error: %@\n", error);
        NSDictionary *allHeaderFields = [task.response valueForKey:@"allHeaderFields"];
        if (allHeaderFields) {
            NSString *serverTimeStr = allHeaderFields[@"Date"];
            NSDate *serverTime = [NSDate dateFromRFC822String:serverTimeStr];
            if (serverTime) {
                NSDate *dateAfter = [NSDate date];
                NSDate *localTime = [dateBefore dateByAddingTimeInterval:[dateAfter timeIntervalSinceDate:dateBefore] / 2];
                _lastServerTime = serverTime;
                _lastLocalTime = localTime;
                [self saveData];
                
                [[NSNotificationCenter defaultCenter] postNotificationName:NOTICE_TIME_SYNC_SUCCEED object:nil];
            }
        } else {
            // 没有网络，更新时间失败
        }
    }];
#endif
}

@end


// Always keep the formatter around as they're expensive to instantiate
static NSDateFormatter *_internetDateTimeFormatter = nil;

// Good info on internet dates here:
// http://developer.apple.com/iphone/library/qa/qa2010/qa1480.html
@implementation NSDate (InternetDateTime)

// Instantiate single date formatter
+ (NSDateFormatter *)internetDateTimeFormatter {
    
    @synchronized(self) {
        if (!_internetDateTimeFormatter) {
            NSLocale *en_US_POSIX = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
            _internetDateTimeFormatter = [[NSDateFormatter alloc] init];
            [_internetDateTimeFormatter setLocale:en_US_POSIX];
            [_internetDateTimeFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
        }
    }
    return _internetDateTimeFormatter;
}

// See http://www.faqs.org/rfcs/rfc822.html
+ (NSDate *)dateFromRFC822String:(NSString *)dateString {
    
    // Keep dateString around a while (for thread-safety)
    NSDate *date = nil;
    if (dateString) {
        NSDateFormatter *dateFormatter = [NSDate internetDateTimeFormatter];
        @synchronized(dateFormatter) {
            // Process
            NSString *RFC822String = [[NSString stringWithString:dateString] uppercaseString];
            if ([RFC822String rangeOfString:@","].location != NSNotFound) {
                if (!date) { // Sun, 19 May 2002 15:21:36 GMT
                    [dateFormatter setDateFormat:@"EEE, d MMM yyyy HH:mm:ss zzz"];
                    date = [dateFormatter dateFromString:RFC822String];
                }
                if (!date) { // Sun, 19 May 2002 15:21 GMT
                    [dateFormatter setDateFormat:@"EEE, d MMM yyyy HH:mm zzz"];
                    date = [dateFormatter dateFromString:RFC822String];
                }
                if (!date) { // Sun, 19 May 2002 15:21:36
                    [dateFormatter setDateFormat:@"EEE, d MMM yyyy HH:mm:ss"];
                    date = [dateFormatter dateFromString:RFC822String];
                }
                if (!date) { // Sun, 19 May 2002 15:21
                    [dateFormatter setDateFormat:@"EEE, d MMM yyyy HH:mm"];
                    date = [dateFormatter dateFromString:RFC822String];
                }
            } else {
                if (!date) { // 19 May 2002 15:21:36 GMT
                    [dateFormatter setDateFormat:@"d MMM yyyy HH:mm:ss zzz"];
                    date = [dateFormatter dateFromString:RFC822String];
                }
                if (!date) { // 19 May 2002 15:21 GMT
                    [dateFormatter setDateFormat:@"d MMM yyyy HH:mm zzz"];
                    date = [dateFormatter dateFromString:RFC822String];
                }
                if (!date) { // 19 May 2002 15:21:36
                    [dateFormatter setDateFormat:@"d MMM yyyy HH:mm:ss"];
                    date = [dateFormatter dateFromString:RFC822String];
                }
                if (!date) { // 19 May 2002 15:21
                    [dateFormatter setDateFormat:@"d MMM yyyy HH:mm"];
                    date = [dateFormatter dateFromString:RFC822String];
                }
            }
            if (!date){
                NSLog(@"Could not parse RFC822 date: \"%@\" Possible invalid format.", dateString);
            }
        }
    }
    // Finished with date string
    return date;
}

// See http://www.faqs.org/rfcs/rfc3339.html
+ (NSDate *)dateFromRFC3339String:(NSString *)dateString {
    
    // Keep dateString around a while (for thread-safety)
    NSDate *date = nil;
    if (dateString) {
        NSDateFormatter *dateFormatter = [NSDate internetDateTimeFormatter];
        @synchronized(dateFormatter) {
            // Process date
            NSString *RFC3339String = [[NSString stringWithString:dateString] uppercaseString];
            RFC3339String = [RFC3339String stringByReplacingOccurrencesOfString:@"Z" withString:@"-0000"];
            // Remove colon in timezone as it breaks NSDateFormatter in iOS 4+.
            // - see https://devforums.apple.com/thread/45837
            if (RFC3339String.length > 20) {
                RFC3339String = [RFC3339String stringByReplacingOccurrencesOfString:@":"
                                                                         withString:@""
                                                                            options:0
                                                                              range:NSMakeRange(20, RFC3339String.length-20)];
            }
            if (!date) { // 1996-12-19T16:39:57-0800
                [dateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ssZZZ"];
                date = [dateFormatter dateFromString:RFC3339String];
            }
            if (!date) { // 1937-01-01T12:00:27.87+0020
                [dateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss.SSSZZZ"];
                date = [dateFormatter dateFromString:RFC3339String];
            }
            if (!date) { // 1937-01-01T12:00:27
                [dateFormatter setDateFormat:@"yyyy'-'MM'-'dd'T'HH':'mm':'ss"];
                date = [dateFormatter dateFromString:RFC3339String];
            }
            if (!date) { // 2017-02-08 03:51:56 Etc/GMT+0800
                [dateFormatter setDateFormat:@"yyyy'-'MM'-'dd' 'HH':'mm':'ss' Etc/GMT'ZZZ"];
                date = [dateFormatter dateFromString:RFC3339String];
            }
            if (!date) { // 2017-02-08 03:51:56 Etc/GMT
                [dateFormatter setDateFormat:@"yyyy'-'MM'-'dd' 'HH':'mm':'ss' Etc/GMT'"];
                date = [dateFormatter dateFromString:RFC3339String];
            }
            if (!date) {
                NSLog(@"Could not parse RFC3339 date: \"%@\" Possible invalid format.", dateString);
            }
        }
    }
    // Finished with date string
    return date;
}

@end
