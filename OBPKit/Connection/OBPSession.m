//
//  OBPSession.m
//  OBPKit
//
//  Created by Torsten Louland on 23/01/2016.
//  Copyright © 2016 TESOBE Ltd. All rights reserved.
//

#import "OBPSession.h"
// sdk
// ext
#import <STHTTPRequest/STHTTPRequest.h>
#import <OAuthCore/OAuthCore.h>
// prj
#import "OBPLogging.h"
#import "OBPServerInfo.h"
#import "OBPWebViewProvider.h"
#import "OBPMarshal.h"
#import "NSString+OBPKit.h"



NSString* const OBPSessionErrorDomain = @"OBPSession";



@interface OBPSession ()
{
	OBPServerInfo*			_serverInfo;
	OBPWebViewProviderRef	_WVProvider;
	NSString*				_callbackURLString;
	NSString*				_requestToken;
	NSString*				_requestTokenSecret;
	NSString*				_verifier;

	OBPMarshal*				_marshal;
}
@property (nonatomic, readwrite) OBPSessionState state;
@property (nonatomic, strong) HandleResultBlock validateCompletion;
@property (nonatomic, readwrite) BOOL valid;
@end



#pragma mark -
@implementation OBPSession
static OBPSessionArray* sSessions = nil;
+ (void)initialize
{
	if (self != [OBPSession class])
		return;
	sSessions = [OBPSessionArray array];
}
+ (nullable OBPSession*)currentSession
{
	return [sSessions firstObject];
}
+ (nullable instancetype)findSessionWithServerInfo:(OBPServerInfo*)serverInfo
{
	OBPSession* session;
	for (session in sSessions)
	if (session->_serverInfo == serverInfo)
		return session;
	return nil;
}
+ (nullable instancetype)sessionWithServerInfo:(OBPServerInfo*)serverInfo
{
	OBPSession* session;
	if (!serverInfo)
		return nil;
	if (nil != (session = [self findSessionWithServerInfo: serverInfo]))
		return session;
	session = [[self alloc] initWithServerInfo: serverInfo
								   webViewProvider: [OBPDefaultWebViewProvider instance]];
	sSessions = [sSessions arrayByAddingObject: session];
	return session;
}
+ (void)removeSession:(OBPSession*)session
{
	if (NSNotFound == [sSessions indexOfObjectIdenticalTo: session])
		return;
	if (session.state != OBPSessionStateInvalid)
		[session invalidate];
	NSMutableArray* ma = [sSessions mutableCopy];
	[ma removeObjectIdenticalTo: session];
	sSessions = [ma copy];
}
+ (OBPSessionArray*)allSessions
{
	return [sSessions copy];
}
#pragma mark -
- (instancetype)initWithServerInfo:(OBPServerInfo*)serverInfo webViewProvider:(OBPWebViewProviderRef)wvp
{
	if (!serverInfo)
		self = nil;
	else
		self = [super init];

	if (self)
	{
		self.webViewProvider = wvp;
		_serverInfo = serverInfo;
		NSDictionary* d = _serverInfo.data;
		if (0 != [d[OBPServerInfo_TokenKey] length] * [d[OBPServerInfo_TokenSecret] length])
			_valid = YES, _state = OBPSessionStateValid;
	}

	return self;
}
#pragma mark -
- (void)validate:(HandleResultBlock)completion
{
	OBP_ASSERT(_state == OBPSessionStateInvalid);
	if (_state != OBPSessionStateValid)
	if (completion)
	{
		if (_state == OBPSessionStateValidating)
			[self completedWith: nil and: nil error: nil];
		_validateCompletion = completion;
		// We keep a strong reference to the webViewProvider for the duration of our authentication process...
		_WVProvider = _webViewProvider ?: [OBPDefaultWebViewProvider instance];
		[self getAuthRequestToken];
	}
}
- (void)invalidate
{
	[self completedWith: nil and: nil error: nil];
}
#pragma mark -
- (void)completedWith:(NSString*)token and:(NSString*)secret error:(NSError*)error // Vagueness of object message name is deliberate.
{
	[_WVProvider resetWebViewProvider];
	_WVProvider = nil;
	_callbackURLString = nil;
	_requestToken = nil;
	_requestTokenSecret = nil;
	_verifier = nil;

	if ([token length] && [secret length])
		_state = OBPSessionStateValid;
	else
		_state = OBPSessionStateInvalid, token = secret = @"";
	BOOL	validWas = _valid;
	BOOL	validNow = _state == OBPSessionStateValid;

	_serverInfo.data = @{
		OBPServerInfo_TokenKey		: token,
		OBPServerInfo_TokenSecret	: secret,
	};

	if (_validateCompletion)
	{
		// We want to call the completion function before KV observers of our valid property get notified.
		HandleResultBlock validateCompletion = _validateCompletion;
		_validateCompletion = nil;
		_valid = validNow; // temporarily set _valid to correct value without triggering KVO
		if (error == nil && !validNow)
			error = [NSError errorWithDomain: NSCocoaErrorDomain code: NSUserCancelledError userInfo: nil];
		validateCompletion(error);
		_valid = validWas; // temporarily reset _valid to old value so KVO will be triggered next...
	}
	self.valid = validNow;
}
- (void)getAuthRequestToken
{
	NSDictionary*			d = _serverInfo.data;
	NSString*				base = d[OBPServerInfo_AuthServerBase];
	NSString*				path = d[OBPServerInfo_RequestPath];
	NSString*				consumerKey = d[OBPServerInfo_ClientKey];
	NSString*				consumerSecret = d[OBPServerInfo_ClientSecret];
	NSString*				callbackScheme;
	NSString*				header;
    STHTTPRequest*			request;
	STHTTPRequest __weak*	request_ifStillAround;

	path = [base stringForURLByAppendingPath: path];
	request_ifStillAround = request = [STHTTPRequest requestWithURLString: path];
	request.HTTPMethod = @"POST";
	request.POSTDictionary = @{};

	callbackScheme = _WVProvider.callbackScheme;
	if (![callbackScheme length])
		callbackScheme = [NSBundle mainBundle].bundleIdentifier;
	_callbackURLString = [callbackScheme stringByAppendingString: @"://callback"];

	header = OAuthHeader(
		request.url,
		request.HTTPMethod,
		nil, // body (parsed for extra query parameters)
		consumerKey,
		consumerSecret,
		nil, // oauth_token
		nil, // oauth_token_secret
		nil, // oauth_verifier
		_callbackURLString,
		OAuthCoreSignatureMethod_HMAC_SHA256);

    [request setHeaderWithName: @"Authorization" value: header];

    request.completionBlock =
		^(NSDictionary *headers, NSString *body)
		{
			STHTTPRequest*	request = request_ifStillAround;
			NSInteger		status = request.responseStatus;
			NSDictionary*	response;
			NSString*		callbackResult;
			BOOL			completedStage = NO;

			if (status == 200)
			{
				body = [body stringByRemovingPercentEncoding];
				response = [body extractURLQueryParams];
				callbackResult = response[@"oauth_callback_confirmed"];
				if([callbackResult isEqualToString: @"true"])
				{
					_requestToken = response[@"oauth_token"];
					_requestTokenSecret = response[@"oauth_token_secret"];
					[self getUsersAuthorisation];
					completedStage = YES;
				}
			}

			if (!completedStage)
			{
				OBP_LOG(@"getAuthRequestToken request completion not successful: status=%d headers=%@ body=%@", (int)status, headers, body);
				[self completedWith: nil and: nil error: [NSError errorWithDomain: OBPSessionErrorDomain code: OBPSessionErrorCompletionUnsuccessful userInfo: @{@"status":@(status), NSURLErrorKey:request?request.url:[NSNull null]}]];
			}
		};

    request.errorBlock =
		^(NSError *error)
		{
			OBP_LOG(@"getAuthRequestToken got error %@", error);
			[self completedWith: nil and: nil error: [NSError errorWithDomain: OBPSessionErrorDomain code: OBPSessionErrorCompletionError userInfo: @{NSUnderlyingErrorKey:error,NSURLErrorKey:request_ifStillAround.url?:[NSNull null]}]];
		};
    
	_state = OBPSessionStateValidating;
    [request startAsynchronous];
	self.valid = _state == OBPSessionStateValid;
}
- (void)getUsersAuthorisation
{
	NSDictionary*			d = _serverInfo.data;
	NSString*				base = d[OBPServerInfo_AuthServerBase];
	NSString*				path = d[OBPServerInfo_GetUserAuthPath];
	NSURLComponents*		baseComponents = [NSURLComponents componentsWithString: base];
	NSURL*					url;

	baseComponents.path = path;
	baseComponents.queryItems = @[[NSURLQueryItem queryItemWithName: @"oauth_token" value: _requestToken]];
	url = baseComponents.URL; // returns nil if path not prefixed by "/"
	OBP_ASSERT(url);

	OBPWebNavigationFilter	filter =
		^BOOL(NSURL* url)
		{
			NSDictionary*	parameters;
			NSString*		requestToken;
			NSString*		urlString = [url absoluteString];

			if ([urlString hasPrefix: _callbackURLString])
			if (nil != (parameters = [url.query extractURLQueryParams]))
			if (nil != (requestToken = parameters[@"oauth_token"]))
			if ([_requestToken isEqualToString: requestToken])
			{
				_verifier = parameters[@"oauth_verifier"];
				[self getAccessToken];
				return YES;
			}

			return NO;
		};

	OBPWebCancelNotifier	cancel =
		^()
		{
			[self completedWith: nil and: nil
						  error: [NSError errorWithDomain: NSCocoaErrorDomain
													 code: NSUserCancelledError
												 userInfo: @{ NSURLErrorKey : url } ]];
		};

	[_WVProvider showURL: url filterNavWith: filter notifyCancelBy: cancel];
}
- (void)getAccessToken
{
	NSDictionary*			d = _serverInfo.data;
	NSString*				base = d[OBPServerInfo_AuthServerBase];
	NSString*				path = d[OBPServerInfo_GetTokenPath];
	NSString*				consumerKey = d[OBPServerInfo_ClientKey];
	NSString*				consumerSecret = d[OBPServerInfo_ClientSecret];
	NSString*				header;
    STHTTPRequest*			request;
	STHTTPRequest __weak*	request_ifStillAround;

	path = [base stringForURLByAppendingPath: path];
	request_ifStillAround = request = [STHTTPRequest requestWithURLString: path];
	request.HTTPMethod = @"POST";
	request.POSTDictionary = @{};

	header = OAuthHeader(
		request.url,
		request.HTTPMethod,
		nil, // body (parsed for extra query parameters)
		consumerKey,
		consumerSecret,
		_requestToken, // oauth_token
		_requestTokenSecret, // oauth_token_secret
		_verifier, // oauth_verifier,
		_callbackURLString,
		OAuthCoreSignatureMethod_HMAC_SHA256);

    [request setHeaderWithName: @"Authorization" value: header];

    request.completionBlock =
		^(NSDictionary *headers, NSString *body)
		{
			STHTTPRequest*	request = request_ifStillAround;
			NSInteger		status = request.responseStatus;
			NSDictionary*	response;
			NSString*		token;
			NSString*		secret;
			BOOL			completedStage = NO;

			if (status == 200)
			{
				body = [body stringByRemovingPercentEncoding];
				response = [body extractURLQueryParams];
				token = response[@"oauth_token"];
				secret = response[@"oauth_token_secret"];
				[self completedWith: token and: secret error: nil];
				completedStage = YES;
			}

			if (!completedStage)
			{
				OBP_LOG(@"getAccessToken request completion not successful: status=%d headers=%@ body=%@", (int)status, headers, body);
				[self completedWith: nil and: nil error: [NSError errorWithDomain: OBPSessionErrorDomain code: OBPSessionErrorCompletionUnsuccessful userInfo: @{@"status":@(status), NSURLErrorKey:request.url?:[NSNull null]}]];
			}
		};

    request.errorBlock =
		^(NSError *error)
		{
			OBP_LOG(@"getAccessToken got error %@", error);
			[self completedWith: nil and: nil error: [NSError errorWithDomain: OBPSessionErrorDomain code: OBPSessionErrorCompletionError userInfo: @{NSUnderlyingErrorKey:error,NSURLErrorKey:request_ifStillAround.url?:[NSNull null]}]];
		};
    
    [request startAsynchronous];
}
#pragma mark -
- (HandleResultBlock)detectRevokeBlockWithChainToBlock:(HandleResultBlock)chainBlock
{
	HandleResultBlock	block =
		^(NSError* error)
		{
			switch (error.code)
			{
				case 401:
					OBP_LOG(@"Request got 401 Unauthorized => Access to server %@ revoked", _serverInfo.name);
					[self invalidate];
					break;

				case NSURLErrorUserAuthenticationRequired:
					if (![error.domain isEqualToString: NSURLErrorDomain])
						break;
					OBP_LOG(@"Request got NSURLErrorUserAuthenticationRequired => Access to server %@ revoked", _serverInfo.name);
					[self invalidate];
					break;
			}

			if (chainBlock != nil)
				chainBlock(error);
		};

	return block;
}
- (BOOL)authorizeSTHTTPRequest:(STHTTPRequest*)request
{
	OBP_ASSERT(_state == OBPSessionStateValid);
	if (_state != OBPSessionStateValid)
		return NO;

	NSDictionary*			d = _serverInfo.data;
	NSString*				consumerKey = d[OBPServerInfo_ClientKey];
	NSString*				consumerSecret = d[OBPServerInfo_ClientSecret];
	NSString*				tokenKey = d[OBPServerInfo_TokenKey];
	NSString*				tokenSecret = d[OBPServerInfo_TokenSecret];
	NSString*				header;

	OBP_ASSERT(0 != [consumerKey length] * [consumerSecret length] * [tokenKey length] * [tokenSecret length]);
	//	If STHTTPRequest's HTTPMethod property is not explicitly set, then STHTTPRequest infers it lazily at the last moment, and we can get a value from the property that is not yet accurate at this stage. Assert that this is not the case here:
	OBP_ASSERT(([request.HTTPMethod isEqualToString: @"GET"] || [request.HTTPMethod isEqualToString: @"DELETE"]) == (request.POSTDictionary==nil && request.rawPOSTData==nil));

	header = OAuthHeader(
		request.url,
		request.HTTPMethod,
		nil, // body (parsed for extra query parameters)
		consumerKey,
		consumerSecret,
		tokenKey, // oauth_token
		tokenSecret, // oauth_token_secret
		nil, // oauth_verifier,
		nil, // callback
		OAuthCoreSignatureMethod_HMAC_SHA256);

    [request setHeaderWithName: @"Authorization" value: header];

	// Chain error handler to detect if token has been revoked
	request.errorBlock = [self detectRevokeBlockWithChainToBlock: request.errorBlock];

	return YES;
}
- (BOOL)authorizeURLRequest:(NSMutableURLRequest*)request andWrapErrorHandler:(HandleResultBlock*)handlerAt
{
	OBP_ASSERT(_state == OBPSessionStateValid);
	if (_state != OBPSessionStateValid)
		return NO;

	NSDictionary*			d = _serverInfo.data;
	NSString*				consumerKey = d[OBPServerInfo_ClientKey];
	NSString*				consumerSecret = d[OBPServerInfo_ClientSecret];
	NSString*				tokenKey = d[OBPServerInfo_TokenKey];
	NSString*				tokenSecret = d[OBPServerInfo_TokenSecret];
	NSString*				header;

	OBP_ASSERT(0 != [consumerKey length] * [consumerSecret length] * [tokenKey length] * [tokenSecret length]);

	header = OAuthHeader(
		request.URL,
		request.HTTPMethod,
		nil, // body (parsed for extra query parameters)
		consumerKey,
		consumerSecret,
		tokenKey, // oauth_token
		tokenSecret, // oauth_token_secret
		nil, // oauth_verifier
		nil, // callback
		OAuthCoreSignatureMethod_HMAC_SHA256);

    [request setValue: header forHTTPHeaderField: @"Authorization"];

	// Chain error handler to check if token has been revoked
	if (handlerAt)
	   *handlerAt = [self detectRevokeBlockWithChainToBlock: *handlerAt];

	return YES;
}
#pragma mark -
- (void)setMarshal:(OBPMarshal*)marshal
{
	if (marshal && marshal.session != self)
		marshal = nil;
	if (_marshal != marshal)
		_marshal = marshal;
}
- (OBPMarshal*)marshal
{
	if (_marshal == nil)
		_marshal = [[OBPMarshal alloc] initWithSessionAuth: self];
	return _marshal;
}
@end


