//
//  main.m
//  GenerateKey
//
//  Created by Torsten Louland on 17/03/2016.
//  Copyright © 2016 TESOBE Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonCrypto.h>
#include <CommonCrypto/CommonRandom.h>
#import "OBPServerInfo.h"



/** GenerateKey

Utility function to generate a text file defining random bytes for inclusion in source code, for eventual use as a symmetric encryption key and initialisation vector. The amount of bytes generated are more than needed for most encryption algorhythms - just use the number of bytes that are necessary for your choice of encryption algorithm.

Typical file content:

	#define KEY_LEN 16
	#define KEY_BYTES 17, 255, 0, 33, ... 42, 176
	#define IV_LEN 16
	#define IV_BYTES 38, 187, 113, ... 46, 3

Example use in an OBPProvideCryptParamsBlock:

	OBPProvideCryptParamsBlock cb =
		^void(OBPCryptParams* ioParams, size_t keySizeMax, size_t ivSizeMax)
		{
			#include "KeyDef.h"

			enum			{kKeyLen = KEY_LEN, kIVLen = IV_LEN};
			const uint8_t	key[kKeyLen] = {KEY_BYTES};
			const uint8_t	iv[kIVLen] = {IV_BYTES};

			#undef KEY_LEN
			#undef KEY_BYTES
			#undef IV_LEN
			#undef IV_BYTES

			// ...now make use of key and iv by copying as many bytes as you need for specific algorithm...

			if (ioParams && ioParams->key)
			{
				size_t len = MIN(MIN(kKeyLen, ioParams->keySize), keySizeMax);
				memcpy(ioParams->key, key, len);
				ioParams->keySize = len;
			}

			if (ioParams && ioParams->iv)
			{
				size_t len = MIN(MIN(kIVLen, ioParams->blockSize), ivSizeMax);
				memcpy(ioParams->iv, iv, len);
				ioParams->blockSize = len;
			}
		};

*/
void GenerateKey()
{
	enum {
		kKeyLenMax = 64, // kOBPClientCredentialMaxCryptKeyLen,
		// ...64 is enough for all but RC2 max and RC4 max.
		kIVLenMax = kOBPClientCredentialMaxCryptBlockLen,
		kBufLen = kKeyLenMax + kIVLenMax,
		kShortsInNSTimeInterval = sizeof(NSTimeInterval)/sizeof(uint16_t),
	};
	union {
		NSTimeInterval	ti;
		uint16_t		shorts[kShortsInNSTimeInterval];
	}					now;
	char				buf[kBufLen];
	const char*			sep;
	uint16_t			n;
	NSMutableString*	ms;
	NSString*			path;

	// Discard a variable number of bytes from pseudo-random sequence
	now.ti = [NSDate timeIntervalSinceReferenceDate];
	n = (now.shorts[0] ^ now.shorts[kShortsInNSTimeInterval-1]) / kBufLen;
	while (n--)
		CCRandomGenerateBytes(buf, kBufLen);
	n = (now.shorts[0] ^ now.shorts[kShortsInNSTimeInterval-1]) % kBufLen;
	if (n)
		CCRandomGenerateBytes(buf, n);

	// Get random bytes to use for key
	CCRandomGenerateBytes(buf, kKeyLenMax);

	// Skip some more
	n = (now.shorts[0] ^ now.shorts[kShortsInNSTimeInterval-1]) / kBufLen;
	while (n--)
		CCRandomGenerateBytes(buf, kBufLen);
	n = (now.shorts[0] ^ now.shorts[kShortsInNSTimeInterval-1]) % kBufLen;
	if (n)
		CCRandomGenerateBytes(buf, n);

	// Get random bytes to use for IV
	CCRandomGenerateBytes(buf+kKeyLenMax, kIVLenMax);

	// Format for storage
	ms = [NSMutableString string];
	[ms appendFormat: @"#define KEY_LEN %d\n", kKeyLenMax];
	for (n = 0, sep = "#define KEY_BYTES "; n < kKeyLenMax; n++, sep = ", ")
		[ms appendFormat: @"%s%u", sep, (unsigned char)buf[n]];
	[ms appendFormat: @"\n#define IV_LEN %d\n", kIVLenMax];
	for (sep = "#define IV_BYTES "; n < kBufLen; n++, sep = ", ")
		[ms appendFormat: @"%s%u", sep, (unsigned char)buf[n]];
	[ms appendString: @"\n"];

	// Write to ~/Desktop/KeyDef.h
	path = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES)[0];
	path = [path stringByAppendingPathComponent: @"KeyDef.h"];
	[ms writeToFile: path atomically: YES encoding: NSUTF8StringEncoding error: NULL];
}

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		GenerateKey();
	}
    return 0;
}
