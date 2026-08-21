/*
 * Copyright (c) Microsoft Corporation.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

 // [macOS]

#if TARGET_OS_OSX

#import <React/RCTWrappedTextView.h>

#import <React/RCTUITextView.h>
#import <React/RCTTextAttributes.h>

@implementation RCTWrappedTextView {
  RCTUITextView *_forwardingTextView;
  RCTUIScrollView *_scrollView;
  RCTClipView *_clipView;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    self.hideVerticalScrollIndicator = NO;

    _scrollView = [[RCTUIScrollView alloc] initWithFrame:self.bounds];
    _scrollView.backgroundColor = [RCTPlatformColor clearColor];
    _scrollView.drawsBackground = NO;
    _scrollView.borderType = NSNoBorder;
    _scrollView.hasHorizontalRuler = NO;
    _scrollView.hasVerticalRuler = NO;
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:NO];
    
    _clipView = [[RCTClipView alloc] initWithFrame:_scrollView.bounds];
    [_scrollView setContentView:_clipView];
    
    _forwardingTextView = [[RCTUITextView alloc] initWithFrame:_scrollView.bounds];
    _forwardingTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _forwardingTextView.delegate = self;
    
    _forwardingTextView.verticallyResizable = YES;
    _forwardingTextView.horizontallyResizable = YES;
    // [Epistles] EP-266 / EP-193 / EP-199: give the NSTextView a floor height.
    // Upstream leaves a `verticallyResizable` NSTextView with no `minSize`, so
    // it collapses to its CONTENT height — in a sparsely-filled multiline field
    // only a one-line strip at the top is the real text view and the rest of the
    // visible box is bare NSClipView that swallows clicks. Clicking there fails
    // to focus (only Tab works). `minSize` is the documented "text view in a
    // scroll view" floor; we keep its height matched to the visible box in
    // -setFrameSize: below so the whole box stays clickable while the field can
    // still grow past the box (scrolling) when content exceeds it.
    //
    // EP-328: the WIDTH component of `minSize` is load-bearing too and must
    // never be 0. The text view is `horizontallyResizable` and the container
    // has `widthTracksTextView`, so with a 0 floor the view shrinks to its
    // CONTENT width, the container follows it down, and the text wraps after
    // roughly one character (an empty field wraps its placeholder into a
    // one-glyph column). Keep the floor at the visible box width — maintained
    // on every layout pass in -setFrameSize: below.
    _forwardingTextView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _forwardingTextView.minSize = self.bounds.size;
    _forwardingTextView.textContainer.containerSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _forwardingTextView.textContainer.widthTracksTextView = YES;
    _forwardingTextView.textInputDelegate = self;
    if ([_forwardingTextView respondsToSelector:@selector(setEnableFocusRing:)]) {
      [_forwardingTextView setEnableFocusRing:YES];
    }
    
    _scrollView.documentView = _forwardingTextView;
    _scrollView.contentView.postsBoundsChangedNotifications = YES;
    
    // Enable the focus ring by default
    _scrollView.enableFocusRing = YES;
    [self addSubview:_scrollView];
    
    // a register for those notifications on the content view.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(boundsDidChange:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:_scrollView.contentView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scrollViewDidScroll:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:_scrollView.contentView];
  }

  return self;
}

// [Epistles] EP-266: keep the editable text view at least as tall as the
// visible box on every layout pass, so a click anywhere in the field lands on
// a focusable view instead of dead NSClipView (see initWithFrame:). Runs after
// super so the auto-resized scroll view already reports its new visible height.
// The text view is only GROWN to fill, never shrunk, so content taller than the
// box keeps scrolling normally.
//
// [Epistles] EP-328: the same floor applies to WIDTH. Without it the
// horizontally-resizable text view collapses to its content width and, because
// the text container tracks the text view, the text wraps one character per
// line. Width is pinned to the visible box (there is no horizontal scroller),
// height stays a floor only.
- (void)setFrameSize:(NSSize)newSize
{
  [super setFrameSize:newSize];
  NSSize visibleSize = _scrollView.contentSize;
  _forwardingTextView.minSize = visibleSize;
  NSRect textFrame = _forwardingTextView.frame;
  BOOL needsResize = NO;
  if (textFrame.size.width != visibleSize.width) {
    textFrame.size.width = visibleSize.width;
    needsResize = YES;
  }
  if (textFrame.size.height < visibleSize.height) {
    textFrame.size.height = visibleSize.height;
    needsResize = YES;
  }
  if (needsResize) {
    _forwardingTextView.frame = textFrame;
  }
}

- (BOOL)isFlipped
{
  return YES;
}

#pragma mark -
#pragma mark Method forwarding to text view

- (void)forwardInvocation:(NSInvocation *)invocation
{
  [invocation invokeWithTarget:_forwardingTextView];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
  if ([_forwardingTextView respondsToSelector:selector]) {
    return [_forwardingTextView methodSignatureForSelector:selector];
  }
  
  return [super methodSignatureForSelector:selector];
}

- (void)boundsDidChange:(NSNotification *)notification
{
}

#pragma mark -
#pragma mark First Responder forwarding

- (NSResponder *)responder
{
  return _forwardingTextView;
}

- (BOOL)acceptsFirstResponder
{
  return _forwardingTextView.acceptsFirstResponder;
}

- (BOOL)becomeFirstResponder
{
  return [_forwardingTextView becomeFirstResponder];
}

- (BOOL)resignFirstResponder
{
  return [_forwardingTextView resignFirstResponder];
}

#pragma mark -
#pragma mark Text Input delegate forwarding

- (id<RCTBackedTextInputDelegate>)textInputDelegate
{
  return _forwardingTextView.textInputDelegate;
}

- (void)setTextInputDelegate:(id<RCTBackedTextInputDelegate>)textInputDelegate
{
  _forwardingTextView.textInputDelegate = textInputDelegate;
}

#pragma mark -
#pragma mark Scrolling control

#if TARGET_OS_OSX // [macOS
- (void)scrollViewDidScroll:(NSNotification *)notification
{
  [self.textInputDelegate scrollViewDidScroll:_scrollView];
}
#endif // macOS]

- (BOOL)scrollEnabled
{
  return _scrollView.isScrollEnabled;
}

- (void)setScrollEnabled:(BOOL)scrollEnabled
{
  _scrollView.scrollEnabled = scrollEnabled;
  [_clipView setConstrainScrolling:!scrollEnabled];
}

- (BOOL)shouldShowVerticalScrollbar
{
  // Hide vertical scrollbar if explicity set to NO
  if (self.hideVerticalScrollIndicator) {
    return NO;
  }

  // Hide vertical scrollbar if attributed text overflows view
  CGSize textViewSize = [_forwardingTextView intrinsicContentSize];
  NSClipView *clipView = (NSClipView *)_scrollView.contentView;
  if (textViewSize.height > clipView.bounds.size.height) {
    return YES;
  };

  return NO;
}

- (void)textInputDidChange
{
  [_scrollView setHasVerticalScroller:[self shouldShowVerticalScrollbar]];
}

- (void)setAttributedText:(NSAttributedString *)attributedText
{
  [_forwardingTextView setAttributedText:attributedText];
  [_scrollView setHasVerticalScroller:[self shouldShowVerticalScrollbar]];
}

#pragma mark -
#pragma mark Text Container Inset override for NSTextView

// This method is there to match the textContainerInset property on RCTUITextField
- (void)setTextContainerInset:(UIEdgeInsets)textContainerInsets
{
  // RCTUITextView has logic in setTextContainerInset[s] to convert the UIEdgeInsets to a valid NSSize struct
  _forwardingTextView.textContainerInsets = textContainerInsets;
}

#pragma mark -
#pragma mark Focus ring

- (BOOL)enableFocusRing
{
  if ([_forwardingTextView respondsToSelector:@selector(enableFocusRing)]) {
    return [_forwardingTextView enableFocusRing];
  }

  return _scrollView.enableFocusRing;
}

- (void)setEnableFocusRing:(BOOL)enableFocusRing 
{
  _scrollView.enableFocusRing = enableFocusRing;
  if ([_forwardingTextView respondsToSelector:@selector(setEnableFocusRing:)]) {
    [_forwardingTextView setEnableFocusRing:enableFocusRing];
  }
}

@end

#endif // TARGET_OS_OSX
