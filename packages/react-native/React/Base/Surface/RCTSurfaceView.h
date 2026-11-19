/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTDefines.h>
#import <React/RCTUIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RCTSurfaceProtocol;

#if TARGET_OS_OSX // [macOS
/**
 * Posted (object: the surface view) when the view lands in a window or its
 * window's backing scale changes, i.e. whenever the pixel grid the surface is
 * drawn on may have changed: a window dragged from a Retina panel to a 1x
 * monitor, or opened on a screen other than the main one.
 */
RCT_EXTERN NSString *const RCTSurfaceViewBackingScaleDidChangeNotification;
#endif // macOS]

/**
 * UIView instance which represents the Surface
 */
@interface RCTSurfaceView : RCTUIView // [macOS]

- (instancetype)initWithSurface:(id<RCTSurfaceProtocol>)surface NS_DESIGNATED_INITIALIZER;

@property (nonatomic, weak, readonly, nullable) id<RCTSurfaceProtocol> surface;

@end

NS_ASSUME_NONNULL_END
