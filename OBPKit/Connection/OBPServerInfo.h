//
//  OBPServerInfo.h
//  OBPKit
//
//  Created by Torsten Louland on 23/01/2016.
//  Copyright (c) 2016-2017 TESOBE Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>



NS_ASSUME_NONNULL_BEGIN



@class OBPServerInfo;
typedef NSArray<OBPServerInfo*> OBPServerInfoArray;



// Keys for values in the dictionary returned by -[OBPServerInfo data]
extern NSString* const OBPServerInfo_APIServer;			// e.g. https://apisandbox.openbankproject.com
extern NSString* const OBPServerInfo_APIVersion;		// e.g. v1.1
extern NSString* const OBPServerInfo_APIBase;			// e.g. https://apisandbox.openbankproject.com/obp/v1.1
extern NSString* const OBPServerInfo_AuthServerBase;	// e.g. https://apisandbox.openbankproject.com
extern NSString* const OBPServerInfo_RequestPath;		// default: /oauth/initiate
extern NSString* const OBPServerInfo_GetUserAuthPath;	// default: /oauth/authorize
extern NSString* const OBPServerInfo_GetTokenPath;		// default: /oauth/token
extern NSString* const OBPServerInfo_ClientKey;			// (aka Consumer Key)
extern NSString* const OBPServerInfo_ClientSecret;		// (aka Consumer Key)
extern NSString* const OBPServerInfo_TokenKey;			// (aka AccessToken)
extern NSString* const OBPServerInfo_TokenSecret;		// (aka AccessSecret)



/**
OBPServerInfo

An instance records the data necessary to access an OBP server, storing keys and secrets securely in the key chain.

The class keeps a persistent record of all complete instances. An instance is complete once its client key and secret have been set. You can get an instance for a new APIServer by asking the class to add an entry for that API server.


*/
@interface OBPServerInfo : NSObject <NSSecureCoding>
+ (nullable instancetype)addEntryForAPIServer:(NSString*)APIServer; ///< add a new instance for accessing the OBP server at url APIServer to the instance recorded by the class. \param APIServer identifies the server through a valid url string, giving scheme, host and optionally the path to the API base including API version path component. \return the new instance. \note If you pass in the API base url, the API server and version will be extracted and set. \note You can have more than one instance for the same server, typically for use with different user logins, and they are differentiated by the unique key property; for user interface, you can differentiate them using the name property.
+ (nullable OBPServerInfo*)firstEntryForAPIServer:(NSString*)APIServer; ///< Finds and returns the first entry matching APIServer. \param APIServer identifies the server through a valid url string, giving scheme, host and optionally the path to the API base including API version path component.
+ (nullable OBPServerInfo*)defaultEntry; ///< returns the first entry. This will be the oldest instance still held. (Convenience when using only a single entry.)
+ (OBPServerInfoArray*)entries;
+ (void)removeEntry:(OBPServerInfo*)entry;

@property (nonatomic, copy, null_resettable) NSString* name; ///< A differentiating name for use in user interface; set to the API host by default
@property (nonatomic, strong, readonly) NSString* APIServer; ///< url string for the API server
@property (nonatomic, strong, readonly) NSString* APIVersion; ///< string for the version of the API to use
@property (nonatomic, strong, readonly) NSString* APIBase; ///< base url for API calls, formed using the APIServer and APIVersion properties
@property (nonatomic, copy) NSDictionary* accessData; ///< Get/set access data. \note When getting data, the returned dictionary contains values for _all_ the OBPServerInfo_<xxx> keys defined in OBPServerInfo.h, with derived and default values filled in as necessary. \note When setting data, _only_ the values for the OBPServerInfo_<xxx> keys defined in OBPServerInfo.h are copied, while other values held are left unchanged. \note The API host is never changed after the instance has been created, regardless of values passed in for the keys OBPServerInfo_APIServer and OBPServerInfo_APIBase, and the client key and secret are not changeable once set.
@property (nonatomic, copy, nullable) NSDictionary* appData; ///< Get/set general data associated with this server for use by the host app. Persisted. Contents must conform to NSSecureCoding.
@property (readonly) BOOL usable; ///< returns YES when entry has credentials to request access (client key and secret).
@property (readonly) BOOL inUse; ///< returns YES when entry has credentials to access user's data (token key and secret).
@end
/*
Note: Keychain authorisations on OSX during development.
-	An OBPServerInfo instance stores credentials in keychain items.
	-	On iOS the items can only be accessed by the iOS app and no others, and asking the user for permission is never needed.
	-	On OSX the items can be accessed by trusted applications.
		-	Each keychain item has an access object containing one or more Access Control Lists, and each ACL contains one or more tags that authorise kinds of operations plus a list of zero or more trusted applications, hence an ACL authorises its trusted applications to perform its tagged operation kinds without further need to request permission from the user.
		-	The application that creates a keychain item is automatically added as an application that is trusted to read the item, via the item's ACLs.
		-	However, when you rebuild the application during development, its identifying information (size, dates, content digest, etc.) changes, the trusted application reference in the ACL will not match the new build, and the user is always asked to give permission. This is an inconvenience during development, but does not happen during production, as the app store installer takes care of updating trusted application references. For more information see [Trusted Applications](https://developer.apple.com/library/mac/documentation/Security/Conceptual/keychainServConcepts/02concepts/concepts.html#//apple_ref/doc/uid/TP30000897-CH204-SW5).
*/



