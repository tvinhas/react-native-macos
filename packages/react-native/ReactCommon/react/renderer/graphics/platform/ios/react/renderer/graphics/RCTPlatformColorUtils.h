/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#import <React/RCTUIKit.h>
#import <vector>

namespace facebook::react {
struct ColorComponents;
struct Color;
} // namespace facebook::react

NS_ASSUME_NONNULL_BEGIN

facebook::react::ColorComponents RCTPlatformColorComponentsFromSemanticItems(std::vector<std::string> &semanticItems);
RCTPlatformColor *RCTPlatformColorFromSemanticItems(std::vector<std::string> &semanticItems); // [macOS]
// Like RCTPlatformColorFromSemanticItems but returns nil on a miss, so callers
// can tell a miss from a name that resolves to transparent.
RCTPlatformColor *_Nullable RCTPlatformColorFromSemanticItemsOrNil(std::vector<std::string> &semanticItems); // [macOS]
// Precondition: `color` is a resolved color, never the miss sentinel, so the
// result stays _Nonnull.
RCTPlatformColor *RCTPlatformColorFromColor(const facebook::react::Color &color); // [macOS]

NS_ASSUME_NONNULL_END
