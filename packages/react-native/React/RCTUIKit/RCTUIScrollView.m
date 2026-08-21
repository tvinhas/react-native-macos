/**
 * Copyright (c) Microsoft Corporation.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// [macOS]

#if TARGET_OS_OSX

#import <React/RCTUIScrollView.h>

// RCTUIScrollView

@implementation RCTUIScrollView

+ (BOOL)isCompatibleWithResponsiveScrolling
{
  // tvinhas fork (Epistles EP-723): NO, deliberately — and on THIS class,
  // not only the Paper RCTScrollView pair (EP-719). RCTUIScrollView is the
  // macOS NSScrollView base for BOTH architectures: Paper's
  // RCTCustomScrollView and Fabric's RCTEnhancedScrollView subclass it.
  // Neither subclass overrides scrollWheel:, so AppKit's default keeps
  // responsive scrolling (concurrent scroll-event dispatch) ENABLED for a
  // Fabric app even after EP-719 turned it off for the Paper classes.
  // Responsive scrolling moves a claimed scroll gesture's event stream onto
  // AppKit's concurrent dispatch path, bypassing -[NSApplication sendEvent:]
  // and every NSEvent local monitor: the app sees the gesture's Began and
  // then silence (EP-723: first swipe delivers Began-only; the next stroke's
  // Changed stream arrives with no Began of its own). Opting the base class
  // out restores classic main-thread dispatch for every RN scroll view.
  return NO;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    self.scrollEnabled = YES;
    self.drawsBackground = NO;
    self.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_rctuiHandleBoundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:self.contentView];
  }
  
  return self;
}

- (void)_rctuiHandleBoundsDidChange:(NSNotification *)notification
{
  if ([_delegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
    [_delegate scrollViewDidScroll:self];
  }
}

- (void)setEnableFocusRing:(BOOL)enableFocusRing {
  if (_enableFocusRing != enableFocusRing) {
    _enableFocusRing = enableFocusRing;
  }

  if (enableFocusRing) {
    // NSTextView has no focus ring by default so let's use the standard Aqua focus ring.
    [self setFocusRingType:NSFocusRingTypeExterior];
  } else {
    [self setFocusRingType:NSFocusRingTypeNone];
  }
}

// UIScrollView properties missing from NSScrollView
- (CGPoint)contentOffset
{
  return self.documentVisibleRect.origin;
}

- (void)setContentOffset:(CGPoint)contentOffset
{
  [self.documentView scrollPoint:contentOffset];
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated
{
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.3; // Set the duration of the animation
            [self.documentView.animator scrollPoint:contentOffset];
        } completionHandler:nil];
    } else {
        [self.documentView scrollPoint:contentOffset];
    }
}

- (UIEdgeInsets)contentInset
{
  return super.contentInsets;
}

- (void)setContentInset:(UIEdgeInsets)insets
{
  super.contentInsets = insets;
}

- (CGSize)contentSize
{
  return self.documentView.frame.size;
}

- (void)setContentSize:(CGSize)contentSize
{
  CGRect frame = self.documentView.frame;
  frame.size = contentSize;
  self.documentView.frame = frame;
}

- (BOOL)showsHorizontalScrollIndicator
{
	return self.hasHorizontalScroller;
}

- (void)setShowsHorizontalScrollIndicator:(BOOL)show
{
	self.hasHorizontalScroller = show;
}

- (BOOL)showsVerticalScrollIndicator
{
	return self.hasVerticalScroller;
}

- (void)setShowsVerticalScrollIndicator:(BOOL)show
{
	self.hasVerticalScroller = show;
}

- (UIEdgeInsets)scrollIndicatorInsets
{
	return self.scrollerInsets;
}

- (void)setScrollIndicatorInsets:(UIEdgeInsets)insets
{
	self.scrollerInsets = insets;
}

- (CGFloat)zoomScale
{
  return self.magnification;
}

- (void)setZoomScale:(CGFloat)zoomScale
{
  self.magnification = zoomScale;
}

- (CGFloat)maximumZoomScale
{
  return self.maxMagnification;
}

- (void)setMaximumZoomScale:(CGFloat)maximumZoomScale
{
  self.maxMagnification = maximumZoomScale;
}

- (CGFloat)minimumZoomScale
{
  return self.minMagnification;
}

- (void)setMinimumZoomScale:(CGFloat)minimumZoomScale
{
  self.minMagnification = minimumZoomScale;
}


- (BOOL)alwaysBounceHorizontal
{
  return self.horizontalScrollElasticity != NSScrollElasticityNone;
}

- (void)setAlwaysBounceHorizontal:(BOOL)alwaysBounceHorizontal
{
  self.horizontalScrollElasticity = alwaysBounceHorizontal ? NSScrollElasticityAllowed : NSScrollElasticityNone;
}

- (BOOL)alwaysBounceVertical
{
  return self.verticalScrollElasticity != NSScrollElasticityNone;
}

- (void)setAlwaysBounceVertical:(BOOL)alwaysBounceVertical
{
  self.verticalScrollElasticity = alwaysBounceVertical ? NSScrollElasticityAllowed : NSScrollElasticityNone;
}

@end

@implementation RCTClipView

- (instancetype)initWithFrame:(NSRect)frameRect
{
   if (self = [super initWithFrame:frameRect]) {
    self.constrainScrolling = NO;
    self.drawsBackground = NO;
  }
  
  return self;
}

- (NSRect)constrainBoundsRect:(NSRect)proposedBounds
{
  if (self.constrainScrolling) {
    return NSMakeRect(0, 0, 0, 0);
  }
  
  return [super constrainBoundsRect:proposedBounds];
}

@end

#endif
