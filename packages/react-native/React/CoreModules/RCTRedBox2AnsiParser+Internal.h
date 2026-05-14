/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <React/RCTUIKit.h> // [macOS]

/**
 * Parses ANSI escape sequences in text and produces an NSAttributedString
 * with the corresponding foreground/background colors applied.
 *
 * Uses the Afterglow color theme (matching LogBox's AnsiHighlight.js).
 */
@interface RCTRedBox2AnsiParser : NSObject

+ (NSAttributedString *)attributedStringFromAnsiText:(NSString *)text
                                            baseFont:(UIFont *)font // [macOS] UIFont is @compatibility_alias-ed to NSFont
                                           baseColor:(RCTUIColor *)color; // [macOS]

@end
