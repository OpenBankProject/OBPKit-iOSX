//
//  OBPMarshal.h
//  OBPKit
//
//  Created by Torsten Louland on 18/02/2016.
//  Copyright © 2016 TESOBE Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>



NS_ASSUME_NONNULL_BEGIN



@class OBPSession;



static NSString* const	OBPMarshalErrorDomain						= @"OBPMarshalErrorDomain";
NS_ENUM(NSInteger) {	OBPMarshalErrorUnexpectedResourceKind		= 4192,
						OBPMarshalErrorUnexpectedResult				= 4193,
};

static NSString* const	OBPMarshalOptionExpectClass					= @"expectClass"; ///< OBPMarshalOptionExpectClass key for options dictionary, value of type Class is the expected class of the deserialized JSON object; mismatch is treated as OBPMarshalErrorUnexpectedResourceKind
static NSString* const	OBPMarshalOptionExpectStatus				= @"expectStatus"; ///< OBPMarshalOptionExpectStatus key for options dictionary, value of type NSNumber is the expected normal response status if other than 200 (the default).
static NSString* const	OBPMarshalOptionDeserializeJSON				= @"deserializeJSON"; ///< OBPMarshalOptionDeserializeJSON key for options dictionary, value of type NSNumber interpretted as BOOL and indicating whether to deserialize the response body as a JSON object: value YES is the same as omitting the option; use NO to suppress.
static NSString* const	OBPMarshalOptionErrorHandler				= @"errorHandler"; ///< OBPMarshalOptionErrorHandler key for options dictionary, value of type HandleOBPMarshalError block gives alternative error handler to the standard handler.



typedef void(^HandleOBPMarshalError)(NSError* error, NSString* path);
typedef void(^HandleOBPMarshalData)(id deserializedJSONObject, NSString* responseBody);



/// Class OBPMarshal helps you marshal resources through the OBP API. Paths are always relative to the OBP API base. There must always be a supplied or default error handler. You can obtain a default instance from an OBPSession instance, or create your own.
@interface OBPMarshal : NSObject
@property (nonatomic, strong) HandleOBPMarshalError errorHandler; ///< Get/set a default error handler block for this instance.
@property (nonatomic, weak, readonly) OBPSession* session; ///< Get the session object that this instance exclusively works with, identifying the OBP server with which it communicates.

- (instancetype)initWithSessionAuth:(OBPSession*)session; ///< Designated initialiser. session parameter is mandatory. Sets a default error handler which simply logs the error in Debug builds.

- (BOOL)getResourceAtAPIPath:(NSString*)path withOptions:(nullable NSDictionary*)options forHandler:(HandleOBPMarshalData)handler; ///< Request the resource at the supplied path from the API base, passing the result to handler, or errors to the default error handler of this instance, or as modified by options. \param path identifies the resource to get, relative to the API base URL. \param options may supply values for any of the following keys: OBPMarshalOptionExpectClass, OBPMarshalOptionExpectStatus, OBPMarshalOptionDeserializeJSON, OBPMarshalOptionErrorHandler; see the description for each key. \returns YES if the request was launched, or NO if the session or parameters were invalid.

@end



NS_ASSUME_NONNULL_END
