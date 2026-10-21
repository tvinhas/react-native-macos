/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow strict
 * @format
 */

import type {ExceptionData} from '../../Core/NativeExceptionsManager';
import type {LogBoxLogData} from './LogBoxLog';
import type {Stack} from './LogBoxSymbolication';

import parseErrorStack from '../../Core/Devtools/parseErrorStack';
import UTFSequence from '../../UTFSequence';
import stringifySafe from '../../Utilities/stringifySafe';
import ansiRegex from 'ansi-regex';

const ANSI_REGEX = ansiRegex().source;

const RE_TRANSFORM_ERROR = /^TransformError /;
const RE_COMPONENT_STACK_LINE = /\n {4}at/;
// [macOS
// The parsers below are linear-time equivalents of the upstream regexes quoted
// in their comments. Those regexes backtrack polynomially (cubically for the
// code frame one) on long adversarial messages, which can freeze the JS thread
// while LogBox handles an error. Each helper returns exactly the regex's
// capture groups (or `false`/`null` when it would not match).

function isLineTerminator(code: number): boolean {
  return code === 0x0a || code === 0x0d || code === 0x2028 || code === 0x2029;
}

function isDigit(code: number): boolean {
  return code >= 0x30 && code <= 0x39;
}

// Index of the first line terminator at or after `from`: where `.*` stops.
function lineEnd(s: string, from: number): number {
  let i = from;
  while (i < s.length && !isLineTerminator(s.charCodeAt(i))) {
    i++;
  }
  return i;
}

// Same as `/@.*\n/.test(s)`.
function hasStackFrameLine(s: string): boolean {
  let at = s.indexOf('@');
  while (at !== -1) {
    const end = lineEnd(s, at + 1);
    if (s.charCodeAt(end) === 0x0a) {
      return true;
    }
    at = s.indexOf('@', end);
  }
  return false;
}

// Same captures as `/^<prefix>(.*): (.*) \((\d+):(\d+)\)\n\n([\s\S]+)/`, for
// mutually exclusive alternatives of `<prefix>`.
//
// Babel transform errors: "TransformError " (optional), then "SyntaxError: "
// or "ReferenceError: ". Captures: 1: file path, 2: error message, 3: line,
// 4: column, 5: code frame.
//
// Metro errors: "InternalError Metro has encountered an error: ". Captures:
// 1: error title, 2: error message (file path), 3: line, 4: column, 5: code
// frame.
function matchErrorWithLocation(
  message: string,
  prefixes: ReadonlyArray<string>,
): ?[string, string, string, string, string] {
  const prefix = prefixes.find(candidate => message.startsWith(candidate));
  if (prefix == null) {
    return null;
  }
  // The header is the first line and must be followed by "\n\n" and a frame.
  const end = lineEnd(message, prefix.length);
  if (
    message.charCodeAt(end) !== 0x0a ||
    message.charCodeAt(end + 1) !== 0x0a ||
    end + 2 >= message.length
  ) {
    return null;
  }
  // The header ends with " (<row>:<column>)".
  let i = end - 1;
  if (message[i] !== ')') {
    return null;
  }
  const columnEnd = i--;
  while (i >= prefix.length && isDigit(message.charCodeAt(i))) {
    i--;
  }
  if (i === columnEnd - 1 || message[i] !== ':') {
    return null;
  }
  const columnStart = i + 1;
  const rowEnd = i--;
  while (i >= prefix.length && isDigit(message.charCodeAt(i))) {
    i--;
  }
  if (i === rowEnd - 1 || message[i] !== '(' || message[i - 1] !== ' ') {
    return null;
  }
  const rowStart = i + 1;
  const locationStart = i - 1;
  // The first `(.*)` is greedy: split at the last ": " before the location.
  if (locationStart - 2 < prefix.length) {
    return null;
  }
  const separator = message.lastIndexOf(': ', locationStart - 2);
  if (separator < prefix.length) {
    return null;
  }
  return [
    message.slice(prefix.length, separator),
    message.slice(separator + 2, locationStart),
    message.slice(rowStart, rowEnd),
    message.slice(columnStart, columnEnd),
    message.slice(end + 2),
  ];
}

const RE_DIGIT_OR_SPACE = /[\d\s]/;

