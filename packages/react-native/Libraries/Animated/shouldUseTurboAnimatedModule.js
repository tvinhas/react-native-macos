/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *
 * @flow strict-local
 * @format
 */

import * as ReactNativeFeatureFlags from '../../src/private/featureflags/ReactNativeFeatureFlags';
import Platform from '../Utilities/Platform';

function shouldUseTurboAnimatedModule(): boolean {
  if (ReactNativeFeatureFlags.cxxNativeAnimatedEnabled()) {
    return false;
  } else {
    // [macOS] Bridgeless macOS registers RCTNativeAnimatedTurboModule too.
    // Checking 'ios' alone sent macOS to the legacy module, whose operations
    // wait on Paper UIManager mounting that never happens: native-driven
    // animations were queued, never ran, and never finished.
    return (
      (Platform.OS === 'ios' || Platform.OS === 'macos') &&
      global.RN$Bridgeless === true
    );
    // macOS]
  }
}

export default shouldUseTurboAnimatedModule;
