//
//  OBPServerInfo.m
//  OBPKit
//
//  Created by Torsten Louland on 23/01/2016.
//  Copyright © 2016 TESOBE Ltd. All rights reserved.
//

#import "OBPServerInfo.h"
// sdk
#import <objc/runtime.h>
#import <CommonCrypto/CommonCrypto.h>
// ext
#import <UICKeyChainStore/UICKeyChainStore.h>
// prj
#import "OBPServerInfoStore.h"
#import "OBPLogging.h"



#define KEY_SEP @"|"
typedef NS_ENUM(uint8_t, EPair) {ePair_ClientKeyAndSecret, ePair_TokenKeyAndSecret};
#define ClientKeyAndSecretKCAccount @"0"
#define TokenKeyAndSecretKCAccount @"1"



NSString* const OBPServerInfo_APIBase			= @"APIBase";
NSString* const OBPServerInfo_APIServer			= @"APIServer";
NSString* const OBPServerInfo_APIVersion		= @"APIVersion";
NSString* const OBPServerInfo_AuthServerBase	= @"AuthServerBase";
NSString* const OBPServerInfo_RequestPath		= @"RequestPath";
NSString* const OBPServerInfo_GetUserAuthPath	= @"GetUserAuthPath";
NSString* const OBPServerInfo_GetTokenPath		= @"GetTokenPath";
NSString* const OBPServerInfo_ClientKey			= @"ClientKey";			// aka Consumer Key
NSString* const OBPServerInfo_ClientSecret		= @"ClientSecret";		// aka Consumer Key
NSString* const OBPServerInfo_TokenKey			= @"TokenKey";			// aka AccessToken
NSString* const OBPServerInfo_TokenSecret		= @"TokenSecret";		// aka AccessSecret



static NSDictionary* gOBPServerInfo = nil;
#define gOBPServerInfoKey_InstanceClass @"class"
#define gOBPServerInfoKey_Store @"store"
#define gOBPServerInfoKey_LoadBlock @"load"
#define gOBPServerInfoKey_SaveBlock @"save"
#define gOBPServerInfoKey_EncryptBlock @"+"
#define gOBPServerInfoKey_DecryptBlock @"-"
#define gOBPServerInfoKey_EntriesArrayHolder @"holder"

void OBPServerInfoCustomise(NSDictionary* config)
{
	if (config == nil || gOBPServerInfo != nil)
		return;

	NSMutableDictionary*	md = [config mutableCopy];
	Class					defClass, useClass, c;
	NSString*				s;

	//	Reject invalid parameters and normalise (while being careful not to trigger +[OBPServerInfo initialize] before we have finished)

	//	1. OBPServerInfo subclass
	defClass = objc_getClass("OBPServerInfo");
	s = config[OBPServerInfoConfig_DataClass];
	useClass = s ? objc_getClass([s UTF8String]) : Nil;
	for (c = useClass; c != Nil; c = class_getSuperclass(c))
		if (c == defClass)
			break;
	if (c == Nil)
		s = @"OBPServerInfo";
	md[OBPServerInfoConfig_DataClass] = s;

	//	2. OBPServerInfoStore subclass
	defClass = objc_getClass("OBPServerInfoStore");
	s = config[OBPServerInfoConfig_StoreClass];
	useClass = s ? objc_getClass([s UTF8String]) : Nil;
	for (c = useClass; c != Nil; c = class_getSuperclass(c))
		if (c == defClass)
			break;
	if (c == Nil)
		s = @"OBPServerInfoStore";
	md[OBPServerInfoConfig_StoreClass] = s;

	//	3. Load and Save Block (require both or none)
	if (!config[OBPServerInfoConfig_LoadBlock]
	  ^ !config[OBPServerInfoConfig_SaveBlock])
	{
		[md removeObjectForKey: OBPServerInfoConfig_LoadBlock];
		[md removeObjectForKey: OBPServerInfoConfig_SaveBlock];
	}

	//	4. Encrypt & Decrypt blocks (require both or none)
	if (!config[OBPServerInfoConfig_ClientCredentialEncryptBlock]
	  ^ !config[OBPServerInfoConfig_ClientCredentialDecryptBlock])
	{
		[md removeObjectForKey: OBPServerInfoConfig_ClientCredentialEncryptBlock];
		[md removeObjectForKey: OBPServerInfoConfig_ClientCredentialDecryptBlock];
	}

	//	5. Only allow encryption param provider if custom enc/decryption not provided
	if (config[OBPServerInfoConfig_ClientCredentialEncryptBlock]
	 && config[OBPServerInfoConfig_ClientCredentialDecryptBlock])
		[md removeObjectForKey: OBPServerInfoConfig_ProvideCryptParamsBlock];

	gOBPServerInfo = [md copy];
}



