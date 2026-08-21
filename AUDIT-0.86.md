# 0.86 breaking-changes audit (react-native-macos)

> Companion to the merge of `facebook/react-native@v0.86.0` into `0.86-tvinhas`
> (merge commit ca334d9a98, June 2026). Documents every upstream change between
> v0.85.3 and v0.86.0 that touches the macOS surface, and how the fork absorbed it.

## Method

The `0.86-tvinhas` branch was cut from `0.85-tvinhas` (tip: 5211aecb79) and the
upstream tag `v0.86.0` was merged directly (602 upstream commits since the
0.85 merge-base). Unlike the 0.83→0.85 jump, this is a single release cycle and
upstream's own changelog lists **zero entries under "Breaking"** for 0.86.0 —
the churn is additive (View Transitions), infrastructural (Metro 0.84, Hermes
V1 bump, prebuilt-binary caching), and corrective (a large crash-fix batch).

115 files conflicted. 47 were files the fork had never modified (byte-identical
to upstream v0.85.3 on our side) and took upstream's 0.86 content wholesale —
all of the generated feature-flag files fall in this bucket (verified: the fork
carries no custom feature flags). 27 were `package.json` version/dep conflicts
resolved by rule (fork identity fields + `workspace:*` refs win; upstream
external-dep bumps win). The remaining ~40 were resolved by hand with the
`[macOS]` carve-outs preserved; every resolved `.mm`/`.h` was checked for
`#if`/`#endif` balance (the 0.85 cycle's unclosed-`#if` lesson).

The audit's scope is the macOS-specific surface: `[macOS ... macOS]` banner
blocks, AppKit branches of `TARGET_OS_*` guards, the `React-RCTUIKit` target,
the RedBox 2.0 AppKit port, and the Hermes V0/V1 selection machinery.

## Changes audited (severity-ordered)

### 1. Hermes V1 bumped to `250829098.0.14` — SEV: MEDIUM

**What changed upstream:** Hermes V1 advanced from `250829098.0.10` to
`250829098.0.14`; `hermes-compiler` dependency bumped to match. Hermes V0
floor moved from `0.16.0` to `0.17.0`. Android switched to the Hermes V1
*stable* release rather than legacy nightlies (JSI ABI mismatch fix).

**File-level evidence:**
- `packages/react-native/sdks/.hermesv1version` → `hermes-v250829098.0.14`
- `packages/react-native/sdks/.hermesversion` → `hermes-v0.17.0`
- `packages/react-native/package.json` → `"hermes-compiler": "250829098.0.14"`

**macOS impact:** The fork's PR #2957 V0/V1 branch-selection gate
(`hermes_v1_enabled()` choosing `static_h` vs `main`) and the
`hermes_commit_at_merge_base` pin both survived the merge intact
(`sdks/hermes-engine/hermes-utils.rb:92,229-262`). Consumers must
pre-download `hermes-ios-250829098.0.14-debug.tar.gz` (the `.0.10`
tarball cached from the 0.85 cycle no longer matches) — same
`HERMES_ENGINE_TARBALL_PATH` workflow as before.

**Fork status after merge:** ✅ absorbed. `pod update hermes-engine
--no-repo-update` was required once (Podfile.lock pinned the 0.85 podspec
checksum).

### 2. View Transitions machinery (new) — SEV: MEDIUM

**What changed upstream:** A new `ViewTransitionModule` TurboModule
(`ReactCommon/react/nativemodule/viewtransition/`), a
`viewTransitionEnabled` feature flag, `unstable_getViewTransitionInstance`
on UIManagerBinding, a `UIManagerViewTransitionDelegate` interface, and a
`viewtransition` source root added to the Fabric build.

**File-level evidence:**
- `Package.swift`: new `reactViewTransitionNativeModule` target; `React-Fabric`
  gained the `viewtransition` sources dir and a `.reactJsInspectorTracing` dep
- `scripts/react_native_pods.rb`: new `pod 'React-viewtransitionnativemodule'`
- `ReactCommon/react/nativemodule/defaults/DefaultTurboModules.cpp` registers it

**macOS impact:** Taken in upstream's form with no macOS conditioning —
consistent with sibling native modules (mutation/intersection observers),
which carry none. The module is C++-level; nothing UIKit-only surfaced in the
build config. **Runtime behavior of view transitions on macOS is untested** —
the feature is flag-gated off by default, so exposure is opt-in.

**Fork status after merge:** ✅ absorbed (compiles); runtime unverified, flag
default-off.

### 2b. New `platform/tvos` view dir shadows the macOS Fabric headers — SEV: HIGH (build break)

**What changed upstream:** 0.86 added
`ReactCommon/react/renderer/components/view/platform/tvos/` containing alias
headers (`using HostPlatformViewEventEmitter = BaseViewEventEmitter;` etc.).

**Why it broke the fork:** The fork's `React-Fabric.podspec` `view` subspec
compiles `components/view/**` and excludes only `platform/android` +
`platform/windows`, letting CocoaPods copy every remaining platform's headers
into the same flattened `Pods/Headers/Private/React-Fabric/react/renderer/components/view/`
path. The copy is glob-ordered, so the *last* platform alphabetically wins:
at 0.85 that was `macos` (beats `cxx`); at 0.86 the new `tvos` dir beat
`macos`, silently replacing the fork's NSEvent-aware
`HostPlatformViewEventEmitter.h`/`KeyEvent.h`/`MouseEvent.h`/`HostPlatformTouch.h`
with upstream's no-op aliases. First build failed with "out-of-line definition
of 'onKeyDown' does not match any declaration in 'BaseViewEventEmitter'".

**Fix:** `platform/tvos` added to the subspec's `exclude_files`
(`React-Fabric.podspec:137`). SPM is unaffected (Package.swift uses explicit
source allowlists). **Pattern to watch:** any new `platform/<name>` directory
upstream adds under a fork `**`-glob subspec will re-trigger this; grep for
new platform dirs after every merge.

**Fork status after merge:** ✅ fixed.

### 3. RendererProxy/RendererImplementation simplified to Fabric-only (#56556) — SEV: MEDIUM

**What changed upstream:** The Bridgeless paper-renderer indirection was
removed; `RendererProxy` and `RendererImplementation` are Fabric-only now.
This is the upstream landing of the fix that downstream consumers (Epistles)
previously carried as a local patch at 0.81.

**macOS impact:** None at merge time (no conflict touched the fork's files).
**Downstream consequence:** any remaining Bridgeless paper-renderer patch in a
consumer app (per memory, Epistles' `patches/react-native-macos+*.patch`) is
now obsolete at 0.86 and should be dropped during the consumer migration.

**Fork status after merge:** ✅ absorbed.

### 4. Event timestamps: `HighResTimeStamp` / `timeStamp` rename — SEV: MEDIUM

**What changed upstream:** Event timestamp propagation from host platforms was
reworked; `BaseTouch`'s debug prop `timestamp` became `timeStamp` typed as
`HighResTimeStamp`.

**File-level evidence:**
- `ReactCommon/react/renderer/components/view/BaseTouch.cpp` (conflicted):
  upstream's `timeStamp` line now coexists with the fork's macOS-only debug
  props (button/altKey/ctrlKey/shiftKey/metaKey). A pre-existing fork typo
  (`TARGET_OS_SX`) in that block was fixed to `TARGET_OS_OSX` during
  resolution — the macOS debug-props block was silently compiled out before.

**macOS impact:** The fork's NSEvent-derived touch fields are unaffected at
runtime; only debug-string output changed.

**Fork status after merge:** ✅ absorbed (+ latent typo fixed).

### 5. `View.js` native view-prop transformations flag — SEV: MEDIUM

**What changed upstream:** Aria/accessibility prop transformation in
`Libraries/Components/View/View.js` is now gated behind
`!ReactNativeFeatureFlags.enableNativeViewPropTransformations()` with a new
`resolvedProps` local.

**macOS impact:** The fork's macOS keyboard handling (`_onKeyDown`/`_onKeyUp`
wrappers driven by `keyDownEvents`/`keyUpEvents`) had to move after the flag
block; it now operates on `resolvedProps` via a copied `propsWithKeyEvents`
object so it works in both flag states. **Watch this spot**: if the flag is
ever enabled by default, verify macOS key events still attach (the native
transformation path must not strip `onKeyDown`/`onKeyUp`).

**Fork status after merge:** ✅ absorbed; flag-on path untested on macOS.

### 6. WebSocket hardening + invalidation crash fix — SEV: LOW

**What changed upstream:** `RCTWebSocketModule connect:` gained nil/empty-URL
validation and header type-checking; delegate callbacks after module
invalidation no longer crash (587ef059a2).

**macOS impact:** Upstream's early-return guard subsumes the fork's
`[macOS]` nil-URL wrapper from the 0.83 era; the fork's `RCTAssertParam(URL)`
line is preserved ahead of upstream's check. The file now differs from
upstream by exactly that one `[macOS]` line.

**Fork status after merge:** ✅ absorbed; fork delta shrank.

### 7. `RCTBackedTextInputDelegateAdapter` NSRangeException fix — SEV: LOW

**What changed upstream:** The range clamp in `shouldChangeText` was rewritten
against `attributedText.length` with an early `return NO` (19350b1c8c).

**macOS impact:** This *replaces* the fork's platform split (`.text` UIKit /
`.string` AppKit) — `attributedText` is on the shared
`RCTBackedTextInputViewProtocol`, so upstream's version is platform-agnostic.
Fork delta in that method is now zero.

**Fork status after merge:** ✅ absorbed; fork carve-out retired.

### 8. `removeClippedSubviews` toggle crash fix — SEV: LOW

**What changed upstream:** `RCTViewComponentView` gained
`_updateRemoveClippedSubviewsState` (91e3f773b7).

**macOS impact:** The new method's loop variable was adapted to `RCTUIView *`
per fork convention. The fork's macOS Fabric focus fixes (PR #2959:
`acceptsFirstResponder`/`becomeFirstResponder`/`makeFirstResponder:`) are
intact elsewhere in the file.

