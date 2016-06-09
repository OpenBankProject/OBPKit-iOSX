//
//  OBPDateFormatter.m
//  OBPKit
//
//  Created by Torsten Louland on 26/05/2016.
//  Copyright © 2016 TESOBE Ltd. All rights reserved.
//

#import "OBPDateFormatter.h"
#import "OBPLogging.h"



@implementation OBPDateFormatter
static OBPDateFormatter* sInstA = nil;
static OBPDateFormatter* sInstB = nil;
+ (void)initialize
{
	if (self != [OBPDateFormatter class])
		return;
	sInstA = [[self alloc] initWithSubseconds: NO];
	sInstB = [[self alloc] initWithSubseconds: YES];
}
+ (NSString*)stringFromDate:(NSDate*)date
{
	return [sInstA stringFromDate: date];
}
+ (NSDate*)dateFromString:(NSString*)string
{
	NSDate* date = [sInstA dateFromString: string] ?: [sInstB dateFromString: string];
	OBP_LOG_IF([string length] && !date, @"[%@ dateFromString: %@] • string format not recognised •", self, string);
	return date;
}
- (instancetype)initWithSubseconds:(BOOL)subsecs
{
	if (nil != (self = [super init]))
	{
		self.timeZone = [NSTimeZone timeZoneForSecondsFromGMT: 0];
		self.dateFormat = subsecs ? @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" : @"yyyy-MM-dd'T'HH:mm:ss'Z'";
	}
	return self;
}
@end