OBPClientCredentialCryptBlock
	MakeCryptBlockUsingParamsProvider(
		OBPProvideCryptParamsBlock provideParams,
		CCOperation op)
{
	if (provideParams == nil)
		return nil;

	OBPClientCredentialCryptBlock cb =
		^NSString*(NSString* credential)
		{
			if (![credential length])
				return credential;

			enum {
				kKeyStoreMax = kOBPClientCredentialMaxCryptKeyLen * 2,
				kIVStoreMax = kOBPClientCredentialMaxCryptBlockLen * 2,
				kStackStoreSize = kOBPClientCredentialMaxCryptBlockLen * 8
			};

			uint8_t					stackStore[kStackStoreSize];
			uint8_t*				buf = stackStore;
			size_t					bufSize = kStackStoreSize, bufSizeMin;
			size_t					inputLen, outputLen;
			NSString*				transformed = credential;
			NSData*					data;
			uint8_t					keyStore[kKeyStoreMax];
			uint8_t					ivStore[kIVStoreMax]; // initialization vector store

			OBPCryptParams			params = {
				.algorithm	= kOBPClientCredentialCryptAlg,
				.options	= 0,
				.keySize	= kOBPClientCredentialCryptKeyLen,
				.blockSize	= kOBPClientCredentialCryptBlockLen,
				.key		= keyStore,
				.iv			= ivStore
			};

			memset(keyStore, 0, kKeyStoreMax);
			memset(ivStore, 0, kIVStoreMax);
			provideParams(&params, kKeyStoreMax, kIVStoreMax);

			if (op == kCCDecrypt)
				data = [[NSData alloc] initWithBase64EncodedString: credential options: 0];
			else
				data = [credential dataUsingEncoding: NSUTF8StringEncoding];
			inputLen = [data length];

			bufSizeMin = (inputLen / params.blockSize + 2) * params.blockSize;
			if (bufSize < bufSizeMin)
				buf = malloc(bufSize = bufSizeMin);
			memcpy(buf, [data bytes], inputLen);
			memset(buf + inputLen, 0, bufSize - inputLen);
			// ...after zeroing remaining buf space, we always need to bump input length up to the
			// next multiple of the encryption block size...
			inputLen = (inputLen + params.blockSize - 1) / params.blockSize * params.blockSize;

			CCCryptorStatus status =
				CCCrypt(
					op,						// kCCEncrypt or kCCDecrypt
					params.algorithm,		// AES, DES, RCA, etc.
					params.options,			// CCOptions: kCCOptionPKCS7Padding, ...
					params.key,
					params.keySize,
					params.iv,				// initialization vector, optional
					buf,					// dataIn, optional per op and alg
					inputLen,				// dataInLength
					buf,					// dataOut (can be transformed in place)
					bufSize,				// dataOutAvailable
					&outputLen);			// dataOutMoved

			if (outputLen < bufSize)
				buf[outputLen] = 0;

			if (status == kCCSuccess)
				transformed = op == kCCEncrypt
							? [[NSData dataWithBytes: buf length: outputLen] base64EncodedStringWithOptions: 0]
							: [NSString stringWithUTF8String: (char*)buf];

			if (buf != stackStore)
				free(buf);

			return transformed;
		};
	return cb;
}



#pragma mark -
@interface OBPServerInfo ()
{
	NSString*		_key;
	NSString*		_name;
	NSString*		_APIServer;
	NSString*		_APIVersion;
	NSString*		_APIBase;
	NSDictionary*	_AuthServerDict;
	NSDictionary*	_cache;
	NSDictionary*	_appData;

	BOOL			_usable;
	BOOL			_inUse;
}
@property (nonatomic, strong) UICKeyChainStore* keyChainStore;
@end



