//
//  OBPWebViewProvider.m
//  OBPKit
//
//  Created by Torsten Louland on 24/01/2016.
//  Copyright (c) 2016-2017 TESOBE Ltd. All rights reserved.
//

#import "OBPWebViewProvider.h"
// sdk
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#include <objc/runtime.h>
#else
#import <AppKit/AppKit.h>
#endif
#import <WebKit/WebKit.h>
// prj
#import "OBPLogging.h"



@interface OBPDefaultWebViewProvider () <WKUIDelegate, WKNavigationDelegate>
+ (BOOL)installCallbackHook:(BOOL)install;
@property (nonatomic, assign) BOOL useExternal;
@property (nonatomic, strong) WKWebView* webView;
- (void)showURL:(NSURL *)url; // make webview, set self as delegate, install in suitable host, show
- (void)doneAndClose:(BOOL)close; // pull down host
- (void)resetWebViewProvider; // clear members
@property (nonatomic, strong) OBPWebNavigationFilter filterNav;
@end



#pragma mark -
#if !TARGET_OS_IPHONE
#define OBPWebViewProviderOS OBPWebViewProvider_OSX
@interface OBPWebViewProvider_OSX : OBPDefaultWebViewProvider <NSWindowDelegate>
@end
#endif

#if TARGET_OS_IPHONE
#define OBPWebViewProviderOS OBPWebViewProvider_iOS
@class OBPWebViewProviderVC;

@interface OBPWebViewProvider_iOS : OBPDefaultWebViewProvider
- (void)webViewProviderVCDidClose:(OBPWebViewProviderVC*)vc;
@end

@interface OBPWebViewProviderVC : UIViewController
@property (nonatomic, weak) OBPWebViewProvider_iOS* owner;
@end
#endif



