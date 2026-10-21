/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow strict-local
 * @format
 */

'use strict';

/*::
import type {Command} from '@react-native-community/cli-types';
 */

// IMPORTANT: This is a routing file only. Do NOT add new command
// definitions or implementations here.
//
// New CLI commands belong in @react-native/community-cli-plugin, and
// may (temporarily) be imported and registered here.
//
// Future state: The Community Template should directly depend on and inject:
// - @react-native-community/cli-platform-android
// - @react-native-community/cli-platform-ios
// - @react-native/community-cli-plugin

const verbose = Boolean(process.env.DEBUG?.includes('react-native'));

function findCommunityPlatformPackage(
  spec /*: string */,
  startDir /*: string */ = process.cwd(),
) {
  // In monorepos, we cannot make any assumptions on where
  // `@react-native-community/*` gets installed. The safest way to find it
  // (barring adding an optional peer dependency) is to start from the project
  // root.
  //
  // Note that we're assuming that the current working directory is the project
  // root. This is also what `@react-native-community/cli` assumes (see
  // https://github.com/react-native-community/cli/blob/14.x/packages/cli-tools/src/findProjectRoot.ts).
  const main = require.resolve(spec, {paths: [startDir]});
  // $FlowFixMe[unsupported-syntax]
  return require(main);
}

let android;
try {
  android = findCommunityPlatformPackage(
    '@react-native-community/cli-platform-android',
  );
} catch {
  if (verbose) {
    console.warn(
      '@react-native-community/cli-platform-android not found, the react-native.config.js may be unusable.',
    );
  }
}

let ios;
try {
  ios = findCommunityPlatformPackage(
    '@react-native-community/cli-platform-ios',
  );
} catch {
  if (verbose) {
    console.warn(
      '@react-native-community/cli-platform-ios not found, the react-native.config.js may be unusable.',
    );
  }
}

// [macOS
let apple;
try {
  const iosPath = require.resolve('@react-native-community/cli-platform-ios', {
    paths: [process.cwd()],
  });
  // $FlowFixMe[untyped-import]
  apple = findCommunityPlatformPackage(
    '@react-native-community/cli-platform-apple',
    iosPath,
  );
} catch {
  if (verbose) {
    console.warn(
      '@react-native-community/cli-platform-apple not found, the react-native.config.js may be unusable.',
    );
  }
}
let macosCommands;
// Loading `runMacOS` requires `@react-native-community/cli`which is an
// optional peer dependency and is not installed when using Expo CLI.
try {
  // $FlowFixMe[untyped-import]
  macosCommands = require('./local-cli/runMacOS/runMacOS');
} catch (e) {
  if (verbose) {
    console.warn(
      `Failed to load runMacOS commands, the react-native.config.js may be unusable: ${e instanceof Error ? e.message : String(e)}`,
    );
  }
}
// macOS]

const commands /*: Array<Command> */ = [];

const {
  bundleCommand,
  codegenCommand,
  spmCommand,
  startCommand,
} = require('@react-native/community-cli-plugin');

// [macOS
// The plugin's `codegen` and `spm` commands run `react-native/scripts/*`,
// which resolves to upstream react-native in an app (and to nothing inside
// this monorepo) instead of this package's macOS-aware scripts. Keep the
// plugin's command definitions, but run the scripts shipped here.
const macosCodegenCommand /*: Command */ = {
  ...codegenCommand,
  func: (_argv, _config, args) =>
    require('./scripts/codegen/generate-artifacts-executor').execute(
      args.path,
      args.platform,
      args.outputPath,
      args.source,
    ),
};

const macosSpmCommand /*: Command */ = {
  ...spmCommand,
  func: async (argv, _config, args) => {
    const passthrough /*: Array<string> */ = [];
    if (argv[0] != null) {
      passthrough.push(argv[0]);
    }
    const stringOpts /*: Array<[string, string]> */ = [
      ['version', '--version'],
      ['productName', '--product-name'],
      ['xcodeproj', '--xcodeproj'],
      ['artifacts', '--artifacts'],
      ['download', '--download'],
    ];
    for (const [key, flag] of stringOpts) {
      if (args[key] != null) {
        passthrough.push(flag, String(args[key]));
      }
    }
    const boolOpts /*: Array<[string, string]> */ = [
      ['skipCodegen', '--skip-codegen'],
      ['deintegrate', '--deintegrate'],
      ['yes', '--yes'],
    ];
    for (const [key, flag] of boolOpts) {
      if (args[key] === true) {
        passthrough.push(flag);
      }
    }
    await require('./scripts/setup-apple-spm').main(passthrough);
  },
};
// macOS]

commands.push(
  bundleCommand,
  startCommand,
  macosSpmCommand,
  macosCodegenCommand,
); // [macOS]

const config = {
  commands,
  platforms: {} /*:: as {[string]: Readonly<{
      projectConfig: unknown,
      dependencyConfig: unknown,
      linkConfig?: unknown, // [macOS]
      npmPackageName?: unknown, // [macOS]
    }>} */,
};

if (ios != null) {
  config.commands.push(...ios.commands);
  config.platforms.ios = {
    projectConfig: ios.projectConfig,
    dependencyConfig: ios.dependencyConfig,
  };
}

if (android != null) {
  config.commands.push(...android.commands);
  config.platforms.android = {
    projectConfig: android.projectConfig,
    dependencyConfig: android.dependencyConfig,
  };
}

// [macOS
if (macosCommands != null) {
  config.commands.push(...macosCommands);
}
if (apple) {
  const {
    REACT_NATIVE: npmPackageName,
  } = require('./scripts/codegen/generate-artifacts-executor/constants.js');
  const macos = {platformName: 'macos'};
  config.platforms.macos = {
    npmPackageName,
    linkConfig: () => {
      return {
        isInstalled: (
          _projectConfig /*: unknown */,
          _package /*: unknown */,
          _dependencyConfig /*: unknown */,
        ) => false,
        register: (
          _package /*: unknown */,
          _dependencyConfig /*: unknown */,
          _obj /*: unknown */,
          _projectConfig /*: unknown */,
        ) => {},
        unregister: (
          _package /*: unknown */,
          _dependencyConfig /*: unknown */,
          _projectConfig /*: unknown */,
          _dependencyConfigs /*: unknown */,
        ) => {},
        copyAssets: (
          _assets /*: unknown */,
          _projectConfig /*: unknown */,
        ) => {},
        unlinkAssets: (
          _assets /*: unknown */,
          _projectConfig /*: unknown */,
        ) => {},
      };
    },
    projectConfig: apple.getProjectConfig(macos),
    dependencyConfig: apple.getDependencyConfig(macos),
  };
}
// macOS]

module.exports = config;
