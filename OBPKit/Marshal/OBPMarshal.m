//
//  OBPMarshal.m
//  OBPKit
//
//  Created by Torsten Louland on 18/02/2016.
//  Copyright © 2016 TESOBE Ltd. All rights reserved.
//

#import "OBPMarshal.h"
// sdk
// ext
#import <STHTTPRequest/STHTTPRequest.h>
// prj
#import "OBPServerInfo.h"
#import "OBPSession.h"
#import "NSString+OBPKit.h"
#import "OBPLogging.h"



@implementation OBPMarshal
- (instancetype)initWithSessionAuth:(OBPSession*)session
{
	if (!session)
		{self = nil; return nil;}
	if (nil == (self = [super init]))
		return nil;
	_session = session;
	[self setDefaultErrorHandler];
	return self;
}
- (void)setDefaultErrorHandler
{
	NSString* APIBase = _session.serverInfo.APIBase;
	_errorHandler =
		^(NSError* error, NSString* path)
		{
			OBP_LOG(@"Request for resource at path %@ served by %@ got error %@", path, APIBase, error);
		};
}
- (BOOL)getResourceAtAPIPath:(NSString*)path withOptions:(NSDictionary*)options forHandler:(HandleOBPMarshalData)resultHandler
{
	NSString*				requestPath;
	STHTTPRequest*			request;
	STHTTPRequest __weak*	request_ifStillAround;
	OBPSession*				session = _session;
	HandleOBPMarshalError	errorHandler = options[@"errorHandler"];
	HandleOBPMarshalError	eh = errorHandler ?: _errorHandler;
	Class					xc = Nil;
	BOOL					deserializeJSON = YES;
	NSInteger				statusAcceptable = 200;

	if (!session.valid || ![path length] || !resultHandler || !eh)
		return NO;

	if (options)
	{
		xc = options[OBPMarshalOptionExpectClass];
		id obj = options[OBPMarshalOptionDeserializeJSON];
		if ([obj respondsToSelector: @selector(boolValue)])
			deserializeJSON = [obj boolValue];
		obj = options[OBPMarshalOptionExpectStatus];
		if ([obj respondsToSelector: @selector(integerValue)])
			statusAcceptable = [obj integerValue];
	}

	requestPath = [session.serverInfo.APIBase stringForURLByAppendingPath: path];
	request = [STHTTPRequest requestWithURLString: requestPath];
	request.HTTPMethod = @"GET";
	request_ifStillAround = request;
    request.completionBlock = ^(NSDictionary *headers, NSString *body) {
		STHTTPRequest *request = request_ifStillAround;
		NSInteger status = request.responseStatus;
		NSError* error = nil;
		BOOL handled = NO;
        if (status == statusAcceptable)
		{
            id container = nil;
			if (deserializeJSON)
			{
				container = [NSJSONSerialization JSONObjectWithData: [body dataUsingEncoding: NSUTF8StringEncoding] options: 0 error: &error];
				OBP_LOG_IF(error, @"[NSJSONSerialization JSONObjectWithData: data options: 0 error:] gave error:\nerror = %@\ndata = %@", error, body);
				OBP_LOG_IF(!error && xc && ![container isKindOfClass: xc], @"Expected to resource at path %@ to yield a %@, but got instead got:\n%@\nfrom body: %@", path, NSStringFromClass(xc), container, body);
				if (!error && xc && ![container isKindOfClass: xc])
					error = [NSError errorWithDomain: OBPMarshalErrorDomain code: OBPMarshalErrorUnexpectedResourceKind userInfo:@{NSLocalizedDescriptionKey:@"Unexpected response data type.",@"body":body?:@""}];
			}
			if (!error)
				resultHandler(container, body), handled = YES;
		}
		else
		{
			OBP_LOG(@"Unexpected response (%@); body = %@", @(status), body);
			error = [NSError errorWithDomain: OBPMarshalErrorDomain code: OBPMarshalErrorUnexpectedResult userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat: @"Unexpected response status (%@).", @(status)],@"body":body?:@""}];
		}
		if (!handled)
			eh(error, path);
	};
    
	request.errorBlock = ^(NSError *error) {
        eh(error, path);
    };

	if ([session authorizeSTHTTPRequest: request])
	{
		[request startAsynchronous];
		return YES;
	}

	return NO;
}
@end