#pragma mark -
@implementation OBPServerInfo
+ (void)initialize
{
	if (self != [OBPServerInfo class])
		return;

	// 1. Set up valid class configuration data in gOBPServerInfo, deriving from customisation data if supplied
	NSMutableDictionary*			md;
	NSString*						className;
	Class							class;
	OBPServerInfoStore*				store;
	OBPServerInfoLoadBlock			loadBlock;
	OBPServerInfoSaveBlock			saveBlock;
	OBPClientCredentialCryptBlock	encryptBlock;
	OBPClientCredentialCryptBlock	decryptBlock;
	OBPProvideCryptParamsBlock		provideCryptParams;

	if (gOBPServerInfo == nil)
		gOBPServerInfo = @{};
	md = [NSMutableDictionary dictionary];

	className = gOBPServerInfo[OBPServerInfoConfig_DataClass] ?: @"OBPServerInfo";
	class = NSClassFromString(className);
	md[gOBPServerInfoKey_InstanceClass] = class;

	className = gOBPServerInfo[OBPServerInfoConfig_StoreClass] ?: @"OBPServerInfoStore";
	class = NSClassFromString(className);
	store = [class alloc];
	store = [store initWithPath: nil];
	md[gOBPServerInfoKey_Store] = store;

	loadBlock = gOBPServerInfo[OBPServerInfoConfig_LoadBlock];
	if (loadBlock == nil)
		loadBlock = ^(){return store.entries;};
	md[gOBPServerInfoKey_LoadBlock] = loadBlock;

	saveBlock = gOBPServerInfo[OBPServerInfoConfig_SaveBlock];
	if (saveBlock == nil)
		saveBlock = ^(OBPServerInfoArray* entries){store.entries = entries;};
	md[gOBPServerInfoKey_SaveBlock] = saveBlock;

	encryptBlock = gOBPServerInfo[OBPServerInfoConfig_ClientCredentialEncryptBlock];
	decryptBlock = gOBPServerInfo[OBPServerInfoConfig_ClientCredentialDecryptBlock];
	if (!encryptBlock || !decryptBlock)
	{
		provideCryptParams = gOBPServerInfo[OBPServerInfoConfig_ProvideCryptParamsBlock];
		if (provideCryptParams)
		{
			encryptBlock = MakeCryptBlockUsingParamsProvider(provideCryptParams, kCCEncrypt);
			decryptBlock = MakeCryptBlockUsingParamsProvider(provideCryptParams, kCCDecrypt);
		}
		else
		{
			encryptBlock = ^(NSString* s){return s;};
			decryptBlock = ^(NSString* s){return s;};
		}
	}
	md[gOBPServerInfoKey_EncryptBlock] = encryptBlock;
	md[gOBPServerInfoKey_DecryptBlock] = decryptBlock;

	md[gOBPServerInfoKey_EntriesArrayHolder] = [NSMutableArray arrayWithObject: @[]];

	gOBPServerInfo = [md copy];

	//	2. Load entries
	OBPServerInfoArray* entries = loadBlock();
	NSMutableArray*		ma = [NSMutableArray array];
	//	Copy valid entries, i.e. keychain still contains corresponding credentials, and remove if not so. (On Mac user can delete keychain items.)
	for (OBPServerInfo* entry in entries)
		if ([entry checkValid])
			[ma addObject: entry];
		else
			OBP_LOG(@"Ignoring invalid entry %@", entry);
	gOBPServerInfo[gOBPServerInfoKey_EntriesArrayHolder][0] = [ma copy];
}
+ (OBPServerInfoArray*)entries
{
	return gOBPServerInfo[gOBPServerInfoKey_EntriesArrayHolder][0];
}
+ (void)save
{
	static BOOL savePending = NO;
	if (savePending)
		return;
	savePending = YES;
	dispatch_async(dispatch_get_main_queue(),
		^{
			savePending = NO;
			NSMutableArray* ma = [NSMutableArray array];
			for (OBPServerInfo* entry in [self entries])
			if (entry.usable)
				[ma addObject:entry];
			OBPServerInfoSaveBlock saveBlock = gOBPServerInfo[gOBPServerInfoKey_SaveBlock];
			saveBlock(ma);
		}
	);
}
+ (instancetype)defaultEntry
{
	OBPServerInfo* entry = [[self entries] firstObject];
	return entry;
}
+ (void)removeEntry:(OBPServerInfo*)entry
{
	if (!entry)
		return;
	NSUInteger index = [[self entries] indexOfObjectIdenticalTo: entry];
	if (index != NSNotFound)
	{
		NSMutableArray* ma = [[self entries] mutableCopy];
		[ma removeObjectIdenticalTo: entry];
		gOBPServerInfo[gOBPServerInfoKey_EntriesArrayHolder][0] = [ma copy];
		[entry storePair: ePair_ClientKeyAndSecret from: @{}];
		[entry storePair: ePair_TokenKeyAndSecret from: @{}];
		entry.keyChainStore = nil;
		if (entry.usable)
			[self save];
	}
}
+ (instancetype)addEntryForAPIServer:(NSString*)APIServer
{
	if (![APIServer length])
		return nil;
	NSURLComponents* components = [NSURLComponents componentsWithString: APIServer];
	OBP_LOG_IF(nil==components, @"[OBPServerInfo addEntryForAPIServer: %@] - error: not valid as a URL", APIServer);
	if (nil==components)
		return nil;
	NSString* key = [[NSUUID UUID] UUIDString];
	Class class;
	OBPServerInfo* entry;
	class = gOBPServerInfo[gOBPServerInfoKey_InstanceClass];
	entry = [class alloc];
	entry = [entry initWithKey: key APIServerURLComponents: components];
	gOBPServerInfo[gOBPServerInfoKey_EntriesArrayHolder][0] = [[self entries] arrayByAddingObject: entry];
	// ...save is only scheduled once the entry's data has been assigned and checked
	return entry;
}
+ (nullable OBPServerInfo*)firstEntryForAPIServer:(NSString*)APIServer
{
	if (![APIServer length])
		return nil;
	OBPServerInfo*		entry;
	NSURLComponents*	components;
	NSString*			matchVersion;
	NSString*			matchServer;
	components = [NSURLComponents componentsWithString: APIServer];
	matchVersion = [self versionFromOBPPath: components.path];
	components.path = nil;
	matchServer = components.string;
	for (entry in [self entries])
	{
		if ([matchServer isEqualToString: entry->_APIServer])
		if (!matchVersion || [matchVersion isEqualToString: entry->_APIVersion])
			return entry;
	}
	return nil;
}
#pragma mark -
+ (NSString*)versionFromOBPPath:(NSString*)path
{
	if (!path)
		return nil;
	NSRange		rangeOBP;
	NSRange		rangeEnd;

	if ((rangeOBP = [path rangeOfString: @"obp/v"]).length)
	{
		path = [path substringFromIndex: rangeOBP.location + rangeOBP.length - 1];
		rangeEnd = [path rangeOfString: @"/"];
		if (rangeEnd.length)
			path = [path substringToIndex: rangeEnd.location];
		return path;
	}
	return nil;
}
+ (NSString*)APIBaseForServer:(NSString*)server andAPIVersion:(NSString*)version
{
	if (![server length] || ![version length])
		return nil;
	NSURLComponents* components;
	NSString* base;
	components = [NSURLComponents componentsWithString: server];
	components.path = [@"/obp/" stringByAppendingString: version];
	base = components.string;
	return base;
}
#pragma mark -
- (instancetype)initWithKey:(NSString*)key APIServerURLComponents:(NSURLComponents*)components
{
	if (nil == (self = [super init]))
		return nil;
	_key = key;
	_name = components.host;
	_APIVersion = [[self class] versionFromOBPPath: components.path] ?: @"v1.2";
	components.path = nil;
	_APIServer = components.string;
	_APIBase = [[self class] APIBaseForServer: _APIServer andAPIVersion: _APIVersion];
	_AuthServerDict = @{
		OBPServerInfo_AuthServerBase	:	_APIServer,
		OBPServerInfo_RequestPath		:	@"/oauth/initiate",
		OBPServerInfo_GetUserAuthPath	:	@"/oauth/authorize",
		OBPServerInfo_GetTokenPath		:	@"/oauth/token",
	};
	return self;
}
+ (BOOL)supportsSecureCoding
{
	return YES; // ==> -initWithCoder: always uses -[NSCoder decodeObjectOfClass:forKey:]
}
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
	if (nil == (self = [super init]))
		return nil;
	Class classNSString = [NSString class];
	_key = [aDecoder decodeObjectOfClass: classNSString forKey: @"key"];
	_name = [aDecoder decodeObjectOfClass: classNSString forKey: @"name"];
	_APIServer = [aDecoder decodeObjectOfClass: classNSString forKey: @"APIServer"];
	_APIVersion = [aDecoder decodeObjectOfClass: classNSString forKey: @"APIVersion"];
	_APIBase = [aDecoder decodeObjectOfClass: classNSString forKey: @"APIBase"];
	_AuthServerDict = [aDecoder decodeObjectOfClass: [NSDictionary class] forKey: @"AuthServerDict"];
	if ([aDecoder containsValueForKey: @"appData"])
		_appData = [aDecoder decodeObjectOfClass: [NSDictionary class] forKey: @"appData"];
	return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
	[aCoder encodeObject: _key forKey: @"key"];
	[aCoder encodeObject: _name forKey: @"name"];
	[aCoder encodeObject: _APIServer forKey: @"APIServer"];
	[aCoder encodeObject: _APIVersion forKey: @"APIVersion"];
	[aCoder encodeObject: _APIBase forKey: @"APIBase"];
	[aCoder encodeObject: _AuthServerDict forKey: @"AuthServerDict"];
	if (_appData)
		[aCoder encodeObject: _appData forKey: @"appData"];
}
- (void)save
{
	if (_usable)
		[[self class] save];
}
#pragma mark -
- (UICKeyChainStore*)keyChainStore
{
	if (_keyChainStore == nil)
	{
		_keyChainStore = [UICKeyChainStore keyChainStoreWithService: _key];
		_keyChainStore.accessibility = UICKeyChainStoreAccessibilityAlways;
	}
	return _keyChainStore;
}
- (void)fetchPair:(EPair)whichPair into:(NSMutableDictionary*)md
{
	BOOL				client = whichPair == ePair_ClientKeyAndSecret;
	NSString*			(^decrypt)(NSString*s) =
							  client
							? (OBPClientCredentialCryptBlock)gOBPServerInfo[gOBPServerInfoKey_DecryptBlock]
							: ^(NSString*s){return s;};
	NSString*			key = client ? ClientKeyAndSecretKCAccount : TokenKeyAndSecretKCAccount;
	NSString*			value;
	NSArray*			pair;

	if ((_cache && nil != (value = _cache[key]))
	 || nil != (value = decrypt(self.keyChainStore[key])))
	if (nil != (pair = [value componentsSeparatedByString: KEY_SEP]))
	if (2 == [pair count])
	{
		md[client ? OBPServerInfo_ClientKey : OBPServerInfo_TokenKey]		= pair[0];
		md[client ? OBPServerInfo_ClientSecret : OBPServerInfo_TokenSecret]	= pair[1];

		if (!_cache || ![_cache[key] isEqual: value])
		{
			NSMutableDictionary* cache = [(_cache ?: @{}) mutableCopy];
			cache[key] = value;
			_cache = [cache copy];
		}
	}
}
- (void)storePair:(EPair)whichPair from:(NSDictionary*)d
{
	BOOL				client = whichPair == ePair_ClientKeyAndSecret;
	NSString*			(^encrypt)(NSString*s) =
							  client
							? (OBPClientCredentialCryptBlock)gOBPServerInfo[gOBPServerInfoKey_EncryptBlock]
							: ^(NSString*s){return s;};
	NSString*			s0 = d[client ? OBPServerInfo_ClientKey : OBPServerInfo_TokenKey];
	NSString*			s1 = d[client ? OBPServerInfo_ClientSecret : OBPServerInfo_TokenSecret];
	NSString*			key = client ? ClientKeyAndSecretKCAccount : TokenKeyAndSecretKCAccount;
	NSString*			valueCached = _cache ? _cache[key] : nil;
	NSString*			value = [s0 length] && [s1 length]
							  ? [s0 stringByAppendingFormat: @"%@%@", KEY_SEP, s1]
							  : nil;

	if (!_cache															// no cache => update
	 || !(value ? [valueCached isEqualToString: value] : !valueCached))	// change => update
	{
		self.keyChainStore[key] = value ? encrypt(value) : nil;
		NSMutableDictionary* md = [(_cache ?: @{}) mutableCopy];
		md[key] = value ?: @"";
		_cache = [md copy];
	}

	if (client)
		_usable = nil != value;
	else
		_inUse = nil != value;
}
#pragma mark -
- (void)setAccessData:(NSDictionary*)data
{
	if (nil == data)
		return;
	BOOL			changed = NO;
	BOOL			changedToken = NO;
	NSString*		APIVersion = nil;
	NSString		*s0, *s1, *k;

	// Check for API version either explicitly or within API base
	if ([(s0 = data[OBPServerInfo_APIVersion]) length])
		APIVersion = s0;
	else
	if ([(s0 = data[OBPServerInfo_APIBase]) length])
	if (![s0 isEqualToString: _APIBase])
		APIVersion = s0.lastPathComponent;

	// Check if API version is changed
	if (APIVersion && ![APIVersion isEqualToString: _APIVersion])
	{
		_APIVersion = APIVersion;
		_APIBase = [[self class] APIBaseForServer: _APIServer andAPIVersion: _APIVersion];
		changed = YES;
	}

	// For Auth server base and paths, check for and apply any new non-empty values
	NSMutableDictionary* md = [_AuthServerDict mutableCopy];
	for (k in @[OBPServerInfo_AuthServerBase, OBPServerInfo_RequestPath,
				OBPServerInfo_GetUserAuthPath, OBPServerInfo_GetTokenPath])
	{
		if ([(s0 = data[k]) length])
		if (![(s1 = md[k]) isEqualToString: s0])
			md[k] = s0;
	}
	if (![_AuthServerDict isEqualToDictionary: md])
		_AuthServerDict = [md copy], changed = YES;

	// If any credentials have been supplied, check and store updates if necessary
	if (data[OBPServerInfo_ClientKey]
	 || data[OBPServerInfo_ClientSecret]
	 || data[OBPServerInfo_TokenKey]
	 || data[OBPServerInfo_TokenSecret])
	{
		// Fetch current credentials
		md = [NSMutableDictionary dictionary];
		[self fetchPair: ePair_ClientKeyAndSecret into: md];
		[self fetchPair: ePair_TokenKeyAndSecret into: md];

		// Set client key and secret if not already set
		int needed = 2;
		for (k in @[OBPServerInfo_ClientKey, OBPServerInfo_ClientSecret])
		{
			if ([(s0 = data[k]) length])
			if (![(s1 = md[k]) length])
				needed--;
		}
		if (needed == 0) // we have the key and secret, so save
			[self storePair: ePair_ClientKeyAndSecret from: data], _usable = YES, changed = YES;

		// Always update token key and secret, including setting to empty (==logged out or revoked access)
		changedToken = NO;
		for (k in @[OBPServerInfo_TokenKey, OBPServerInfo_TokenSecret])
		{
			if (nil != (s0 = data[k]))
			if (![(s1 = md[k]) isEqualToString: s0])
				changedToken = YES;
		}
		if (changedToken)
			[self storePair: ePair_TokenKeyAndSecret from: data];

		self.keyChainStore = nil;
	}

	if (changed)
		[self save];
}
- (NSDictionary*)accessData
{
	// load data from key chain and return (never store; we only store retrieval params)
	NSMutableDictionary*	md = [NSMutableDictionary dictionary];
	md[OBPServerInfo_APIServer] = _APIServer;
	md[OBPServerInfo_APIVersion] = _APIVersion;
	md[OBPServerInfo_APIBase] = _APIBase;
	[md addEntriesFromDictionary: _AuthServerDict];
	[self fetchPair: ePair_ClientKeyAndSecret into: md];
	[self fetchPair: ePair_TokenKeyAndSecret into: md];
	self.keyChainStore = nil;
	return [md copy];
}
- (BOOL)checkValid
{
	NSMutableDictionary* md;
	md = [NSMutableDictionary dictionary];
	[self fetchPair: ePair_ClientKeyAndSecret into: md];
	[self fetchPair: ePair_TokenKeyAndSecret into: md];
	_usable = [md[OBPServerInfo_ClientKey] length] && [md[OBPServerInfo_ClientSecret] length];
	_inUse = [md[OBPServerInfo_TokenKey] length] && [md[OBPServerInfo_TokenSecret] length];
	return _usable;
}
#pragma mark -
- (void)setAppData:(NSDictionary*)appData
{
	if (appData ? [_appData isEqualToDictionary: appData] : !_appData)
		return;
	_appData = [appData copy];
	[self save];
}
- (NSDictionary*)appData
{
	return _appData;
}
#pragma mark -
- (void)setName:(NSString*)name
{
	if (![name length])
		name = [NSURLComponents componentsWithString: _APIServer].host;
	if ([name isEqualToString: _name])
		return;
	_name = name;
	[self save];
}
@end