**Fork status after merge:** ✅ absorbed.

### 9. `ReactCxxTurboModuleProvider` rename absorbs a fork patch — SEV: LOW

**What changed upstream:** `TurboModuleManager.cpp` →
`ReactCxxTurboModuleProvider.cpp`; upstream adopted the same guarded
`AnimatedModule` registration the fork added in 0.85 (null provider defers to
default) and moved `DefaultTurboModules::getTurboModule` to the end of the
chain.

**macOS impact:** The fork's 0.85 patch is fully subsumed; the resolved file
is byte-identical to upstream v0.86.0. Fork delta retired.

**Fork status after merge:** ✅ absorbed; fork patch retired.

### 10. Legacy Jest tests deleted in favor of Fantom ports — SEV: LOW

**What changed upstream:** `TextInput-test.js`, `TouchableHighlight-test.js`,
`SectionList-test.js` (+snapshots) were deleted, ported to Fantom `*-itest.js`.

**macOS impact:** The fork's `TextInput-test.js` carries `[macOS]` assertions
for `setSelection`/`setGhostText`, so it was **kept** against upstream's
deletion (with a `[macOS]` banner explaining why). Its snapshot file was
deleted by the merge and must be regenerated (`jest -u`). The other two
orphaned snapshots were deleted with their tests (fork deltas there were
auto-generated macOS default props only, nothing hand-written).
`LogBoxInspectorStackFrames-test.js.snap` was hand-merged (upstream's new
rendered props + the fork's `acceptsFirstMouse`/`enableFocusRing` artifacts)
and should also be re-verified with `jest -u`.

**Fork status after merge:** ⚠️ partial — `jest -u` pass still owed.

### 11. Metro ^0.84, jest-preset registry literal vs yarn age gate — SEV: LOW

**What changed upstream:** Metro bumped to `^0.84.3` across
`community-cli-plugin` and friends; `@react-native/jest-preset` pins its
workspace-sibling deps by literal version (`0.86.0`).

**macOS impact:** None native. But the monorepo's `.yarnrc.yml` sets
`npmMinimalAgeGate: 7d`, and 0.86.0 npm artifacts were &lt;7 days old at merge
time — `yarn install` failed on `@react-native/js-polyfills@0.86.0`. Fixed by
switching `packages/jest-preset`'s dep to `workspace:*` (fork convention, used
by `metro-config` and `react-native` already). Hermes toolchain deps
(`hermes-parser`/`hermes-eslint`/`hermes-estree`) took upstream's 0.36.0.

