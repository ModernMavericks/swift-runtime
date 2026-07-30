#!/bin/sh
# mavericks-swift self-test — validate the INSTALLED Swift runtime on THIS Mac (OS X 10.9).
#
# Requires the runtime installed first:  sudo installer -pkg mavericks-swift-*.pkg -target /
# Then:   ./run-selftest.sh          quick pass/fail of every bundled test
#         ./run-selftest.sh --gate   the full acceptance bar: 100x each + Guard Malloc
#
# The tests link the runtime at /usr/lib/swift (absolute rpath), so they exercise the
# EXACT copy the .pkg installed — this tells you it works on your hardware, not ours.
set -eu
cd "$(dirname "$0")"

CORE=/usr/lib/swift/libswiftCore.dylib
[ -f "$CORE" ] || {
  echo "mavericks-swift runtime not found at $CORE" >&2
  echo "Install it first:  sudo installer -pkg mavericks-swift-*.pkg -target /" >&2
  # 77 = SKIP, the family convention (shared-cmake's run-repo-tests.sh, and ctest's
  # SKIP_RETURN_CODE): this needs the runtime installed on a real 10.9 box. A CI runner was never
  # going to have one, so this is "not applicable here", not a failure.
  exit 77
}

MODE="${1:-quick}"
pass=0; fail=0; failed=""
for t in bin/*; do
  [ -x "$t" ] || continue
  name=$(basename "$t")
  ok=1
  if [ "$MODE" = "--gate" ]; then
    n=0; while [ $n -lt 100 ]; do "./$t" >/dev/null 2>&1 || { ok=0; break; }; n=$((n+1)); done
    [ $ok = 1 ] && { DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib "./$t" >/dev/null 2>&1 || ok=0; }
    label="100x+gmalloc"
  else
    "./$t" >/dev/null 2>&1 || ok=0
    label="run"
  fi
  if [ $ok = 1 ]; then printf '  PASS (%s): %s\n' "$label" "$name"; pass=$((pass+1))
  else printf '  FAIL: %s\n' "$name"; fail=$((fail+1)); failed="$failed $name"; fi
done

echo "----------------------------------------"
echo "passed=$pass  failed=$fail"
if [ $fail -eq 0 ]; then
  echo "ALL PASS — the Swift runtime works on this machine."
else
  echo "FAILURES:$failed"
  echo "(Please report at the project's issue tracker with your exact OS X build: sw_vers.)"
  exit 1
fi
