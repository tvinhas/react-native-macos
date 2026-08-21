# 0.85 breaking-changes audit (react-native-macos)

> Companion to the merge of `facebook/0.85-stable` into `0.85-merge`
> (commit 408bef94, May 2026). Documents every upstream breaking
> change between v0.83.0 and v0.85.3 and how the fork absorbed it.

## Method

Because `react-native-macos` skipped 0.84, the `0.85-merge` jump absorbed two upstream
release cycles' worth of breaking changes at once (1,061 upstream commits from
`facebook/0.85-stable`). The audit was reconstructed from three sources: (a) the
upstream 0.84 and 0.85 release notes (Hermes V1 default, legacy iOS arch removal,
React 19.2.3 sync, iOS Prebuild, `RCTHostRuntimeDelegate` deprecation, jest-preset
extraction, Node floor bump, new Animation Backend, `StyleSheet.absoluteFillObject`
removal); (b) a directed read of the merged tree for the file-level fingerprints
of each change (preprocessor guards in `React/Base` and `Libraries/AppDelegate`,
the SPM target sources expansion in `Package.swift`, the new V0/V1 Hermes branch
selection in `sdks/hermes-engine/hermes-utils.rb`, the new `KeyEventData` type in
`Libraries/Types/CoreEventTypes.js`); (c) the conflict markers and fork-side
restoration commits captured during the rebase.

The audit's scope is the **macOS-specific surface**: the `[macOS ... macOS]`
banner blocks, AppKit branches of `TARGET_OS_*` guards, the `React-RCTUIKit`
target, the macOS-only `MacOSViewProps` / `KeyboardEventProps` / `HandledKeyEvent`
types, the `apps/mac/` deployment target (macOS 14+), and the `hermes_commit_at_merge_base`
trick in `hermes-utils.rb` that pins Hermes to the *upstream merge-base* commit
rather than `static_h` tip. Pure-iOS or pure-Android churn is not audited here
unless it secondary-bled into a macOS file.

The merge tree was clean enough to compile after manual conflict resolution
but not regression-free: two of the follow-ups in the final section are
runtime-untested code paths that survived the merge without crashing the
compiler but have not been exercised on a real macOS host.

## Breaking changes (severity-ordered)

### 1. Hermes V1 as the default engine  — landed in 0.84  — SEV: HIGH

**What changed upstream:** Hermes V1 (the `hermesvm.framework` build from the
`static_h` Hermes branch) is now the default engine; V0 (`hermes.framework`
from `main`) survives only behind `RCT_HERMES_V1_ENABLED=0`. The version
scheme also flipped — V1 uses the long-form `hermes-compiler@250829098.0.X`
calendar version, V0 keeps the legacy `0.14.0`-style scheme.

**File-level evidence:**
- `packages/react-native/sdks/.hermesversion` pins V0 at `hermes-v0.16.0`
- `packages/react-native/sdks/.hermesv1version` pins V1 at `hermes-v250829098.0.10`
- `packages/react-native/sdks/hermes-engine/hermes-utils.rb:91-93,261-262`
  defines `hermes_v1_enabled()` (defaulting to V1 unless `RCT_HERMES_V1_ENABLED=0`)
  and selects branch `static_h` vs `main` accordingly
- `packages/react-native/Package.swift:50` consumes the V1 prebuilt at
  `.build/artifacts/hermes/destroot/.../hermesvm.xcframework`
- `Package.swift:973` defines `HERMES_V1_ENABLED=1` for every Swift target

**macOS impact:** The fork ships PR #2957 from the 0.83 cycle — the
`hermes-utils.rb` change that gates the from-source branch selection on
`hermes_v1_enabled()`. Without it, `RCT_HERMES_V1_ENABLED=1 +
RCT_BUILD_HERMES_FROM_SOURCE=true` would clone V0 source while the podspec
expects V1 framework artifacts. The 0.85 merge kept this gate intact;
the `hermes_commit_at_merge_base` lookup in `hermes-utils.rb:228-275` was
extended with the same V0/V1 branch awareness so the fork's pinned-to-merge-base
Hermes commit comes from the correct branch.

**Fork status after merge:** ✅ absorbed.