#pragma mark -
@implementation OBPDefaultWebViewProvider
{
	NSString*				_callbackSchemeName;
	NSString*				_callbackScheme;
	OBPWebNavigationFilter	_filterNav;
	OBPWebCancelNotifier	_notifyCancel;
	NSURL*					_initialURL;
}
static OBPDefaultWebViewProvider* sOBPWebViewProvider = nil;
+ (void)initialize
{
	if (self != [OBPDefaultWebViewProvider class])
		return;
	sOBPWebViewProvider = [[OBPWebViewProviderOS alloc] initPrivate];
}
+ (instancetype)instance
{
	return sOBPWebViewProvider;
}
+ (void)configureToUseExternalWebViewer:(BOOL)useExternal
				 withCallbackSchemeName:(NSString*)callbackSchemeName
				 andInstallCallbackHook:(BOOL)installCallbackHook
{
	NSString*		scheme = [self callbackSchemeWithName: callbackSchemeName];

	if (![scheme length])
	{
		//	Throwing an exception for errors here doesn't help when this has been called from -[NSApplicationDelegate applicationDidFinishLaunching:] because the exception is silently caught and the app is left in an indeterminate state. So we need brute force in DEBUG mode (in release builds, app will fall back to using internal web view)...
		if ([callbackSchemeName length])
		{
			OBP_LOG(@"Bundle CFBundleURLTypes does not contain any CFBundleURLSchemes with CFBundleURLName of \"%@\". Ensure that there are entries and that the correct name is used. This is mandatory.", callbackSchemeName);
		#if DEBUG
			abort();
		#endif
		}
		else
		if (useExternal)
		{
			OBP_LOG(@"%@", @"A callbackSchemeName parameter is mandatory when using an external web viewer, and must match the CFBundleURLName of one of the CFBundleURLSchemes in the CFBundleURLTypes entry in the main bundle info dictionary.");
		#if DEBUG
			abort();
		#endif
		}
		useExternal = NO;
		scheme = sOBPWebViewProvider->_callbackScheme;
	}
	else
	if ([scheme rangeOfString: @"[^-+.A-Za-z0-9]+" options: NSRegularExpressionSearch].length)
	{
		OBP_LOG(@"Scheme %@ contains illegal characters. Should be [A-Za-z][-+.A-Za-z0-9]+ (RFC2396 Appendix A). Also advisable to use lowercase — some servers make this conversion leading to round-trip mismatch.", scheme);
#if DEBUG
		abort();
#endif
		useExternal = NO;
		scheme = sOBPWebViewProvider->_callbackScheme;
	}
	else
	if (![scheme isEqualToString: [scheme lowercaseString]])
	{
		OBP_LOG(@"Although uppercase characters are legal in schemes (RFC2396 Appendix A), callback schemes can be converted to lowercase by some servers, leading to a mismatch when filtering for a callback. Convert %@ to lowercase.", scheme);
#if DEBUG
		abort();
#endif
		useExternal = NO;
		scheme = sOBPWebViewProvider->_callbackScheme;
	}

	installCallbackHook &= useExternal;

	if ([[sOBPWebViewProvider class] installCallbackHook: installCallbackHook])
	{
		sOBPWebViewProvider->_callbackScheme = scheme;
		sOBPWebViewProvider->_useExternal = useExternal;
	}
}
+ (NSString*)callbackSchemeWithName:(NSString*)schemeName
{
	if (![schemeName length])
		return nil;
	/*	Info dictionary should contain a section like this in order to declare which URL schemes it can handle, and hence can be sent to it by the system.
			<key>CFBundleURLTypes</key>
			<array>
				<dict>
					<key>CFBundleURLName</key>
					<string>aName</string>
					<key>CFBundleTypeRole</key>
					<string>Viewer</string>
					<key>CFBundleURLSchemes</key>
					<array>
						<string>aScheme</string>
					</array>
				</dict>
			</array>
	*/
	NSArray			*schemes, *urlTypes = [NSBundle mainBundle].infoDictionary[@"CFBundleURLTypes"];
	NSString		*name, *scheme;
	NSDictionary	*d;
	for (d in urlTypes)
	{
		name = d[@"CFBundleURLName"];
		if ([name isEqualToString: schemeName])
		{
			schemes = d[@"CFBundleURLSchemes"];
			scheme = [schemes firstObject];
			return scheme;
		}
	}
	return nil;
}
+ (NSString*)callbackSchemeFromBundleIdentifier
{
	NSString*	scheme;
	scheme = [@"x-" stringByAppendingString: [NSBundle mainBundle].bundleIdentifier];
	scheme = [scheme stringByReplacingOccurrencesOfString: @"." withString: @"-"];
	scheme = [scheme lowercaseString]; // uppercase is allowed but some servers return scheme converted to lowercase leading to roundtrip mismatch
	// Remove characters not allowed in schemes by RFC2396
	NSRange		rg;
	while ((rg = [scheme rangeOfString: @"[^-+.A-Za-z0-9]+" options: NSRegularExpressionSearch]).length)
		scheme = [scheme stringByReplacingCharactersInRange: rg withString: @""];
	return scheme;
}
+ (BOOL)installCallbackHook:(BOOL)install
{
	return NO;
}
+ (BOOL)handleCallbackURL:(NSURL*)url
{
	return [sOBPWebViewProvider handleCallbackURL: url];
}
#pragma mark -
- (instancetype)init {self = nil; return self;} // the designated non-initialiser
- (instancetype)initPrivate
{
	if (nil == (self = [super init]))
		return nil;
	_callbackScheme = [[self class] callbackSchemeFromBundleIdentifier];
	return self;
}
- (NSString*)callbackScheme
{
	return _callbackScheme;
}
- (void)showURL:(NSURL*)url
  filterNavWith:(OBPWebNavigationFilter)navigationFilter
 notifyCancelBy:(OBPWebCancelNotifier)cancelNotifier
{
	if (nil == url || nil == navigationFilter || nil == cancelNotifier)
		return;
	_initialURL = url;
	_filterNav = navigationFilter;
	_notifyCancel = cancelNotifier;
	[self showURL: url];
}
- (void)showURL:(NSURL*)url
{
	// subclass imp
}
- (void)doneAndClose:(BOOL)close
{
	if (_notifyCancel)
		_notifyCancel();
	[self resetWebViewProvider];
}
- (void)resetWebViewProvider
{
	_notifyCancel = nil;
	_filterNav = nil;
	self.webView = nil;
}
- (BOOL)handleCallbackURL:(NSURL*)url // return route for external web viewing
{
	if (_filterNav && _filterNav(url))
	{
		_notifyCancel = nil;
		[self resetWebViewProvider];
	}
	return NO;
}
- (void)setWebView:(WKWebView*)webView
{
	if (_webView == webView)
		return;
	if (_webView)
		_webView.UIDelegate = nil, _webView.navigationDelegate = nil;
	_webView = webView;
	if (_webView)
		_webView.UIDelegate = self, _webView.navigationDelegate = self;
}
#pragma mark - WKUIDelegate
- (void)webViewDidClose:(WKWebView *)webView
{
	OBP_LOG_IF(0, @"[%@ webViewDidClose: %@]", self, webView);
	[self doneAndClose: YES];
}
#pragma mark - WKNavigationDelegate
- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction decisionHandler:(void(^)(WKNavigationActionPolicy))decisionHandler
{
	WKNavigationActionPolicy	policy = WKNavigationActionPolicyAllow;
	WKNavigationType			navType = navigationAction.navigationType;
	NSURL*						navURL;

	OBP_LOG_IF(0, @"\nnavigationAction: %@", navigationAction);

	if (navType == WKNavigationTypeLinkActivated
	 || navType == WKNavigationTypeOther)
	{
		navURL = navigationAction.request.URL;
		if (_filterNav(navURL))
		{
			_notifyCancel = nil;
			policy = WKNavigationActionPolicyCancel;
			dispatch_async(
				dispatch_get_main_queue(),
				^{[self doneAndClose: YES];}
			);
		}
		else
		if (![_initialURL.host isEqualToString: navURL.host]
		 || ![_initialURL.path isEqualToString: navURL.path])
		{
			// Pass external links to system appointed browser
			policy = WKNavigationActionPolicyCancel;
		#if TARGET_OS_IPHONE
			[[UIApplication sharedApplication] openURL: navURL];
		#else
			[[NSWorkspace sharedWorkspace] openURL: navURL];
		#endif
		}
	}

	decisionHandler(policy);
}
@end



