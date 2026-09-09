# msc.sh -- sourced (with $HERE set to the sourcing script's dir): set $SHIPYARD to the installed
# mavericks-shipyard scripts dir. Prefer $SHIPYARD_SCRIPTS (exported by shipyard's install@v1);
# fall back to the CMake user package registry (a local `cmake --install`), then a sibling checkout
# (a dev box that never installed it). This is the only per-repo part of consuming shipyard's
# shell scripts; the logic itself (clone_pinned.sh, ...) lives in shipyard.
SHIPYARD="${SHIPYARD_SCRIPTS:-}"
[ -d "$SHIPYARD" ] || SHIPYARD="$(cat "$HOME/.cmake/packages/MavericksShipyard/"* 2>/dev/null | head -1)/scripts"
[ -d "$SHIPYARD" ] || SHIPYARD="$HERE/../mavericks-shipyard/scripts"
[ -d "$SHIPYARD" ] || { echo "cannot locate mavericks-shipyard scripts (set SHIPYARD_SCRIPTS or run install@v1)" >&2; return 1 2>/dev/null || exit 1; }
export SHIPYARD
