/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTLinkingManager.h>

#import <FBReactNativeSpec/FBReactNativeSpec.h>
#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>

#import "RCTLinkingPlugins.h"

#if !TARGET_OS_OSX // [macOS]
static NSString *const kOpenURLNotification = @"RCTOpenURLNotification";
#else // [macOS

NSString *const RCTOpenURLNotification = @"RCTOpenURLNotification";

static NSString *initialURL = nil;
static BOOL moduleInitalized = NO;
static BOOL alwaysForegroundLastWindow = YES;

static void postNotificationWithURL(NSString *url, id sender)
{
  NSDictionary<NSString *, id> *payload = @{@"url" : url};
  [[NSNotificationCenter defaultCenter] postNotificationName:RCTOpenURLNotification object:sender userInfo:payload];
}

#endif // macOS]

@interface RCTLinkingManager () <NativeLinkingManagerSpec>

#if !TARGET_OS_OSX // [macOS]

/// Common logic for handling user activities originating from both AppDelegate- and SceneDelegate- lifecycle methods
+ (void)handleUserActivity:(NSUserActivity *)userActivity window:(UIWindow *)window;

/// Common logic for handling user activities from AppDelegate-lifecycle methods.
+ (BOOL)handleAppDelegateURL:(NSURL *)URL app:(UIApplication *)app;

/// Posts a URL notification that will be handled by the emitter to JS; this method is used to invoke instance methods
/// of RCTLinkingManager from class methods via NSNotificationCenter.
/// @param URL The URL to be emitted.
+ (void)postNotificationWithURL:(NSURL *)URL;
#endif // [macOS]

@end

@implementation RCTLinkingManager

RCT_EXPORT_MODULE()

#if !TARGET_OS_OSX // [macOS]
+ (void)postNotificationWithURL:(NSURL *)URL
{
  NSDictionary<NSString *, id> *payload = @{@"url" : URL.absoluteString};
  [[NSNotificationCenter defaultCenter] postNotificationName:kOpenURLNotification object:nil userInfo:payload];
}
#endif // [macOS]

- (dispatch_queue_t)methodQueue
{
  return dispatch_get_main_queue();
}

#pragma mark - RCTEventEmitter methods

#if !TARGET_OS_OSX // [macOS]
- (void)startObserving
{
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleOpenURLNotification:)
                                               name:kOpenURLNotification
                                             object:nil];
}

- (void)stopObserving
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}
#else // [macOS
- (void)startObserving
{
  moduleInitalized = YES;

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleOpenURLNotification:)
                                               name:RCTOpenURLNotification
                                             object:nil];
}

- (void)stopObserving
{
  moduleInitalized = NO;
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}
#endif // macOS]

- (NSArray<NSString *> *)supportedEvents
{
  return @[ @"url" ];
}

#pragma mark - JS methods

#if !TARGET_OS_OSX // [macOS]
+ (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)URL
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options
{
  return [self handleAppDelegateURL:URL app:app];
}

+ (BOOL)application:(UIApplication *)application
              openURL:(NSURL *)URL
    sourceApplication:(NSString *)sourceApplication
           annotation:(id)annotation
{
  return [self handleAppDelegateURL:URL app:application];
}

+ (BOOL)application:(UIApplication *)application
    continueUserActivity:(NSUserActivity *)userActivity
      restorationHandler:(nonnull void (^)(NSArray<id<UIUserActivityRestoring>> *_Nullable))restorationHandler
{
  if (RCTIsSceneDelegateApp()) {
    return NO;
  }

  [RCTLinkingManager handleUserActivity:userActivity window:RCTKeyWindow()];
  return YES;
}

#pragma mark - SceneDelegate methods

+ (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity
{
  [RCTLinkingManager handleUserActivity:userActivity window:RCTKeyWindow()];
}

+ (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts
{
  if (URLContexts.count == 0) {
    return;
  }

  NSURL *URL = URLContexts.allObjects.firstObject.URL;
  if (URL == nil) {
    return;
  }
  [RCTLinkingManager postNotificationWithURL:URL];
}

#pragma mark - Common logic methods

+ (void)handleUserActivity:(NSUserActivity *)userActivity window:(UIWindow *)window
{
  // This can be nullish when launching an App Clip.
  if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb] && userActivity.webpageURL != nil) {
    [RCTLinkingManager postNotificationWithURL:userActivity.webpageURL];
  }
}

+ (BOOL)handleAppDelegateURL:(NSURL *)URL app:(UIApplication *)app
{
  if (RCTIsSceneDelegateApp()) {
    return NO;
  }

  [RCTLinkingManager postNotificationWithURL:URL];
  return YES;
}

- (void)handleOpenURLNotification:(NSNotification *)notification
{
  [self sendEventWithName:@"url" body:notification.userInfo];
}

- (void)openURL:(NSString *)urlString resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  NSURL *URL = [RCTConvert NSURL:urlString];
  [RCTSharedApplication() openURL:URL
                          options:@{}
                completionHandler:^(BOOL success) {
                  if (success) {
                    resolve(@YES);
                  } else {
#if TARGET_OS_SIMULATOR
                    // Simulator-specific code
                    if ([URL.absoluteString hasPrefix:@"tel:"]) {
                      RCTLogWarn(@"Unable to open the Phone app in the simulator for telephone URLs. URL:  %@", URL);
                      resolve(@NO);
                    } else {
                      reject(RCTErrorUnspecified, [NSString stringWithFormat:@"Unable to open URL: %@", URL], nil);
                    }
#else
          // Device-specific code
          reject(RCTErrorUnspecified, [NSString stringWithFormat:@"Unable to open URL: %@", URL], nil);
#endif
                  }
                }];
}