**Fork status after merge:** ✅ absorbed.

### 12. RedBox 2.0: upstream idle between 0.85.3 and 0.86.0 — SEV: NONE (good news)

**What changed upstream:** Nothing of substance — across all 8 RedBox files
the only upstream 0.86 delta is a one-character whitespace fix in
`RCTRedBox2AnsiParser.mm` (applied).

**macOS impact:** The fork's ~1,500-line AppKit port (RCTRedBox2Controller,
RCTRedBoxController, ANSI parser, `+Internal.h` headers) carried over
verbatim. Still **runtime-unverified** (carried over from the 0.85 cycle —
induce a JS crash in RNTester-macOS and confirm the panel paints, keyboard
shortcuts land, auto-retry countdown works).

**Fork status after merge:** ✅ absorbed; runtime smoke test still owed.

### 13. Stale codegen `lib/` silently generates pre-0.86 specs — SEV: MEDIUM (build break)

**What happened:** `@react-native/codegen` resolves to the workspace package
(`packages/react-native-codegen`), whose compiled `lib/` is gitignored and was
last built during the 0.85 cycle. The executor's `buildCodegenIfNeeded()` only
builds when `lib/` is **missing**, not stale — so post-merge codegen ran 0.85
parser/generator code and emitted an `FBReactNativeSpecJSI.h` without
`NativeViewTransitionCxxSpec`, failing the build at
`NativeViewTransition.h:23` ("no template named 'NativeViewTransitionCxxSpec'").

**Fix:** `yarn build` in `packages/react-native-codegen`, then
`node scripts/generate-codegen-artifacts.js -p . -t ios` from
`packages/react-native` (note: `-p .`, not the app dir — rn-tester's own
codegenConfig only declares `AppSpecs`). **Pattern to watch:** after every
upstream merge, rebuild the codegen workspace package before running pod
install, or codegen output will be silently stale.

