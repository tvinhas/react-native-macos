# MIGRATION.md — consuming `react-native-macos@0.83.0-tvinhas`

This file is **not committed** — it's a local working note describing how to consume the GitHub Release at `tvinhas/react-native-macos@v0.83.0-tvinhas` from a downstream project (Epistles, RNTA, anything else).

The release is at:
**https://github.com/tvinhas/react-native-macos/releases/tag/v0.83.0-tvinhas**

It contains 24 `.tgz` files — `react-native-macos` itself plus the workspace deps the monorepo bundles. Workspace `workspace:*` refs were resolved to `0.83.0-tvinhas` literals at pack time, so the tarballs are self-contained as long as every transitive dep is also pulled from the release (or a npm-published version that satisfies the literal).

---

## What's in this release

Beyond upstream `microsoft/react-native-macos` `0.83-merge` tip, the release rolls in 9 fork-side PRs (filed upstream as #2956–#2964):

| PR | Touches | What |
|---|---|---|
| #2956 | `react-native.config.js` | Use `REACT_NATIVE` constant for `npmPackageName` |
| #2957 | `hermes-utils.rb` | Pick `static_h` vs `main` Hermes branch by `RCT_HERMES_V1_ENABLED` |
| #2958 | `RCTSwiftUI.podspec`, `RCTSwiftUIContainerView.swift` | Expose `React-RCTUIKit` to Swift consumers |
| #2959 | `RCTViewComponentView.mm`, `RCTMountingManager.mm`, `RCTVirtualViewComponentView.mm` | Three macOS Fabric focus regressions |
| #2960 | `RNTesterPods.xcodeproj/project.pbxproj` | Restore the file that was missing from `0.83-merge` |
| #2961 | `fmt.podspec` | Patch `fmt/base.h` consteval gate via `prepare_command` for Xcode 26.x |
| #2962 | `RCTViewComponentView.mm` | Guard iOS-only methods so the file compiles on macOS |
| #2963 | `packages/react-native/package.json` | Include `React-RCTUIKit.podspec` in npm publish files array |
| #2964 | `TouchableBounce.js`, `AccessibilityInfo.js` | Align macOS `[macOS]` carve-outs with upstream 0.83 restructures |

End-to-end validated on Xcode 26.5 / Apple Silicon: RNTester-macOS.app + microsoft/react-native-test-app's `example-macos` both build cleanly with `hermesvm.framework` linked.

---

## Consumer install — yarn

If your project uses yarn (classic or berry), add to your **app's `package.json`**:

```json
{
  "dependencies": {
    "react-native-macos": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-macos-0.83.0-tvinhas.tgz"
  },
  "resolutions": {
    "@react-native/assets-registry": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-assets-registry-0.83.0-tvinhas.tgz",
    "@react-native/babel-plugin-codegen": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-babel-plugin-codegen-0.83.0-tvinhas.tgz",
    "@react-native/babel-preset": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-babel-preset-0.83.0-tvinhas.tgz",
    "@react-native/codegen": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-codegen-0.83.0-tvinhas.tgz",
    "@react-native/community-cli-plugin": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-community-cli-plugin-0.83.0-tvinhas.tgz",
    "@react-native/compatibility-check": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-compatibility-check-0.83.0-tvinhas.tgz",
    "@react-native/core-cli-utils": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-core-cli-utils-0.83.0-tvinhas.tgz",
    "@react-native/debugger-frontend": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-debugger-frontend-0.83.0-tvinhas.tgz",
    "@react-native/debugger-shell": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-debugger-shell-0.83.0-tvinhas.tgz",
    "@react-native/dev-middleware": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-dev-middleware-0.83.0-tvinhas.tgz",
    "@react-native/eslint-config": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-eslint-config-0.83.0-tvinhas.tgz",
    "@react-native/eslint-plugin": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-eslint-plugin-0.83.0-tvinhas.tgz",
    "@react-native/eslint-plugin-specs": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-eslint-plugin-specs-0.83.0-tvinhas.tgz",
    "@react-native/gradle-plugin": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-gradle-plugin-0.83.0-tvinhas.tgz",
    "@react-native/js-polyfills": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-js-polyfills-0.83.0-tvinhas.tgz",
    "@react-native/metro-babel-transformer": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-metro-babel-transformer-0.83.0-tvinhas.tgz",
    "@react-native/metro-config": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-metro-config-0.83.0-tvinhas.tgz",
    "@react-native/new-app-screen": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-new-app-screen-0.83.0-tvinhas.tgz",
    "@react-native/normalize-colors": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-normalize-colors-0.83.0-tvinhas.tgz",
    "@react-native/popup-menu-android": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-popup-menu-android-0.83.0-tvinhas.tgz",
    "@react-native/typescript-config": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-typescript-config-0.83.0-tvinhas.tgz",
    "@react-native-macos/virtualized-lists": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-macos-virtualized-lists-0.83.0-tvinhas.tgz",
    "react-native-macos-init": "https://github.com/tvinhas/react-native-macos/releases/download/v0.83.0-tvinhas/react-native-macos-init-0.83.0-tvinhas.tgz"
  }
}
```

Then:

```bash
yarn install
```

## Consumer install — npm

npm uses `overrides` instead of `resolutions` (same effect, different field name). Replace the `"resolutions"` key above with `"overrides"`.

```bash
npm install
```

> [!NOTE]
> For npm, you might also want to set `"react-native-macos"` in `overrides` so transitive deps that reference `react-native-macos@<some-other-version>` (e.g., `react-native-safe-area-context`'s peer deps) collapse onto the tarball too.

## Required `react` / `react-native` versions

The fork depends on:

```json
{
  "react": "^19.2.0",
  "react-native": "^0.83.0"
}
```

If your app currently pins `react@19.1.x` and `react-native@0.81.x`, bump them in the same `package.json` change.

## After install: `pod install`

```bash
cd <your-app>/macos
pod install
```

This exercises every fork-side build-system fix in the release: `fmt` consteval workaround, `React-RCTUIKit.podspec` inclusion, Hermes V1 branch selection, etc. Expect 86 deps to resolve and the workspace to generate.

## After `pod install`: `xcodebuild`

```bash
xcodebuild \
  -workspace <your-workspace>.xcworkspace \
  -scheme <your-scheme> \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  build
```

End-to-end build green has been validated against `microsoft/react-native-test-app`'s `example-macos` (44 MB `.app`, links `hermesvm.framework`) and the fork's own `RNTester-macOS`.

---

## Caveats

1. **Not signed, not on npm registry.** Tarball URLs only.
2. **Workspace dep names are still namespaced as `@react-native/*`** (not `@tvinhas/*`) — so if a downstream consumer has a `react-native@^0.83.0` install from npm, yarn/npm might prefer the npm-published `@react-native/codegen` over our tarball. The `resolutions`/`overrides` block forces the tarball.
3. **The `0.83-tvinhas` branch source on the fork still has `workspace:*` refs** — only the packed tarballs carry resolved `0.83.0-tvinhas` literals. Don't `npm install github:tvinhas/react-native-macos#0.83-tvinhas` directly; use the tarball URL.
4. **`@react-native/tester`** (~122 MB) was excluded from the release — it's the fork's internal test harness, not in any consumer's dep chain.
5. **Long-term path**: when `microsoft/react-native-macos` ships an official `0.83.x` release, swap the tarball URL for `"react-native-macos": "^0.83.0"` from npm and drop the `resolutions` block.

---

## Migration steps for Epistles (when you're ready)

Not executed yet. Path:

1. `apps/mac/package.json`: change `react-native-macos: "0.81.7"` → tarball URL, `react-native: "0.81.6"` → `"^0.83.0"`, `@react-native/babel-preset` / `@react-native/metro-config` / `@react-native/typescript-config` → `"^0.83.0"`.
2. Add the `resolutions` block above to **the monorepo root `package.json`** (since Epistles is a yarn workspace, root-level resolutions cascade).
3. `npm install` from the Epistles monorepo root.
4. Delete `patches/react-native-macos+0.81.7.patch` — the Bridgeless paper-renderer fix it carried isn't needed at 0.83 (per memory `project_rn_bridgeless_paper_renderer_patch`, upstream PR #56556 fixes this at 0.86 — but Epistles' patch was already a 0.81-specific workaround; verify it's actually obsolete before deletion).
5. `cd apps/mac/macos && pod install`.
6. `./build.sh --mac` (codesigning + DMG + k8s-secret env injection per memory `project_mac_build_script`).
7. Smoke-test the resulting `.app` for the known macOS-fork bug surface (e.g., `<Modal>` Fabric crash from memory `project_rn_macos_modal_crashes_fabric` is fixed in 0.83; vault cold-launch gap from memory `project_vault_cold_launch_gap` is orthogonal and unaffected).
