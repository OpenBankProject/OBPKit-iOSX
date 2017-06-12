//
//  OBPMarshal.m
//  OBPKit
//
//  Created by Torsten Louland on 18/02/2016.
//  Copyright (c) 2016-2017 TESOBE Ltd. All rights reserved.
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
#import "OBPDateFormatter.h"



typedef NS_ENUM(uint8_t, OBPMarshalVerb)
{
	eOBPMarshalVerb_GET,
	eOBPMarshalVerb_PUT,
	eOBPMarshalVerb_POST,
	eOBPMarshalVerb_DELETE,

	eOBPMarshalVerb_count
};



NSString* NSStringDescribingNSURLRequest(NSURLRequest* request);
NSString* NSStringDescribingNSURLResponseAndData(NSHTTPURLResponse* response, NSData* data);



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
	__weak __typeof(self) self_ifStillAlive = self;
	_errorHandler =
		^(NSError* error, NSString* path)
		{
			OBP_LOG(@"Request for resource at path %@ served by %@ got error %@", path, self_ifStillAlive.session.serverInfo.APIBase, error);
		};
}
- (BOOL)getResourceAtAPIPath:(NSString*)p withOptions:(NSDictionary*)o forResultHandler:(HandleOBPMarshalData)rh orErrorHandler:(HandleOBPMarshalError)eh
{
	if (eh == nil && o)
		eh = o[@"errorHandler"];
	return [self sendRequestVerb: eOBPMarshalVerb_GET withPayload: nil toAPIPath: p withOptions: o forResultHandler: rh orErrorHandler: eh];
}
- (BOOL)updateResource:(id)r atAPIPath:(NSString*)p withOptions:(NSDictionary*)o forResultHandler:(HandleOBPMarshalData)rh orErrorHandler:(HandleOBPMarshalError)eh
{
	if (eh == nil && o)
		eh = o[@"errorHandler"];
	return [self sendRequestVerb: eOBPMarshalVerb_PUT withPayload: r toAPIPath: p withOptions: o forResultHandler: rh orErrorHandler: eh];
}
- (BOOL)createResource:(id)r atAPIPath:(NSString*)p withOptions:(NSDictionary*)o forResultHandler:(HandleOBPMarshalData)rh orErrorHandler:(HandleOBPMarshalError)eh
{
	if (eh == nil && o)
		eh = o[@"errorHandler"];
	return [self sendRequestVerb: eOBPMarshalVerb_POST withPayload: r toAPIPath: p withOptions: o forResultHandler: rh orErrorHandler: eh];
}
- (BOOL)deleteResourceAtAPIPath:(NSString*)p withOptions:(NSDictionary*)o forResultHandler:(HandleOBPMarshalData)rh orErrorHandler:(HandleOBPMarshalError)eh
{
	if (eh == nil && o)
		eh = o[@"errorHandler"];
	return [self sendRequestVerb: eOBPMarshalVerb_DELETE withPayload: nil toAPIPath: p withOptions: o forResultHandler: rh orErrorHandler: eh];
}
- (BOOL)sendRequestVerb:(OBPMarshalVerb)verb
			withPayload:(id)payload
			  toAPIPath:(NSString*)path
			withOptions:(NSDictionary*)options
	   forResultHandler:(HandleOBPMarshalData)resultHandler
		 orErrorHandler:(HandleOBPMarshalError)errorHandler
{
	OBPSession*				session = _session;
	HandleOBPMarshalError	eh = errorHandler ?: _errorHandler;

	if ((!session.valid && ![options[OBPMarshalOptionOnlyPublicResources] isEqual: @YES])
	 || ![path length] || !resultHandler || !eh)
		return NO;

	NSString*				requestPath;
	STHTTPRequest*			request;
	STHTTPRequest __weak*	request_ifStillAround;
	NSString*				method;
	Class					expectedDeserializedObjectClass = [NSDictionary class];
	id						obj;
	BOOL					onlyPublicResources = NO;
	BOOL					sendDictAsForm = NO;
	BOOL					serializeToJSON = YES;
	BOOL					deserializeJSON = YES;
	BOOL					verbose = [[NSUserDefaults standardUserDefaults] boolForKey: @"OBPMarshalVerbose"];
	NSArray*				acceptableStatusCodes;
	NSDictionary*			dict;
	NSString*				key;
	NSData*					data;
	NSError*				error;
	NSMutableDictionary*	moreHeaders = [NSMutableDictionary dictionary];

	// Method
	switch (verb)
	{
		case eOBPMarshalVerb_GET:
			method = @"GET";
			acceptableStatusCodes = @[@200];
			break;
		case eOBPMarshalVerb_PUT:
			method = @"PUT";
			acceptableStatusCodes = @[@200];
			break;
		case eOBPMarshalVerb_POST:
			method = @"POST";
			acceptableStatusCodes = @[@201];
			break;
		case eOBPMarshalVerb_DELETE:
			method = @"DELETE";
			acceptableStatusCodes = @[@204];
			break;
		default:
			return NO;
	}

	// Options
	if (options)
	{
		// Expected class of object after deserialisation
		obj = options[OBPMarshalOptionExpectClass];
		if (obj)
		if ([obj isEqual: [NSNull null]] || obj == [NSNull class])
			expectedDeserializedObjectClass = nil;
		else
			expectedDeserializedObjectClass = obj;

		// Make public calls? (suppress authorisation)
		obj = options[OBPMarshalOptionOnlyPublicResources];
		if ([obj respondsToSelector: @selector(boolValue)])
			onlyPublicResources = [obj boolValue];

		// Send payload as form?
		obj = options[OBPMarshalOptionSendDictAsForm];
		if ([obj respondsToSelector: @selector(boolValue)])
			serializeToJSON = !(sendDictAsForm = [obj boolValue]);

		// Expect reply body is JSON and deserialize?
		obj = options[OBPMarshalOptionDeserializeJSON];
		if ([obj respondsToSelector: @selector(boolValue)])
			deserializeJSON = [obj boolValue];

		// Expect non-default reply status code(s)?
		obj = options[OBPMarshalOptionExpectStatus];
		if ([obj respondsToSelector: @selector(integerValue)])
			acceptableStatusCodes = @[obj];
		else
		if ([obj isKindOfClass: [NSArray class]])
			acceptableStatusCodes = obj;

		// Add extra headers?
		dict = obj = options[OBPMarshalOptionExtraHeaders];
		if ([obj isKindOfClass: [NSDictionary class]])
		for (key in dict)
		{
			obj = dict[key];
			if ([obj isKindOfClass: [NSDate class]])
				moreHeaders[key] = [OBPDateFormatter stringFromDate: obj];
			else
				moreHeaders[key] = [obj description];
		}
	}

	// Make the request and add its payload
	requestPath = [session.serverInfo.APIBase stringForURLByAppendingPath: path];
	request = [STHTTPRequest requestWithURLString: requestPath];
	request.HTTPMethod = method;

	if (payload)
	{
		if ([payload isKindOfClass: [NSData class]])
			request.rawPOSTData = data = payload;
		else
		if (sendDictAsForm)
		{
			if ([payload isKindOfClass: [NSDictionary class]])
				request.POSTDictionary = payload;
			else
				OBP_LOG(@"••• Payload needs to be a dictionary to send as a form; ignored: %@", payload);
		}
		else
		if (serializeToJSON)
		{
			data = [NSJSONSerialization dataWithJSONObject: payload options: 0 error: &error];
			OBP_LOG_IF(error || !data, @"Payload JSON serialize failed with error %@\n for data %@", error, payload);
			if (data)
			{
				request.rawPOSTData = data;
				moreHeaders[@"Content-Type"] = @"application/json";
			}
		}
		else
			OBP_LOG(@"••• Payload ignored: %@", payload);
	}

	if ([moreHeaders count])
		[request.requestHeaders addEntriesFromDictionary: moreHeaders];

	// Reply handler
	request_ifStillAround = request;
    request.completionBlock = ^(NSDictionary *headers, NSString *body) {
		STHTTPRequest *request = request_ifStillAround;
		NSInteger status = request.responseStatus;
		OBP_LOG_IF(verbose, @"\nResponse: %d\nHeaders: %@\nBody: %@", (int)status, headers, body);
		NSError* error = nil;
		BOOL handled = NO;
        if (NSNotFound != [acceptableStatusCodes indexOfObject: @(status)])
		{
            id container = nil;
			if (deserializeJSON)
			{
				container = [NSJSONSerialization JSONObjectWithData: [body dataUsingEncoding: NSUTF8StringEncoding] options: 0 error: &error];
				OBP_LOG_IF(error, @"[NSJSONSerialization JSONObjectWithData: data options: 0 error:] gave error:\nerror = %@\ndata = %@", error, body);
				OBP_LOG_IF(!error && expectedDeserializedObjectClass && ![container isKindOfClass: expectedDeserializedObjectClass], @"Expected to resource at path %@ to yield a %@, but got instead got:\n%@\nfrom body: %@", path, NSStringFromClass(expectedDeserializedObjectClass), container, body);
				if (!error && expectedDeserializedObjectClass && ![container isKindOfClass: expectedDeserializedObjectClass])
					error = [NSError errorWithDomain: OBPMarshalErrorDomain code: OBPMarshalErrorUnexpectedResourceKind userInfo:@{NSLocalizedDescriptionKey:@"Unexpected response data type.",@"body":body?:@""}];
			}
			if (!error)
				resultHandler(container, body), handled = YES;
		}
		else
		{
			OBP_LOG(@"Unexpected response (%@), when expecting %@; body = %@", @(status), acceptableStatusCodes, body);
			error = [NSError errorWithDomain: OBPMarshalErrorDomain code: OBPMarshalErrorUnexpectedResult userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat: @"Unexpected response status (%@).", @(status)],@"body":body?:@""}];
		}
		if (!handled)
			eh(error, path);
	};

	// Error handler
	request.errorBlock = ^(NSError *error) {
        eh(error, path);
    };

	// Authorise and send
	if (onlyPublicResources || [session authorizeSTHTTPRequest: request])
	{
		[request startAsynchronous];
		OBP_LOG_IF(verbose, @"\n%@", NSStringDescribingNSURLRequest((NSURLRequest*)[(id)request performSelector: @selector(request)]));
		return YES;
	}

	return NO;
}
@end



