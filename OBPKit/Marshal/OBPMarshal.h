//
//  OBPMarshal.h
//  OBPKit
//
//  Created by Torsten Louland on 18/02/2016.
//  Copyright (c) 2016-2017 TESOBE Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>



NS_ASSUME_NONNULL_BEGIN



@class OBPSession;



static NSString* const	OBPMarshalErrorDomain						= @"OBPMarshalErrorDomain";
NS_ENUM(NSInteger) {	OBPMarshalErrorUnexpectedResourceKind		= 4192,
						OBPMarshalErrorUnexpectedResult				= 4193,
};

static NSString* const	OBPMarshalOptionOnlyPublicResources			= @"onlyPublic"; ///< OBPMarshalOptionOnlyPublicResources key for options dictionary, value of type NSNumber interpreted as BOOL, where value YES indicates omit authorization in order to act on only the publicly available resources and value NO (default when omitted) indicates add authorisation so as to act on both the privately available resources of the authorised user and the publicly available resources.
static NSString* const	OBPMarshalOptionSendDictAsForm				= @"serializeToJSON"; ///< OBPMarshalOptionSendDictAsForm key for options dictionary, value of type NSNumber interpreted as BOOL, where value YES indicates send a dictionary payload as "application/x-www-form-urlencoded", and value NO (same as omitting the option) indicates serialize the payload (for POST/PUT...) as a JSON object; a payload of type NSData is always sent as raw data.
static NSString* const	OBPMarshalOptionExtraHeaders				= @"extraHeaders"; ///< OBPMarshalOptionExtraHeaders key for options dictionary, value of type dictionary, containing extra header key-value pairs that are acceptable for the particular API call, e.g. for sorting, and subranging by date and/or ordinal; header values supplied as NSDate and NSNumber will be converted to correct string values.
static NSString* const	OBPMarshalOptionExpectClass					= @"expectClass"; ///< OBPMarshalOptionExpectClass key for options dictionary, value of type Class is the expected class of the deserialized JSON object, pass [NSNull null] or [NSNull class] to signify no fixed expectation; if omited, then desrialized object is expected to be an NSDictionary; mismatch is treated as OBPMarshalErrorUnexpectedResourceKind
static NSString* const	OBPMarshalOptionExpectStatus				= @"expectStatus"; ///< OBPMarshalOptionExpectStatus key for options dictionary, value of type NSNumber or array of NSNumber giving the expected normal response status code(s); when omitted, the default expectations are 201 for POST, 204 for DELETE, 200 for others.
static NSString* const	OBPMarshalOptionDeserializeJSON				= @"deserializeJSON"; ///< OBPMarshalOptionDeserializeJSON key for options dictionary, value of type NSNumber interpreted as BOOL and indicating whether to deserialize the response body as a JSON object: value YES is the same as omitting the option; use NO to suppress.
static NSString* const	OBPMarshalOptionErrorHandler				= @"errorHandler"; ///< OBPMarshalOptionErrorHandler key for options dictionary, value of type HandleOBPMarshalError block gives alternative error handler to the standard handler.



typedef void(^HandleOBPMarshalError)(NSError* error, NSString* path); // (error, path)
typedef void(^HandleOBPMarshalData)(id deserializedObject, NSString* responseBody); // (deserializedObject, responseBody)