// Returns a predicate telling whether a code frame
// (`[ >]{2}[\d\s]+ \|[\s\S]+` or `\u{001b}[\s\S]+`) starts right after the
// "\n" at index `n`. Must be called with increasing `n`; the end of the
// `[\d\s]+` run is cached so a whole scan stays linear.
function makeCodeFrameStartTest(s: string): (n: number) => boolean {
  let runEnd = 0;
  return n => {
    const first = s[n + 1];
    if (first === '\u001b') {
      return n + 2 < s.length;
    }
    const second = s[n + 2];
    if (
      (first !== ' ' && first !== '>') ||
      (second !== ' ' && second !== '>')
    ) {
      return false;
    }
    const runStart = n + 3;
    if (runEnd < runStart) {
      runEnd = runStart;
    }
    while (runEnd < s.length && RE_DIGIT_OR_SPACE.test(s[runEnd])) {
      runEnd++;
    }
    return (
      runEnd - runStart >= 2 &&
      s[runEnd - 1] === ' ' &&
      s[runEnd] === '|' &&
      runEnd + 1 < s.length
    );
  };
}

// Same captures as
// `/^(?:TransformError )?(?:.*):? (?:.*?)(\/.*): ([\s\S]+?)\n([ >]{2}[\d\s]+ \|[\s\S]+|\u{001b}[\s\S]+)/u`
// (- non-capturing "TransformError " (optional)
//  - non-capturing Error message
//  1: file path
//  2: error message
//  3: code frame, which includes code snippet indicators or terminal escape
//     sequences for formatting.)
function matchBabelCodeFrameError(message: string): ?[string, string, string] {
  const end = lineEnd(message, 0);
  let lastFrame = -1;
  const isFrameStart = makeCodeFrameStartTest(message);
  for (
    let n = message.indexOf('\n');
    n !== -1;
    n = message.indexOf('\n', n + 1)
  ) {
    if (isFrameStart(n)) {
      lastFrame = n;
    }
  }
  if (lastFrame === -1) {
    return null;
  }
  // The path is greedy: it ends at the last ": " on the first line that still
  // leaves a non-empty message before some code frame. It starts at the first
  // "/" after the last space that precedes a "/" within it.
  const from = Math.min(end - 2, lastFrame - 3);
  if (from < 0) {
    return null;
  }
  const separator = message.lastIndexOf(': ', from);
  if (separator < 1) {
    return null;
  }
  const lastSlash = message.lastIndexOf('/', separator - 1);
  if (lastSlash < 1) {
    return null;
  }
  const space = message.lastIndexOf(' ', lastSlash - 1);
  if (space === -1) {
    return null;
  }
  const pathStart = message.indexOf('/', space + 1);
  // The message is lazy: it ends at the first code frame after it.
  const isFirstFrameStart = makeCodeFrameStartTest(message);
  let frame = -1;
  for (
    let n = message.indexOf('\n', separator + 3);
    n !== -1;
    n = message.indexOf('\n', n + 1)
  ) {
    if (isFirstFrameStart(n)) {
      frame = n;
      break;
    }
  }
  if (frame === -1) {
    return null;
  }
  return [
    message.slice(pathStart, separator),
    message.slice(separator + 2, frame),
    message.slice(frame + 1),
  ];
}
// macOS]

// https://github.com/babel/babel/blob/33dbb85e9e9fe36915273080ecc42aee62ed0ade/packages/babel-code-frame/src/index.ts#L183-L184
const RE_BABEL_CODE_FRAME_MARKER_PATTERN = new RegExp(
  [
    // Beginning of a line (per 'm' flag)
    '^',
    // Optional ANSI escapes for colors
    `(?:${ANSI_REGEX})*`,
    // Marker
    '>',
    // Optional ANSI escapes for colors
    `(?:${ANSI_REGEX})*`,
    // Left padding for line number
    ' +',
    // Line number
    '[0-9]+',
    // Gutter
    ' \\|',
  ].join(''),
  'm',
);

export type ExtendedExceptionData = ExceptionData & {
  isComponentError: boolean,
  ...
};
export type Category = string;
export type CodeFrame = Readonly<{
  content: string,
  location: ?{
    row: number,
    column: number,
    ...
  },
  fileName: string,

  // TODO: When React switched to using call stack frames,
  // we gained the ability to use the collapse flag, but
  // it is not integrated into the LogBox UI.
  collapse?: boolean,
}>;
export type Message = Readonly<{
  content: string,
  substitutions: ReadonlyArray<
    Readonly<{
      length: number,
      offset: number,
    }>,
  >,
}>;

