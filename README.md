## OBPKit for OSX and iOS ![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)

TESOBE Ltd.


1.	[Overview](#overview)
1.	[Installation](#installation)
	1.	[Installation with Carthage](#installation-with-carthage)
	1.	[Installation with CocoaPods](#installation-with-cocoapods)
1.	[Classes](#classes)
	1.	[OBPServerInfo](#obpserverinfo)
	1.	[OBPSession](#obpsession)
	1.	[OBPWebViewProvider](#obpwebviewprovider)
	1.	[OBPMarshal](#obpmarshal)
	1.	[OBPDateFormatter](#obpdateformatter)
1.	[How to Use](#how-to-use)
1.	[Customising OBPMarshal Behaviour](#customising-obpmarshal-behaviour)



### Overview

OBPKit allows you to easily connect your existing iOS and OSX apps to servers offering the [Open Bank Project API][API].

It takes care of the authorisation process, and once the user has given your app permission to access his/her resources, it provides you with a helper to marshal resources through the API, or if you want to roll your own, you can use OBPKit to add authorisation headers to the requests you form yourself.

You can look at the [HelloOBP-iOS][] and [HelloOBP-Mac][] sample applications to see OBPKit in use.



### Installation

You can use either [Carthage][] or [CocoaPods][] ([more](https://cocoapods.org/about)). (If you are sitting on the fence, there is a way to support both until you are ready to decide based on experience. Link coming soon; ask for details if interested.)

#### Installation with Carthage

1.	[Install the latest Carthage][Carthage-install] — in a nutshell: install [homebrew](http://brew.sh), run `brew update` and run `brew install carthage`.

1.	If you don't already have one, create a file named `Cartfile` at the root level of your project folder. To your Cartfile add...

		github "OpenBankProject/OBPKit-iOSX"

1.	Run `carthage update --platform iOS,Mac` (omitting the platforms you do not need). This will add to your project's root directory, the directories Carthage/Checkouts, containing all the needed projects, and Carthage/Build/{iOS,Mac}, containing the frameworks built from the projects. It will also add a Cartfile.resolved file at root level.

1.	In Xcode, open the project for your app, select your app target, go to the build phases tab and expand the `Embed Frameworks` phase, and drag in the OBPKit, OAuthCore, STHTTPRequest and UICKeyChainStore frameworks from the Carthage/Build/{iOS,Mac} subfolder for your app platform.

1.	You will also need to add the Security framework to your `Link Binary With Libraries` build phase.

1.	Add `Carthage/` to your `.gitignore` file before you commit this change.

#### Installation with CocoaPods

1.	[Install the latest CocoaPods][CocoaPods-install]

1.	If you already have a Podfile, add…

	```ruby
	pod 'OAuthCore', :git => 'https://github.com/t0rst/OAuthCore.git'
	# ...OBPKit currently requires the t0rst fork of OAuthCore
	pod 'OBPKit', :git => 'https://github.com/OpenBankProject/OBPKit-iOSX.git'
	```

	…to your target dependencies. Otherwise, create a file named `Podfile` at the root level of your project folder, with contents like…

	```ruby
	platform :ios, '8.0' # delete if inappropriate
	platform :osx, '10.9' # delete if inappropriate
	target 'your-app-target-name' do
		pod 'OAuthCore', :git => 'https://github.com/t0rst/OAuthCore.git'
		# ...OBPKit currently requires the t0rst fork of OAuthCore
		pod 'OBPKit', :git => 'https://github.com/OpenBankProject/OBPKit-iOSX.git'
	end
	```

1.	Run `pod install`. This will modify your yourproj.xcproj, add yourproj.xcworkspace and Podfile.lock, and add a Pods folder at the root level of your project folder. Use yourproj.xcworkspace from now on.

1.	Add `Pods/` to your `.gitignore` file before you commit this change.



### Classes

There are three main classes to use, one protocol to adopt and some helpers.

#### OBPServerInfo

An `OBPServerInfo` instance records the data necessary to access an OBP server. It stores sensitive credentials securely in the key chain.

The `OBPServerInfo` class keeps a persistent record of all complete instances. An instance is complete once its client key and secret have been set. You can typically obtain these for your app from https://host-serving-OBP-API/consumer-registration.

You can use the `OBPServerInfo` class to keep a record of all the OBP servers for which you support a connection; usually you will just have one, but more are possible. `OBPServerInfo` instances are reloaded automatically when your app is launched.

A default instance of the helper class `OBPServerInfoStorage` handles the actual save and restore. You can customise your storage approach by nominating that your override class be used. You can configure this, as well as other security details, by passing a dictionary of customisation options to the function `OBPServerInfoCustomise` before the `OBPServerInfo` class initialize has been called.

#### OBPSession

You request an `OBPSession` instance for the OBP server you want to connect to, and use it to handle the authorisation sequence, and once access is gained, use the session's marshall object to help you marshal resources through the API. 

By default, `OBPSession` uses OAuth for authorisation, which is the correct way for your app to gain your user's permission to access his/her resources, and OBPKit makes this very easy to use. However, during initial development, you can also set the `authMethod` of your instance to use [Direct Login][DirectLogin] if you wish. (You can also set the `authMethod` to none in order to restrict access to just the public resources on an OBP server; or do this as needed for individual calls to OBPMarshall.) 

The `OBPSession` class keeps track of the instances that are currently alive, and will create or retrieve an `OBPSession` instance for an `OBPServerInfo` instance identifying a server you want to talk to. Both `OBPServerInfo` and `OBPSession` allow you to access default instances for when you only want to deal with singletons.

#### OBPWebViewProvider

For OAuth, `OBPSession` needs some part of your app to act as an `OBPWebViewProvider` protocol adopter in order to show the user a web page when it is time to get authorisation to access his/her resources.

If you don't provide an `OBPWebViewProvider` protocol adopter, then the `OBPDefaultWebViewProvider` class singleton will be used. It provides basic support, and you can choose whether an in-app or external web view is brought up by calling configuring with the class member `+configureToUseExternalWebViewer:withCallbackSchemeName:andInstallCallbackHook:`. There are advantages and disadvantages to both, as set out in the Xcode quick help for the class.

#### OBPMarshal

A default `OBPMarshal` instance is available from your `OBPSession` object, and will take care of creating, fetching, updating and deleting resources from the API, with response data and corresponding deserialised object delivered to your completion blocks. You can easily override the default behaviour by invoking a range of options. You can also supply extra headers via the options to, for example, limit by ordinal or date the range of transactions you retrieve. 

| REST API Verb | OBPMarshal Call |
| --- | --- |
| GET | `-getResourceAtAPIPath:withOptions:forResultHandler:orErrorHandler:` |
| POST | `-createResource:atAPIPath:withOptions:forResultHandler:orErrorHandler:` |
| PUT | `-updateResource:atAPIPath:withOptions:forResultHandler:orErrorHandler:` |
| DELETE | `-deleteResourceAtAPIPath:withOptions:forResultHandler:orErrorHandler:` |

#### OBPDateFormatter

You can use the `OBPDateFormatter` helper to convert back and forth between `NSDate` instances and the string representation used when sending and recieving OBP API resources.



### How to Use

The [HelloOBP-iOS][] and [HelloOBP-Mac][] sample apps demonstrate simple use of the OBPKit classes.

In your app delegate after start-up, check for and create the `OBPServerInfo` instance for the main server you will connect to (if it hasn't already been restored from a previous run):

```objc
if (nil == [OBPServerInfo firstEntryForAPIServer: kDefaultServer_APIBase])
{
	OBPServerInfo* serverInfo;
	serverInfo = [OBPServerInfo addEntryForAPIServer: kDefaultServer_APIBase];
	serverInfo.data = DefaultServerDetails();
}
```

Here the details of the default server are fetched from a simple header (DefaultServerDetails.h), which is insecure, but in production, you might want to give the API keys some stronger protection. While getting up and running, this kind of thing is sufficient:

```objc
static NSString* const kDefaultServer_APIBase = @"https://apisandbox.openbankproject.com/obp/v2.0.0/";
NS_INLINE NSDictionary* DefaultServerDetails() {
	return @{
		OBPServerInfo_APIBase			: kDefaultServer_APIBase,
		OBPServerInfo_AuthServerBase	: @"https://apisandbox.openbankproject.com/",
		OBPServerInfo_ClientKey			: @"0iz1zuscashkoyd3ztzb3i5whuubzetfihfc52ve",
		OBPServerInfo_ClientSecret		: @"p4li5mklyt1h42w5u0tx4w2evtn2yz3gmntyn2ty",
	};
}
```

In your main or starting view, create the OBPSession instances that you want to work with:

```objc
if (_session == nil)
{
	OBPServerInfo*	serverInfo = [OBPServerInfo firstEntryForAPIServer: chosenServer_APIBase];
	_session = [OBPSession sessionWithServerInfo: serverInfo];
}
```

When the user requests to log in, ask the default session instance to validate, i.e. get authorisation for accessing resources on behalf of the client:

```objc
- (void)viewDidLoad
{
	...

	// Kick off session authentication
	[[OBPSession currentSession] validate:
		^(NSError* error)
		{
			if (error == nil) // success, do stuff...
				[self fetchAccounts];
		}
	];
}
```

After this, you can use the marshal property of the current session instance to retrieve resources from the API:

```objc
OBPMarshal*				marshal = [OBPSession currentSession].marshal;
NSString*				path = [NSString stringWithFormat: @"banks/%@/accounts/private", bankID];
HandleOBPMarshalData	responseHandler = 
	^(id deserializedObject, NSString* responseBody)
	{
		_accountsDict = deserializedObject;
		[self loadAccounts];
	};

[marshal getResourceAtAPIPath: path
				  withOptions: nil
		   forResponseHandler: responseHandler
			   orErrorHandler: nil]; // nil ==> use default error handler
```

### Customising OBPMarshal Behaviour

Most of the time, the default behaviour of `OBPMarshal` is what you will want, but for special situations you can easily override the default `OBPMarshal` behaviour by passing an options dictionary in with your calls:

| To… | add the key… | with value… |
| :--- | :--- | :--- |
| …access only public resources | `OBPMarshalOptionOnlyPublicResources` | `@YES` |
| …add extra headers | `OBPMarshalOptionExtraHeaders` | `@{ @"obp_limit" : @(chunkSize), @"obp_offset" : @(nextChunkOffset) }` (…for example) |
| …expect a response body that isn't JSON | `OBPMarshalOptionDeserializeJSON` | `@NO` |
| …expect a JSON container object that is not a dictionary | `OBPMarshalOptionExpectClass` | `[NSArray class]` (…for example) |
| …expect a JSON container object that could be any class | `OBPMarshalOptionExpectClass` | `[NSNull null]` |
| …expect a non-default HTTP status code | `OBPMarshalOptionExpectStatus` | `@201` |
| …accept several HTTP status codes | `OBPMarshalOptionExpectStatus` | `@[@201, @212]` |
| …send a form instead of JSON | `OBPMarshalOptionSendDictAsForm` | `@YES` |



[OBP]: http://www.openbankproject.com
[API]: https://github.com/OpenBankProject/OBP-API/wiki
[DirectLogin]: https://github.com/OpenBankProject/OBP-API/wiki/Direct-Login
[HelloOBP-iOS]: https://github.com/OpenBankProject/Hello-OBP-OAuth1.0a-IOS
[HelloOBP-Mac]: https://github.com/OpenBankProject/Hello-OBP-OAuth1.0a-Mac
[Carthage]: https://github.com/Carthage/Carthage/blob/master/README.md
[Carthage-install]: https://github.com/Carthage/Carthage/blob/master/README.md#installing-carthage
[CocoaPods]: https://github.com/CocoaPods/CocoaPods/blob/master/README.md
[CocoaPods-install]: http://guides.cocoapods.org/using/getting-started.html#installation
