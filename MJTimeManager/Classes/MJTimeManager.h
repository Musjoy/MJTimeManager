//
//  MJTimeManager.h
//  Common
//
//  Created by 黄磊 on 15/6/27.
//  Copyright © 2015年 OkNanRen. All rights reserved.
//

#import <Foundation/Foundation.h>

/** 时间同步成功通知 */
static NSString *const NOTICE_TIME_SYNC_SUCCEED     = @"NoticeTimeSyncSucceed";


@interface MJTimeManager : NSObject

+ (MJTimeManager *)shareInstance;

/** 当前服务器时间 */
+ (NSDate *)curServerTime;


/** 时间同步 type:同步类型<1-启动同步 2-进入同步 3-开网同步> */
- (void)syncTimeWithType:(int)type;

// 以下用于时间增量更新
- (NSDate *)lastFetchTimeOf:(NSString *)action withUserId:(NSNumber *)userId identifier:(NSString *)identifier;

- (void)setLastFetchTime:(NSDate *)lastFetchTime action:(NSString *)action userId:(NSNumber *)userId identifier:(NSString *)identifier;

// 以下用户ID增量更新
- (NSNumber *)lastFetchIdOf:(NSString *)action withUserId:(NSNumber *)userId identifier:(NSString *)identifier;

- (void)setLastFetchId:(NSNumber *)lastFetchId action:(NSString *)action userId:(NSNumber *)userId identifier:(NSString *)identifier;

@end


// A category to parse internet date & time strings
@interface NSDate (InternetDateTime)


+ (NSDate *)dateFromRFC3339String:(NSString *)dateString;
+ (NSDate *)dateFromRFC822String:(NSString *)dateString;

@end
