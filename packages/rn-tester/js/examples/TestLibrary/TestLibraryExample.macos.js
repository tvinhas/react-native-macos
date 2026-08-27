/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow
 * @format
 */

'use strict';

// [macOS] The iOS variant of this example exercises the SwiftPM
// autolinking fixtures (react-native-test-library-apple and
// react-native-test-library-common), which the CocoaPods-based macOS
// build does not install. This variant exists so the example list shared
// with iOS resolves when bundling with --platform macos.

import type {RNTesterModuleExample} from '../../types/RNTesterTypes';

const React = require('react');
const {Text, View} = require('react-native');

exports.title = 'Test library (SPM autolinking fixture)';
exports.category = 'Basic';
exports.description =
  'iOS-only SwiftPM autolinking fixture; not part of the macOS CocoaPods build.';
exports.examples = [
  {
    title: 'Call both native modules',
    render(): React.MixedElement {
      return (
        <View>
          <Text>
            The SwiftPM autolinking test libraries this example exercises are
            not installed by the macOS CocoaPods build.
          </Text>
        </View>
      );
    },
  },
] as Array<RNTesterModuleExample>;
