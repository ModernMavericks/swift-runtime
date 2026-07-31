# msc.sh -- sourced (with $HERE set to the sourcing script's dir): set $MSC to the installed
# mavericks-shared-cmake scripts dir. Prefer $MSC_SCRIPTS (exported by shared-cmake's install@v1);
# fall back to the CMake user package registry (a local `cmake --install`), then a sibling checkout
# (a dev box that never installed it). This is the only per-repo part of consuming shared-cmake's
# shell scripts; the logic itself (clone_pinned.sh, ...) lives in shared-cmake.
MSC="${MSC_SCRIPTS:-}"
[ -d "$MSC" ] || MSC="$(cat "$HOME/.cmake/packages/MavericksSharedCMake/"* 2>/dev/null | head -1)/scripts"
[ -d "$MSC" ] || MSC="$HERE/../mavericks-shared-cmake/scripts"
[ -d "$MSC" ] || { echo "cannot locate mavericks-shared-cmake scripts (set MSC_SCRIPTS or run install@v1)" >&2; return 1 2>/dev/null || exit 1; }
export MSC