### 2. Legacy iOS architecture removed as default  — landed in 0.84  — SEV: HIGH

**What changed upstream:** Fabric / new arch is now the only path React Native
defaults to on iOS. Cocoapods scripts now set `RCT_NEW_ARCH_ENABLED=1`
unconditionally and the C-preprocessor flag `RCT_REMOVE_LEGACY_ARCH=1` is added
to every target by `react_native_pods.rb`.

**File-level evidence:**
- `packages/react-native/scripts/react_native_pods.rb:108,130,549-552`
  forces `RCT_NEW_ARCH_ENABLED=1` and threads `-DRCT_REMOVE_LEGACY_ARCH=1`
  into the project
- `packages/react-native/Package.swift:972` makes `RCT_REMOVE_LEGACY_ARCH=1`
  unconditional for SPM builds
- `RCT_REMOVE_LEGACY_ARCH`-gated code still exists in `React/CoreModules/RCTLogBox.mm`
  and `RCTLogBoxView.mm`, but only as `#ifndef RCT_REMOVE_LEGACY_ARCH` blocks
  that are now compiled out by default

**macOS impact:** None of the macOS-specific code paths exercise the legacy
paper renderer directly (the fork's `apps/mac/` already runs Fabric in
practice — see memory `project_rn_macos_modal_crashes_fabric`). The
`RCT_REMOVE_LEGACY_ARCH`-gated paper-renderer source in `RCTLogBox*` *still
compiles* when that flag isn't set, so a downstream consumer that opted out
would still get the legacy fallback. We don't ship that mode. Confirm before
0.87 whether `apps/mac/` ever boots with `RCT_REMOVE_LEGACY_ARCH=0` — if not,
the legacy LogBox view could be cut.

**Fork status after merge:** ✅ absorbed. Uncertain whether runtime tests on
macOS exercise the legacy-arch fallback at all; I didn't find any test fixture
that flips the flag. Treat the fallback as "compiles, untested".

### 3. TurboModule Cxx cleanup wave  — landed in 0.84  — SEV: HIGH

**What changed upstream:** Five symbols were removed in one cleanup wave:
- `RCTCxxModule`, `TurboCxxModule` (Obj-C++)
- Java/Kotlin `CxxModule`
- C++ `CxxModule` base class
- `CatalystInstance` CxxModule support
- `TurboModuleBinding`'s public constructor (made `private`)
- `unstable_shouldEnableLegacyModuleInterop()` accessor

**File-level evidence:**
- `ReactCommon/react/nativemodule/core/ReactCommon/TurboModuleBinding.h:49-55`
  shows the constructor is now `private`, friended only to
  `BridgelessNativeModuleProxy`. Construction outside that proxy must go
  through the static `install()` overloads.
- `grep -rn "RCTCxxModule\|TurboCxxModule"` across `React/` and `ReactCommon/`
  returns no hits (the symbols are gone).
- `grep -rn "unstable_shouldEnableLegacyModuleInterop"` returns no hits.

**macOS impact:** The fork didn't ship any of these symbols in its
`[macOS ... macOS]` carve-outs, so the surface change was purely upstream.
The fork's macOS turbomodule path (`React/CoreModules/PlatformStubs/...`)
uses the supported `install()` entry points and was untouched.

**Fork status after merge:** ✅ absorbed.

### 4. React synced to 19.2.3  — landed in 0.84  — SEV: MEDIUM

**What changed upstream:** Peer pinned to `react@^19.2.3`. Several Flow
utilities were aliased to TS-style names: `$ReadOnly<{...}>` → `Readonly<{...}>`,
`$ReadOnlyArray<T>` → `ReadonlyArray<T>`, `$Keys<T>` → `keyof T`, and event
handler return types flipped from `void` to `unknown`.

**File-level evidence:**
- `packages/react-native/package.json:179` pins `"react": "^19.2.3"`
- `packages/jest-preset/package.json` declares `"peerDependencies": { "react": "^19.2.3" }`
- `Libraries/Components/View/ViewPropTypes.js:106-130, 174-179` shows the
  fork's `KeyboardEventProps` (macOS-only) and the new upstream `KeyEventProps`
  side-by-side, both written with the new `Readonly<{...}>` syntax