NSString* NSStringDescribingNSURLRequest(NSURLRequest* request)
{
	// Snippet from: http://stackoverflow.com/a/31734423/618653
	NSMutableString *message = [NSMutableString stringWithString:@"---Request------------------\n"];
	[message appendFormat:@"URL: %@\n",[request.URL description] ];
	[message appendFormat:@"Method: %@\n",[request HTTPMethod]];
	for (NSString *header in [request allHTTPHeaderFields])
	{
		[message appendFormat:@"%@: %@\n",header,[request valueForHTTPHeaderField:header]];
	}
	[message appendFormat:@"Body: %@\n",[[NSString alloc] initWithData:[request HTTPBody] encoding:NSUTF8StringEncoding]];
	[message appendString:@"----------------------------\n"];
	return [NSString stringWithFormat:@"%@",message];
};

NSString* NSStringDescribingNSURLResponseAndData(NSHTTPURLResponse* response, NSData* data)
{
	// Snippet from: http://stackoverflow.com/a/31734423/618653
	NSString *responsestr = [[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSUTF8StringEncoding];
	NSMutableString *message = [NSMutableString stringWithString:@"---Response------------------\n"];
	[message appendFormat:@"URL: %@\n",[response.URL description] ];
	[message appendFormat:@"MIMEType: %@\n",response.MIMEType];
	[message appendFormat:@"Status Code: %ld\n",(long)response.statusCode];
	for (NSString *header in [[response allHeaderFields] allKeys])
	{
		[message appendFormat:@"%@: %@\n",header,[response allHeaderFields][header]];
	}
	[message appendFormat:@"Response Data: %@\n",responsestr];
	[message appendString:@"----------------------------\n"];
	return [NSString stringWithFormat:@"%@",message];
};


