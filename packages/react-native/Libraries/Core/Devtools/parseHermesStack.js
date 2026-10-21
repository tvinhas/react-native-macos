/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow strict
 * @format
 */

'use strict';

type HermesStackLocationNative = Readonly<{
  type: 'NATIVE',
}>;

type HermesStackLocationSource = Readonly<{
  type: 'SOURCE',
  sourceUrl: string,
  line1Based: number,
  column1Based: number,
}>;

type HermesStackLocationInternalBytecode = Readonly<{
  type: 'INTERNAL_BYTECODE',
  sourceUrl: string,
  line1Based: number,
  virtualOffset0Based: number,
}>;

type HermesStackLocationBytecode = Readonly<{
  type: 'BYTECODE',
  sourceUrl: string,
  line1Based: number,
  virtualOffset0Based: number,
}>;

type HermesStackLocation =
  | HermesStackLocationNative
  | HermesStackLocationSource
  | HermesStackLocationInternalBytecode
  | HermesStackLocationBytecode;

type HermesStackEntryFrame = Readonly<{
  type: 'FRAME',
  location: HermesStackLocation,
  functionName: string,
}>;

type HermesStackEntrySkipped = Readonly<{
  type: 'SKIPPED',
  count: number,
}>;

type HermesStackEntry = HermesStackEntryFrame | HermesStackEntrySkipped;

export type HermesParsedStack = Readonly<{
  message: string,
  entries: ReadonlyArray<HermesStackEntry>,
}>;

// [macOS
// Parses a frame line exactly like the upstream regex
//   /^ {4}at (.+?)(?: \((native)\)?| \((address at )?(.*?):(\d+):(\d+)\))$/
// whose capturing groups were:
// 1. function name
// 2. is this a native stack frame?
// 3. is this a bytecode address or a source location?
// 4. source URL (filename)
// 5. line number (1 based)
// 6. column number (1 based) or virtual offset (0 based)
// but in linear time: the regex backtracks quadratically on long malformed
// frames (e.g. many " (" without a location). The function name still ends at
// the first " (" (the regex is lazy), so source URLs that contain " (" such as
// "/Applications/My App (Beta).app/..." keep parsing correctly.
const FRAME_PREFIX = '    at ';

type ParsedFrame = {
  functionName: string,
  native: boolean,
  bytecode: boolean,
  sourceUrl: string,
  line: string,
  column: string,
};

function isLineTerminator(code: number): boolean {
  return code === 0x0a || code === 0x0d || code === 0x2028 || code === 0x2029;
}

function isDigit(code: number): boolean {
  return code >= 0x30 && code <= 0x39;
}

function parseFrame(line: string): ?ParsedFrame {
  if (!line.startsWith(FRAME_PREFIX) || line.length === FRAME_PREFIX.length) {
    return null;
  }
  // `.` never matches a line terminator.
  for (let i = FRAME_PREFIX.length; i < line.length; i++) {
    if (isLineTerminator(line.charCodeAt(i))) {
      return null;
    }
  }
  const frame = line.slice(FRAME_PREFIX.length);
  for (const suffix of [' (native)', ' (native']) {
    if (frame.length > suffix.length && frame.endsWith(suffix)) {
      return {
        functionName: frame.slice(0, -suffix.length),
        native: true,
        bytecode: false,
        sourceUrl: '',
        line: '',
        column: '',
      };
    }
  }
  // ":<line>:<column>)" at the end.
  let i = frame.length - 1;
  if (frame[i] !== ')') {
    return null;
  }
  const columnEnd = i--;
  while (i >= 0 && isDigit(frame.charCodeAt(i))) {
    i--;
  }
  if (i === columnEnd - 1 || frame[i] !== ':') {
    return null;
  }
  const lineEnd = i--;
  while (i >= 0 && isDigit(frame.charCodeAt(i))) {
    i--;
  }
  if (i === lineEnd - 1 || frame[i] !== ':') {
    return null;
  }
  const locationEnd = i;
  const locationStart = frame.indexOf(' (', 1);
  if (locationStart === -1 || locationStart + 2 > locationEnd) {
    return null;
  }
  const bytecode = frame.startsWith('address at ', locationStart + 2);
  return {
    functionName: frame.slice(0, locationStart),
    native: false,
    bytecode,
    sourceUrl: frame.slice(
      locationStart + (bytecode ? 2 + 'address at '.length : 2),
      locationEnd,
    ),
    line: frame.slice(locationEnd + 1, lineEnd),
    column: frame.slice(lineEnd + 1, columnEnd),
  };
}
// macOS]

// Capturing groups:
// 1. count of skipped frames
const RE_SKIPPED = /^ {4}... skipping (\d+) frames$/;
const RE_COMPONENT_NO_STACK = /^ {4}at .*$/;

function isInternalBytecodeSourceUrl(sourceUrl: string): boolean {
  // See https://github.com/facebook/hermes/blob/3332fa020cae0bab751f648db7c94e1d687eeec7/lib/VM/Runtime.cpp#L1100
  return sourceUrl === 'InternalBytecode.js';
}

function parseLine(line: string): ?HermesStackEntry {
  const asFrame = parseFrame(line); // [macOS]
  if (asFrame) {
    return {
      type: 'FRAME',
      functionName: asFrame.functionName,
      location: asFrame.native
        ? {type: 'NATIVE'}
        : asFrame.bytecode
          ? isInternalBytecodeSourceUrl(asFrame.sourceUrl)
            ? {
                type: 'INTERNAL_BYTECODE',
                sourceUrl: asFrame.sourceUrl,
                line1Based: Number.parseInt(asFrame.line, 10),
                virtualOffset0Based: Number.parseInt(asFrame.column, 10),
              }
            : {
                type: 'BYTECODE',
                sourceUrl: asFrame.sourceUrl,
                line1Based: Number.parseInt(asFrame.line, 10),
                virtualOffset0Based: Number.parseInt(asFrame.column, 10),
              }
          : {
              type: 'SOURCE',
              sourceUrl: asFrame.sourceUrl,
              line1Based: Number.parseInt(asFrame.line, 10),
              column1Based: Number.parseInt(asFrame.column, 10),
            },
    };
  }
  const asSkipped = line.match(RE_SKIPPED);
  if (asSkipped) {
    return {
      type: 'SKIPPED',
      count: Number.parseInt(asSkipped[1], 10),
    };
  }
}

export default function parseHermesStack(stack: string): HermesParsedStack {
  const lines = stack.split(/\n/);
  let entries: Array<HermesStackEntryFrame | HermesStackEntrySkipped> = [];
  let lastMessageLine = -1;
  for (let i = 0; i < lines.length; ++i) {
    const line = lines[i];
    if (!line) {
      continue;
    }
    const entry = parseLine(line);
    if (entry) {
      entries.push(entry);
      continue;
    }
    if (RE_COMPONENT_NO_STACK.test(line)) {
      // Skip component stacks without source location.
      // TODO: This will not be displayed, not sure how to handle it.
      continue;
    }
    // No match - we're still in the message
    lastMessageLine = i;
    entries = [];
  }
  const message = lines.slice(0, lastMessageLine + 1).join('\n');
  return {message, entries};
}
