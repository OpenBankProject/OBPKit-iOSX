//
//  OBPServerInfoStore.h
//  OBPKit
//
//  Created by Torsten Louland on 15/03/2016.
//  Copyright (c) 2016-2017 TESOBE Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>



NS_ASSUME_NONNULL_BEGIN



@class OBPServerInfo;



/// An OBPServerInfoStore instance will handle writing and reading of OBPServerInfo instances to and from persistent storage for the OBPServerInfo class, and hence is a possible override point for implementing your own more secure storage scheme.
@interface OBPServerInfoStore : NSObject
- (instancetype)initWithPath:(nullable NSString*)path; ///< Designated initializer. \param path identifies the location to find/store archived data if non-nil; otherwise a default path is used, which on iOS is file AD.dat in the app's Documents directory, and on OSX is the file AD.dat in ~/Library/Application Support/<bundle id>.
@property (nonatomic, strong, readonly) NSString* path; ///< \returns the path to which data is archived.
@property (nonatomic, copy) NSArray<OBPServerInfo*>*_Nonnull entries; ///< set synchronously writes the supplied entries to an archive at .path, while get synchronously reads and restores entries from the archive at .path.
@end



NS_ASSUME_NONNULL_END
