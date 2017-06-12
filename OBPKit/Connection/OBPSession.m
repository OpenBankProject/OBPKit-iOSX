//
//  OBPSession.m
//  OBPKit
//
//  Created by Torsten Louland on 23/01/2016.
//  Copyright (c) 2016-2017 TESOBE Ltd. All rights reserved.
//

#import "OBPSession.h"
// sdk
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif
// ext
#import <STHTTPRequest/STHTTPRequest.h>
#import <OAuthCore/OAuthCore.h>
// prj
#import "OBPLogging.h"
#import "OBPServerInfo.h"
#import "OBPWebViewProvider.h"
#import "OBPMarshal.h"
#import "NSString+OBPKit.h"
#import "STHTTPRequest+Error.h"



NSString* const OBPSessionErrorDomain = @"OBPSession";

#define DL_TOKEN_SECRET @"-"



@interface OBPSession ()
{
	OBPServerInfo*			_serverInfo;
	OBPMarshal*				_marshal;
	//
	OBPAuthMethod			_authMethod;
	// Direct Login
	// OAuth1
	OBPWebViewProviderRef	_WVProvider;
	NSString*				_callbackURLString;
	NSString*				_requestToken;
	NSString*				_requestTokenSecret;
	NSString*				_verifier;
}
@property (nonatomic, readwrite) OBPSessionState state;
@property (nonatomic, strong) HandleResultBlock validateCompletion;
@property (nonatomic, readwrite) BOOL valid;
@end



@interface OBPSession (OAuth1)
- (void)startValidating1;
- (void)addAuthorizationHeader1ToSTHTTPRequest:(STHTTPRequest*)request;
- (void)addAuthorizationHeader1ToURLRequest:(NSMutableURLRequest*)request;
@end



