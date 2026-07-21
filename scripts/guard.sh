#!/bin/sh
# Project wrapper around mavericks-shared-cmake's assert_binary_compatible.sh.
# Encodes mavericks-swift's 10.9 policy and delegates to the shared guard:
#   - EXTEND the denylist to the full post-10.9 os_* family (underscore-robust; the
#     shared default only covers os_unfair_lock + os_log single-underscore).
#   - ALLOW those families ONLY when imported *weak* (the Swift runtime NULL-checks
#     them via SWIFT_RUNTIME_WEAK_CHECK). os_unfair_lock is deliberately NOT allowed:
#     the runtime calls it UNGUARDED, so it must be built out (pthreads/patch).
# Usage: scripts/guard.sh <dylib> [<dylib> ...]
set -eu

# Locate the shared guard from mavericks-shared-cmake: installed MSC (find_package registry /
# --prefix), an env override, or a sibling checkout. Not vendored -- consumed like trackpad2/dimmit.
SHARED=""
for c in \
  "${MSC_SCRIPTS:-}/assert_binary_compatible.sh" \
  "${MavericksSharedCMake_SCRIPTS:-}/assert_binary_compatible.sh" \
  "$HOME/.local/share/cmake/MavericksSharedCMake/scripts/assert_binary_compatible.sh" \
  "$(dirname "$0")/../../mavericks-shared-cmake/scripts/assert_binary_compatible.sh" ; do
  [ -n "$c" ] && [ -f "$c" ] && { SHARED="$c"; break; }
done
[ -n "$SHARED" ] || { echo "guard: cannot find mavericks-shared-cmake assert_binary_compatible.sh" >&2
                      echo "       install it (cmake --install) or set MSC_SCRIPTS." >&2; exit 4; }

# Full post-10.9 os_* family, tolerant of the one/two leading-underscore SPI naming.
export MAVERICKS_POST_10_9_SYMBOLS='__?os_signpost.*|__?os_log.*|_os_system_version_get_current_version|__?os_availability.*'
# Guarded-weak allowlist: OK only when weak. (os_unfair_lock intentionally absent.)
export MAVERICKS_ALLOW_GUARDED_WEAK='_objc_realizeClassFromSwift|_objc_readClassPair|_objc_setHook_.*|_objc_addLoadImageFunc|__?os_log.*|__?os_signpost.*|_os_system_version_get_current_version|__availability_version_check|__dyld_is_objc_constant'

exec sh "$SHARED" "$@"