**Fork status after merge:** ✅ fixed.

### 14. Build-environment drift (not merge-related, recorded for the next cycle)

- `packages/rn-tester/.xcode.env.local` (untracked) pinned
  `NODE_BINARY=/opt/homebrew/Cellar/node@24/24.15.0/bin/node` — a versioned
  Cellar path that died with a Homebrew node upgrade, failing the
  "Generate Specs" script phase. Rewritten to the stable
  `/opt/homebrew/opt/node@24/bin/node` symlink.
- `Gemfile.lock` (after the merge) wants bundler 4.0.11, which system Ruby
  2.6 can't provide; the global CocoaPods 1.16.2 satisfies the `~> 1.13`
  Gemfile constraint and was used directly instead of `bundle exec`.

## What didn't break (negative findings)

- **All 9 fork PRs (#2956–#2964) survived.** Verified individually post-merge:
  `react-native.config.js` `REACT_NATIVE` constant (+ its type fields rewritten
  to upstream's new `Readonly`/`unknown` Flow style), `hermes-utils.rb` V1 gate,
  `ReactApple/RCTSwiftUI/RCTSwiftUI.podspec` `React-RCTUIKit` dep, Fabric focus
  fixes, `RNTesterPods.xcodeproj`, `fmt.podspec` consteval `prepare_command`,
  `package.json` files array, `TouchableBounce.js`/`AccessibilityInfo.js`
  carve-outs.
- **`KeyEvent`/`KeyEventData` split intact** (`CoreEventTypes.js:367/410/437`);
  upstream didn't touch the area. The naming smell flagged in AUDIT-0.85 item
  11 remains unaddressed — still recommended to resolve before the next merge.
- **Package.swift macOS plumbing held**: `.macOS(.v14)`, conditional
  AppKit/UIKit `platformLinkerSettings`, `React-RCTUIKit` target, the
  `reactFabricViewPlatform*` macOS source switch. `swift package dump-package`
  parses (71 targets).
- **Feature flags**: fork carries zero custom flags; all 19 generated
  feature-flag files took upstream 0.86 wholesale. The 0.85-era
  `redBoxV2IOS()`-false-on-macOS behavior that routes macOS to the fork's
  RedBox2 controller is upstream code, unchanged.
- **`peerDependencies.react-native: "*"`** wildcards restored in
  `new-app-screen`, `react-native-popup-menu-android`, `virtualized-lists`
  (upstream pins `0.86.0`; the fork must stay agnostic).

## Validation status (2026-06-11)

- `yarn install` clean (after jest-preset `workspace:*` fix, item 11)
- `pod install` clean — 89 deps, 88 pods, Hermes V1 `250829098.0.14` via
  `HERMES_ENGINE_TARBALL_PATH`
- `xcodebuild` RNTester-macOS Debug arm64: **BUILD SUCCEEDED** (52 MB .app,
  `hermesvm.framework` bundled) — after the tvos-exclude (item 2b), codegen
  rebuild (item 13), and node-path (item 14) fixes
- `jest packages/react-native/Libraries`: **110 suites / 1299 tests / 204
  snapshots all green** (17 snapshots regenerated: TextInput recreated,
  LogBoxInspector*, Pressable, assetRelativePath — all diffs were macOS render
  artifacts: `acceptsFirstMouse`, `enableFocusRing`, `mouseDownCanMoveWindow`,
  `keyDownEvents`, repo-relative `testUri`)

## Follow-ups
- **RedBox 2.0 runtime smoke test on macOS** — carried over from 0.85, still
  not done: crash RNTester-macOS and verify the AppKit panel.
- **View Transitions on macOS** — flag-gated off; before anyone enables
  `viewTransitionEnabled`, exercise it in RNTester-macOS (the mounting layer
  interaction with NSView animation is unproven).
- **`enableNativeViewPropTransformations` flag-on path** — verify macOS
  `keyDownEvents`/`keyUpEvents` still attach if upstream defaults this on
  (item 5).
- **`TARGET_OS_SX` typo class** — one was found and fixed in `BaseTouch.cpp`.
  Worth a tree-wide `grep -rn 'TARGET_OS_SX\b'` before each release pack to
  catch silently-dead `[macOS]` blocks.
- **Consumer migration note**: Epistles can drop any Bridgeless
  paper-renderer patch at 0.86 (upstream #56556 landed — item 3) and must
  re-pin Hermes tarball to `250829098.0.14` (item 1).
- **`KeyEvent`/`KeyEventData` naming** — still owed from AUDIT-0.85; cost
  re-confirmed this cycle (30 min of grep-disambiguation).
