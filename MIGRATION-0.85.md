# MIGRATION-0.85.md — consuming `react-native-macos@0.85.3-tvinhas`

This file is **not committed** — it's a local working note describing how to consume the GitHub Release at `tvinhas/react-native-macos@v0.85.3-tvinhas.2` from a downstream project (Epistles, RNTA, anything else).

The release is at:
**https://github.com/tvinhas/react-native-macos/releases/tag/v0.85.3-tvinhas.2**

`v0.85.3-tvinhas.2` carries exactly **2** `.tgz` assets — `react-native-macos` itself and `@react-native-macos/virtualized-lists` (the only two artifacts not on the public npm registry). Every `@react-native/*` dep is pinned to plain `0.85.3` inside the `react-native-macos` tarball's `package.json` and resolves straight from npm — no per-package tarball needed. (The original `v0.85.3-tvinhas` tag had all 25 workspace tarballs with `0.85.3-tvinhas` literals; it's superseded — do not consume it.)

> ### ⚠️ Immutable-tag discipline — never clobber a released asset
>
> npm caches a tarball body keyed by URL + integrity (`~/.npm/_cacache`), and a lockfile pins that integrity. If you mutate an asset at a fixed URL (`gh release upload --clobber`), consumers silently keep the **old** bytes — even after `npm cache clean --force` + lockfile delete + reinstall (the only escape is `rm -rf ~/.npm/_cacache` *and* a fresh URL). So: **every re-pack cuts a NEW immutable tag** — `v0.85.3-tvinhas.2`, then `.3`, `.4`, … Released assets are append-only and never replaced. The package `version` inside the tarball stays `0.85.3-tvinhas` (peers resolve fine; the URL is the immutability boundary, not the semver).

---

## What's in this release

Beyond `v0.83.0-tvinhas`, this release absorbs 1,061 upstream commits from `facebook/react-native` 0.83.0 → 0.85.3 (the 0.84 npm tag is skipped — code-equivalent path) plus a native AppKit port of upstream's new RedBox 2.0 dev error overlay.

| | |
|---|---|
| Upstream RN version absorbed | **0.85.3** |
| Hermes V1 (default engine) | `250829098.0.10` |
| Hermes V0 (legacy fallback) | `0.16.0` |
| React | `^19.2.3` |
| Node engine | `^20.19.4 \|\| ^22.13.0 \|\| ^24.3.0 \|\| >= 25.0.0` |
| RedBox 2.0 on macOS | ✅ ported to AppKit |