- (void)canOpenURL:(NSString *)urlString
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(__unused RCTPromiseRejectBlock)reject
{
  NSURL *URL = [RCTConvert NSURL:urlString];
  if (RCTRunningInAppExtension()) {
    // Technically Today widgets can open urls, but supporting that would require
    // a reference to the NSExtensionContext
    resolve(@NO);
    return;
  }

  // This can be expensive, so we deliberately don't call on main thread
  BOOL canOpen = [RCTSharedApplication() canOpenURL:URL];
  NSString *scheme = [URL scheme];
  if (canOpen) {
    resolve(@YES);
  } else if (![[scheme lowercaseString] hasPrefix:@"http"] && ![[scheme lowercaseString] hasPrefix:@"https"]) {
    // On iOS 9 and above canOpenURL returns NO without a helpful error.
    // Check if a custom scheme is being used, and if it exists in LSApplicationQueriesSchemes
    NSArray *querySchemes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"LSApplicationQueriesSchemes"];
    if (querySchemes != nil &&
        ([querySchemes containsObject:scheme] || [querySchemes containsObject:[scheme lowercaseString]])) {
      resolve(@NO);
    } else {
      reject(
          RCTErrorUnspecified,
          [NSString
              stringWithFormat:@"Unable to open URL: %@. Add %@ to LSApplicationQueriesSchemes in your Info.plist.",
                               URL,
                               scheme],
          nil);
    }
  } else {
    resolve(@NO);
  }
}

- (void)getInitialURL:(RCTPromiseResolveBlock)resolve reject:(__unused RCTPromiseRejectBlock)reject
{
  NSURL *initialURL = nil;
#pragma clang diagnostic push // [macOS]
#pragma clang diagnostic ignored "-Wdeprecated-declarations" // [macOS]
  if (self.bridge.launchOptions[UIApplicationLaunchOptionsURLKey] != nullptr) {
    initialURL = self.bridge.launchOptions[UIApplicationLaunchOptionsURLKey];
  } else {
    NSDictionary *userActivityDictionary =
        self.bridge.launchOptions[UIApplicationLaunchOptionsUserActivityDictionaryKey];
    if ([userActivityDictionary[UIApplicationLaunchOptionsUserActivityTypeKey] isEqual:NSUserActivityTypeBrowsingWeb]) {
      initialURL = ((NSUserActivity *)userActivityDictionary[@"UIApplicationLaunchOptionsUserActivityKey"]).webpageURL;
    }
  }
#pragma clang diagnostic pop // [macOS]
  resolve(RCTNullIfNil(initialURL.absoluteString));
}

- (void)openSettings:(RCTPromiseResolveBlock)resolve reject:(__unused RCTPromiseRejectBlock)reject
{
  NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
  [RCTSharedApplication() openURL:url
                          options:@{}
                completionHandler:^(BOOL success) {
                  if (success) {
                    resolve(nil);
                  } else {
                    reject(RCTErrorUnspecified, @"Unable to open app settings", nil);
                  }
                }];
}

#else // [macOS

+ (void)setAlwaysForegroundLastWindow:(BOOL)alwaysForeground
{
  alwaysForegroundLastWindow = alwaysForeground;
}

+ (void)getUrlEventHandler:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
  // extract url value from the event
  NSString *url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];

  // If the application was launched via URL, this handler will be called before
  // the module is initialized by the bridge. Store the initial URL, because we are not listening to the notification yet.
  if (!moduleInitalized && initialURL == nil) {
    initialURL = url;
  }

  postNotificationWithURL(url, self);
}

- (void)handleOpenURLNotification:(NSNotification *)notification
{
  // Activate app, because [NSApp mainWindow] returns nil when the app is hidden and another app is maximized
  [NSApp activateIgnoringOtherApps:YES];
  // foreground top level window
  if (alwaysForegroundLastWindow) {
    NSWindow *lastWindow = [[NSApp windows] lastObject];
    [lastWindow makeKeyAndOrderFront:nil];
  }
  [self sendEventWithName:@"url" body:notification.userInfo];
}

- (void)openURL:(NSString *)urlString resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  NSURL *URL = [RCTConvert NSURL:urlString];
  BOOL result = URL != nil && [[NSWorkspace sharedWorkspace] openURL:URL];
  if (result) {
    resolve(@YES);
  } else {
    reject(RCTErrorUnspecified, [NSString stringWithFormat:@"Unable to open URL: %@", urlString], nil);
  }
}

- (void)canOpenURL:(NSString *)urlString
           resolve:(RCTPromiseResolveBlock)resolve
            reject:(__unused RCTPromiseRejectBlock)reject
{
  resolve(@YES);
}

- (void)getInitialURL:(RCTPromiseResolveBlock)resolve reject:(__unused RCTPromiseRejectBlock)reject
{
  resolve(RCTNullIfNil(initialURL));
}

- (void)openSettings:(RCTPromiseResolveBlock)resolve reject:(__unused RCTPromiseRejectBlock)reject
{
  // macOS doesn't have a direct equivalent of UIApplicationOpenSettingsURLString
  // Open System Preferences instead
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:"]];
  resolve(nil);
}

#endif // macOS]

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeLinkingManagerSpecJSI>(params);
}

@end

Class RCTLinkingManagerCls(void)
{
  return RCTLinkingManager.class;
}
