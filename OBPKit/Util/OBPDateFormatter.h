//
//  OBPDateFormatter.h
//  OBPKit
//
//  Created by Torsten Louland on 26/05/2016.
//  Copyright © 2016 TESOBE Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>



/// OBPDateFormatter deals only with the date formats used by the OBP API, which are a subset of the ISO 8601 format possibilities.
@interface OBPDateFormatter : NSDateFormatter
+ (NSString*)stringFromDate:(NSDate*)date;
+ (NSDate*)dateFromString:(NSString*)string;
@end
