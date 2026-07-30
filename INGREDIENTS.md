# Build ingredients

Everything baked into the shipped runtime `.pkg`, and how a change to it reaches a release.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Swift version (own upstream) | `SWIFT_VERSION` in `build.sh`, `VERSION` | ❌ untracked | manual: bump + tag `<upstream>-mavericks.1` |
| ModernMavericks swift-toolchain build environment | `TOOLCHAIN_REF` + `TOOLCHAIN_SHA256` in `build.sh` | ❌ untracked | manual: bump + cut a repackage |
| Source patches (`patches/`) | this repo | n/a | own recipe, not an ingredient |
| Sparkle framework, MacOSX10.9 SDK | `ModernMavericks/shared-cmake@v1` | ✅ github-actions manager tracks the tag | `@v1` is a moving tag; no path changes, so nothing auto-repackages |

## Why there is no repackage-on-ingredient-bump caller here — yet

`TOOLCHAIN_REF` is a genuine ingredient pin: a swift-toolchain repackage
(`6.3.3-mavericks.1 → .2`) changes what this runtime is built with, which is exactly the case the
family's `repackage-on-ingredient-bump` pattern automates. Wiring it up is deliberately **not** done,
for two reasons:

1. **Acceptance here is manual, by design.** A macOS 26 runner is structurally blind to the 10.9-only
   behaviour this runtime exists to fix — see the release-gating note at the top of
   `.github/workflows/release.yml`. CI green is not acceptance; real-10.9 validation is. An
   auto-published repackage would ship an unvalidated runtime, which is a worse trade here than in
   repos whose CI can actually prove the product.
2. **The pins aren't separable yet.** `SWIFT_VERSION` (own upstream → `-mavericks.1`) and
   `TOOLCHAIN_REF` (ingredient → `-mavericks.(N+1)`) live in the same file, and the decision script
   compares changed *paths*, not lines. It cannot tell the two cases apart until each pin is its own
   file (e.g. `components/swift-toolchain/version` and `components/swift/version`).

To adopt the pattern later: split those pins into files, add Renovate customManagers for each, give
`release.yml` a `workflow_dispatch` `local_release` input that cuts and publishes
`-mavericks.(N+1)` inline, then add the caller with
`own-upstream-paths: components/swift/version`. Do that only alongside a decision about whether an
auto-cut repackage may publish before someone has run it on real 10.9 hardware.
