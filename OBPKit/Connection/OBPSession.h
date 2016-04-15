//
//  OBPSession.h
//  OBPKit
//
//  Created by Torsten Louland on 23/01/2016.
//  Copyright © 2016 TESOBE Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>



NS_ASSUME_NONNULL_BEGIN



extern NSString* const	OBPSessionErrorDomain;
NS_ENUM(NSInteger) {	OBPSessionErrorCompletionUnsuccessful		= 4096,
						OBPSessionErrorCompletionError				= 4097,
};



@class OBPServerInfo;
@class OBPSession;
typedef NSArray<OBPSession*> OBPSessionArray;
@class OBPWebViewProvider;
@protocol OBPWebViewProvider;
typedef NSObject<OBPWebViewProvider>* OBPWebViewProviderRef;
@class OBPMarshal;
@class STHTTPRequest;



typedef void(^HandleResultBlock)(NSError* _Nullable);



typedef NS_ENUM(uint8_t, OBPSessionState)
{
	OBPSessionStateInvalid,
	OBPSessionStateValid,
	OBPSessionStateInvalidating,
	OBPSessionStateValidating,
};



/**	OBPSession

An OBPSession \em instance sets up authorised sessions with an OBP server, can authorise subsequent API requests, and provides convenient access to a helper for marshalling resources through the API.

The OBPSession \em class object holds and manages instances, allowing you to find, add, remove and gain general access to them.


An OBPSession instance associates with one OBPServerInfo through its lifetime, which represents the server to connect to and persists credentials. Hence, if the serverInfo has restored authorisation from a previous run of the host application, then a session is ready to continue immediately the instance is created.

A session instance will need to present a web view to gain authorisation from the user. You can optionally provide this by introducing an object that implements the OBPWebViewProvider protocol. Otherwise, the OBPDefaultWebViewProvider singleton will be used.

Each instance holds an OBPMarshal helper object in its marshal property, for retrieving resources through the API. You can replace the default instance with your own if you need a different implementation or behaviour.
*/
@interface OBPSession : NSObject
// Managing sessions
+ (nullable instancetype)sessionWithServerInfo:(OBPServerInfo*)serverInfo; ///< Return a session instance for use with the server represented by the supplied info, creating it if necessary; there is only one OBPSession instance per OBPServerInfo instance. \param serverInfo identifies the OBP API server to connect to, and is retained by the OBPSession instance for its lifetime.
+ (nullable OBPSession*)findSessionWithServerInfo:(OBPServerInfo*)serverInfo; ///< Return the OBPSession instance that uses the supplied OBPServerInfo instance, or nil if not found.
+ (void)removeSession:(OBPSession*)session; ///< Remove the supplied instance from the class' record of all sessions.
+ (nullable OBPSession*)currentSession; ///< Return the first session instance. (Convenience for when working with a single session at a time.)
+ (OBPSessionArray*)allSessions; ///< Return the list of session instances currently held by the class.

// Instance set up
@property (nonatomic, weak, nullable) OBPWebViewProviderRef webViewProvider; ///< Set/get an object that can provide a web view when requested by this instance, i.e. conforming to protocol OBPWebViewProvider. The web view is for use during the session validation process to ask the user to authorise access to their data. If nil, then the OBPDefaultWebViewProvider singleton is used. Changes to the web view provider are ignored while validation is in progress.

@property (nonatomic, strong, readonly) OBPServerInfo* serverInfo; ///< Get the OBPServerInfo instance that represents the OBP API server with which this session connects.

// Connection
- (void)validate:(HandleResultBlock)completion; ///< Ask this session to go through the authorisation process and call the supplied completion block with the result. If the session is already valid, then the request is ignored. If it is currently validating, then the previous validation attempt is aborted, completion called with a NSUserCancelledError, and a new validation sequence started. A strong reference to the webViewProvider (or if nil, to -[OBPDefaultWebViewProvider instance]) is taken, held until completion and used to bring up a web view when the user is asked for authorisation. If validation is completed successfully, then authorisation is stored through the serverInfo instance, and completion is called with nil for error. If validation fails, completion is called with an error. If user authorisation is sought via an external browser, it is possible that the user does not complete it (e.g. browsed away from auth web page), and no completion is returned, and it is for this scenario that subsequent calls to validate will abandon the original request and start a fresh one.

- (void)invalidate; ///< Make the session invalid. Any persisted authorisation is discarded, and therefore new validation is needed before any more interaction with the OBP server is possible. If a validation was in progress, it is canceled and its completion called with NSUserCancelledError.

@property (nonatomic, readonly) OBPSessionState state; ///< Find out the current OBPSessionState for this instance, i.e. whether this session is valid, in the process of validating or invalidating, or is invalid.

@property (nonatomic, readonly) BOOL valid; ///< Find out whether this instance has state OBPSessionStateValid. This property is observable using KVO; change notifications happen after validation completion callbacks have been called.

// Authorising subsequent requests in a valid session
- (BOOL)authorizeSTHTTPRequest:(STHTTPRequest*)request; ///< Add an authorisation header to the supplied request. Call this as the very last step before launching the request.
- (BOOL)authorizeURLRequest:(NSMutableURLRequest*)request andWrapErrorHandler:(HandleResultBlock _Nullable * _Nonnull)errorHandlerAt; ///< Add an authorisation header to the supplied request. Call as last step before launching an NSURLRequest. \param errorHandlerAt points to your local variable that references an error handler block which you will use to handle any errors from the execution of request; it will be replaced by an error handler belonging to this instance, and which will in turn call your original handler; this is necessary so that this instance can detect any errors that show that access has been revoked.

// Access helper for marshalling resources through OBP API as part of this session
@property (nonatomic, strong) OBPMarshal* marshal; ///< Get a default helper for marshalling resources through the OBP API (or one that has been previously assigned) for this session. Reseting to nil will cause a default marshal helper to be created at next request. Assign your own subclass instance if you need an alternative implementation to be used.
@end



NS_ASSUME_NONNULL_END
