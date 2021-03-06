//
//  NSString+OBPKit.m
//  OBPKit
//
//  Created by Torsten Louland on 25/01/2016.
//  Copyright (c) 2016-2017 TESOBE Ltd. All rights reserved.
//

#import "NSString+OBPKit.h"
// sdk
// prj
#import "OBPLogging.h"



@implementation NSString (OBPKit)
- (NSString*)stringByAddingPercentEncodingForAllRFC3986ReservedCharachters
{
	static NSCharacterSet* sAllowedSet = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sAllowedSet = [NSCharacterSet characterSetWithCharactersInString:
			@"-._~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
			// ...the Unreserved Characters in RFC 3986, Section 2.3. (Unfortunately the NSURLUtilities category on NSCharacterSet provides allowed sets for Host, User, Password, Path, Query and Fragment, but not the Unreserved set.)
	});
	return [self stringByAddingPercentEncodingWithAllowedCharacters: sAllowedSet];
}
- (NSString*)stringByAppendingURLQueryParams:(NSDictionary*)dictionary
{
    NSMutableString*	str = [self mutableCopy];
	const char*			sep = [str rangeOfString:@"?"].length ? "&" : "?";
    
    for (id key in dictionary)
	{
        NSString *keyString = [key description];
        NSString *valString = [dictionary[key] description];
		keyString = [keyString stringByAddingPercentEncodingForAllRFC3986ReservedCharachters];
		valString = [valString stringByAddingPercentEncodingForAllRFC3986ReservedCharachters];
		[str appendFormat: @"%s%@=%@", sep, keyString, valString];
		sep = "&";
    }

    return [str copy];
}

-(NSDictionary *)extractURLQueryParams
{
    NSMutableDictionary	*params = [NSMutableDictionary dictionary];
    NSArray				*pairs, *elements;
	NSString			*pair, *key, *val;

	pairs = [self componentsSeparatedByString: @"&"];

    for (pair in pairs)
	{
        elements = [pair componentsSeparatedByString: @"="];
		OBP_LOG_IF(2 != [elements count], @"-extractQueryParams\nNot an element pair: %@\nQuery string: %@", pair, self);
		if ([elements count] != 2)
			continue;
		key = elements[0];
		val = elements[1];
        key = [key stringByRemovingPercentEncoding];
        val = [val stringByRemovingPercentEncoding];
        
        params[key] = val;
    }

    return [params copy];
}

- (NSString*)stringForURLByAppendingPath:(NSString*)path
{
	if (path == nil)
		return self;
	BOOL	trailing = 0 != [self rangeOfString: @"/" options: NSAnchoredSearch+NSBackwardsSearch].length;
	BOOL	leading = 0 != [path rangeOfString: @"/" options: NSAnchoredSearch].length;
	if (trailing && leading) // too many
		path = [path substringFromIndex: 1], leading = NO;
	else
	if (!trailing && !leading) // too few
		path = [@"/" stringByAppendingString: path], leading = YES;
	path = [self stringByAppendingString: path];
	return path;
}
@end
