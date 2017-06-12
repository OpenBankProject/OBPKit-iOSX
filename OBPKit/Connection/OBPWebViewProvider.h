//
//  OBPWebViewProvider.h
//  OBPKit
//
//  Created by Torsten Louland on 24/01/2016.
//  Copyright (c) 2016-2017 TESOBE Ltd. All rights reserved.
//

#import <Foundation/Foundation.h>



NS_ASSUME_NONNULL_BEGIN



typedef BOOL(^OBPWebNavigationFilter)(NSURL*); // return YES if the target URL has been reached
typedef void(^OBPWebCancelNotifier)(); //



///	Protocol OBPWebViewProvider declares the tasks that OBPSession needs performed in order to facilitate the user authentication stage of the OAuth authorisation sequence.
@protocol OBPWebViewProvider <NSObject>

- (NSString*)callbackScheme; ///< Recommend the URL scheme that should be used for OAuth callbacks (i.e. when redirecting with the result of user's login); this can be a simple scheme for embedded web views, but if the provider shows an external webview, then the scheme needs to be one which the OS recognises as exclusively handled by this app.

- (void)showURL:(NSURL*)url filterNavWith:(OBPWebNavigationFilter)navigationFilter notifyCancelBy:(OBPWebCancelNotifier)canceled; ///< Show url in a webview, pass page navigation and redirects through navigationFilter, and call cancelled if the web view is closed by the user. \param url locates the web page in which the user will authorise client access to his/her resources. \param navigationFilter should be called with every new url to be loaded in the page, and will return YES when the authorisation callback url is detected, signifying that the provider should close the webview. \param cancel should be called if the user closes the webview.

- (void)resetWebViewProvider; ///< Called to close the webview (if possible) when an incomplete auth request has been canceled or abandoned for some reason.

@end



/**
Class OBPDefaultWebViewProvider implements minimum web view provider functionality, accessible through a singleton instance.

With no configuration, it will bring up a basic in-app web view, but you can also configure it use an external browser. What are the differences? The in-app web browser is the most basic. An external browser is fully featured and gives security helpers that the user may rely on, i.e. offering to fetch appropriate account and password pairs from secure keychain, browser or third party storage — this is a very big deal for the eighty percent of users who are non-technical. However, iOS may also interrupt the callback handling from an external browser, by asking the user to confirm whether they want to return to the original app, which can be confusing to the user (who should not have to know anything about internal workings of OAuth).

If you want to use an external browser, you must ensure that your application's info.plist file declares URL schemes that your app will recognise and respond to and that are unique to your app, e.g. by including...

\code
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>callback</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>x-${PRODUCT_BUNDLE_IDENTIFIER:lower}</string>
      </array>
    </dict>
  </array>
\endcode

...and then passing the name of the scheme ('callback' in the example above) to the configuration call +configureToUseExternalWebViewer:withCallbackSchemeName:andInstallHandlerHook:. If you do not already handle incoming URLs then you can ask for a handler hook to be installed, otherwise you must add a call to +handleCallbackURL: in your existing handler.
*/
@interface OBPDefaultWebViewProvider : NSObject <OBPWebViewProvider>

+ (instancetype)instance; ///< Access the singleton instance of this class.

+ (void)configureToUseExternalWebViewer:(BOOL)useExternal withCallbackSchemeName:(nullable NSString*)callbackSchemeName andInstallCallbackHook:(BOOL)installCallbackHook; ///< Configure how OBPDefaultWebViewProvider's singleton instance will behave. By default, it will use an in-app webview. \param useExternal will when YES, cause a URLs to be shown in the system's default web viewer, or when NO, cause an in-app web view to be brought up. \param callbackSchemeName identifies which entry in the main bundle's CFBundleURLTypes array to find by its CFBundleURLName. If found, then the first of the CFBundleURLSchemes in the entry is used. If not found, then bad things will happen as this parameter is mandatory when using an external web view view. It is optional for in-app web views. \param installCallbackHook will when YES, and useExternal is also YES, request that the singleton instance installs a hook function to receive the callback messages from the system and then forward them to +handleCallbackURL:. This is available on OSX, and will replace any existing message handler. However, it is currently not available on iOS, as it is prevented by security measures, so you must call +handleCallbackURL: directly instead, and the install request just performs a verification. If useExternal is YES and installCallbackHook is NO, then you are indicating that you will call +handleCallbackURL: directly. On OSX, do this from an apple event handler that you have installed, which handles events with class kInternetEventClass and id kAEGetURL (the URL is the direct object). On iOS, do this from either -[UIApplicationDelegate application:openURL:options:] or -[UIApplicationDelegate application:openURL:sourceApplication:annotation:].

+ (BOOL)handleCallbackURL:(NSURL*)url; ///< Let OBPDefaultWebViewProvider check if this url is a callback it has been waiting for and handle it. \param url is a URL received on iOS through either -[UIApplicationDelegate application:openURL:options:] or -[UIApplicationDelegate application:openURL:sourceApplication:annotation:], or on OSX though your handler for apple events with class kInternetEventClass and id kAEGetURL. \returns YES if url was handled.

+ (NSString*)callbackSchemeFromBundleIdentifier; ///< Helper that constructs and returns a callback scheme of the form x-<bundleIdentifier>, converted to lower case and with illegal characters removed. You can use this if user auth is requested via an in-app web view.
+ (NSString*)callbackSchemeWithName:(NSString*)schemeName; ///< Helper that retrieves the named callback URL scheme from the bundle, if present. You need to use this (and therefore need to have added your schemes to the bundle) if user auth is requested via a web view external to the app.

@end



NS_ASSUME_NONNULL_END