@interface OBPSession (DirectLogin)
- (void)startValidating2;
- (void)addAuthorizationHeader2ToSTHTTPRequest:(STHTTPRequest*)request;
- (void)addAuthorizationHeader2ToURLRequest:(NSMutableURLRequest*)request;
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
+ (void)setCurrentSession:(OBPSession*)session
{
	NSUInteger index = session ? [sSessions indexOfObjectIdenticalTo: session] : NSNotFound;
	OBP_LOG_IF(index == NSNotFound, @"[OBPSession setCurrentSession: %@] — bad parameter.", session);
	if (index == NSNotFound || index == 0)
		return;
	NSMutableArray<OBPSession*>* ma = [sSessions mutableCopy];
	[ma removeObjectIdenticalTo: session];
	[ma insertObject: session atIndex: 0];
	sSessions = [ma copy];
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
	session = [[self alloc] initWithServerInfo: serverInfo];
	session.webViewProvider = [OBPDefaultWebViewProvider instance];
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
- (instancetype)initWithServerInfo:(OBPServerInfo*)serverInfo
{
	if (!serverInfo)
		self = nil;
	else
		self = [super init];

	if (self)
	{
		_serverInfo = serverInfo;
		NSDictionary* d = _serverInfo.accessData;
		NSString* token = d[OBPServerInfo_TokenKey];
		NSString* secret = d[OBPServerInfo_TokenSecret];
		if (0 != [token length] * [secret length])
			_valid = YES, _state = OBPSessionStateValid;
		_authMethod = OBPAuthMethod_OAuth1;
		if ([DL_TOKEN_SECRET isEqualToString: secret])
			_authMethod = OBPAuthMethod_DirectLogin;
	}

	return self;
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
#pragma mark -
- (void)setAuthMethod:(OBPAuthMethod)authMethod
{
	if (_authMethod != authMethod)
	{
		[self invalidate];
		_authMethod = authMethod;
	}
}
#pragma mark -
- (void)validate:(HandleResultBlock)completion
{
	OBP_ASSERT(_state == OBPSessionStateInvalid);
	if (_state != OBPSessionStateValid)
	if (completion)
	{
		if (_state == OBPSessionStateValidating)
			[self invalidate];
		_validateCompletion = completion;
		[self startValidating];
	}
}
- (void)invalidate
{
	NSDictionary*	data = @{
		OBPServerInfo_TokenKey		: @"",
		OBPServerInfo_TokenSecret	: @"",
	};
	[self endWithState: OBPSessionStateInvalid data: data error: nil];
}
- (void)startValidating
{
	switch (_authMethod)
	{
		case OBPAuthMethod_None:
			[self endWithState: OBPSessionStateValid data: nil error: nil];
			break;
		case OBPAuthMethod_OAuth1:
			[self startValidating1];
			break;
		case OBPAuthMethod_DirectLogin:
			[self startValidating2];
			break;
		default:
			break;
	}
}
- (void)endWithState:(OBPSessionState)newState data:(NSDictionary*)data error:(NSError*)error // Vagueness of object message name is deliberate.
{
	BOOL	validNow = newState == OBPSessionStateValid;
	BOOL	validWas = _valid;
	_state = newState;
	_serverInfo.accessData = data;
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
#pragma mark -
- (HandleResultBlock)detectRevokeBlockWithChainToBlock:(HandleResultBlock)chainBlock
{
	HandleResultBlock	block =
		^(NSError* error)
		{
			switch (error.code)
			{
				case 401:
					OBP_LOG(@"Request got 401 Unauthorized => Access to server %@ revoked", self.serverInfo.name);
					[self invalidate];
					break;

				case NSURLErrorUserAuthenticationRequired:
					if (![error.domain isEqualToString: NSURLErrorDomain])
						break;
					OBP_LOG(@"Request got NSURLErrorUserAuthenticationRequired => Access to server %@ revoked", self.serverInfo.name);
					[self invalidate];
					break;
			}

			if (chainBlock != nil)
				chainBlock(error);
		};

	return block;
}
- (BOOL)addAuthorizationHeaderToSTHTTPRequest:(STHTTPRequest*)request
{
	switch (_authMethod)
	{
		case OBPAuthMethod_OAuth1:
			[self addAuthorizationHeader1ToSTHTTPRequest: request];
			break;
		case OBPAuthMethod_DirectLogin:
			[self addAuthorizationHeader2ToSTHTTPRequest: request];
			break;
		default:
			return NO;
			break;
	}
	return YES;
}
- (BOOL)addAuthorizationHeaderToURLRequest:(NSMutableURLRequest*)request
{
	switch (_authMethod)
	{
		case OBPAuthMethod_OAuth1:
			[self addAuthorizationHeader1ToURLRequest: request];
			break;
		case OBPAuthMethod_DirectLogin:
			[self addAuthorizationHeader2ToURLRequest: request];
			break;
		default:
			return NO;
			break;
	}
	return YES;
}
- (BOOL)authorizeSTHTTPRequest:(STHTTPRequest*)request
{
	OBP_ASSERT(self.state == OBPSessionStateValid || self.authMethod == OBPAuthMethod_None);
	if (self.state != OBPSessionStateValid && self.authMethod != OBPAuthMethod_None)
		return NO;

	HandleResultBlock		errorBlock = request.errorBlock;

	// If auth header installed, chain error handler to check if token has been revoked
	if ([self addAuthorizationHeaderToSTHTTPRequest: request])
		errorBlock = [self detectRevokeBlockWithChainToBlock: errorBlock];

	if (errorBlock)
	{
		STHTTPRequest __weak*	request_ifStillAround = request;
		errorBlock =
			^(NSError* error)
			{
				STHTTPRequest*	request = request_ifStillAround;
				// Add server-side description to error if available. (STHTTPRequest enhancement)
				error = request ? [request errorByAddingServerSideDescriptionToError: error] : error;
				errorBlock(error);
			};
	}

	request.errorBlock = errorBlock;

	return YES;
}
- (BOOL)authorizeURLRequest:(NSMutableURLRequest*)request andWrapErrorHandler:(HandleResultBlock*)handlerAt
{
	OBP_ASSERT(self.state == OBPSessionStateValid || self.authMethod == OBPAuthMethod_None);
	if (self.state != OBPSessionStateValid && self.authMethod != OBPAuthMethod_None)
		return NO;

	// If auth header installed, chain error handler to check if token has been revoked
	if ([self addAuthorizationHeaderToURLRequest: request])
	if (handlerAt)
	   *handlerAt = [self detectRevokeBlockWithChainToBlock: *handlerAt];

	return YES;
}
@end



#pragma mark -
@implementation OBPSession (OAuth1)
- (void)startValidating1
{
	// We keep a strong reference to the webViewProvider for the duration of our authentication process...
	_WVProvider = _webViewProvider ?: [OBPDefaultWebViewProvider instance];
	[self getAuthRequestToken];
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

	OBPSessionState	newState;
	if ([token length] && [secret length])
		newState = OBPSessionStateValid;
	else
		newState = OBPSessionStateInvalid, token = secret = @"";

	NSDictionary*	data = @{
		OBPServerInfo_TokenKey		: token,
		OBPServerInfo_TokenSecret	: secret,
	};

	[self endWithState: newState data: data error: error];
}
- (void)getAuthRequestToken
{
	NSDictionary*			d = _serverInfo.accessData;
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
			STHTTPRequest *request = request_ifStillAround;
			// Add server-side description to error if available. (STHTTPRequest enhancement)
			error = request ? [request errorByAddingServerSideDescriptionToError: error] : error;
			OBP_LOG(@"getAuthRequestToken got error %@", error);
			[self completedWith: nil and: nil error: [NSError errorWithDomain: OBPSessionErrorDomain code: OBPSessionErrorCompletionError userInfo: @{NSUnderlyingErrorKey:error,NSURLErrorKey:request_ifStillAround.url?:[NSNull null]}]];
		};
    
	_state = OBPSessionStateValidating;
    [request startAsynchronous];
	self.valid = _state == OBPSessionStateValid;
}
- (void)getUsersAuthorisation
{
	NSDictionary*			d = _serverInfo.accessData;
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
	NSDictionary*			d = _serverInfo.accessData;
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
			STHTTPRequest *request = request_ifStillAround;
			// Add server-side description to error if available. (STHTTPRequest enhancement)
			error = request ? [request errorByAddingServerSideDescriptionToError: error] : error;
			OBP_LOG(@"getAccessToken got error %@", error);
			[self completedWith: nil and: nil error: [NSError errorWithDomain: OBPSessionErrorDomain code: OBPSessionErrorCompletionError userInfo: @{NSUnderlyingErrorKey:error,NSURLErrorKey:request_ifStillAround.url?:[NSNull null]}]];
		};
    
    [request startAsynchronous];
}
#pragma mark -
- (void)addAuthorizationHeader1ToSTHTTPRequest:(STHTTPRequest*)request
{
	NSDictionary*			d = _serverInfo.accessData;
	NSString*				consumerKey = d[OBPServerInfo_ClientKey];
	NSString*				consumerSecret = d[OBPServerInfo_ClientSecret];
	NSString*				tokenKey = d[OBPServerInfo_TokenKey];
	NSString*				tokenSecret = d[OBPServerInfo_TokenSecret];
	NSString*				header;

	OBP_ASSERT(0 != [consumerKey length] * [consumerSecret length] * [tokenKey length] * [tokenSecret length] && ![DL_TOKEN_SECRET isEqualToString: tokenSecret]);
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
}
- (void)addAuthorizationHeader1ToURLRequest:(NSMutableURLRequest*)request
{
	NSDictionary*			d = _serverInfo.accessData;
	NSString*				consumerKey = d[OBPServerInfo_ClientKey];
	NSString*				consumerSecret = d[OBPServerInfo_ClientSecret];
	NSString*				tokenKey = d[OBPServerInfo_TokenKey];
	NSString*				tokenSecret = d[OBPServerInfo_TokenSecret];
	NSString*				header;

	OBP_ASSERT(0 != [consumerKey length] * [consumerSecret length] * [tokenKey length] * [tokenSecret length] && ![DL_TOKEN_SECRET isEqualToString: tokenSecret]);

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
}
@end



#pragma mark -
@implementation OBPSession (DirectLogin)
- (void)startValidating2
{
	ProvideDirectLoginParamsBlock	provider =
		_directLoginParamsProvider
		?:
		^void(ReceiveDirectLoginParamsBlock receiver)
		{
			NSString*			title = @"Log In";
			NSString*			message = [NSString stringWithFormat: @"Please enter your Username and Password to log in to\n%@", self.serverInfo.name];
			NSString*			actionButtonTitle = @"Log In";
			NSString*			cancelButtonTitle = @"Cancel";
			NSString*			usernamePlaceholder = @"Username";
			NSString*			passwordPlaceholder = @"Password";
#if TARGET_OS_IPHONE
			UIAlertController*	ac;
			UIAlertAction*		aa;
			ac = [UIAlertController alertControllerWithTitle: title message: message
											  preferredStyle: UIAlertControllerStyleAlert];
			[ac addTextFieldWithConfigurationHandler:^(UITextField* textField) {
				textField.placeholder = usernamePlaceholder;
			}];
			[ac addTextFieldWithConfigurationHandler:^(UITextField* textField) {
				textField.placeholder = passwordPlaceholder;
				textField.secureTextEntry = YES;
			}];
			aa = [UIAlertAction actionWithTitle: cancelButtonTitle style: UIAlertActionStyleCancel
										handler: ^(UIAlertAction*a) {
					receiver(nil, nil);
				}];
			[ac addAction: aa];
			aa = [UIAlertAction actionWithTitle: actionButtonTitle style: UIAlertActionStyleDefault
										handler: ^(UIAlertAction* action) {
					receiver(ac.textFields[0].text, ac.textFields[1].text);
				}];
			[ac addAction: aa];
			UIWindow*			window = [UIApplication sharedApplication].keyWindow;
			UIViewController*	vc = window.rootViewController; // walk down tree?
			[vc presentViewController: ac animated: YES completion: nil];
#else
			enum {
				tf_un=0, tf_pw, tf_count,
				frame_un=tf_un, frame_pw=tf_pw, frame_av, frame_count,
			};
			NSTextField*		username;
			NSTextField*		password;
			NSTextField*		tf;
			NSUInteger			i;
			CGRect				frame[frame_count] = {{2,28,280,20},{2,0,280,20},{0,0,284,48}};
			for (i = 0; i < tf_count; i++)
			{
				if (i == tf_un)
					tf = username = [[NSTextField alloc] initWithFrame: frame[i]];
				else
					tf = password = [[NSSecureTextField alloc] initWithFrame: frame[i]];
				tf.placeholderString = i == tf_un ? usernamePlaceholder : passwordPlaceholder;
				tf.maximumNumberOfLines = 1;
				tf.drawsBackground = YES; tf.bordered = YES; tf.editable = YES; tf.selectable = YES;
			}
			NSView*				accessoryView = [[NSView alloc] initWithFrame: frame[frame_av]];
			[accessoryView addSubview: username];
			[accessoryView addSubview: password];

			NSAlert*			alert = [[NSAlert alloc] init];
			alert.messageText = title;
			alert.informativeText = message;
			[alert addButtonWithTitle: actionButtonTitle];
			[alert addButtonWithTitle: cancelButtonTitle];
			alert.accessoryView = accessoryView;
			[alert layout];

			[alert beginSheetModalForWindow: NSApp.keyWindow
						  completionHandler:
				^(NSModalResponse returnCode) {
					if (returnCode == NSAlertFirstButtonReturn)
					{
						receiver(username.stringValue, password.stringValue);
					}
				}
			];
#endif
		};

	ReceiveDirectLoginParamsBlock	receiver =
		^void(NSString* username, NSString* password)
		{
			[self getAuthTokenWithParams: username : password];
		};

	provider(receiver);
}
- (void)getAuthTokenWithParams:(NSString*)username :(NSString*)password
{
	if (![username length] || ![password length])
	{
		[self endWithState: OBPSessionStateInvalid
					  data: nil
					 error: [NSError errorWithDomain: NSCocoaErrorDomain code: NSUserCancelledError userInfo: nil]];
		return;
	}

	NSDictionary*			d = _serverInfo.accessData;
	NSString*				base = d[OBPServerInfo_AuthServerBase];
	NSString*				path = @"/my/logins/direct";
	NSString*				consumerKey = d[OBPServerInfo_ClientKey];
	NSString*				header;
    STHTTPRequest*			request;
	STHTTPRequest __weak*	request_ifStillAround;

	path = [base stringForURLByAppendingPath: path];
	request_ifStillAround = request = [STHTTPRequest requestWithURLString: path];
	request.HTTPMethod = @"POST";
	request.POSTDictionary = @{};

	header = [NSString stringWithFormat: @"DirectLogin username=\"%@\", password=\"%@\", consumer_key=\"%@\"", username, password, consumerKey];
    [request setHeaderWithName: @"Authorization" value: header];

    request.completionBlock =
		^(NSDictionary *headers, NSString *body)
		{
			STHTTPRequest*	request = request_ifStillAround;
			NSInteger		status = request.responseStatus;
			NSDictionary*	response;
			NSString*		token;
			BOOL			completedStage = NO;
			NSError*		error = nil;

			if (status == 200)
			{
				response = [NSJSONSerialization JSONObjectWithData: [body dataUsingEncoding: NSUTF8StringEncoding] options: 0 error: &error];
				token = response[@"token"];
				if ([token length])
				{
					[self endWithState: OBPSessionStateValid
								  data: @{	OBPServerInfo_TokenKey : token,
											OBPServerInfo_TokenSecret : DL_TOKEN_SECRET}
								 error: nil];
					completedStage = YES;
				}
			}

			if (!completedStage)
			{
				OBP_LOG(@"getAuthToken request completion not successful: status=%d headers=%@ body=%@", (int)status, headers, body);
				[self endWithState: OBPSessionStateInvalid
							  data: @{OBPServerInfo_TokenKey : @"", OBPServerInfo_TokenSecret : @""}
							 error: [NSError errorWithDomain: OBPSessionErrorDomain code: OBPSessionErrorCompletionUnsuccessful userInfo: @{@"status":@(status), NSURLErrorKey:request?request.url:[NSNull null]}]];
			}
		};

    request.errorBlock =
		^(NSError *error)
		{
			STHTTPRequest *request = request_ifStillAround;
			// Add server-side description to error if available. (STHTTPRequest enhancement)
			error = request ? [request errorByAddingServerSideDescriptionToError: error] : error;
			OBP_LOG(@"getAuthToken got error %@", error);
			[self endWithState: OBPSessionStateInvalid
						  data: @{OBPServerInfo_TokenKey : @"", OBPServerInfo_TokenSecret : @""}
						 error: [NSError errorWithDomain: OBPSessionErrorDomain code: OBPSessionErrorCompletionError userInfo: @{NSUnderlyingErrorKey:error,NSURLErrorKey:request_ifStillAround.url?:[NSNull null]}]];
		};
    
	_state = OBPSessionStateValidating;
    [request startAsynchronous];
	self.valid = _state == OBPSessionStateValid;
}
- (void)addAuthorizationHeader2ToSTHTTPRequest:(STHTTPRequest*)request
{
	NSDictionary*			d = _serverInfo.accessData;
	NSString*				tokenKey = d[OBPServerInfo_TokenKey];
	NSString*				tokenSecret = d[OBPServerInfo_TokenSecret];
	NSString*				header;

	OBP_ASSERT([tokenKey length] * [DL_TOKEN_SECRET isEqualToString: tokenSecret]);

	header = [NSString stringWithFormat: @"DirectLogin token=\"%@\"", tokenKey];

    [request setHeaderWithName: @"Authorization" value: header];
}
- (void)addAuthorizationHeader2ToURLRequest:(NSMutableURLRequest*)request
{
	NSDictionary*			d = _serverInfo.accessData;
	NSString*				tokenKey = d[OBPServerInfo_TokenKey];
	NSString*				tokenSecret = d[OBPServerInfo_TokenSecret];
	NSString*				header;

	OBP_ASSERT([tokenKey length] * [DL_TOKEN_SECRET isEqualToString: tokenSecret]);

	header = [NSString stringWithFormat: @"DirectLogin token=\"%@\"", tokenKey];

    [request setValue: header forHTTPHeaderField: @"Authorization"];
}
@end


