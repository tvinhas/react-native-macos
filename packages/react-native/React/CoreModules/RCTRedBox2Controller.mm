/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RCTRedBox2Controller+Internal.h"

#import <React/RCTDefines.h>
#import <React/RCTJSStackFrame.h>
#import <React/RCTReloadCommand.h>
#import <React/RCTUIKit.h> // [macOS]
#import <React/RCTUtils.h>

#include <array>

#if TARGET_OS_OSX // [macOS]
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#endif // macOS]

#import "RCTJscSafeUrl+Internal.h"
#import "RCTRedBox2AnsiParser+Internal.h"
#import "RCTRedBox2ErrorParser+Internal.h"
#import "RCTRedBoxHMRClient+Internal.h"

// @lint-ignore-every CLANGTIDY clang-diagnostic-switch-default
// NOTE: clang-diagnostic-switch-default conflicts with clang-diagnostic-switch-enum

#if RCT_DEV_MENU

#if !TARGET_OS_OSX // [macOS]

#pragma mark - RCTRedBox2Controller

// Color Palette (matching LogBoxStyle.js)
static UIColor *RCTRedBox2BackgroundColor()
{
  return [UIColor colorWithRed:51.0 / 255 green:51.0 / 255 blue:51.0 / 255 alpha:1.0];
}

static UIColor *RCTRedBox2ErrorColor()
{
  return [UIColor colorWithRed:243.0 / 255 green:83.0 / 255 blue:105.0 / 255 alpha:1.0];
}

static UIColor *RCTRedBox2TextColor(CGFloat opacity)
{
  return [UIColor colorWithWhite:1.0 alpha:opacity];
}

enum class Section : uint8_t { Message, CodeFrame, CallStack, kMaxValue };
static constexpr size_t kSectionCount = static_cast<size_t>(Section::kMaxValue);

struct SectionState {
  bool visible = false;
};

static const NSTimeInterval kAutoRetryInterval = 20.0;

@implementation RCTRedBox2Controller {
  UITableView *_stackTraceTableView;
  UILabel *_headerTitleLabel;
  UILabel *_errorCategoryLabel;
  NSString *_lastErrorMessage;
  NSArray<RCTJSStackFrame *> *_lastStackTrace;
  NSArray<NSString *> *_customButtonTitles;
  NSArray<RCTRedBox2ButtonPressHandler> *_customButtonHandlers;
  int _lastErrorCookie;
  RCTRedBox2ErrorData *_errorData;
  std::array<SectionState, kSectionCount> _sectionStates;
  NSTimer *_autoRetryTimer;
  NSInteger _autoRetryCountdown;
  UIButton *_reloadButton;
  NSString *_reloadBaseText;
  RCTRedBoxHMRClient *_hmrClient;
}

- (instancetype)initWithCustomButtonTitles:(NSArray<NSString *> *)customButtonTitles
                      customButtonHandlers:(NSArray<RCTRedBox2ButtonPressHandler> *)customButtonHandlers
{
  self = [super init];
  if (self != nullptr) {
    _lastErrorCookie = -1;
    _customButtonTitles = customButtonTitles;
    _customButtonHandlers = customButtonHandlers;
    self.modalPresentationStyle = UIModalPresentationFullScreen;
  }
  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = RCTRedBox2BackgroundColor();

  // Header bar (adds itself to self.view)
  UIView *headerBar = [self createHeaderBar];

  // Footer button bar
  UIView *footerBar = [self createFooterBar];

  // Stack trace table
  _stackTraceTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  _stackTraceTableView.translatesAutoresizingMaskIntoConstraints = NO;
  _stackTraceTableView.delegate = self;
  _stackTraceTableView.dataSource = self;
  _stackTraceTableView.backgroundColor = [UIColor clearColor];
#if !TARGET_OS_TV
  _stackTraceTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
#endif
  _stackTraceTableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
  _stackTraceTableView.bounces = NO;
  [self.view addSubview:_stackTraceTableView];

  [NSLayoutConstraint activateConstraints:@[
    [_stackTraceTableView.topAnchor constraintEqualToAnchor:headerBar.bottomAnchor],
    [_stackTraceTableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_stackTraceTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_stackTraceTableView.bottomAnchor constraintEqualToAnchor:footerBar.topAnchor],
  ]];
}

#pragma mark - Header Bar

