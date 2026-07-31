# Build ingredients

Everything baked into the shipped runtime `.pkg`, and how a change to it reaches a release.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Swift version (own upstream) | `SWIFT_VERSION` in `build.sh` | ❌ untracked | auto-cuts `<upstream>-mavericks.1` on the push to main |
| ModernMavericks swift-toolchain build environment | `TOOLCHAIN_REF` + `TOOLCHAIN_SHA256` in `build.sh` | ❌ untracked | auto-repackages `-mavericks.(N+1)` |
| Source patches (`patches/`) | this repo | n/a | auto-repackages `-mavericks.(N+1)`: they change what ships |
| Sparkle framework, MacOSX10.9 SDK | `ModernMavericks/shared-cmake@v1` | ✅ github-actions manager tracks the tag | `@v1` is a moving tag; no path changes, so nothing auto-repackages |

## How a bump reaches a release

Both paths are automatic, and they are kept apart by *which pin moved*:

- **`SWIFT_VERSION` moved** → a new upstream. `version.sh` reports `RELEASE=yes` because that upstream
  has no tag yet, so the push to main auto-cuts `-mavericks.1`.
- **`TOOLCHAIN_REF`, `BUILDSUPPORT_SHA256`, or anything under `patches/` moved** → an ingredient bump.
  `repackage-on-ingredient-bump.yml` dispatches `release.yml` with `local_release=true`, which cuts
  `-mavericks.(N+1)`.

The caller declares `own-upstream-paths: build.sh:SWIFT_VERSION` — a *key*, not a path, because both
kinds of pin live in the same file. Without it a Swift bump would publish twice: `-mavericks.1` from
the push and `-mavericks.2` from the dispatched repackage.

## Automatic publishing does not mean automatic acceptance

This is the one place where that distinction bites, and it is a deliberate choice rather than an
oversight. A macOS 26 runner is structurally blind to the 10.9-only behaviour this runtime exists to
fix — see the release-gating note at the top of `.github/workflows/release.yml`. So an auto-cut
release here **can reach a 10.9 user through Sparkle before anyone has run it on real hardware**.

The trade accepted: shipping promptly and letting real-hardware breakage surface as a follow-up
`-mavericks.(N+1)`, rather than holding every ingredient bump behind a manual validation step. If a
release turns out to be bad on 10.9, the fix is another repackage — the same remedy the rest of the
family uses, and the reason `N` exists.

What this does *not* change: CI green is still not acceptance. Real-10.9 validation remains the bar
for believing a release is good; it is no longer the bar for publishing one.
