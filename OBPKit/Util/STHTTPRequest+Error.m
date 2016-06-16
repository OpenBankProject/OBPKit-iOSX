//
//  STHTTPRequest+Error.m
//  OBPKit
//
//  Created by Torsten Louland on 16/06/2016.
//  Copyright © 2016 TESOBE Ltd. All rights reserved.
//

#import "STHTTPRequest+Error.h"



@implementation STHTTPRequest (Error)
- (NSError*)errorByAddingServerSideDescriptionToError:(NSError*)inError
{
	NSInteger		status = inError.code;

	if (status < 400
	 || status > 600
	 || status != self.responseStatus
	 || ![inError.domain isEqualToString: NSStringFromClass([self class])])
		return inError;

	NSData*			data = self.responseData;

	if (!data || ![data length])
		return inError;

	NSDictionary*	headers = self.responseHeaders;
	NSError*		error = nil;
	NSString*		errorDescription = inError.localizedDescription;
	NSString*		serverSideDescription = nil;
	NSDictionary*	userInfo = inError.userInfo;
	NSString*		s;
	NSRange			r;

	// If possible, expose the server's own description of the error...
	if ([(s = headers[@"Content-Type"]) hasPrefix: @"application/json"])
	{
		id container = [NSJSONSerialization JSONObjectWithData: data options: 0 error: &error];
		id serverSideInfo;
		if (container && [container isKindOfClass:[NSDictionary class]])
		if (nil != (serverSideInfo = ((NSDictionary *)container)[@"error"]))
			serverSideDescription = [serverSideInfo description];
	}
	else
	if ([(s = headers[@"Content-Type"]) hasPrefix: @"text/html"])
	{
		// See if the body contains a simple error message that we can extract. Anything more complicated falls back to including the whole body below.
		s = [[NSString alloc] initWithData:data encoding: NSUTF8StringEncoding];
		r = [s rangeOfString: @"<(body|BODY)>[^<]+</(body|BODY)>" options: NSRegularExpressionSearch];
		if (r.length)
			r.length -= 13, r.location += 6;
		if (r.length)
			serverSideDescription = [s substringWithRange: r];
	}

	// When there was possibly server-side error information and it is in a form we don't cater for, optionally include header and data for debugging
	NSMutableDictionary*	md = [(userInfo?:@{}) mutableCopy];
	if (serverSideDescription)
	{
		// Don't add a second time (if STHTTPRequest is now handling this (pending))
		if (0 == [errorDescription rangeOfString: serverSideDescription].length)
			errorDescription = [errorDescription stringByAppendingFormat:@" (%@)", serverSideDescription];
	}
	else
	{
		md[@"headers"] = headers ?: @{};
		md[@"data"] = data ? [[NSString alloc] initWithData:data encoding: NSUTF8StringEncoding] : @"";
	}
	if (errorDescription)
		md[NSLocalizedDescriptionKey] = errorDescription;
	userInfo = [md copy];

    error = [NSError errorWithDomain: inError.domain code: inError.code userInfo: userInfo];

	return error;
}
@end