- (UIView *)createHeaderBar
{
  UIView *headerContainer = [[UIView alloc] init];
  headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
  headerContainer.backgroundColor = RCTRedBox2ErrorColor();

  _headerTitleLabel = [[UILabel alloc] init];
  _headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  _headerTitleLabel.textColor = [UIColor whiteColor];
  _headerTitleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
  _headerTitleLabel.textAlignment = NSTextAlignmentCenter;
  [headerContainer addSubview:_headerTitleLabel];

  [self.view addSubview:headerContainer];

  [NSLayoutConstraint activateConstraints:@[
    [headerContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [headerContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [headerContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

    [_headerTitleLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:12],
    [_headerTitleLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-12],
    [_headerTitleLabel.bottomAnchor constraintEqualToAnchor:headerContainer.bottomAnchor constant:-12],
    [_headerTitleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
  ]];

  return headerContainer;
}

#pragma mark - Footer Bar

- (UIView *)createFooterBar
{
  const CGFloat buttonHeight = 48;

  NSString *reloadText = @"Reload";
  NSString *dismissText = @"Dismiss";
  NSString *copyText = @"Copy";

  UIButton *dismissButton = [self footerButton:dismissText
                       accessibilityIdentifier:@"redbox-dismiss"
                                      selector:@selector(dismiss)];
  _reloadBaseText = reloadText;
  _reloadButton = [self footerButton:reloadText accessibilityIdentifier:@"redbox-reload" selector:@selector(reload)];
  UIButton *copyButton = [self footerButton:copyText
                    accessibilityIdentifier:@"redbox-copy"
                                   selector:@selector(copyStack)];

  UIStackView *buttonStackView = [[UIStackView alloc] init];
  buttonStackView.translatesAutoresizingMaskIntoConstraints = NO;
  buttonStackView.axis = UILayoutConstraintAxisHorizontal;
  buttonStackView.distribution = UIStackViewDistributionFillEqually;
  buttonStackView.alignment = UIStackViewAlignmentTop;
  buttonStackView.backgroundColor = RCTRedBox2BackgroundColor();

  [buttonStackView addArrangedSubview:dismissButton];
  [buttonStackView addArrangedSubview:_reloadButton];
  [buttonStackView addArrangedSubview:copyButton];

  for (NSUInteger i = 0; i < [_customButtonTitles count]; i++) {
    UIButton *button = [self footerButton:_customButtonTitles[i]
                  accessibilityIdentifier:@""
                                  handler:_customButtonHandlers[i]];
    [buttonStackView addArrangedSubview:button];
  }

  // Shadow layer above footer
  buttonStackView.layer.shadowColor = [UIColor blackColor].CGColor;
  buttonStackView.layer.shadowOffset = CGSizeMake(0, -2);
  buttonStackView.layer.shadowRadius = 2;
  buttonStackView.layer.shadowOpacity = 0.5;

  [self.view addSubview:buttonStackView];

  CGFloat bottomInset = [self bottomSafeViewHeight];

  [NSLayoutConstraint activateConstraints:@[
    [buttonStackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [buttonStackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [buttonStackView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [buttonStackView.heightAnchor constraintEqualToConstant:buttonHeight + bottomInset],
  ]];

  for (UIButton *btn in buttonStackView.arrangedSubviews) {
    [btn.heightAnchor constraintEqualToConstant:buttonHeight].active = YES;
  }

  return buttonStackView;
}

- (UIButton *)styledButton:(NSString *)title accessibilityIdentifier:(NSString *)accessibilityIdentifier
{
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.accessibilityIdentifier = accessibilityIdentifier;
  button.titleLabel.font = [UIFont systemFontOfSize:14];
  button.titleLabel.textAlignment = NSTextAlignmentCenter;
  button.backgroundColor = RCTRedBox2BackgroundColor();
  [button setTitle:title forState:UIControlStateNormal];
  [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  [button setTitleColor:RCTRedBox2TextColor(0.5) forState:UIControlStateHighlighted];
  return button;
}

- (UIButton *)footerButton:(NSString *)title
    accessibilityIdentifier:(NSString *)accessibilityIdentifier
                   selector:(SEL)selector
{
  UIButton *button = [self styledButton:title accessibilityIdentifier:accessibilityIdentifier];
  [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
  return button;
}

- (UIButton *)footerButton:(NSString *)title
    accessibilityIdentifier:(NSString *)accessibilityIdentifier
                    handler:(RCTRedBox2ButtonPressHandler)handler
{
  UIButton *button = [self styledButton:title accessibilityIdentifier:accessibilityIdentifier];
  [button addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
            handler();
          }]
      forControlEvents:UIControlEventTouchUpInside];
  return button;
}

- (CGFloat)bottomSafeViewHeight
{
#if TARGET_OS_MACCATALYST
  return 0;
#else
  return RCTKeyWindow().safeAreaInsets.bottom;
#endif
}

#pragma mark - Error Display

- (NSString *)stripAnsi:(NSString *)text
{
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\x1b\\[[0-9;]*m"
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:&error];
  return [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, [text length]) withTemplate:@""];
}

- (void)showErrorMessage:(NSString *)message
               withStack:(NSArray<RCTJSStackFrame *> *)stack
                isUpdate:(BOOL)isUpdate
             errorCookie:(int)errorCookie
{
  // Remove ANSI color codes from the message
  NSString *messageWithoutAnsi = [self stripAnsi:message];

  BOOL isRootViewControllerPresented = self.presentingViewController != nil;
  // Show if this is a new message, or if we're updating the previous message
  BOOL isNew = !isRootViewControllerPresented && !isUpdate;
  BOOL isUpdateForSameMessage = !isNew &&
      (isRootViewControllerPresented && isUpdate &&
       ((errorCookie == -1 && [_lastErrorMessage isEqualToString:messageWithoutAnsi]) ||
        (errorCookie == _lastErrorCookie)));
  if (isNew || isUpdateForSameMessage) {
    _lastStackTrace = stack;
    // message is displayed using UILabel, which is unable to render text of
    // unlimited length, so we truncate it
    _lastErrorMessage = [messageWithoutAnsi substringToIndex:MIN((NSUInteger)10000, messageWithoutAnsi.length)];
    _lastErrorCookie = errorCookie;

    // Parse the message to extract structure (title, code frame, etc.)
    _errorData = [RCTRedBox2ErrorParser parseErrorMessage:message name:nil componentStack:nil isFatal:YES];
    [self updateSectionVisibility];

    [_stackTraceTableView reloadData];

    if (!isRootViewControllerPresented) {
      [RCTKeyWindow().rootViewController presentViewController:self animated:NO completion:nil];
    }

    // Update all UI from _errorData (view is now guaranteed to be loaded)
    _headerTitleLabel.text = _errorData.isCompileError ? @"Failed to compile" : @"Error";
    [_stackTraceTableView reloadData];
    [_stackTraceTableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]
                                atScrollPosition:UITableViewScrollPositionTop
                                        animated:NO];

    [self startAutoRetryIfApplicable];
    [self _startHMRClient];
  }
}

- (void)dismiss
{
  [self stopAutoRetry];
  [self dismissViewControllerAnimated:NO completion:nil];
}

- (void)reload
{
  [self _stopHMRClient];
  [self stopAutoRetry];
  if (_actionDelegate != nil) {
    [_actionDelegate reloadFromRedBoxController:self];
  } else {
    // In bridgeless mode `RCTRedBox` gets deallocated, we need to notify listeners anyway.
    RCTTriggerReloadCommandListeners(@"Redbox");
    [self dismiss];
  }
}

#pragma mark - Native HMR Connection

- (void)_startHMRClient
{
  [self _stopHMRClient];
  if (!_bundleURL) {
    return;
  }
  __weak __typeof(self) weakSelf = self;
  _hmrClient = [[RCTRedBoxHMRClient alloc] initWithBundleURL:_bundleURL
                                                onFileChange:^{
                                                  [weakSelf reload];
                                                }];
  [_hmrClient start];
}

- (void)_stopHMRClient
{
  [_hmrClient stop];
  _hmrClient = nil;
}

#pragma mark - Auto-Retry

- (void)startAutoRetryIfApplicable
{
  [self stopAutoRetry];
  if (!_errorData.isRetryable) {
    return;
  }
  _autoRetryCountdown = (NSInteger)kAutoRetryInterval;
  [self updateReloadButtonTitle];
  _autoRetryTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                     target:self
                                                   selector:@selector(autoRetryTick)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)stopAutoRetry
{
  [_autoRetryTimer invalidate];
  _autoRetryTimer = nil;
  if (_reloadButton) {
    [_reloadButton setTitle:_reloadBaseText forState:UIControlStateNormal];
  }
}

- (void)autoRetryTick
{
  _autoRetryCountdown--;
  if (_autoRetryCountdown <= 0) {
    [self stopAutoRetry];
    [self reload];
  } else {
    [self updateReloadButtonTitle];
  }
}

- (void)updateReloadButtonTitle
{
  NSString *title = [NSString stringWithFormat:@"%@ (%lds)", _reloadBaseText, (long)_autoRetryCountdown];
  [_reloadButton setTitle:title forState:UIControlStateNormal];
}

- (void)copyStack
{
  NSMutableString *fullStackTrace;

  if (_lastErrorMessage != nil) {
    fullStackTrace = [_lastErrorMessage mutableCopy];
    [fullStackTrace appendString:@"\n\n"];
  } else {
    fullStackTrace = [NSMutableString string];
  }

  for (RCTJSStackFrame *stackFrame in _lastStackTrace) {
    [fullStackTrace appendString:[NSString stringWithFormat:@"%@\n", stackFrame.methodName]];
    if (stackFrame.file != nullptr) {
      [fullStackTrace appendFormat:@"    %@\n", [self formatFrameSource:stackFrame]];
    }
  }
#if !TARGET_OS_TV
  UIPasteboard *pb = [UIPasteboard generalPasteboard];
  [pb setString:fullStackTrace];
#endif
}

- (NSString *)formatFrameSource:(RCTJSStackFrame *)stackFrame
{
  NSString *file = [RCTJscSafeUrl normalUrlFromJscSafeUrl:stackFrame.file];
  // Strip query string (e.g. ?platform=ios&dev=true) before extracting the filename.
  NSRange queryRange = [file rangeOfString:@"?"];
  if (queryRange.location != NSNotFound) {
    file = [file substringToIndex:queryRange.location];
  }
  NSString *fileName = RCTNilIfNull(file) ? [file lastPathComponent] : @"<unknown file>";
  NSString *lineInfo = [NSString stringWithFormat:@"%@:%lld", fileName, (long long)stackFrame.lineNumber];

  if (stackFrame.column != 0) {
    lineInfo = [lineInfo stringByAppendingFormat:@":%lld", (long long)stackFrame.column];
  }
  return lineInfo;
}

#pragma mark - Section Helpers

- (void)updateSectionVisibility
{
  _sectionStates = {};
  _sectionStates[static_cast<size_t>(Section::Message)].visible = true;
  _sectionStates[static_cast<size_t>(Section::CodeFrame)].visible = _errorData.codeFrame.length > 0;
  _sectionStates[static_cast<size_t>(Section::CallStack)].visible =
      _lastStackTrace.count > 0 && _errorData.codeFrame.length == 0;
}

- (NSInteger)visibleSectionCount
{
  NSInteger count = 0;
  for (size_t i = 0; i < kSectionCount; i++) {
    if (_sectionStates[i].visible) {
      count++;
    }
  }
  return count;
}

- (Section)sectionForIndex:(NSInteger)index
{
  NSInteger visible = 0;
  for (size_t i = 0; i < kSectionCount; i++) {
    if (_sectionStates[i].visible) {
      if (visible == index) {
        return static_cast<Section>(i);
      }
      visible++;
    }
  }
  RCTAssert(NO, @"Invalid section index %ld", (long)index);
  return Section::kMaxValue;
}

- (NSString *)displayMessage
{
  return _errorData.message.length > 0 ? [self stripAnsi:_errorData.message] : _lastErrorMessage;
}

#pragma mark - TableView DataSource & Delegate

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView
{
  return [self visibleSectionCount];
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  if ([self sectionForIndex:section] == Section::CallStack) {
    return static_cast<NSInteger>(_lastStackTrace.count);
  }
  return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  switch ([self sectionForIndex:indexPath.section]) {
    case Section::Message: {
      UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"msg-cell"];
      return [self reuseCell:cell forErrorMessage:[self displayMessage]];
    }
    case Section::CodeFrame: {
      UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"code-cell"];
      return [self reuseCell:cell forCodeFrame:_errorData];
    }
    case Section::CallStack:
    case Section::kMaxValue:
      break;
  }
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
  NSUInteger index = indexPath.row;
  RCTJSStackFrame *stackFrame = _lastStackTrace[index];
  return [self reuseCell:cell forStackFrame:stackFrame];
}

- (UITableViewCell *)reuseCell:(UITableViewCell *)cell forErrorMessage:(NSString *)message
{
  if (cell == nullptr) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"msg-cell"];
    cell.backgroundColor = RCTRedBox2BackgroundColor();
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    // Error category label (e.g. "Syntax Error", "Uncaught Error")
    _errorCategoryLabel = [[UILabel alloc] init];
    _errorCategoryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _errorCategoryLabel.textColor = RCTRedBox2ErrorColor();
    _errorCategoryLabel.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
    _errorCategoryLabel.numberOfLines = 1;
    [cell.contentView addSubview:_errorCategoryLabel];

    // Error message label
    UILabel *messageLabel = [[UILabel alloc] init];
    messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    messageLabel.accessibilityIdentifier = @"redbox-error";
    messageLabel.textColor = [UIColor whiteColor];
    messageLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    messageLabel.lineBreakMode = NSLineBreakByWordWrapping;
    messageLabel.numberOfLines = 0;
    messageLabel.tag = 100;
    [cell.contentView addSubview:messageLabel];

    [NSLayoutConstraint activateConstraints:@[
      [_errorCategoryLabel.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:15],
      [_errorCategoryLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
      [_errorCategoryLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],

      [messageLabel.topAnchor constraintEqualToAnchor:_errorCategoryLabel.bottomAnchor constant:10],
      [messageLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
      [messageLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12],
      [messageLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-15],
    ]];
  }

  _errorCategoryLabel.text = _errorData.title;
  UILabel *messageLabel = [cell.contentView viewWithTag:100];
  messageLabel.text = message;

  return cell;
}

- (UITableViewCell *)reuseCell:(UITableViewCell *)cell forStackFrame:(RCTJSStackFrame *)stackFrame
{
  if (cell == nullptr) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
    cell.textLabel.font = [UIFont fontWithName:@"Menlo-Regular" size:14];
    cell.textLabel.lineBreakMode = NSLineBreakByCharWrapping;
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightLight];
    cell.detailTextLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.backgroundColor = [UIColor clearColor];
    cell.selectedBackgroundView = [UIView new];
    cell.selectedBackgroundView.backgroundColor = RCTRedBox2BackgroundColor();
    cell.selectedBackgroundView.layer.cornerRadius = 5;
  }

  cell.textLabel.text = stackFrame.methodName ?: @"(unnamed method)";
  if (stackFrame.file != nullptr) {
    cell.detailTextLabel.text = [self formatFrameSource:stackFrame];
  } else {
    cell.detailTextLabel.text = @"";
  }

  if (stackFrame.collapse) {
    cell.textLabel.textColor = RCTRedBox2TextColor(0.4);
    cell.detailTextLabel.textColor = RCTRedBox2TextColor(0.3);
  } else {
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = RCTRedBox2TextColor(0.8);
  }

  return cell;
}

- (UITableViewCell *)reuseCell:(UITableViewCell *)cell forCodeFrame:(RCTRedBox2ErrorData *)errorData
{
  if (cell == nullptr) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"code-cell"];
    cell.backgroundColor = [UIColor clearColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
  }

  // Remove old subviews
  for (UIView *subview in cell.contentView.subviews) {
    [subview removeFromSuperview];
  }

  // Code frame container with rounded corners
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  container.backgroundColor = RCTRedBox2BackgroundColor();
  container.layer.cornerRadius = 3;
  container.clipsToBounds = YES;
  [cell.contentView addSubview:container];

  // Render code frame with ANSI syntax highlighting
  UIFont *codeFont = [UIFont fontWithName:@"Menlo-Regular" size:12];
  NSAttributedString *highlighted = [RCTRedBox2AnsiParser attributedStringFromAnsiText:errorData.codeFrame
                                                                              baseFont:codeFont
                                                                             baseColor:[UIColor whiteColor]];

  UILabel *codeLabel = [[UILabel alloc] init];
  codeLabel.translatesAutoresizingMaskIntoConstraints = NO;
  codeLabel.attributedText = highlighted;
  codeLabel.numberOfLines = 0;
  codeLabel.lineBreakMode = NSLineBreakByClipping;

  UIScrollView *codeScrollView = [[UIScrollView alloc] init];
  codeScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  codeScrollView.showsHorizontalScrollIndicator = YES;
  codeScrollView.showsVerticalScrollIndicator = NO;
  codeScrollView.bounces = NO;
  [codeScrollView addSubview:codeLabel];
  [container addSubview:codeScrollView];

  // File name label below the code frame
  UILabel *fileLabel = [[UILabel alloc] init];
  fileLabel.translatesAutoresizingMaskIntoConstraints = NO;
  NSString *fileName = errorData.codeFrameFileName.lastPathComponent ?: errorData.codeFrameFileName;
  if (errorData.codeFrameRow > 0) {
    fileLabel.text = [NSString
        stringWithFormat:@"%@ (%ld:%ld)", fileName, (long)errorData.codeFrameRow, (long)errorData.codeFrameColumn + 1];
  } else if (fileName.length > 0) {
    fileLabel.text = fileName;
  }
  fileLabel.textColor = RCTRedBox2TextColor(0.5);
  fileLabel.font = [UIFont fontWithName:@"Menlo-Regular" size:12];
  fileLabel.textAlignment = NSTextAlignmentCenter;
  [cell.contentView addSubview:fileLabel];

  [NSLayoutConstraint activateConstraints:@[
    [container.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:5],
    [container.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:10],
    [container.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-10],

    [codeScrollView.topAnchor constraintEqualToAnchor:container.topAnchor constant:10],
    [codeScrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:10],
    [codeScrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-10],
    [codeScrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-10],

    [codeLabel.topAnchor constraintEqualToAnchor:codeScrollView.topAnchor],
    [codeLabel.leadingAnchor constraintEqualToAnchor:codeScrollView.leadingAnchor],
    [codeLabel.trailingAnchor constraintEqualToAnchor:codeScrollView.trailingAnchor],
    [codeLabel.bottomAnchor constraintEqualToAnchor:codeScrollView.bottomAnchor],
    [codeLabel.heightAnchor constraintEqualToAnchor:codeScrollView.heightAnchor],

    [fileLabel.topAnchor constraintEqualToAnchor:container.bottomAnchor constant:10],
    [fileLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:10],
    [fileLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-10],
    [fileLabel.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
  ]];

  return cell;
}

- (CGFloat)tableView:(__unused UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
  auto section = [self sectionForIndex:indexPath.section];
  if (section == Section::Message || section == Section::CodeFrame) {
    return UITableViewAutomaticDimension;
  }
  return 50;
}

- (CGFloat)tableView:(__unused UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath
{
  switch ([self sectionForIndex:indexPath.section]) {
    case Section::Message:
      return 100;
    case Section::CodeFrame:
      return 200;
    case Section::CallStack:
    case Section::kMaxValue:
      return 50;
  }
}

- (UIView *)sectionHeaderViewWithTitle:(NSString *)title
{
  UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 38)];
  headerView.backgroundColor = [UIColor clearColor];

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = title;
  label.textColor = [UIColor whiteColor];
  label.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
  [headerView addSubview:label];

  [NSLayoutConstraint activateConstraints:@[
    [label.leadingAnchor constraintEqualToAnchor:headerView.leadingAnchor constant:12],
    [label.trailingAnchor constraintEqualToAnchor:headerView.trailingAnchor constant:-12],
    [label.bottomAnchor constraintEqualToAnchor:headerView.bottomAnchor constant:-10],
  ]];

  return headerView;
}