/** Class OBPMarshal helps you marshal resources through the OBP API with get (GET), create (POST), update (PUT) and delete (DELETE) operations. Paths are always relative to the OBP API base. There must always be a supplied error handler or a default error handler. You can obtain a default instance from an OBPSession instance, or create your own.

	An OBPMarshal instance will:
	
	-	use private API calls, i.e. with authorisation by the session object. You can make public API call (no authorisation) by adding OBPMarshalOptionOnlyPublicResources : @YES to your options dictionary.

	-	use its own error handler, unless you supply one as a parameter, or by adding OBPMarshalOptionErrorHandler : yourErrorHandler to the options dictionary; the parameter is chosen in preference to the option.

	-	send a resource (create, update) supplied as NSData as the raw data, and a resource supplied as any other valid JSON root object kind as its serialised JSON description. To send a dictionary resource as a form, include OBPMarshalOptionSendDictAsForm : @YES in your options dictionary.
	
	-	accept a response with status code 201 for create (POST), 204 for DELETE, and 200 for get and update (GET, PUT), and will reject the response if the status is different. To specify one or more status codes to accept instead of the defaults, add OBPMarshalOptionExpectStatus key with a single NSNumber or an NSArray of NSNumber to your options dictionary, e.g. OBPMarshalOptionExpectStatus : @212, or OBPMarshalOptionExpectStatus : @[@201, @212].
	
	-	if the response body is non-empty, expect it to be a serialized object in JSON format, will deserialize it for you and will reject the response if deserialised object is not a dictionary. To prevent deserialisation, add OBPMarshalOptionDeserializeJSON : @NO to your options dictionary. To expect a different class of JSON root object include OBPMarshalOptionExpectClass : class in your options dictionary. To suppress class checking, add OBPMarshalOptionExpectClass : [NSNull null].
	
	To add extra headers that modify the action of the call, add OBPMarshalOptionExtraHeaders : headerDictionary to your options dictionary. For example, to page transactions with get /banks/BANK_ID/accounts/ACCOUNT_ID/VIEW_ID/transactions, you can add OBPMarshalOptionExtraHeaders : @{@"obp_limit":@(chunkSize), @"obp_offset":@(nextChunkOffset)}. Note that OBPMarshal will convert any NSDate values you pass to strings using OBPDateFormatter.
*/
@interface OBPMarshal : NSObject
@property (nonatomic, strong) HandleOBPMarshalError errorHandler; ///< Get/set a default error handler block for this instance.
@property (nonatomic, weak, readonly) OBPSession* session; ///< Get the session object that this instance exclusively works with, identifying the OBP server with which it communicates.

- (instancetype)initWithSessionAuth:(OBPSession*)session; ///< Designated initialiser. session parameter is mandatory. Sets a default error handler which simply logs the error in Debug builds.

- (BOOL)getResourceAtAPIPath:(NSString*)path withOptions:(nullable NSDictionary*)options forResultHandler:(HandleOBPMarshalData)resultHandler orErrorHandler:(nullable HandleOBPMarshalError)errorHandler; ///< Request the resource at path from API base (GET), passing the result to handler, or errors to the error handler. \param path identifies the resource to get, relative to the API base URL. \param options may supply key-value pairs to customise behaviour. \returns YES if the request was launched, or NO if the session or parameters were invalid. \sa See the class description for details of default behaviour and how to override using the options parameter.

- (BOOL)updateResource:(id)resource atAPIPath:(NSString*)path withOptions:(nullable NSDictionary*)options forResultHandler:(HandleOBPMarshalData)resultHandler orErrorHandler:(nullable HandleOBPMarshalError)errorHandler; ///< Update the resource at path from API base (PUT), passing the result to handler, or errors to the error handler. \param path identifies the resource to update, relative to the API base URL. \param options may supply key-value pairs to customise behaviour. \returns YES if the request was launched, or NO if the session or parameters were invalid. \sa See the class description for details of default behaviour and how to override using the options parameter.

- (BOOL)createResource:(id)resource atAPIPath:(NSString*)path withOptions:(nullable NSDictionary*)options forResultHandler:(HandleOBPMarshalData)resultHandler orErrorHandler:(nullable HandleOBPMarshalError)errorHandler; ///< Create a resource at path from API base (POST), passing the result to handler, or errors to the error handler. \param path identifies the resource to create, relative to the API base URL. \param options may supply key-value pairs to customise behaviour. \returns YES if the request was launched, or NO if the session or parameters were invalid. \sa See the class description for details of default behaviour and how to override using the options parameter.

- (BOOL)deleteResourceAtAPIPath:(NSString*)path withOptions:(nullable NSDictionary*)options forResultHandler:(HandleOBPMarshalData)resultHandler orErrorHandler:(nullable HandleOBPMarshalError)errorHandler; ///< Delete the resource at path from API base (DELETE), passing the result to handler, or errors to the error handler. \param options may supply key-value pairs to customise behaviour. \returns YES if the request was launched, or NO if the session or parameters were invalid. \sa See the class description for details of default behaviour and how to override using the options parameter.

@end



NS_ASSUME_NONNULL_END