const SUBSTITUTION = UTFSequence.BOM + '%s';

export function parseInterpolation(args: ReadonlyArray<unknown>): Readonly<{
  category: Category,
  message: Message,
}> {
  const categoryParts = [];
  const contentParts = [];
  const substitutionOffsets = [];

  const remaining = [...args];
  if (typeof remaining[0] === 'string') {
    const formatString = String(remaining.shift());
    const formatStringParts = formatString.split('%s');
    const substitutionCount = formatStringParts.length - 1;
    const substitutions = remaining.splice(0, substitutionCount);

    let categoryString = '';
    let contentString = '';

    let substitutionIndex = 0;
    for (const formatStringPart of formatStringParts) {
      categoryString += formatStringPart;
      contentString += formatStringPart;

      if (substitutionIndex < substitutionCount) {
        if (substitutionIndex < substitutions.length) {
          // Don't stringify a string type.
          // It adds quotation mark wrappers around the string,
          // which causes the LogBox to look odd.
          const substitution =
            typeof substitutions[substitutionIndex] === 'string'
              ? substitutions[substitutionIndex]
              : stringifySafe(substitutions[substitutionIndex]);
          substitutionOffsets.push({
            length: substitution.length,
            offset: contentString.length,
          });

          categoryString += SUBSTITUTION;
          contentString += substitution;
        } else {
          substitutionOffsets.push({
            length: 2,
            offset: contentString.length,
          });

          categoryString += '%s';
          contentString += '%s';
        }

        substitutionIndex++;
      }
    }

    categoryParts.push(categoryString);
    contentParts.push(contentString);
  }

  const remainingArgs = remaining.map(arg => {
    // Don't stringify a string type.
    // It adds quotation mark wrappers around the string,
    // which causes the LogBox to look odd.
    return typeof arg === 'string' ? arg : stringifySafe(arg);
  });
  categoryParts.push(...remainingArgs);
  contentParts.push(...remainingArgs);

  return {
    category: categoryParts.join(' '),
    message: {
      content: contentParts.join(' '),
      substitutions: substitutionOffsets,
    },
  };
}

function isComponentStack(consoleArgument: string) {
  // Component stacks are formatted as call stack frames:
  // - Hermes format: "    at Component (/path/to/file.js:1:2)"
  // - JSC format: "Component@/path/to/file.js:1:2"
  return (
    RE_COMPONENT_STACK_LINE.test(consoleArgument) ||
    hasStackFrameLine(consoleArgument) // [macOS]
  );
}

export function parseComponentStack(message: string): {
  stack: Stack,
} {
  const stack = parseErrorStack(message);
  return {
    stack: stack ?? [],
  };
}

