/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTUIKit.h> // [macOS]

#if !TARGET_OS_OSX // [macOS]
@interface AppDelegate : UIResponder <UIApplicationDelegate>
#else // [macOS
#if __has_include(<React/RCTDefaultReactNativeFactoryDelegate.h>)
#import <React/RCTDefaultReactNativeFactoryDelegate.h>
#import <React/RCTReactNativeFactory.h>
#else
#import <RCTDefaultReactNativeFactoryDelegate.h>
#import <RCTReactNativeFactory.h>
#endif

// macOS has no UIScene lifecycle, so the app delegate hosts React Native
// directly. iOS and visionOS host it from SceneDelegate.
@interface AppDelegate : RCTDefaultReactNativeFactoryDelegate <NSApplicationDelegate>

@property (nonatomic, strong, nonnull) NSWindow *window;
@property (nonatomic, strong, nonnull) RCTReactNativeFactory *reactNativeFactory;
#endif // macOS]

@end
