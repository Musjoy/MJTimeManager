//
//  MJTimeManager.m
//  Common
//
//  Created by 黄磊 on 15/6/27.
//  Copyright © 2015年 OkNanRen. All rights reserved.
//

#import "MJTimeManager.h"
#import HEADER_SERVER_URL
#ifdef MODULE_WEB_SERVICE
#import "MJWebService.h"
#endif

#define kLastServerDate @"lastServerDate"
#define kLastLocalDate @"lastLocalDate"
#define kOtherServerDates @"otherServerDates"

#define kDefaultLastSyncTime @"lasySyncTime"

static MJTimeManager *s_timeManager = nil;

@interface MJTimeManager ()

@property (nonatomic, strong) NSDate *lastServerDate;                           ///< 最后一次记录的服务器时间
@property (nonatomic, strong) NSDate *lastLocalDate;                            ///< 最后一次记录的服务器对应的本地时间
@property (nonatomic, assign) NSTimeInterval lastSystemUpTime;                  ///< 最后一次记录的系统运行时长

@property (nonatomic, strong) NSMutableDictionary *dicOtherServerDates;         ///< 其他服务器时间

@end


@implementation MJTimeManager

+ (MJTimeManager *)sharedInstance
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
        NSDictionary *dicTime = [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultLastSyncTime];
        if (dicTime) {
            NSDate *lastServerDate = [dicTime objectForKey:kLastServerDate];
            NSDate *lastLocalDate = [dicTime objectForKey:kLastLocalDate];
            if (lastLocalDate) {
                NSDate *curDate = [NSDate date];
                if ([lastLocalDate compare:curDate] == NSOrderedDescending) {
                    // 如果当前时间比上次保存的时间还小，使用修改的时间
                    lastLocalDate = curDate;
                }
                self.lastLocalDate = lastLocalDate;
                self.lastServerDate = lastServerDate;
                self.lastSystemUpTime = [[NSProcessInfo processInfo] systemUptime];
                
                NSDictionary *dicOtherServers = [dicTime objectForKey:kOtherServerDates];
                if (dicOtherServers) {
                    [self.dicOtherServerDates addEntriesFromDictionary:dicOtherServers];
                }
            }
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(systemClockChanged:) name:NSSystemClockDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStatusActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
#ifdef MODULE_WEB_SERVICE
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appStatusActive:) name:kNoticGetNetwork object:nil];
#endif
    }
    return self;
}

- (NSMutableDictionary *)dicOtherServerDates
{
    if (_dicOtherServerDates == nil) {
        _dicOtherServerDates = [[NSMutableDictionary alloc] init];
    }
    return _dicOtherServerDates;
}

#pragma mark - Notification Receive

// 用户时间修改通知NSSystemClockDidChangeNotification、UIApplicationSignificantTimeChangeNotification
- (void)systemClockChanged:(NSNotification *)aNotic
{
    if (_lastLocalDate == nil) {
        // 没有获取过服务器时间
        return;
    }
    //
    NSTimeInterval curSystemUpTime = [[NSProcessInfo processInfo] systemUptime];
    NSTimeInterval dTime = curSystemUpTime - _lastSystemUpTime;
    if (dTime < 0) {
        // 这种情况应该不会存在
        return;
    }
    
    // 更新对应本地时间
    NSDate *oldLocalTime = [_lastLocalDate dateByAddingTimeInterval:dTime];
    NSDate *curLocalTime = [NSDate date];
    
    NSTimeInterval dLocTime = [curLocalTime timeIntervalSince1970] - [oldLocalTime timeIntervalSince1970];
    _lastLocalDate = [_lastLocalDate dateByAddingTimeInterval:dLocTime];

}

- (void)appStatusActive:(NSNotification *)aNotic
{
    [self syncTime];
}

#pragma mark - Public

+ (NSDate *)curServerDate
{
    return [[self sharedInstance] curServerDate];
}

+ (NSDate *)curServerDateForServer:(NSString *)serverKey
{
    return [[self sharedInstance] curServerDateForServer:serverKey];
}

+ (void)updateServer:(NSString *)serverKey serverDate:(NSDate *)serverDate localDate:(NSDate *)localDate
{
    [[self sharedInstance] updateServer:serverKey serverDate:serverDate localDate:localDate];
}

#pragma mark - Private

- (NSDate *)curServerDate
{
    NSDate *curDate = [NSDate date];
    return [self serverDateForDate:curDate];
}