/**
OBPServerInfoCustomise allows you to change or replace OBPServerInfo behaviours.
	
You can optionally customise any of: instance class, save & load blocks, credential encrypt and decrypt blocks, and/or credential encrypt and decrypt parameters. Just call OBPServerInfoCustomise with a dictionary of customisation information. OBPServerInfoCustomise must be called before +[OBPServerInfo initialize] has been invoked, and once only; other calls are ignored. Values in `config` can be as follows:

	-	config[OBPServerInfoConfig_DataClass] gives the subclass of OBPServerInfo to instantiate (OBPServerInfo if absent);

	-	config[OBPServerInfoConfig_StoreClass] gives the subclass of OBPServerInfoStore to instantiate (OBPServerInfoStore if absent);

	-	config[OBPServerInfoConfig_LoadBlock] and config[OBPServerInfoConfig_SaveBlock] give the blocks to invoke to load entries from and save entries to persistent storage (if less than both are supplied then an OBPServerInfoStore instance is used);

	-	config[OBPServerInfoConfig_ClientCredentialEncryptBlock] gives a block to encrypt the client credentials before storage into the keychain;

	-	config[OBPServerInfoConfig_ClientCredentialDecryptBlock] gives a block to decrypt the client credentials after retrieval from the keychain;

	-	config[OBPServerInfoConfig_ProvideCryptParamsBlock] gives a block to provide parameters for encryption of the client credentials while stored in the keychain; at a minimum, the encryption key and initialisation vector, but a non-default encryption algorithm can also be selected. It is ignored if both a client credential encryption and decryption block is present. Encryption is advisable on OSX because retrieval of the client key and secret via the Key Chain Access application needs just the account login, so another unscrupulous developer could easily download your app and obtain your client key and secret; this problem does not arise on iOS. See also comment describing OBPProvideCryptParamsBlock.

\note By default OBPServerInfo uses DES encryption (very weak), as DES seems to be the strongest encryption (!) that can gain an exemption from some of the export certification process that is oblogatory for all apps that are distributed through the AppStore. You should consider using stronger encryption in your production app, but you will then also need to get export certification from Apple in order to ship your app — you will need to comply with the requirements for "trade compliance" in iTunes Connect.
*/
void OBPServerInfoCustomise(NSDictionary* config);

     // types for customise config dict values
typedef OBPServerInfoArray*_Nonnull	(^OBPServerInfoLoadBlock)(void);
typedef void						(^OBPServerInfoSaveBlock)(OBPServerInfoArray* entries);
typedef NSString*_Nonnull			(^OBPClientCredentialCryptBlock)(NSString* _Nonnull credential); // (credential)
typedef struct OBPCryptParams {
	uint32_t algorithm; uint32_t options; size_t keySize, blockSize; uint8_t *key, *iv;
} OBPCryptParams;
typedef void						(^OBPProvideCryptParamsBlock)(OBPCryptParams* ioParams, size_t maxKeySize, size_t maxIVSize); ///< Provide encryption/decryption parameters. When called, *ioParams has working values for all but *key and *iv (initialisation vector). At a minimum, copy your cryptographic key into *(ioParams->key); it is also good practice to copy an initialisation vector into *(ioParams->iv), and this must always be the same length as ioParams->blockSize. Run the GenerateKey target of OBPKit once to generate a file with random byte sequences for use as keys and initialisation vectors, which you can then copy into your project. You can also change the encryption algorithm using values defined in CCAlgorithm in CommonCrypto.h, in which case you must also set compatible key and block sizes as also defined in CommonCrypto.h, and options if appropriate (CCOPtions). Note that anything stronger than DES will require your app to have an export certificate. Parameters maxKeySize and maxIVSize and give the amount of storage pointed to by ioParams->key and ioParams->iv, which should be sufficient for all the algorithm types provided by CommonCrypto.h; if you need more, then point them at your own non-volatile storage.

     // keys for customise confi                                    value type
#define OBPServerInfoConfig_DataClass                    @"dc"   // NSString with class name
#define OBPServerInfoConfig_StoreClass                   @"sc"   // NSString with class name
#define OBPServerInfoConfig_LoadBlock                    @"lb"   // OBPServerInfoLoadBlock
#define OBPServerInfoConfig_SaveBlock                    @"sb"   // OBPServerInfoSaveBlock
#define OBPServerInfoConfig_ClientCredentialEncryptBlock @"eb"   // OBPClientCredentialCryptBlock
#define OBPServerInfoConfig_ClientCredentialDecryptBlock @"db"   // OBPClientCredentialCryptBlock
#define OBPServerInfoConfig_ProvideCryptParamsBlock      @"pp"   // OBPProvideCryptParamsBlock

#define kOBPClientCredentialCryptAlg                     kCCAlgorithmDES
#define kOBPClientCredentialCryptKeyLen                  kCCKeySizeDES
#define kOBPClientCredentialCryptIVLen                   kCCBlockSizeDES
#define kOBPClientCredentialCryptBlockLen                kCCBlockSizeDES
	// ...see notes above at reason for DES.

#define kOBPClientCredentialMaxCryptKeyLen               kCCKeySizeMaxRC4
#define kOBPClientCredentialMaxCryptBlockLen             kCCBlockSizeAES128
	// ...limits for buffer sizes




NS_ASSUME_NONNULL_END