#pragma mark -
#if !TARGET_OS_IPHONE
@implementation OBPWebViewProvider_OSX
{
	NSWindow*					_window;
}
- (void)makeWebView
{
	enum {kAuthScreenStdWidth = 1068, kAuthScreenStdHeight = 724};
	WKWebView*	webView;
	NSScreen*	mainScreen = [NSScreen mainScreen];
	CGSize		size = mainScreen.frame.size;
	CGRect		contentRect = {.origin={0,0}, .size=size};
	contentRect = CGRectInset(contentRect, MAX(0, (size.width - kAuthScreenStdWidth)/2),
										   MAX(0, (size.height - kAuthScreenStdHeight)/2));
	_window = [[NSWindow alloc] initWithContentRect: contentRect
										  styleMask: NSTitledWindowMask
												   + NSClosableWindowMask
												   + NSResizableWindowMask
												   + NSUnifiedTitleAndToolbarWindowMask
												   + NSFullSizeContentViewWindowMask
											backing: NSBackingStoreRetained
											  defer: YES
											 screen: mainScreen];
	_window.delegate = self;
	_window.releasedWhenClosed = NO;

	contentRect.origin = CGPointZero;
	self.webView = webView = [[WKWebView alloc] initWithFrame: contentRect];
	webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;

	_window.contentView = webView;
	[_window makeFirstResponder: webView];
}
- (void)showURL:(NSURL*)url
{
	if (self.useExternal)
	{
		[[NSWorkspace sharedWorkspace] openURL: url];
	}
	else
	{
		if (!self.webView)
			[self makeWebView];
		[_window makeKeyAndOrderFront: self];
		[self.webView loadRequest: [NSURLRequest requestWithURL: url]];
	}
}
- (void)doneAndClose:(BOOL)close
{
	if (close)
	{
		_window.delegate = nil;
		[_window close];
	}

	[super doneAndClose: close];
}
- (void)resetWebViewProvider
{
	[super resetWebViewProvider];
	if (_window)
		_window.delegate = nil, _window = nil;
}
#pragma mark - NSWindowDelegate
- (void)windowWillClose:(NSNotification*)notification
{
	OBP_LOG_IF(0, @"[%@ windowWillClose: %@]", self, notification);
	[self doneAndClose: NO];
}
#pragma mark -
+ (BOOL)installCallbackHook:(BOOL)install
{
	static BOOL sInstalled = NO;
	if (sInstalled == install)
		return YES;

	NSAppleEventManager* aeMgr = [NSAppleEventManager sharedAppleEventManager];
	if (install)
		[aeMgr setEventHandler: self andSelector: @selector(handleURLEvent:withReplyEvent:)
				 forEventClass: kInternetEventClass andEventID: kAEGetURL];
	else
		[aeMgr removeEventHandlerForEventClass: kInternetEventClass andEventID: kAEGetURL];

	sInstalled = install;
	return YES;
}
+ (void)handleURLEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
	if (event.eventClass != kInternetEventClass
	 || event.eventID != kAEGetURL)
		return;
	NSAppleEventDescriptor*	objDesc = [event paramDescriptorForKeyword: keyDirectObject];
	NSString*				urlStr = [objDesc stringValue];
	if ([urlStr length])
		[self handleCallbackURL: [NSURL URLWithString: urlStr]];
}
@end
#endif // !TARGET_OS_IPHONE



