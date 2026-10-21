/**
 * Copyright (c) Microsoft Corporation.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// [macOS]

#if TARGET_OS_OSX

#import <React/RCTUILabel.h>

@implementation RCTUILabel {}

- (instancetype)initWithFrame:(NSRect)frameRect
{
  if (self = [super initWithFrame:frameRect]) {
    [self setBezeled:NO];
    [self setDrawsBackground:NO];
    [self setEditable:NO];
    [self setSelectable:NO];
    [self setWantsLayer:YES];
  }
  
  return self;
}

- (void)setText:(NSString *)text
{
  [self setStringValue:text];
}

// [macOS The header declares UILabel's text/numberOfLines/textAlignment. Without
// explicit accessors clang auto-synthesizes ivar-backed ones: the text getter
// then always returns nil and numberOfLines/textAlignment never reach the
// NSTextField. Back them with the AppKit equivalents (microsoft #3056).
- (NSString *)text
{
  return self.stringValue;
}

- (void)setNumberOfLines:(NSInteger)numberOfLines
{
  self.maximumNumberOfLines = numberOfLines;
}

- (NSInteger)numberOfLines
{
  return self.maximumNumberOfLines;
}

- (void)setTextAlignment:(NSTextAlignment)textAlignment
{
  self.alignment = textAlignment;
}

- (NSTextAlignment)textAlignment
{
  return self.alignment;
}
// macOS]

@end

#endif
