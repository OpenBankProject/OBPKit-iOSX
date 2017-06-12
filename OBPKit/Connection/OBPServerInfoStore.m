//
//  OBPServerInfoStore.m
//  OBPKit
//
//  Created by Torsten Louland on 15/03/2016.
//  Copyright (c) 2016-2017 TESOBE Ltd. All rights reserved.
//

#import "OBPServerInfoStore.h"
#import "OBPServerInfo.h"



@implementation OBPServerInfoStore
{
	NSString*			_path;
}
- (instancetype)initWithPath:(nullable NSString*)path
{
	self = [super init];
	if (self)
		_path = path ?: [self defaultPath];
	return self;
}
- (NSString*)defaultPath
{
	#define kServerInfoFileName @"SI.dat"
	NSString*		name;
	NSString*		path;
	name = [NSBundle mainBundle].bundleIdentifier;
#if TARGET_OS_IPHONE
	path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
	name = [name stringByAppendingString: @"." kServerInfoFileName];
#else
	path = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)[0];
	path = [path stringByAppendingPathComponent: name];
	name = kServerInfoFileName;
	[[NSFileManager defaultManager] createDirectoryAtPath: path
							  withIntermediateDirectories: YES
									attributes: nil error: NULL];
#endif
	path = [path stringByAppendingPathComponent: name];
	return path;
}
- (void)setEntries:(OBPServerInfoArray*)entries
{
	OBPServerInfoArray* a = [entries copy];
	[NSKeyedArchiver archiveRootObject: a toFile: _path];
}
- (OBPServerInfoArray*)entries
{
	return [NSKeyedUnarchiver unarchiveObjectWithFile: _path] ?: @[];
}
@end