- (UIView *)tableView:(__unused UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
  switch ([self sectionForIndex:section]) {
    case Section::CodeFrame:
      return [self sectionHeaderViewWithTitle:@"Source"];
    case Section::CallStack:
      return [self sectionHeaderViewWithTitle:@"Call Stack"];
    case Section::Message:
    case Section::kMaxValue:
      return nil;
  }
}

- (CGFloat)tableView:(__unused UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
  auto s = [self sectionForIndex:section];
  return (s == Section::CodeFrame || s == Section::CallStack) ? 38 : 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
  if ([self sectionForIndex:indexPath.section] == Section::CallStack) {
    NSUInteger row = indexPath.row;
    RCTJSStackFrame *stackFrame = _lastStackTrace[row];
    [_actionDelegate redBoxController:self openStackFrameInEditor:stackFrame];
  }
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Key Commands

- (NSArray<UIKeyCommand *> *)keyCommands
{
  return @[
    // Dismiss red box
    [UIKeyCommand keyCommandWithInput:UIKeyInputEscape modifierFlags:0 action:@selector(dismiss)],
    // Reload
    [UIKeyCommand keyCommandWithInput:@"r" modifierFlags:UIKeyModifierCommand action:@selector(reload)],
    // Copy = Cmd-Option C since Cmd-C in the simulator copies the pasteboard from
    // the simulator to the desktop pasteboard.
    [UIKeyCommand keyCommandWithInput:@"c"
                        modifierFlags:UIKeyModifierCommand | UIKeyModifierAlternate
                               action:@selector(copyStack)],
  ];
}

- (BOOL)canBecomeFirstResponder
{
  return YES;
}

@end

#else // [macOS

#pragma mark - RCTRedBox2Controller (macOS)

// Color Palette (matching LogBoxStyle.js)
static RCTUIColor *RCTRedBox2BackgroundColor()
{
  return [RCTUIColor colorWithRed:51.0 / 255 green:51.0 / 255 blue:51.0 / 255 alpha:1.0];
}

static RCTUIColor *RCTRedBox2ErrorColor()
{
  return [RCTUIColor colorWithRed:243.0 / 255 green:83.0 / 255 blue:105.0 / 255 alpha:1.0];
}

static RCTUIColor *RCTRedBox2TextColor(CGFloat opacity)
{
  return [RCTUIColor colorWithWhite:1.0 alpha:opacity];
}

enum class Section : uint8_t { Message, CodeFrame, CallStack, kMaxValue };
static constexpr size_t kSectionCount = static_cast<size_t>(Section::kMaxValue);

struct SectionState {
  bool visible = false;
};

static const NSTimeInterval kAutoRetryInterval = 20.0;

// Row kinds for the flattened table model. NSTableView has no sections, so we
// expand the iOS section/row hierarchy into a single ordered list of rows.
enum class RowKind : uint8_t {
  Message,
  CodeFrame,
  SectionHeader,
  StackFrame,
};

@interface RCTRedBox2RowDescriptor : NSObject
@property (nonatomic, assign) RowKind kind;
@property (nonatomic, copy, nullable) NSString *headerTitle;
@property (nonatomic, strong, nullable) RCTJSStackFrame *stackFrame;
@end

@implementation RCTRedBox2RowDescriptor
@end

// Forward declaration so RCTRedBox2RootView can forward keyDown: to the controller.
@interface RCTRedBox2Controller (KeyHandling)
- (BOOL)handleKeyDown:(NSEvent *)event;
@end

// Container view that opts in to keyDown: routing for the controller.
@interface RCTRedBox2RootView : NSView
@property (nonatomic, weak, nullable) RCTRedBox2Controller *controller;
@end

@implementation RCTRedBox2RootView
- (BOOL)acceptsFirstResponder
{
  return YES;
}
- (BOOL)becomeFirstResponder
{
  return YES;
}
- (void)keyDown:(NSEvent *)event
{
  if ([self.controller handleKeyDown:event]) {
    return;
  }
  [super keyDown:event];
}
@end

// Custom NSTableRowView that draws no selection highlight (mirrors iOS
// UITableViewCellSelectionStyleNone behavior on the message + code-frame rows).
@interface RCTRedBox2NoSelectionRowView : NSTableRowView
@end

@implementation RCTRedBox2NoSelectionRowView
- (void)drawSelectionInRect:(__unused NSRect)dirtyRect
{
  // Intentionally empty — message and code-frame rows are non-selectable.
}
@end

@interface RCTRedBox2Controller () {
 @public
  NSTableView *_stackTraceTableView;
  NSScrollView *_stackTraceScrollView;
  NSTextField *_headerTitleLabel;
  NSTextField *_errorCategoryLabel;
  NSTextField *_messageBodyLabel;
  NSString *_lastErrorMessage;
  NSArray<RCTJSStackFrame *> *_lastStackTrace;
  NSArray<NSString *> *_customButtonTitles;
  NSArray<RCTRedBox2ButtonPressHandler> *_customButtonHandlers;
  int _lastErrorCookie;
  RCTRedBox2ErrorData *_errorData;
  std::array<SectionState, kSectionCount> _sectionStates;
  NSTimer *_autoRetryTimer;
  NSInteger _autoRetryCountdown;
  NSButton *_reloadButton;
  NSString *_reloadBaseText;
  RCTRedBoxHMRClient *_hmrClient;
  NSArray<RCTRedBox2RowDescriptor *> *_rows;
  NSWindow *_redBoxWindow;
  BOOL _isPresented;
}
@end

@implementation RCTRedBox2Controller

- (instancetype)initWithCustomButtonTitles:(NSArray<NSString *> *)customButtonTitles
                      customButtonHandlers:(NSArray<RCTRedBox2ButtonPressHandler> *)customButtonHandlers
{
  self = [super initWithNibName:nil bundle:nil];
  if (self != nullptr) {
    _lastErrorCookie = -1;
    _customButtonTitles = customButtonTitles;
    _customButtonHandlers = customButtonHandlers;
    _rows = @[];
  }
  return self;
}

- (void)loadView
{
  RCTRedBox2RootView *rootView = [[RCTRedBox2RootView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
  rootView.controller = self;
  rootView.wantsLayer = YES;
  rootView.layer.backgroundColor = RCTRedBox2BackgroundColor().CGColor;
  self.view = rootView;
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  // Header bar (adds itself to self.view)
  NSView *headerBar = [self createHeaderBar];

  // Footer button bar
  NSView *footerBar = [self createFooterBar];

  // Stack trace table
  _stackTraceTableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
  _stackTraceTableView.translatesAutoresizingMaskIntoConstraints = NO;
  _stackTraceTableView.dataSource = self;
  _stackTraceTableView.delegate = self;
  _stackTraceTableView.headerView = nil;
  _stackTraceTableView.allowsColumnReordering = NO;
  _stackTraceTableView.allowsColumnResizing = NO;
  _stackTraceTableView.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
  _stackTraceTableView.backgroundColor = [NSColor clearColor];
  _stackTraceTableView.allowsTypeSelect = NO;
  _stackTraceTableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleNone;
  _stackTraceTableView.intercellSpacing = NSMakeSize(0, 0);
  _stackTraceTableView.gridStyleMask = NSTableViewGridNone;
  _stackTraceTableView.target = self;
  _stackTraceTableView.action = @selector(handleTableClick:);

  NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:@"info"];
  tableColumn.resizingMask = NSTableColumnAutoresizingMask;
  [_stackTraceTableView addTableColumn:tableColumn];

  _stackTraceScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  _stackTraceScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  _stackTraceScrollView.autoresizesSubviews = YES;
  _stackTraceScrollView.drawsBackground = NO;
  _stackTraceScrollView.hasVerticalScroller = YES;
  _stackTraceScrollView.hasHorizontalScroller = NO;
  _stackTraceScrollView.borderType = NSNoBorder;
  _stackTraceScrollView.documentView = _stackTraceTableView;
  [self.view addSubview:_stackTraceScrollView];

  [NSLayoutConstraint activateConstraints:@[
    [_stackTraceScrollView.topAnchor constraintEqualToAnchor:headerBar.bottomAnchor],
    [_stackTraceScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [_stackTraceScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [_stackTraceScrollView.bottomAnchor constraintEqualToAnchor:footerBar.topAnchor],
  ]];
}

- (void)viewDidAppear
{
  [super viewDidAppear];
  // Make sure our root view captures key events so Escape / Cmd-R / Cmd-Option-C work.
  [self.view.window makeFirstResponder:self.view];
}

#pragma mark - Helpers

+ (NSTextField *)labelWithText:(nullable NSString *)text
{
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.editable = NO;
  label.bordered = NO;
  label.bezeled = NO;
  label.drawsBackground = NO;
  label.selectable = NO;
  label.stringValue = text ?: @"";
  return label;
}

#pragma mark - Header Bar

- (NSView *)createHeaderBar
{
  NSView *headerContainer = [[NSView alloc] init];
  headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
  headerContainer.wantsLayer = YES;
  headerContainer.layer.backgroundColor = RCTRedBox2ErrorColor().CGColor;

  _headerTitleLabel = [RCTRedBox2Controller labelWithText:@""];
  _headerTitleLabel.textColor = [NSColor whiteColor];
  _headerTitleLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold];
  _headerTitleLabel.alignment = NSTextAlignmentCenter;
  [headerContainer addSubview:_headerTitleLabel];

  [self.view addSubview:headerContainer];

  [NSLayoutConstraint activateConstraints:@[
    [headerContainer.topAnchor constraintEqualToAnchor:self.view.topAnchor],
    [headerContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [headerContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

    [_headerTitleLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:12],
    [_headerTitleLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-12],
    [_headerTitleLabel.topAnchor constraintEqualToAnchor:headerContainer.topAnchor constant:12],
    [_headerTitleLabel.bottomAnchor constraintEqualToAnchor:headerContainer.bottomAnchor constant:-12],
  ]];

  return headerContainer;
}

#pragma mark - Footer Bar

- (NSView *)createFooterBar
{
  const CGFloat buttonHeight = 48;

  NSString *reloadText = @"Reload";
  NSString *dismissText = @"Dismiss";
  NSString *copyText = @"Copy";

  NSButton *dismissButton = [self footerButton:dismissText
                       accessibilityIdentifier:@"redbox-dismiss"
                                      selector:@selector(dismiss)];
  _reloadBaseText = reloadText;
  _reloadButton = [self footerButton:reloadText accessibilityIdentifier:@"redbox-reload" selector:@selector(reload)];
  NSButton *copyButton = [self footerButton:copyText
                    accessibilityIdentifier:@"redbox-copy"
                                   selector:@selector(copyStack)];

  NSStackView *buttonStackView = [[NSStackView alloc] init];
  buttonStackView.translatesAutoresizingMaskIntoConstraints = NO;
  buttonStackView.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  buttonStackView.distribution = NSStackViewDistributionFillEqually;
  buttonStackView.alignment = NSLayoutAttributeTop;
  buttonStackView.spacing = 0;
  buttonStackView.wantsLayer = YES;
  buttonStackView.layer.backgroundColor = RCTRedBox2BackgroundColor().CGColor;

  [buttonStackView addArrangedSubview:dismissButton];
  [buttonStackView addArrangedSubview:_reloadButton];
  [buttonStackView addArrangedSubview:copyButton];

  for (NSUInteger i = 0; i < [_customButtonTitles count]; i++) {
    NSButton *button = [self footerButton:_customButtonTitles[i]
                  accessibilityIdentifier:@""
                                  handler:_customButtonHandlers[i]];
    [buttonStackView addArrangedSubview:button];
  }

  // Shadow above footer (mirrors iOS shadow on the stack view).
  buttonStackView.layer.shadowColor = [NSColor blackColor].CGColor;
  buttonStackView.layer.shadowOffset = CGSizeMake(0, -2);
  buttonStackView.layer.shadowRadius = 2;
  buttonStackView.layer.shadowOpacity = 0.5;

  [self.view addSubview:buttonStackView];

  CGFloat bottomInset = [self bottomSafeViewHeight];

  [NSLayoutConstraint activateConstraints:@[
    [buttonStackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [buttonStackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [buttonStackView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [buttonStackView.heightAnchor constraintEqualToConstant:buttonHeight + bottomInset],
  ]];

  for (NSView *btn in buttonStackView.arrangedSubviews) {
    [btn.heightAnchor constraintEqualToConstant:buttonHeight].active = YES;
  }

  return buttonStackView;
}

- (NSButton *)styledButton:(NSString *)title accessibilityIdentifier:(NSString *)accessibilityIdentifier
{
  NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.accessibilityIdentifier = accessibilityIdentifier;
  button.bordered = NO;
  button.bezelStyle = NSBezelStyleShadowlessSquare;
  [button setButtonType:NSButtonTypeMomentaryChange];
  button.wantsLayer = YES;
  button.layer.backgroundColor = RCTRedBox2BackgroundColor().CGColor;
  NSAttributedString *attributedTitle = [[NSAttributedString alloc]
      initWithString:title
          attributes:@{
            NSForegroundColorAttributeName : [NSColor whiteColor],
            NSFontAttributeName : [NSFont systemFontOfSize:14],
            NSParagraphStyleAttributeName : ({
              NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
              style.alignment = NSTextAlignmentCenter;
              style;
            }),
          }];
  button.attributedTitle = attributedTitle;
  return button;
}

- (NSButton *)footerButton:(NSString *)title
    accessibilityIdentifier:(NSString *)accessibilityIdentifier
                   selector:(SEL)selector
{
  NSButton *button = [self styledButton:title accessibilityIdentifier:accessibilityIdentifier];
  button.target = self;
  button.action = selector;
  return button;
}

- (NSButton *)footerButton:(NSString *)title
    accessibilityIdentifier:(NSString *)accessibilityIdentifier
                    handler:(RCTRedBox2ButtonPressHandler)handler
{
  NSButton *button = [self styledButton:title accessibilityIdentifier:accessibilityIdentifier];
  // Capture handler via associated object so the button can invoke it.
  objc_setAssociatedObject(button, @selector(rct_handler), handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
  button.target = self;
  button.action = @selector(_invokeCustomButtonHandler:);
  return button;
}

- (void)_invokeCustomButtonHandler:(NSButton *)sender
{
  RCTRedBox2ButtonPressHandler handler = objc_getAssociatedObject(sender, @selector(rct_handler));
  if (handler) {
    handler();
  }
}

- (CGFloat)bottomSafeViewHeight
{
  // macOS has no safe-area inset for the bottom button bar.
  return 0;
}

- (void)_setReloadButtonTitle:(NSString *)title
{
  NSAttributedString *attributed = [[NSAttributedString alloc]
      initWithString:title ?: @""
          attributes:@{
            NSForegroundColorAttributeName : [NSColor whiteColor],
            NSFontAttributeName : [NSFont systemFontOfSize:14],
            NSParagraphStyleAttributeName : ({
              NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
              style.alignment = NSTextAlignmentCenter;
              style;
            }),
          }];
  _reloadButton.attributedTitle = attributed;
}

#pragma mark - Error Display

- (NSString *)stripAnsi:(NSString *)text
{
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\x1b\\[[0-9;]*m"
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:&error];
  return [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, [text length]) withTemplate:@""];
}

- (void)showErrorMessage:(NSString *)message
               withStack:(NSArray<RCTJSStackFrame *> *)stack
                isUpdate:(BOOL)isUpdate
             errorCookie:(int)errorCookie
{
  // Remove ANSI color codes from the message
  NSString *messageWithoutAnsi = [self stripAnsi:message];

  BOOL isAlreadyPresented = _isPresented;
  // Show if this is a new message, or if we're updating the previous message
  BOOL isNew = !isAlreadyPresented && !isUpdate;
  BOOL isUpdateForSameMessage = !isNew &&
      (isAlreadyPresented && isUpdate &&
       ((errorCookie == -1 && [_lastErrorMessage isEqualToString:messageWithoutAnsi]) ||
        (errorCookie == _lastErrorCookie)));
  if (isNew || isUpdateForSameMessage) {
    _lastStackTrace = stack;
    // Match iOS truncation. Even though NSTextField can render more, we keep
    // parity with the iOS branch.
    _lastErrorMessage = [messageWithoutAnsi substringToIndex:MIN((NSUInteger)10000, messageWithoutAnsi.length)];
    _lastErrorCookie = errorCookie;

    // Parse the message to extract structure (title, code frame, etc.)
    _errorData = [RCTRedBox2ErrorParser parseErrorMessage:message name:nil componentStack:nil isFatal:YES];
    [self updateSectionVisibility];
    [self _rebuildRows];

    // Force the view to load so headerTitleLabel etc. are wired up before we
    // present.
    (void)self.view;

    [_stackTraceTableView reloadData];

    if (!isAlreadyPresented) {
      [self _presentWindow];
    }

    _headerTitleLabel.stringValue = _errorData.isCompileError ? @"Failed to compile" : @"Error";
    [_stackTraceTableView reloadData];
    if (_rows.count > 0) {
      [_stackTraceTableView scrollRowToVisible:0];
    }

    [self startAutoRetryIfApplicable];
    [self _startHMRClient];
  }
}

- (void)_presentWindow
{
  if (_isPresented) {
    return;
  }
  NSWindow *parent = NSApp.mainWindow ?: NSApp.keyWindow;
  NSRect frame;
  if (parent != nil) {
    frame = parent.frame;
  } else {
    NSScreen *screen = [NSScreen mainScreen];
    frame = screen ? screen.visibleFrame : NSMakeRect(0, 0, 800, 600);
  }

  _redBoxWindow = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
  _redBoxWindow.releasedWhenClosed = NO;
  _redBoxWindow.level = NSStatusWindowLevel;
  _redBoxWindow.opaque = YES;
  _redBoxWindow.backgroundColor = RCTRedBox2BackgroundColor();
  _redBoxWindow.contentViewController = self;
  [_redBoxWindow makeKeyAndOrderFront:nil];
  [_redBoxWindow makeFirstResponder:self.view];
  _isPresented = YES;
}

- (void)dismiss
{
  [self stopAutoRetry];
  [self _stopHMRClient];
  if (_redBoxWindow) {
    [_redBoxWindow orderOut:nil];
    _redBoxWindow.contentViewController = nil;
    _redBoxWindow = nil;
  }
  _isPresented = NO;
}

- (void)reload
{
  [self _stopHMRClient];
  [self stopAutoRetry];
  if (_actionDelegate != nil) {
    [_actionDelegate reloadFromRedBoxController:self];
  } else {
    // In bridgeless mode `RCTRedBox` gets deallocated, we need to notify listeners anyway.
    RCTTriggerReloadCommandListeners(@"Redbox");
    [self dismiss];
  }
}

#pragma mark - Native HMR Connection

- (void)_startHMRClient
{
  [self _stopHMRClient];
  if (!_bundleURL) {
    return;
  }
  __weak __typeof(self) weakSelf = self;
  _hmrClient = [[RCTRedBoxHMRClient alloc] initWithBundleURL:_bundleURL
                                                onFileChange:^{
                                                  [weakSelf reload];
                                                }];
  [_hmrClient start];
}

- (void)_stopHMRClient
{
  [_hmrClient stop];
  _hmrClient = nil;
}

#pragma mark - Auto-Retry

- (void)startAutoRetryIfApplicable
{
  [self stopAutoRetry];
  if (!_errorData.isRetryable) {
    return;
  }
  _autoRetryCountdown = (NSInteger)kAutoRetryInterval;
  [self updateReloadButtonTitle];
  _autoRetryTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                     target:self
                                                   selector:@selector(autoRetryTick)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)stopAutoRetry
{
  [_autoRetryTimer invalidate];
  _autoRetryTimer = nil;
  if (_reloadButton) {
    [self _setReloadButtonTitle:_reloadBaseText];
  }
}

- (void)autoRetryTick
{
  _autoRetryCountdown--;
  if (_autoRetryCountdown <= 0) {
    [self stopAutoRetry];
    [self reload];
  } else {
    [self updateReloadButtonTitle];
  }
}

- (void)updateReloadButtonTitle
{
  NSString *title = [NSString stringWithFormat:@"%@ (%lds)", _reloadBaseText, (long)_autoRetryCountdown];
  [self _setReloadButtonTitle:title];
}

- (void)copyStack
{
  NSMutableString *fullStackTrace;

  if (_lastErrorMessage != nil) {
    fullStackTrace = [_lastErrorMessage mutableCopy];
    [fullStackTrace appendString:@"\n\n"];
  } else {
    fullStackTrace = [NSMutableString string];
  }

  for (RCTJSStackFrame *stackFrame in _lastStackTrace) {
    [fullStackTrace appendString:[NSString stringWithFormat:@"%@\n", stackFrame.methodName]];
    if (stackFrame.file != nullptr) {
      [fullStackTrace appendFormat:@"    %@\n", [self formatFrameSource:stackFrame]];
    }
  }
  NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
  [pasteboard clearContents];
  [pasteboard setString:fullStackTrace forType:NSPasteboardTypeString];
}

- (NSString *)formatFrameSource:(RCTJSStackFrame *)stackFrame
{
  NSString *file = [RCTJscSafeUrl normalUrlFromJscSafeUrl:stackFrame.file];
  // Strip query string (e.g. ?platform=ios&dev=true) before extracting the filename.
  NSRange queryRange = [file rangeOfString:@"?"];
  if (queryRange.location != NSNotFound) {
    file = [file substringToIndex:queryRange.location];
  }
  NSString *fileName = RCTNilIfNull(file) ? [file lastPathComponent] : @"<unknown file>";
  NSString *lineInfo = [NSString stringWithFormat:@"%@:%lld", fileName, (long long)stackFrame.lineNumber];

  if (stackFrame.column != 0) {
    lineInfo = [lineInfo stringByAppendingFormat:@":%lld", (long long)stackFrame.column];
  }
  return lineInfo;
}

#pragma mark - Section Helpers

- (void)updateSectionVisibility
{
  _sectionStates = {};
  _sectionStates[static_cast<size_t>(Section::Message)].visible = true;
  _sectionStates[static_cast<size_t>(Section::CodeFrame)].visible = _errorData.codeFrame.length > 0;
  _sectionStates[static_cast<size_t>(Section::CallStack)].visible =
      _lastStackTrace.count > 0 && _errorData.codeFrame.length == 0;
}

- (void)_rebuildRows
{
  NSMutableArray<RCTRedBox2RowDescriptor *> *rows = [NSMutableArray array];
  if (_sectionStates[static_cast<size_t>(Section::Message)].visible) {
    RCTRedBox2RowDescriptor *row = [RCTRedBox2RowDescriptor new];
    row.kind = RowKind::Message;
    [rows addObject:row];
  }
  if (_sectionStates[static_cast<size_t>(Section::CodeFrame)].visible) {
    RCTRedBox2RowDescriptor *header = [RCTRedBox2RowDescriptor new];
    header.kind = RowKind::SectionHeader;
    header.headerTitle = @"Source";
    [rows addObject:header];

    RCTRedBox2RowDescriptor *row = [RCTRedBox2RowDescriptor new];
    row.kind = RowKind::CodeFrame;
    [rows addObject:row];
  }
  if (_sectionStates[static_cast<size_t>(Section::CallStack)].visible) {
    RCTRedBox2RowDescriptor *header = [RCTRedBox2RowDescriptor new];
    header.kind = RowKind::SectionHeader;
    header.headerTitle = @"Call Stack";
    [rows addObject:header];

    for (RCTJSStackFrame *frame in _lastStackTrace) {
      RCTRedBox2RowDescriptor *row = [RCTRedBox2RowDescriptor new];
      row.kind = RowKind::StackFrame;
      row.stackFrame = frame;
      [rows addObject:row];
    }
  }
  _rows = rows;
}

- (NSString *)displayMessage
{
  return _errorData.message.length > 0 ? [self stripAnsi:_errorData.message] : _lastErrorMessage;
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(__unused NSTableView *)tableView
{
  return (NSInteger)_rows.count;
}

- (NSTableRowView *)tableView:(__unused NSTableView *)tableView rowViewForRow:(NSInteger)row
{
  if (row < 0 || (NSUInteger)row >= _rows.count) {
    return nil;
  }
  RowKind kind = _rows[(NSUInteger)row].kind;
  if (kind != RowKind::StackFrame) {
    // Non-stack rows are non-selectable; suppress selection highlight too.
    return [[RCTRedBox2NoSelectionRowView alloc] init];
  }
  return nil;
}

- (NSView *)tableView:(NSTableView *)tableView
    viewForTableColumn:(__unused NSTableColumn *)tableColumn
                   row:(NSInteger)row
{
  if (row < 0 || (NSUInteger)row >= _rows.count) {
    return nil;
  }
  RCTRedBox2RowDescriptor *descriptor = _rows[(NSUInteger)row];
  switch (descriptor.kind) {
    case RowKind::Message: {
      NSTableCellView *cell = [tableView makeViewWithIdentifier:@"msg-cell" owner:self];
      return [self reuseCell:cell forErrorMessage:[self displayMessage]];
    }
    case RowKind::CodeFrame: {
      NSTableCellView *cell = [tableView makeViewWithIdentifier:@"code-cell" owner:self];
      return [self reuseCell:cell forCodeFrame:_errorData];
    }
    case RowKind::SectionHeader: {
      NSTableCellView *cell = [tableView makeViewWithIdentifier:@"hdr-cell" owner:self];
      return [self reuseCell:cell forSectionHeader:descriptor.headerTitle ?: @""];
    }
    case RowKind::StackFrame: {
      NSTableCellView *cell = [tableView makeViewWithIdentifier:@"cell" owner:self];
      return [self reuseCell:cell forStackFrame:descriptor.stackFrame];
    }
  }
  return nil;
}

- (BOOL)tableView:(__unused NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
  if (row < 0 || (NSUInteger)row >= _rows.count) {
    return NO;
  }
  return _rows[(NSUInteger)row].kind == RowKind::StackFrame;
}

- (void)handleTableClick:(__unused id)sender
{
  NSInteger row = _stackTraceTableView.clickedRow;
  if (row < 0 || (NSUInteger)row >= _rows.count) {
    return;
  }
  RCTRedBox2RowDescriptor *descriptor = _rows[(NSUInteger)row];
  if (descriptor.kind == RowKind::StackFrame && descriptor.stackFrame != nil) {
    [_actionDelegate redBoxController:self openStackFrameInEditor:descriptor.stackFrame];
  }
  // Always clear selection to match iOS deselectRowAtIndexPath:animated:YES behavior.
  [_stackTraceTableView deselectAll:nil];
}

#pragma mark - Cell builders

- (NSTableCellView *)reuseCell:(NSTableCellView *)cell forErrorMessage:(NSString *)message
{
  if (cell == nullptr) {
    cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = @"msg-cell";
    cell.wantsLayer = YES;
    cell.layer.backgroundColor = RCTRedBox2BackgroundColor().CGColor;

    // Error category label (e.g. "Syntax Error", "Uncaught Error")
    NSTextField *categoryLabel = [RCTRedBox2Controller labelWithText:@""];
    categoryLabel.textColor = RCTRedBox2ErrorColor();
    categoryLabel.font = [NSFont systemFontOfSize:21 weight:NSFontWeightBold];
    categoryLabel.maximumNumberOfLines = 1;
    categoryLabel.cell.wraps = NO;
    categoryLabel.cell.usesSingleLineMode = YES;
    categoryLabel.identifier = @"msg-cell-category";
    [cell addSubview:categoryLabel];

    // Error message label
    NSTextField *messageLabel = [RCTRedBox2Controller labelWithText:@""];
    messageLabel.accessibilityIdentifier = @"redbox-error";
    messageLabel.selectable = YES;
    messageLabel.textColor = [NSColor whiteColor];
    messageLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    messageLabel.maximumNumberOfLines = 0;
    messageLabel.cell.wraps = YES;
    messageLabel.cell.usesSingleLineMode = NO;
    messageLabel.cell.lineBreakMode = NSLineBreakByWordWrapping;
    messageLabel.identifier = @"msg-cell-body";
    [cell addSubview:messageLabel];
    cell.textField = messageLabel;

    [NSLayoutConstraint activateConstraints:@[
      [categoryLabel.topAnchor constraintEqualToAnchor:cell.topAnchor constant:15],
      [categoryLabel.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
      [categoryLabel.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],

      [messageLabel.topAnchor constraintEqualToAnchor:categoryLabel.bottomAnchor constant:10],
      [messageLabel.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
      [messageLabel.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
      [messageLabel.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-15],
    ]];
  }

  NSTextField *categoryLabel = nil;
  NSTextField *messageLabel = nil;
  for (NSView *sub in cell.subviews) {
    if ([sub.identifier isEqualToString:@"msg-cell-category"]) {
      categoryLabel = (NSTextField *)sub;
    } else if ([sub.identifier isEqualToString:@"msg-cell-body"]) {
      messageLabel = (NSTextField *)sub;
    }
  }
  categoryLabel.stringValue = _errorData.title ?: @"";
  messageLabel.stringValue = message ?: @"";

  _errorCategoryLabel = categoryLabel;
  _messageBodyLabel = messageLabel;

  return cell;
}

- (NSTableCellView *)reuseCell:(NSTableCellView *)cell forStackFrame:(RCTJSStackFrame *)stackFrame
{
  if (cell == nullptr) {
    cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = @"cell";

    NSTextField *methodLabel = [RCTRedBox2Controller labelWithText:@""];
    methodLabel.font = [NSFont fontWithName:@"Menlo-Regular" size:14];
    methodLabel.cell.lineBreakMode = NSLineBreakByCharWrapping;
    methodLabel.maximumNumberOfLines = 2;
    methodLabel.cell.wraps = YES;
    methodLabel.cell.usesSingleLineMode = NO;
    methodLabel.identifier = @"stack-method";
    [cell addSubview:methodLabel];
    cell.textField = methodLabel;

    NSTextField *fileLabel = [RCTRedBox2Controller labelWithText:@""];
    fileLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightLight];
    fileLabel.cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
    fileLabel.maximumNumberOfLines = 1;
    fileLabel.cell.usesSingleLineMode = YES;
    fileLabel.identifier = @"stack-file";
    [cell addSubview:fileLabel];

    [NSLayoutConstraint activateConstraints:@[
      [methodLabel.topAnchor constraintEqualToAnchor:cell.topAnchor constant:5],
      [methodLabel.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
      [methodLabel.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],

      [fileLabel.topAnchor constraintEqualToAnchor:methodLabel.bottomAnchor constant:2],
      [fileLabel.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
      [fileLabel.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
    ]];
  }

  NSTextField *methodLabel = nil;
  NSTextField *fileLabel = nil;
  for (NSView *sub in cell.subviews) {
    if ([sub.identifier isEqualToString:@"stack-method"]) {
      methodLabel = (NSTextField *)sub;
    } else if ([sub.identifier isEqualToString:@"stack-file"]) {
      fileLabel = (NSTextField *)sub;
    }
  }

  methodLabel.stringValue = stackFrame.methodName ?: @"(unnamed method)";
  if (stackFrame.file != nullptr) {
    fileLabel.stringValue = [self formatFrameSource:stackFrame] ?: @"";
  } else {
    fileLabel.stringValue = @"";
  }

  if (stackFrame.collapse) {
    methodLabel.textColor = RCTRedBox2TextColor(0.4);
    fileLabel.textColor = RCTRedBox2TextColor(0.3);
  } else {
    methodLabel.textColor = [NSColor whiteColor];
    fileLabel.textColor = RCTRedBox2TextColor(0.8);
  }

  return cell;
}

- (NSTableCellView *)reuseCell:(NSTableCellView *)cell forCodeFrame:(RCTRedBox2ErrorData *)errorData
{
  // Code-frame cell content varies with the parsed error, so we rebuild the
  // contents on every reuse rather than caching subviews.
  if (cell == nullptr) {
    cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = @"code-cell";
  }

  for (NSView *subview in [cell.subviews copy]) {
    [subview removeFromSuperview];
  }

  // Code frame container with rounded corners
  NSView *container = [[NSView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  container.wantsLayer = YES;
  container.layer.backgroundColor = RCTRedBox2BackgroundColor().CGColor;
  container.layer.cornerRadius = 3;
  container.layer.masksToBounds = YES;
  [cell addSubview:container];

  // Render code frame with ANSI syntax highlighting
  NSFont *codeFont = [NSFont fontWithName:@"Menlo-Regular" size:12];
  NSAttributedString *highlighted = [RCTRedBox2AnsiParser attributedStringFromAnsiText:errorData.codeFrame
                                                                              baseFont:codeFont
                                                                             baseColor:[NSColor whiteColor]];

  NSTextField *codeLabel = [RCTRedBox2Controller labelWithText:@""];
  codeLabel.attributedStringValue = highlighted ?: [[NSAttributedString alloc] initWithString:@""];
  codeLabel.maximumNumberOfLines = 0;
  codeLabel.cell.wraps = NO;
  codeLabel.cell.usesSingleLineMode = NO;
  codeLabel.cell.lineBreakMode = NSLineBreakByClipping;
  codeLabel.selectable = YES;

  NSScrollView *codeScrollView = [[NSScrollView alloc] init];
  codeScrollView.translatesAutoresizingMaskIntoConstraints = NO;
  codeScrollView.hasHorizontalScroller = YES;
  codeScrollView.hasVerticalScroller = NO;
  codeScrollView.borderType = NSNoBorder;
  codeScrollView.drawsBackground = NO;
  codeScrollView.documentView = codeLabel;
  [container addSubview:codeScrollView];

  // File name label below the code frame
  NSTextField *fileLabel = [RCTRedBox2Controller labelWithText:@""];
  NSString *fileName = errorData.codeFrameFileName.lastPathComponent ?: errorData.codeFrameFileName;
  if (errorData.codeFrameRow > 0) {
    fileLabel.stringValue = [NSString
        stringWithFormat:@"%@ (%ld:%ld)", fileName, (long)errorData.codeFrameRow, (long)errorData.codeFrameColumn + 1];
  } else if (fileName.length > 0) {
    fileLabel.stringValue = fileName;
  }
  fileLabel.textColor = RCTRedBox2TextColor(0.5);
  fileLabel.font = [NSFont fontWithName:@"Menlo-Regular" size:12];
  fileLabel.alignment = NSTextAlignmentCenter;
  [cell addSubview:fileLabel];

  [NSLayoutConstraint activateConstraints:@[
    [container.topAnchor constraintEqualToAnchor:cell.topAnchor constant:5],
    [container.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
    [container.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],

    [codeScrollView.topAnchor constraintEqualToAnchor:container.topAnchor constant:10],
    [codeScrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:10],
    [codeScrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-10],
    [codeScrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-10],

    [fileLabel.topAnchor constraintEqualToAnchor:container.bottomAnchor constant:10],
    [fileLabel.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:10],
    [fileLabel.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-10],
    [fileLabel.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-10],
  ]];

  return cell;
}

- (NSTableCellView *)reuseCell:(NSTableCellView *)cell forSectionHeader:(NSString *)title
{
  if (cell == nullptr) {
    cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
    cell.identifier = @"hdr-cell";

    NSTextField *label = [RCTRedBox2Controller labelWithText:@""];
    label.textColor = [NSColor whiteColor];
    label.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    label.identifier = @"hdr-cell-label";
    [cell addSubview:label];
    cell.textField = label;

    [NSLayoutConstraint activateConstraints:@[
      [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:12],
      [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-12],
      [label.bottomAnchor constraintEqualToAnchor:cell.bottomAnchor constant:-10],
    ]];
  }
  NSTextField *label = nil;
  for (NSView *sub in cell.subviews) {
    if ([sub.identifier isEqualToString:@"hdr-cell-label"]) {
      label = (NSTextField *)sub;
      break;
    }
  }
  label.stringValue = title ?: @"";
  return cell;
}

#pragma mark - Row heights

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
  if (row < 0 || (NSUInteger)row >= _rows.count) {
    return 50;
  }
  RCTRedBox2RowDescriptor *descriptor = _rows[(NSUInteger)row];
  switch (descriptor.kind) {
    case RowKind::Message: {
      // Measure message body height to approximate iOS auto-sizing.
      NSString *message = [self displayMessage] ?: @"";
      CGFloat width = MAX(tableView.frame.size.width - 24, 100);
      NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
      style.lineBreakMode = NSLineBreakByWordWrapping;
      NSDictionary *attrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
        NSParagraphStyleAttributeName : style,
      };
      CGRect rect = [message boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                          options:NSStringDrawingUsesLineFragmentOrigin
                                       attributes:attrs
                                          context:nil];
      // 15 top + 21pt category line + 10 spacer + body + 15 bottom.
      return ceil(rect.size.height) + 15 + 21 + 10 + 15;
    }
    case RowKind::CodeFrame:
      return 200;
    case RowKind::SectionHeader:
      return 38;
    case RowKind::StackFrame:
      return 50;
  }
}

#pragma mark - Key Commands

- (BOOL)handleKeyDown:(NSEvent *)event
{
  // Escape: keyCode 53
  if (event.keyCode == 53) {
    [self dismiss];
    return YES;
  }
  NSString *chars = event.charactersIgnoringModifiers ?: @"";
  NSEventModifierFlags mods = event.modifierFlags;
  BOOL cmd = (mods & NSEventModifierFlagCommand) != 0;
  BOOL opt = (mods & NSEventModifierFlagOption) != 0;
  // Cmd-Option-C — copy stack
  if (cmd && opt && [chars isEqualToString:@"c"]) {
    [self copyStack];
    return YES;
  }
  // Cmd-R — reload
  if (cmd && !opt && [chars isEqualToString:@"r"]) {
    [self reload];
    return YES;
  }
  return NO;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

@end

#endif // macOS]

#endif