**Carried forward from 0.83-tvinhas** (all 9 fork-side PRs filed upstream as #2956–#2964):

| PR | Touches | What |
|---|---|---|
| #2956 | `react-native.config.js` | Use `REACT_NATIVE` constant for `npmPackageName` |
| #2957 | `hermes-utils.rb` | Pick `static_h` vs `main` Hermes branch by `RCT_HERMES_V1_ENABLED` |
| #2958 | `RCTSwiftUI.podspec`, `RCTSwiftUIContainerView.swift` | Expose `React-RCTUIKit` to Swift consumers |
| #2959 | `RCTViewComponentView.mm`, `RCTMountingManager.mm`, `RCTVirtualViewComponentView.mm` | Three macOS Fabric focus regressions |
| #2960 | `RNTesterPods.xcodeproj/project.pbxproj` | Restore file missing from upstream's `0.83-merge` branch |
| #2961 | `fmt.podspec` | Patch `fmt/base.h` consteval gate via `prepare_command` for Xcode 26.x |
| #2962 | `RCTViewComponentView.mm` | Guard iOS-only methods so the file compiles on macOS |
| #2963 | `packages/react-native/package.json` | Include `React-RCTUIKit.podspec` in npm publish files array |
| #2964 | `TouchableBounce.js`, `AccessibilityInfo.js` | Align macOS `[macOS]` carve-outs with upstream 0.83 restructures |

**New in 0.85-tvinhas** (filed as a single feat commit `30d534948d`):

- **RedBox 2.0 macOS port** (~1,500 lines new AppKit code) in `RCTRedBox2Controller.mm` + `RCTRedBoxController.mm` + their `+Internal.h` headers + companion parsers
- 7 additional 0.85-merge-up patches: `RCTUtils.mm` preprocessor recovery, `RCTUIManager.mm` new-arch stub retyping, `RCTFrameTimingsObserver.mm` macOS stub, `RCTSurfaceTouchHandler.mm` gesture guard, `RCTScheduler.mm` `CADisplayLink` via `NSScreen` (macOS 14+), `RCTLogBoxView.mm` legacy-arch guard, `RCTDevLoadingView.mm` dealloc branch

End-to-end validated on Xcode 26.5 / Apple Silicon / arm64 / macOS 14.6 target:
- RNTester-macOS.app builds clean (51 MB, links `hermesvm.framework`)
- react-native-test-app's `example-macos` builds clean from Verdaccio publish (49 MB `ReactTestApp.app`)

---

## Consumer install — yarn

As of the 2026-05-16 re-pack, `react-native-macos-0.85.3-tvinhas.tgz`'s own
`package.json` pins its `@react-native/*` deps to the plain upstream npm
version `0.85.3` (they are byte-equivalent to upstream — the fork only forks
`react-native` itself and `@react-native-macos/virtualized-lists`). So a
consumer no longer needs to override every `@react-native/*` package. The
**only** non-npm dep is `@react-native-macos/virtualized-lists` (fork-only,
not published to npm).

If your project uses yarn (classic or berry), add to your **app's `package.json`**:

```json
{
  "dependencies": {
    "react-native-macos": "https://github.com/tvinhas/react-native-macos/releases/download/v0.85.3-tvinhas.2/react-native-macos-0.85.3-tvinhas.tgz"
  },
  "resolutions": {
    "@react-native-macos/virtualized-lists": "https://github.com/tvinhas/react-native-macos/releases/download/v0.85.3-tvinhas.2/react-native-macos-virtualized-lists-0.85.3-tvinhas.tgz"
  }
}
```

Then:

```bash
yarn install
```

## Consumer install — npm

npm uses `overrides` instead of `resolutions`. npm enforces "you cannot override a direct dependency with a *different* spec than what `dependencies` declares" unless you use the `$<name>` reference syntax — so for the `react-native-macos` entry that appears in *both* `dependencies` and `overrides`, use `$react-native-macos`. Per the note above, the only `@react-native/*`-namespaced override still required is the fork-only `@react-native-macos/virtualized-lists` tarball; everything else resolves from npm at `0.85.3`:

```json
{
  "dependencies": {
    "react-native-macos": "https://github.com/tvinhas/react-native-macos/releases/download/v0.85.3-tvinhas.2/react-native-macos-0.85.3-tvinhas.tgz"
  },
  "overrides": {
    "react-native-macos": "$react-native-macos",
    "@react-native-macos/virtualized-lists": "https://github.com/tvinhas/react-native-macos/releases/download/v0.85.3-tvinhas.2/react-native-macos-virtualized-lists-0.85.3-tvinhas.tgz"
  }
}
```

> The `$react-native-macos` self-reference still matters: it forces transitive deps that peer-depend on `react-native-macos@<other version>` (e.g. `react-native-safe-area-context`) to collapse onto the tarball rather than falling back to a registry version.

Then:

```bash
npm install
```

The `"react-native-macos": "$react-native-macos"` entry forces transitive deps that reference `react-native-macos@<some-other-version>` (e.g., `react-native-safe-area-context`'s peer deps) to collapse onto the same tarball that `dependencies` resolves. Without it, npm warns about peer-dep mismatch and may fall back to the npm-registry version.

## Required `react` / `react-native` versions

The fork depends on:

```json
{
  "react": "^19.2.3",
  "react-native": "^0.85.0"
}
```

If your app currently pins one of the following, bump:
- `react`: `19.1.x` or `19.2.x` → `19.2.3`
- `react-native`: `^0.81.x` / `^0.83.x` → `^0.85.0` (or pin exactly to `0.85.3`)
- `react-native-macos`: `0.81.7` / `0.83.0-tvinhas` → the `v0.85.3-tvinhas` tarball URL
- `@react-native/babel-preset`, `@react-native/metro-config`, `@react-native/typescript-config` (and any other `@react-native/*` packages in `devDependencies`) → `0.85.3` from npm

Note: bump these in BOTH `dependencies` AND `devDependencies` where they appear. Epistles currently has `@react-native/*` deps pinned at `0.81.x` in both blocks of `apps/mac/package.json`.

## Node version

Requires `^20.19.4 || ^22.13.0 || ^24.3.0 || >= 25.0.0`. If your `apps/mac/` is currently building under an older Node, you'll need to bump.

## After install: `pod install`

```bash
cd <your-app>/macos
HERMES_ENGINE_TARBALL_PATH=/path/to/cached/hermes-ios-250829098.0.10-debug.tar.gz pod install
```

Why the env var: the Hermes V1 podspec tries to download `hermes-ios-250829098.0.10-debug.tar.gz` from Maven Central. That sometimes rate-limits (HTTP 429) and falls back to a "build from git" path that requires the consumer to be inside a react-native git checkout (it computes a merge-base with `facebook/react-native`). Most consumer apps aren't. Pointing `HERMES_ENGINE_TARBALL_PATH` at a pre-downloaded tarball bypasses both paths.

You can pull the tarball directly from Maven Central — but use `-fL`, not `-L`, so a 429 fails loudly instead of writing the HTML error page to disk as a fake tarball:

```bash
curl -fL -o hermes-ios-250829098.0.10-debug.tar.gz \
  https://repo1.maven.org/maven2/com/facebook/hermes/hermes-ios/250829098.0.10/hermes-ios-250829098.0.10-hermes-ios-debug.tar.gz \
  || { echo "Maven 429 — try again in a few minutes, or copy from ~/repos/react-native-macos/packages/rn-tester/Pods/hermes-engine-artifacts/ if you have the fork checked out locally"; exit 1; }
file hermes-ios-250829098.0.10-debug.tar.gz  # should report "gzip compressed data"
```

…or copy from `~/repos/react-native-macos/packages/rn-tester/Pods/hermes-engine-artifacts/` if you have the fork checked out locally.

This exercises every fork-side build-system fix in the release: `fmt` consteval workaround, `React-RCTUIKit.podspec` inclusion, Hermes V1 branch selection, etc. Expect 86 deps to resolve.

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

End-to-end build green has been validated against `microsoft/react-native-test-app`'s `example-macos` (49 MB `ReactTestApp.app`, links `hermesvm.framework`) and the fork's own `RNTester-macOS` (51 MB).

---

## Caveats

1. **Not signed, not on npm registry.** Tarball URLs only.
2. **`@react-native/*` deps resolve from the npm registry at `0.85.3` by design** (post 2026-05-16 re-pack). The fork only forks `react-native` itself + `@react-native-macos/virtualized-lists`; every `@react-native/*` package is byte-equivalent to upstream, so `react-native-macos-0.85.3-tvinhas.tgz`'s `package.json` pins them to plain `0.85.3` and a consumer pulls them straight from npm — *no* per-package override. Only `@react-native-macos/virtualized-lists` (fork-only, unpublished) still needs a tarball override. (Pre-2026-05-16 tarballs pinned these to `0.85.3-tvinhas` and required the full override list — that's gone.)
3. **The `0.85-tvinhas` branch source on the fork still has `workspace:*` refs** — only the packed tarballs carry resolved `0.85.3-tvinhas` literals. Don't `npm install github:tvinhas/react-native-macos#0.85-tvinhas` directly; use the tarball URL.
4. **`@react-native/tester`** (~122 MB) was excluded from the release — it's the fork's internal test harness, not in any consumer's dep chain.
5. **`AUDIT-0.85.md`** in this same directory documents every upstream breaking change and how the fork absorbed it. Read it before resolving any merge conflict that involves new files post-0.85.
6. **`KeyDownEvent` / `KeyUpEvent` TS aliases are misaligned in the auto-generated `ReactNativeApi.d.ts`.** The hand-written `Libraries/Types/CoreEventTypes.d.ts` correctly exports `KeyEvent` as `NativeSyntheticEvent<NativeKeyEvent>` (fork's NSEvent-wrapped shape), and `ViewPropTypes.d.ts` types `onKeyDown`/`onKeyUp` against that. **Primary consumer use case is fine.** However, the auto-generated `packages/react-native/ReactNativeApi.d.ts:2939` declares a *local* `KeyEvent` with the upstream web-style shape (`{key, code, altKey, ctrlKey, metaKey, shiftKey, ...}`) and wraps `KeyDownEvent`/`KeyUpEvent` around it. TS consumers who import `KeyDownEvent` directly (rare) and access `e.nativeEvent.capsLockKey` will get a type error. Workaround: import `KeyEvent` (not `KeyDownEvent`) from `react-native` for handler types. The proper fix is upstream-coordinated and requires regenerating `ReactNativeApi.d.ts` with the fork's snapshot — deferred to a follow-up.
7. **Long-term path**: when `microsoft/react-native-macos` ships an official `0.85.x` release, swap the tarball URL for `"react-native-macos": "^0.85.0"` from npm and drop the `resolutions` block.

---

## Migration steps for Epistles (when you're ready)

Not executed yet. Path:

1. `apps/mac/package.json` (current state per the Epistles repo: `react-native-macos: "0.81.7"`, `react-native: "0.81.6"`, `react: "19.1.4"`):
   - `react-native-macos: "0.81.7"` → the `v0.85.3-tvinhas` tarball URL
   - `react-native: "0.81.6"` → `"^0.85.0"` (or pin exactly `"0.85.3"`) from npm
   - `react: "19.1.4"` → `"19.2.3"` (or `"^19.2.3"`)
   - In **`devDependencies` as well as `dependencies`**: bump every `@react-native/*` entry currently at `0.81.x` to `0.85.3` from npm (these are upstream packages; they don't need our fork). Specifically check: `@react-native/babel-preset`, `@react-native/metro-config`, `@react-native/typescript-config`, `@react-native/codegen` if present.
   - If `package.json` declares an `engines.node` constraint, bump the floor to `^20.19.4 || ^22.13.0 || ^24.3.0 || >= 25.0.0`.
2. Epistles uses **npm** workspaces, so add the **minimal npm `overrides`** block from the "Consumer install — npm" section above to the monorepo root `package.json` — just `"react-native-macos": "$react-native-macos"` + the `@react-native-macos/virtualized-lists` tarball. (Done 2026-05-16: the 6 obsolete `@react-native/*` overrides — assets-registry, codegen, community-cli-plugin, gradle-plugin, js-polyfills, normalize-colors — were removed after the tarball re-pack; `npm install --dry-run` resolves clean without them.)
3. `npm install` (or `yarn install`) from the Epistles monorepo root.
4. Check whether `patches/react-native-macos+0.83.7.patch` or similar still exists — verify each patched line still has its target in the new version, and drop patches that became obsolete (per memory `project_rn_bridgeless_paper_renderer_patch`, upstream PR #56556 lands in 0.86+, so a Bridgeless paper-renderer patch — if any — should be safe to drop at 0.86 but may still be needed at 0.85).
5. `cd apps/mac/macos`
6. Pre-download the Hermes V1 tarball (see "After install: `pod install`" section above) and set `HERMES_ENGINE_TARBALL_PATH`
7. `pod install`
8. `./build.sh --mac` (codesigning + DMG + k8s-secret env injection per memory `project_mac_build_script`)
9. Smoke-test the resulting `.app` for the known macOS-fork bug surface, *including* the new RedBox 2.0 macOS implementation — induce a JS crash and confirm the new RedBox renders correctly (header bar, message section, code-frame section with ANSI highlighting, stack-frame section, Esc/Cmd-R/Cmd-Option-C shortcuts, auto-retry countdown on retryable errors). This is the **runtime-untested** part of our port — the build is green but I have not loaded the app and crashed it to see RedBox 2.0 actually paint.

## Known regressions to watch for during smoke-test

Beyond the standard 0.83-era checklist (Modal Fabric crash, vault cold-launch gap, etc.), these are 0.85-specific:

- **CADisplayLink macOS path**: `RCTScheduler.mm` now uses `[[NSScreen mainScreen] displayLinkWithTarget:selector:]` for layout-animation vsync. macOS 14+ only. If your deployment target is lower, this will fail to link or crash at runtime.
- **RCTFrameTimingsObserver stub**: the upstream 0.85 frame-timing screenshotting machinery (Performance API tracing) is no-op on macOS in this release. Frame-timing devtools events won't fire on macOS until someone implements the CVDisplayLink-based equivalent.
- **RedBox 2.0 keyboard shortcuts**: the agent that wrote the port used native `keyDown:` on a custom `RCTRedBox2RootView`. Confirm that focus actually lands on that view when the RedBox presents (Esc / Cmd-R / Cmd-Option-C). If focus doesn't land there, the buttons still work via mouse — just the shortcuts won't.
- **`KeyEvent` / `KeyEventData` rename**: any consumer code in Epistles that imports `KeyEvent` from `react-native/Libraries/Types/CoreEventTypes` will keep getting the fork's NSEvent-wrapped form. Upstream's new web-style `KeyEvent` is now exposed as `KeyEventData`. If Epistles never imported the upstream form, no impact. (Audit covered in AUDIT-0.85.md item 11.)
- **Animation Backend on layout props**: the new `useNativeDriver: true` on layout props (`width`, `marginLeft`, etc.) is *additive* in 0.85, but the C++ animation-driver path on macOS is untested. If Epistles starts using it, validate carefully.