#pragma mark -
#if TARGET_OS_IPHONE
@implementation OBPWebViewProviderVC
{
	UIView*			_rootView;
	UIToolbar*		_toolbar;
	WKWebView*		_webView;
}
- (instancetype)initWithOwner:(OBPWebViewProvider_iOS*)owner
{
	if (nil == (self = [super initWithNibName: nil bundle: nil]))
		return nil;
	self.owner = owner;
	self.modalPresentationStyle = UIModalPresentationFullScreen;
	return self;
}
- (void)loadView
{
	UIView*				rootView;
	UIToolbar*			toolbar;
	WKWebView*			webView;
	CGRect				availableArea = [UIScreen mainScreen].bounds;
	CGRect				frame = {.origin = CGPointZero, .size = availableArea.size};
	NSDictionary*		views;
	NSDictionary*		metrics;
	NSMutableArray*		constraints;

	rootView = [[UIView alloc] initWithFrame: frame];

	toolbar = [[UIToolbar alloc] init];
	toolbar.items = @[
		[[UIBarButtonItem alloc] initWithTitle: NSLocalizedString(@"Cancel", nil) style:UIBarButtonItemStylePlain target: self action: @selector(cancel:)],
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFlexibleSpace target: nil action: NULL]
	];
	frame = availableArea;
	frame.origin.y = frame.size.height - toolbar.intrinsicContentSize.height;
	frame.size.height = toolbar.intrinsicContentSize.height;
	toolbar.frame = frame;

	frame = availableArea;
	frame.size.height -= toolbar.intrinsicContentSize.height;
	webView = [[WKWebView alloc] initWithFrame: frame];
	webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;

	[rootView addSubview: webView];
	[rootView addSubview: toolbar];

	views = NSDictionaryOfVariableBindings(webView, toolbar);
	metrics = @{};
	constraints = [NSMutableArray array];
	#define AddConstraintsFor(fmt) [constraints addObjectsFromArray: [NSLayoutConstraint constraintsWithVisualFormat: fmt options: 0 metrics: metrics views: views]]
	AddConstraintsFor(@"H:|[webView]|");
	AddConstraintsFor(@"H:|[toolbar]|");
	AddConstraintsFor(@"V:|[webView][toolbar]|");
	#undef AddConstraintsFor
	[NSLayoutConstraint activateConstraints: constraints];
	[rootView addConstraints: constraints];

	_toolbar = toolbar;
	_webView = webView;
	self.view = _rootView = rootView;
	self.owner.webView = _webView;
}
- (void)setView:(UIView*)view
{
	if (view == nil)
		_webView = nil, _toolbar = nil, _rootView = nil;
	[super setView: view];
}
- (void)cancel:(id)sender
{
	[self dismissViewControllerAnimated: YES completion: ^{
		[_owner webViewProviderVCDidClose: self];
	}];
}
@end