- `Libraries/Components/View/ViewPropTypes.js:102` shows the
  `=> unknown` return-type shape on the `onAccessibilityEscape` callback
  (and lines 51, 59, 86, 94 for `onAccessibilityAction`, `onAccessibilityTap`,
  `onLayout`, `onMagicTap` — same pattern)

**macOS impact:** The fork's `[macOS]` Flow types had to be rewritten from
the old `$ReadOnly<{| ... |}>` exact-object form to the new `Readonly<{...}>`
inexact-object form in a few places. The `HandledKeyEvent` declaration at
`CoreEventTypes.js:398-404` keeps the legacy `Readonly<{| ... |}>` exact-object
form (Flow still accepts that syntax) — note for future merges, upstream may
eventually drop exact-object syntax entirely; if/when that happens, this type
will need rewriting.

**Fork status after merge:** ✅ absorbed.

### 5. iOS Prebuild as default  — landed in 0.84  — SEV: MEDIUM

**What changed upstream:** React Native Core and its dependencies are now
distributed as precompiled XCFrameworks. The Cocoapods integration grew a
prebuild step that builds the XCFrameworks once and links them into the host
app, replacing the per-target compile that previously happened inside
`pod install`.

**File-level evidence:**
- `packages/react-native/Package.swift:42-52` declares `ReactNativeDependencies`
  and `hermesPrebuilt` as `BinaryTarget`s pointing at
  `third-party/ReactNativeDependencies.xcframework` and
  `.build/artifacts/hermes/destroot/.../hermesvm.xcframework`
- `Package.swift:18-21` documents the `RN_DEP_VERSION=nightly HERMES_VERSION=nightly node scripts/ios-prebuild`
  flow that materializes both xcframeworks before Xcode opens the package

**macOS impact:** The fork's `[macOS]` linker carve-outs in `Package.swift`
threaded `AppKit`/`UIKit` conditionally on top of the prebuilt binary targets
(see `reactGraphicsApple:288-293` and `reactRCTUIKit:660-669`). Because the
xcframeworks themselves are linked unmodified, the per-platform framework
selection happens at the SPM target boundary rather than inside the
binary. This held up cleanly during the merge — the only fork-side adjustment
was rewriting the SPM target sources list (see item 9) for the new directory
layout inside `reactFabric`.

**Fork status after merge:** ✅ absorbed. Uncertain whether the macOS-host
prebuild script `scripts/ios-prebuild` produces a macOS slice of
`ReactNativeDependencies.xcframework` correctly; I didn't read the script. If
the fork plans to publish prebuilt artifacts the way PR #2957/PR #2963 wired
the npm publish, this is the next thing to verify.

### 6. `RCTHostRuntimeDelegate` merged into `RCTHostDelegate`  — landed in 0.85  — SEV: MEDIUM

**What changed upstream:** The two protocols were unified — `didInitializeRuntime:`
moved into `RCTHostDelegate`. `RCTHostRuntimeDelegate` is kept as a deprecated
shim so existing call sites still compile, but the `RCTHost.runtimeDelegate`
property is marked `[[deprecated]]`.

**File-level evidence:**
- `ReactCommon/react/runtime/platform/ios/ReactCommon/RCTHost.h:63-71` keeps
  the deprecated protocol with a `[[deprecated("Use 'RCTHostDelegate' instead")]]`
  attribute on both the protocol and its lone method
- `RCTHost.h:78-83,86,92` shows all three designated initializers now take
  a single `id<RCTHostDelegate>` for both responsibilities
- `Libraries/AppDelegate/RCTReactNativeFactory.mm:40,236` and
  `Libraries/AppDelegate/RCTRootViewFactory.{h,mm}` adopt `RCTHostDelegate`
  exclusively
- The `runtimeDelegate` property at `RCTHost.h:100-101` is preserved as a
  deprecated stub

**macOS impact:** The fork's `RCTReactNativeFactory` and `RCTDefaultReactNativeFactoryDelegate`
already conformed to `RCTHostDelegate`. No macOS-specific call site needed to
flip. The 0.83→0.85 jump made the deprecation warning visible at compile time
in `apps/mac/` — consumers that took a typed reference to `RCTHostRuntimeDelegate`
will need to migrate.