- (NSDate *)curServerDateForServer:(NSString *)serverKey
{
    if (serverKey == nil || _dicOtherServerDates == nil) {
        return [self curServerDate];
    }
    NSDate *curDate = [NSDate date];
    NSDate *theServerDate = [_dicOtherServerDates objectForKey:serverKey];
    if (theServerDate) {
        NSTimeInterval dTime = [self timeIntervalToDate:curDate];
        return [theServerDate dateByAddingTimeInterval:dTime];
    }
    return [self curServerDate];
}

- (void)updateServer:(NSString *)serverKey serverDate:(NSDate *)serverDate localDate:(NSDate *)localDate
{
    if (_lastLocalDate == nil) {
        return;
    }
    
    NSTimeInterval dTime = [_lastLocalDate timeIntervalSince1970] - [localDate timeIntervalSince1970];
    
    serverDate = [serverDate dateByAddingTimeInterval:dTime];
    
    [self.dicOtherServerDates setObject:serverDate forKey:serverKey];
    
    [self saveData];
}

- (void)updateServerDate:(NSDate *)serverDate atLocalDate:(NSDate *)localDate
{
    if (_dicOtherServerDates) {
        NSTimeInterval dTime = [serverDate timeIntervalSince1970] - [_lastServerDate timeIntervalSince1970];
        NSArray *allKey = [_dicOtherServerDates allKeys];
        for (NSString *aKey in allKey) {
            NSDate *aDate = _dicOtherServerDates[aKey];
            aDate = [aDate dateByAddingTimeInterval:dTime];
            [_dicOtherServerDates setObject:aDate forKey:aKey];
        }
    }
    _lastServerDate = serverDate;
    _lastLocalDate = localDate;
    [self saveData];
}

#pragma mark -

- (NSDate *)serverDateForDate:(NSDate *)locTime
{
    if (_lastLocalDate == nil) {
        return locTime;
    }
    
    NSTimeInterval dTime = [self timeIntervalToDate:locTime];
    
    NSDate *aServerDate = [_lastServerDate dateByAddingTimeInterval:dTime];
    
    return aServerDate;
}

- (NSTimeInterval)timeIntervalToDate:(NSDate *)aDate
{
    NSTimeInterval dTime = [aDate timeIntervalSince1970] - [_lastLocalDate timeIntervalSince1970];
    
    if (dTime < 0) {
        dTime = 0;
    }
    
    return dTime;
}

- (void)saveData
{
    if (_lastLocalDate == nil || _lastServerDate == nil) {
        return;
    }
    NSDictionary *aDic = [NSDictionary dictionaryWithObjectsAndKeys:
                          _lastServerDate, kLastServerDate,
                          _lastLocalDate, kLastLocalDate,
                          _dicOtherServerDates, kOtherServerDates, nil];
    [[NSUserDefaults standardUserDefaults] setObject:aDic forKey:kDefaultLastSyncTime];
}

#pragma mark -

- (void)syncTime
{
    static BOOL isRequst = NO;
    if (isRequst) {
        return;
    }
    isRequst = YES;
    NSDate *dateBefore = [NSDate date];
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:kServerSyncTimeUrl]]
                                       queue:queue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               dispatch_async(dispatch_get_main_queue(), ^{
                                   NSDictionary *allHeaderFields = [response valueForKey:@"allHeaderFields"];
                                   NSString *serverDateStr = allHeaderFields[@"Date"];
                                   NSDate *serverDate = [NSDate dateFromRFC822String:serverDateStr];
                                   NSLog(@"%@", serverDate);
                                   if (serverDate) {
                                       NSDate *dateAfter = [NSDate date];
                                       NSDate *localDate = [dateBefore dateByAddingTimeInterval:[dateAfter timeIntervalSinceDate:dateBefore] / 2];
                                       
                                       [self updateServerDate:serverDate atLocalDate:localDate];
                                       
                                       [[NSNotificationCenter defaultCenter] postNotificationName:kNoticTimeSyncSucceed object:nil];
                                   }
                                   isRequst = NO;
                               });
                           }];
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
            if (!date) { // 2017-02-08 03:51:56 ETC/GMT+0800
                [dateFormatter setDateFormat:@"yyyy'-'MM'-'dd' 'HH':'mm':'ss' ETC/GMT'ZZZ"];
                date = [dateFormatter dateFromString:RFC3339String];
            }
            if (!date) { // 2017-02-08 03:51:56 ETC/GMT
                [dateFormatter setDateFormat:@"yyyy'-'MM'-'dd' 'HH':'mm':'ss' ETC/GMT'"];
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
