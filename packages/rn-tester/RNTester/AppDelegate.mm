/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AppDelegate.h"

#if !TARGET_OS_TV
#import <React/RCTPushNotificationManager.h>
#import <UserNotifications/UserNotifications.h>
#endif

#if TARGET_OS_OSX // [macOS
#import "NativeExampleViews/FlexibleSizeExampleView.h"
#import "NativeExampleViews/UpdatePropertiesExampleView.h"

#import <React/RCTBundleURLProvider.h>
#import <React/RCTDefines.h>
#import <ReactCommon/RCTSampleTurboModule.h>
#import <ReactCommon/RCTTurboModuleManager.h>

#import <NativeCxxModuleExample/NativeCxxModuleExample.h>
#ifndef RN_DISABLE_OSS_PLUGIN_HEADER
#import <RNTMyNativeViewComponentView.h>
#endif

#if __has_include(<ReactAppDependencyProvider/RCTAppDependencyProvider.h>)
#import <ReactAppDependencyProvider/RCTAppDependencyProvider.h>
#endif

static NSString *const kBundlePath = @"js/RNTesterApp.macos";
#endif // macOS]

#if TARGET_OS_VISION // [visionOS
#import "SceneDelegate.h"
#endif // visionOS]

#if !TARGET_OS_TV
@interface AppDelegate () <UNUserNotificationCenterDelegate>
@end
#endif

@implementation AppDelegate

#if !TARGET_OS_OSX // [macOS]
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
#if !TARGET_OS_TV
  [[UNUserNotificationCenter currentNotificationCenter] setDelegate:self];
#endif
  return YES;
}
#else // [macOS
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  self.reactNativeFactory = [[RCTReactNativeFactory alloc] initWithDelegate:self];
#if __has_include(<ReactAppDependencyProvider/RCTAppDependencyProvider.h>)
  self.dependencyProvider = [RCTAppDependencyProvider new];
#endif

  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 720)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable |
                                            NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  self.window.title = @"RNTesterApp";

  [self.reactNativeFactory startReactNativeWithModuleName:@"RNTesterApp"
                                                 inWindow:self.window
                                        initialProperties:[self prepareInitialProps]
                                            launchOptions:[notification userInfo]];

  [[UNUserNotificationCenter currentNotificationCenter] setDelegate:self];
}

- (NSDictionary *)prepareInitialProps
{
  NSMutableDictionary *initProps = [NSMutableDictionary dictionary];
  NSString *routeUri = [[NSUserDefaults standardUserDefaults] stringForKey:@"route"];
  if (routeUri != nil) {
    NSString *example = [NSString stringWithFormat:@"rntester://example/%@Example", routeUri];
    initProps[@"exampleFromAppetizeParams"] = example;
  }
  return [initProps copy];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self bundleURL];
}

- (NSURL *)bundleURL
{
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:kBundlePath];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const std::string &)name
                                                      jsInvoker:(std::shared_ptr<facebook::react::CallInvoker>)jsInvoker
{
  if (name == facebook::react::NativeCxxModuleExample::kModuleName) {
    return std::make_shared<facebook::react::NativeCxxModuleExample>(jsInvoker);
  }

  return [super getTurboModule:name jsInvoker:jsInvoker];
}

- (NSArray<id<RCTBridgeModule>> *)extraModulesForBridge:(__unused RCTBridge *)bridge
{
  return @[
    [[FlexibleSizeExampleViewManager alloc] initWithRootViewFactory:self.reactNativeFactory.rootViewFactory],
    [[UpdatePropertiesExampleViewManager alloc] initWithRootViewFactory:self.reactNativeFactory.rootViewFactory],
  ];
}

#ifndef RN_DISABLE_OSS_PLUGIN_HEADER
- (nonnull NSDictionary<NSString *, Class<RCTComponentViewProtocol>> *)thirdPartyFabricComponents
{
  NSMutableDictionary *dict = [super thirdPartyFabricComponents].mutableCopy;
  if (!dict[@"RNTMyNativeView"]) {
    dict[@"RNTMyNativeView"] = NSClassFromString(@"RNTMyNativeViewComponentView");
  }
  if (!dict[@"SampleNativeComponent"]) {
    dict[@"SampleNativeComponent"] = NSClassFromString(@"RCTSampleNativeComponentComponentView");
  }
  return dict;
}
#endif
#endif // macOS]

#if TARGET_OS_VISION // [visionOS
// The visionOS Info.plist declares a scene manifest without configurations,
// so hand out the shared SceneDelegate here.
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                                   options:(UISceneConnectionOptions *)options
{
  UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:nil
                                                                       sessionRole:connectingSceneSession.role];
  configuration.delegateClass = [SceneDelegate class];
  return configuration;
}
#endif // visionOS]

#if !TARGET_OS_TV
// Required for the remoteNotificationsRegistered event.
- (void)application:(__unused UIApplication *)application
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
  [RCTPushNotificationManager didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

// Required for the remoteNotificationRegistrationError event.
- (void)application:(__unused UIApplication *)application
    didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
  [RCTPushNotificationManager didFailToRegisterForRemoteNotificationsWithError:error];
}

#pragma mark - UNUserNotificationCenterDelegate

// Required for the remoteNotificationReceived and localNotificationReceived events
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
  [RCTPushNotificationManager didReceiveNotification:notification];
  completionHandler(UNNotificationPresentationOptionNone);
}

// Required for the remoteNotificationReceived and localNotificationReceived events
// Called when a notification is tapped from background. (Foreground notification will not be shown per
// the presentation option selected above).
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler
{
  UNNotification *notification = response.notification;

  // This condition will be true if tapping the notification launched the app.
  if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
    // This can be retrieved with getInitialNotification.
    [RCTPushNotificationManager setInitialNotification:notification];
  }

  [RCTPushNotificationManager didReceiveNotification:notification];
  completionHandler();
}
#endif

@end