**Fork status after merge:** ✅ absorbed.

### 7. `@react-native/jest-preset` extracted to a separate workspace package  — landed in 0.85  — SEV: LOW

**What changed upstream:** The jest preset moved out of `packages/react-native/jest-preset.js`
into its own workspace package at `packages/jest-preset/`. `react-native/jest-preset.js`
became a thin shim.

**File-level evidence:**
- `packages/jest-preset/package.json` exists, declaring
  `"name": "@react-native/jest-preset"`, `"version": "0.85.3"`,
  `"main": "./jest-preset.js"`, and `"engines": { "node": ">= 20.19.4" }`
- `packages/react-native/jest-preset.js` is now 27 lines:
  ```js
  try { module.exports = require('@react-native/jest-preset'); }
  catch (error) {
    if (error.code === 'MODULE_NOT_FOUND') { throw new Error(... migration message ...); }
    else { throw error; }
  }
  ```

**macOS impact:** None on the runtime surface. Consumers that wired
`preset: 'react-native'` in `jest.config.js` keep working through the shim;
consumers that want to drop the shim should switch to
`preset: '@react-native/jest-preset'`. The fork's monorepo workspace
machinery picks up the new package via the workspace globs without an
explicit edit.

**Fork status after merge:** ✅ absorbed.

### 8. Node.js floor raised to v20.19.4  — landed in 0.85  — SEV: LOW

**What changed upstream:** Minimum supported Node bumped to 20.19.4 across
the monorepo. Several `engines` fields tightened to refuse older runtimes.

**File-level evidence:**
- `packages/react-native/package.json:24`:
  `"node": "^20.19.4 || ^22.13.0 || ^24.3.0 || >= 25.0.0"`
- `packages/jest-preset/package.json:17`: `"node": ">= 20.19.4"`

**macOS impact:** None on the native side. Developer machines and CI runners
need to be on Node 20.19.4 or newer. The fork's `apps/mac/` build doesn't
ship Node, so consumer machines (Epistles devs, RNTester) inherit the floor
on `react-native-macos` install.

**Fork status after merge:** ✅ absorbed.

### 9. New Animation Backend  — landed in 0.85  — SEV: MEDIUM

**What changed upstream:** A new C++ animation backend lives at
`ReactCommon/react/renderer/animationbackend/` and makes layout props
animatable with `useNativeDriver: true`. The Fabric SPM target now compiles
both `animated/` and `animationbackend/` source roots.

**File-level evidence:**
- `Package.swift:485` lists `animated`, `animationbackend`, `components/scrollview/platform/ios`,
  `observers/intersection`, `observers/mutation` in the `reactFabric.sources`
  array — all new entries relative to 0.83
- The directory `ReactCommon/react/renderer/animationbackend/` is present and
  compiles under the same `cxxSettings` as the rest of the Fabric target

**macOS impact:** No conflict during merge — the new sources are pure C++
with no platform splits. The fork's macOS Fabric Modal / Switch / ScrollView
overrides did not collide. Open question for runtime: whether the new
animation backend correctly drives `NSView.frame` updates on macOS when
`useNativeDriver: true` is set on a layout prop. The macOS shadow-view
mounting pipeline hasn't been exercised against the new backend in this
audit; flag it for a manual test in RNTester-macOS.

**Fork status after merge:** ⚠️ partial — code lands, runtime behavior on
macOS unverified.

### 10. `StyleSheet.absoluteFillObject` removed  — landed in 0.85  — SEV: LOW

**What changed upstream:** The `absoluteFillObject` named export was removed
from the `StyleSheet` API. The frozen `absoluteFill` (StyleSheet handle, not
plain object) remains. Consumers that needed the plain object should inline
`{position: 'absolute', top: 0, left: 0, bottom: 0, right: 0}`.

**File-level evidence:**
- `Libraries/StyleSheet/StyleSheetExports.js:21-29,110` exports only
  `absoluteFill` (the frozen object referenced via a registered StyleSheet
  id). No `absoluteFillObject` export remains.
- `grep -rn "absoluteFillObject"` across `packages/react-native/Libraries`
  returns no hits.