#pragma mark -
@implementation OBPWebViewProvider_iOS
{
	OBPWebViewProviderVC*		_vc;
}
- (void)webViewProviderVCDidClose:(OBPWebViewProviderVC*)vc
{
	[self doneAndClose: NO];
}
- (UIViewController*)topVC
{
	UIViewController	*vc, *topVC = nil;
	UIWindow			*window, *topWindow = nil;
	for (window in [UIApplication sharedApplication].windows)
	{
		if (!window.isHidden)
		if (window.windowLevel == UIWindowLevelNormal)
		if (window.screen == [UIScreen mainScreen])
			topWindow = window;
	}
	vc = topWindow.rootViewController;
	while (vc)
	{
		topVC = vc;
		if ([vc isKindOfClass: [UINavigationController class]])
			vc = [(UINavigationController*)vc topViewController];
		else
			vc = [vc.childViewControllers lastObject];
	}
	return topVC;
}
- (void)showURL:(NSURL*)url
{
	if (self.useExternal)
		[[UIApplication sharedApplication] openURL: url];
	else
	{
		_vc = [[OBPWebViewProviderVC alloc] initWithOwner: self];
		[[self topVC] presentViewController: _vc animated: YES completion: ^{
			[self.webView loadRequest: [NSURLRequest requestWithURL: url]];
		}];
	}
}
- (void)doneAndClose:(BOOL)close
{
	if (close)
		[_vc dismissViewControllerAnimated: YES completion: ^{
			[super doneAndClose: close];
		}];
	else
		[super doneAndClose: close];
}
- (void)resetWebViewProvider
{
	[super resetWebViewProvider];
	if (_vc)
	{
		if (_vc.presentingViewController)
			[_vc dismissViewControllerAnimated: NO completion: ^{}];
		_vc.owner = nil, _vc = nil;
	}
}
#pragma mark -
+ (BOOL)installCallbackHook:(BOOL)install
{
	static BOOL sInstalled = NO;
	if (sInstalled == install)
		return YES;
	id<UIApplicationDelegate>	appDelegate = [UIApplication sharedApplication].delegate;
	SEL							sel;
	Method						method;
	BOOL						methodAdded;

	if (install)
	{
		if ((0))
		{
			// Approach A.
			// Installing an implementaion for -application:openURL:options: or -application:openURL:sourceApplication:annotation: does not work. The installation is successful (test calls pass through ok), but the UIApplication object does not send these messages to the delegate, even though the app is correctly reactivated by a callback from an external browser. The implication is that only the state at the time of instantiation of the app delegate is honoured (if it isn't an oversight, then it could be a security feature to thwart code injection after launch). Hence, we are patching too late. Unwaranted complexity to do it earlier.

			for (int n = 0; n < 2; n++)
			{
				sel = n ? @selector(application:openURL:options:)
						: @selector(application:openURL:sourceApplication:annotation:);
				// Cant tail patch, so complain if there is already a handler
				if ([appDelegate respondsToSelector: sel])
				{
				#if DEBUG
					OBP_LOG(@"%@ already implements %@. Call +[OBPDefaultWebViewProvider handleCallbackURL:] from within the implementation, because +[%@ %@] will not patch it to make the call.", NSStringFromClass([appDelegate class]), NSStringFromSelector(sel), NSStringFromClass([self class]), NSStringFromSelector(_cmd));
					abort();
				#endif
					return NO;
				}
			}
			NSInteger OSv = [[[UIDevice currentDevice].systemVersion componentsSeparatedByString: @"."][0] integerValue];
			sel = OSv >= 9	? @selector(application:openURL:options:)
							: @selector(application:openURL:sourceApplication:annotation:);
			methodAdded = NO;
			Class class_AppDelegate = [appDelegate class];
			if (class_AppDelegate)
			if (NULL == (method = class_getInstanceMethod(class_AppDelegate, sel)))
			if (NULL != (method = class_getInstanceMethod(self, sel)))
			if (class_addMethod(class_AppDelegate,
								sel, method_getImplementation(method), method_getTypeEncoding(method)))
			{
				method = class_getInstanceMethod(class_AppDelegate, sel);
				methodAdded = method != nil;
			}
			if (!methodAdded)
				return NO;
		}
		else
		{
			// Approach B
			// Force the developer to implement -application:openURL:options: or -application:openURL:sourceApplication:annotation: and to correctly call +[OBPDefaultWebViewProvider handleCallbackURL:] from within it.
			NSURL*			loopTestURL = [NSURL URLWithString: [[sOBPWebViewProvider callbackScheme] stringByAppendingString: @"://OBPLoopTest"]];
			__block BOOL	passed = NO;
			sOBPWebViewProvider.filterNav = ^BOOL(NSURL* url) {
				BOOL match = [url isEqual: loopTestURL];
				passed |= match;
				return match;
			};
			if ([appDelegate respondsToSelector: @selector(application:openURL:options:)])
			{
				[appDelegate application: [UIApplication sharedApplication] openURL: loopTestURL options: @{}];
				OBP_LOG_IF(!passed, @"%@", @"To use OBPDefaultWebViewProvider with an external web viewer, you must test +[OBPDefaultWebViewProvider handleCallbackURL:] from within your UIApplicationDelegate implementation of -application:openURL:options:");
			}
			else
			if ([appDelegate respondsToSelector: @selector(application:openURL:sourceApplication:annotation:)])
			{
				[appDelegate application: [UIApplication sharedApplication] openURL: loopTestURL sourceApplication: nil annotation: @{}];
				OBP_LOG_IF(!passed, @"%@", @"To use OBPDefaultWebViewProvider with an external web viewer, you must test +[OBPDefaultWebViewProvider handleCallbackURL:] from within your UIApplicationDelegate implementation of -application:openURL:sourceApplication:annotation:");
			}
			else
				OBP_LOG(@"%@", @"To use OBPDefaultWebViewProvider with an external web viewer, your UIApplicationDelegate must implement -application:openURL:sourceApplication:annotation: or -application:openURL:options: and test +[OBPDefaultWebViewProvider handleCallbackURL:] early within the implementation.");
			sOBPWebViewProvider.filterNav = nil;
			if (!passed)
			{
			#if DEBUG
				abort();
			#endif
				return NO;
			}
		}
	}
	else
	{
		// really?
		return NO;
	}
	sInstalled = install;
	return YES;
}
//	Note: these two method implementation will be swizzled into place, after which self will be a different class, so do not reference self either implicitly or explicitly
- (BOOL)application:(UIApplication*)a openURL:(NSURL*)u sourceApplication:(NSString*)s annotation:(id)n
{
	return [OBPDefaultWebViewProvider handleCallbackURL: u];
}
- (BOOL)application:(UIApplication*)a openURL:(NSURL*)u options:(NSDictionary<NSString*, id>*)o
{
	return [OBPDefaultWebViewProvider handleCallbackURL: u];
}
@end
#endif // !TARGET_OS_IPHONE



