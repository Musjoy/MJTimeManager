//
//  MJTimeManager.h
//  Common
//
//  Created by 黄磊 on 15/6/27.
//  Copyright © 2015年 OkNanRen. All rights reserved.
//

#import <Foundation/Foundation.h>

/** 时间同步成功通知 */
static NSString *const kNoticTimeSyncSucced     = @"NoticeTimeSyncSucceed";


@interface MJTimeManager : NSObject

+ (MJTimeManager *)shareInstance;

/// 当前服务器时间
+ (NSDate *)curServerDate;

/// 获取对应服务器的当前时间，如果不存在直接取curServerDate
+ (NSDate *)curServerDateForServer:(NSString *)serverKey;

/// 更新对应服务器当前时间
+ (void)updateServer:(NSString *)serverKey serverDate:(NSDate *)serverDate localDate:(NSDate *)localDate;

/// 同步时间
- (void)syncTime;

@end


// A category to parse internet date & time strings
@interface NSDate (InternetDateTime)

+ (NSDate *)dateFromRFC3339String:(NSString *)dateString;
+ (NSDate *)dateFromRFC822String:(NSString *)dateString;

@end