export function parseLogBoxException(
  error: ExtendedExceptionData,
): LogBoxLogData {
  const message =
    error.originalMessage != null ? error.originalMessage : 'Unknown';

  // [macOS
  const metroInternalError = matchErrorWithLocation(message, [
    'InternalError Metro has encountered an error: ',
  ]);
  // macOS]
  if (metroInternalError) {
    const [content, fileName, row, column, codeFrame] = metroInternalError; // [macOS]

    return {
      level: 'fatal',
      type: 'Metro Error',
      stack: [],
      isComponentError: false,
      componentStack: [],
      codeFrame: {
        fileName,
        location: {
          row: parseInt(row, 10),
          column: parseInt(column, 10),
        },
        content: codeFrame,
      },
      message: {
        content,
        substitutions: [],
      },
      category: `${fileName}-${row}-${column}`,
      extraData: error.extraData,
    };
  }

  // [macOS
  const babelTransformError = matchErrorWithLocation(message, [
    'TransformError SyntaxError: ',
    'TransformError ReferenceError: ',
    'SyntaxError: ',
    'ReferenceError: ',
  ]);
  // macOS]
  if (babelTransformError) {
    // Transform errors are thrown from inside the Babel transformer.
    const [fileName, content, row, column, codeFrame] = babelTransformError; // [macOS]

    return {
      level: 'syntax',
      stack: [],
      isComponentError: false,
      componentStack: [],
      codeFrame: {
        fileName,
        location: {
          row: parseInt(row, 10),
          column: parseInt(column, 10),
        },
        content: codeFrame,
      },
      message: {
        content,
        substitutions: [],
      },
      category: `${fileName}-${row}-${column}`,
      extraData: error.extraData,
    };
  }

  // Perform a cheap match first before trying to parse the full message, which
  // can get expensive for arbitrary input.
  if (RE_BABEL_CODE_FRAME_MARKER_PATTERN.test(message)) {
    const babelCodeFrameError = matchBabelCodeFrameError(message); // [macOS]

    if (babelCodeFrameError) {
      // Codeframe errors are thrown from any use of buildCodeFrameError.
      const [fileName, content, codeFrame] = babelCodeFrameError; // [macOS]
      return {
        level: 'syntax',
        stack: [],
        isComponentError: false,
        componentStack: [],
        codeFrame: {
          fileName,
          location: null, // We are not given the location.
          content: codeFrame,
        },
        message: {
          content,
          substitutions: [],
        },
        category: `${fileName}-${1}-${1}`,
        extraData: error.extraData,
      };
    }
  }

  if (message.match(RE_TRANSFORM_ERROR)) {
    return {
      level: 'syntax',
      stack: error.stack,
      isComponentError: error.isComponentError,
      componentStack: [],
      message: {
        content: message,
        substitutions: [],
      },
      category: message,
      extraData: error.extraData,
    };
  }

  const componentStack = error.componentStack;
  if (error.isFatal || error.isComponentError) {
    if (componentStack != null) {
      const {stack} = parseComponentStack(componentStack);
      return {
        level: 'fatal',
        stack: error.stack,
        isComponentError: error.isComponentError,
        componentStack: stack,
        extraData: error.extraData,
        ...parseInterpolation([message]),
      };
    } else {
      return {
        level: 'fatal',
        stack: error.stack,
        isComponentError: error.isComponentError,
        componentStack: [],
        extraData: error.extraData,
        ...parseInterpolation([message]),
      };
    }
  }

  if (componentStack != null) {
    // It is possible that console errors have a componentStack.
    const {stack} = parseComponentStack(componentStack);
    return {
      level: 'error',
      stack: error.stack,
      isComponentError: error.isComponentError,
      componentStack: stack,
      extraData: error.extraData,
      ...parseInterpolation([message]),
    };
  }

  // Most `console.error` calls won't have a componentStack. We parse them like
  // regular logs which have the component stack buried in the message.
  return {
    level: 'error',
    stack: error.stack,
    isComponentError: error.isComponentError,
    extraData: error.extraData,
    ...parseLogBoxLog([message]),
  };
}

export function withoutANSIColorStyles(message: unknown): unknown {
  if (typeof message !== 'string') {
    return message;
  }

  return message.replace(
    // eslint-disable-next-line no-control-regex
    /[\u001b\u009b][[()#;?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]/g,
    '',
  );
}

export function parseLogBoxLog(args: ReadonlyArray<unknown>): {
  componentStack: Stack,
  category: Category,
  message: Message,
} {
  const message = withoutANSIColorStyles(args[0]);
  let argsWithoutComponentStack: Array<unknown> = [];
  let componentStack: Stack = [];

  // Extract component stack from warnings like "Some warning%s".
  if (
    typeof message === 'string' &&
    message.slice(-2) === '%s' &&
    args.length > 0
  ) {
    const lastArg = args[args.length - 1];
    if (typeof lastArg === 'string' && isComponentStack(lastArg)) {
      argsWithoutComponentStack = args.slice(0, -1);
      argsWithoutComponentStack[0] = message.slice(0, -2);
      const {stack} = parseComponentStack(lastArg);
      componentStack = stack;
    }
  }

  if (componentStack.length === 0 && argsWithoutComponentStack.length === 0) {
    // Try finding the component stack elsewhere.
    for (const arg of args) {
      if (typeof arg === 'string' && isComponentStack(arg)) {
        // Strip out any messages before the component stack.
        let messageEndIndex = arg.search(RE_COMPONENT_STACK_LINE);
        if (messageEndIndex < 0) {
          // Handle JSC component stacks.
          messageEndIndex = arg.search(/\n/);
        }
        if (messageEndIndex > 0) {
          argsWithoutComponentStack.push(arg.slice(0, messageEndIndex));
        }

        const {stack} = parseComponentStack(arg);
        componentStack = stack;
      } else {
        argsWithoutComponentStack.push(arg);
      }
    }
  }

  return {
    ...parseInterpolation(argsWithoutComponentStack),
    componentStack,
  };
}