**macOS impact:** None at the native layer. JS consumers in `apps/mac/` and
shared `packages/ui/` that reference `StyleSheet.absoluteFillObject` will
break at runtime with `undefined`. Downstream apps (Epistles, RNTester-macOS)
need a one-liner codemod.

**Fork status after merge:** ✅ absorbed.

### 11. `KeyEvent`/`KeyEventData` collision resolved  — landed in 0.85  — SEV: MEDIUM

**What changed upstream:** 0.85 introduced a generic web-style keyboard event
type `KeyEvent` in `Libraries/Types/CoreEventTypes.js`. The fork already had
an `NSEvent`-wrapped `KeyEvent` type (macOS-specific) with the same name.

**File-level evidence:**
- `Libraries/Types/CoreEventTypes.js:367-385` keeps the fork's macOS
  `NSEvent`-wrapped `KeyEvent` under the `[macOS ... macOS]` banner
- `CoreEventTypes.js:407-435` declares the upstream's web-style payload type
  as `KeyEventData` (renamed from upstream's `KeyEvent`) to avoid collision
- `CoreEventTypes.js:437-439` exports `KeyUpEvent` and `KeyDownEvent` as
  `NativeSyntheticEvent<KeyEventData>` — these are what the upstream
  `KeyEventProps` references
- `Libraries/Components/View/ViewPropTypes.js:106-130` keeps the macOS-only
  `KeyboardEventProps` (which references the fork's `KeyEvent`)
- `ViewPropTypes.js:174-179` defines the upstream `KeyEventProps` (which
  references `KeyDownEvent`/`KeyUpEvent`)
- `ViewPropTypes.js:654,656` spreads both `KeyEventProps` and `KeyboardEventProps`
  into `ViewProps`

**macOS impact:** This is the most invasive macOS-specific resolution in the
merge. The fork's `KeyEvent` type stays under `[macOS]`, the upstream type
was renamed to `KeyEventData`, and both prop types coexist on `ViewProps`.
Naming is now inconsistent (`KeyboardEventProps` is macOS, `KeyEventProps` is
upstream/web). Long-term this should be standardized — see follow-ups.

**Fork status after merge:** ✅ absorbed, but the naming is a smell.

## What didn't break (negative findings)

- **The fork's 9 0.83-era PRs (#2956–#2964) all survived the merge.** They
  patch `react-native.config.js`, `hermes-utils.rb`, `RCTSwiftUI.podspec`,
  three `RCTViewComponentView.mm` / `RCTMountingManager.mm` /
  `RCTVirtualViewComponentView.mm` Fabric focus regressions,
  `RNTesterPods.xcodeproj`, `fmt.podspec` (Xcode 26.x consteval gate),
  `packages/react-native/package.json` (npm publish files), and
  `TouchableBounce.js` / `AccessibilityInfo.js` `[macOS]` carve-outs. Re-check
  these manually after each upstream merge — they are not yet upstreamed.
- **macOS-specific `[macOS]` JS markers survived intact** in `TouchableBounce.js`,
  `Text.js`, `AccessibilityInfo.js`, `ViewPropTypes.js`, `CoreEventTypes.js`,
  and the `[macOS ... macOS]` banner blocks throughout `React/Base/RCTUtils.mm`
  and `Libraries/AppDelegate/RCTRootViewFactory.mm`.
- **`RCTUIKit.h` Swift module exposure** (the `React-RCTUIKit` SPM target at
  `Package.swift:659-669`) is unchanged. PR #2958's mechanism — the
  `RCTSwiftUIWrapper` target depending on `rctSwiftUI` and the
  `platformLinkerSettings: [.linkedFramework("UIKit", .when(...)), .linkedFramework("AppKit", .when(...))]`
  conditional linking — held up across the merge.
- **`react-native-macos` package naming + workspace refs preserved.**
  `packages/react-native/package.json:1` keeps `"name": "react-native-macos"`
  with `"version": "1000.0.0"` (the workspace-development sentinel).
  Workspace `*` refs from `packages/jest-preset/` and elsewhere resolve
  correctly against this name without an explicit alias.
- **macOS-14 deployment target survived the Hermes V1 + iOS Prebuild
  intersection.** `Package.swift:750` declares
  `platforms: [.iOS(.v15), .macOS(.v14), .macCatalyst(.v13)]` and the
  `hermesvm.xcframework` binary slice for macOS still resolves at link time.
- **`RCT_REMOVE_LEGACY_ARCH`-gated paper-renderer code still compiles**, so
  a consumer that explicitly opts out of the new arch will get the legacy
  fallback rather than a missing symbol. (We don't ship that mode; this is
  defensive only.)

## Follow-ups

- **`RCTRedBox.mm` had ~760 lines of inline duplicate `RCTRedBoxController`
  that were deleted during the merge** (`React/CoreModules/RCTRedBox.mm` is now
  382 lines; the file routes through `_RCTRedBoxController+Internal.h` and
  `_RCTRedBox2Controller+Internal.h` at lines 23-24, and switches between
  `RCTRedBoxController` and `RCTRedBox2Controller` at lines 199-202).
  RedBox 2.0 has not been runtime-verified on macOS. Build an artificially
  crashing RNTester-macOS scene and confirm the panel renders correctly with
  the macOS `NSWindow` host (not `UIWindow`).
- **`RCTUtils.mm` carried an unclosed `#if !TARGET_OS_OSX` block at one point
  during the rebase** that would have silently excluded ~680 lines of code on
  macOS. The current tree at `React/Base/RCTUtils.mm` balances correctly
  (`grep -n` shows matched `#if/#else/#endif` pairs across all 1,353 lines).
  Pattern to watch for in future merges: every preprocessor block should be
  audited for balance after each merge — a missing `#endif` is silent on the
  compiler but ships dead code on macOS.
- **`RCTFrameTimingsObserver.mm` is a new 0.85 file currently stubbed as
  no-op on macOS.** At `React/DevSupport/RCTFrameTimingsObserver.mm:300-319`
  the macOS branch is an empty `@implementation` with no-op `start` and
  `stop` methods. A proper implementation would use `CVDisplayLink` (or the
  modern macOS-14+ `NSScreen.displayLink(target:selector:)`) to drive
  frame-time tracking. Until that's done, devtools timeline frame-screenshots
  feature is silently disabled on macOS.
- **`CADisplayLink` on macOS requires macOS 14+** via
  `NSScreen.displayLinkWithTarget:selector:`. The fork's deployment target
  is macOS 14 (`Package.swift:750`), so this is fine for now, but if/when
  the fork ever supports macOS 13 again, the `RCTFrameTimingsObserver`
  macOS port (above) will need a `CVDisplayLink` fallback.
- **The `KeyEvent` / `KeyEventData` naming inherited from item 11 is a
  smell.** Long-term, either the fork's macOS-only `KeyEvent` (NSEvent-wrapped)
  should be renamed to `MacOSKeyEvent` and the upstream `KeyEventData` should
  reclaim the `KeyEvent` name, or the macOS prop set (`KeyboardEventProps`)
  should be renamed to align with the upstream's `KeyEventProps`. Pick one
  before the next merge — leaving both at their current names will cost the
  next maintainer 30 minutes of grep-disambiguation.
- **`scripts/ios-prebuild` macOS slice unverified** (see item 5). If the
  fork plans to publish prebuilt xcframeworks alongside the `.tgz` tarball
  release (the way `tvinhas/react-native-macos@v0.83.0-tvinhas` ships
  source), confirm that the macOS slice of `ReactNativeDependencies.xcframework`
  is produced correctly by the prebuild step before any binary publish.
- **Animation backend macOS runtime untested** (see item 9). The C++
  layer compiles, but `useNativeDriver: true` on a layout prop has not been
  exercised against the macOS shadow-view mounting pipeline. Build an
  RNTester-macOS scene that animates `width` or `marginLeft` with
  `useNativeDriver: true` and confirm it doesn't crash.
- **`RCT_REMOVE_LEGACY_ARCH=0` macOS behavior unverified** (see item 2).
  If `apps/mac/` never boots with that flag flipped, propose cutting the
  paper-renderer `RCTLogBoxView` / `RCTLogBox` macOS code paths in the
  0.87 cycle to reduce the maintenance surface.
