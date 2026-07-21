#!/bin/sh
# Compile the ready test sources against the 10.9 target and bundle them into a
# downloadable self-test tarball that ships in the same Release as the .pkg.
# Users extract it and run ./run-selftest.sh to validate the runtime on THEIR hardware.
#
# The bundled subset GROWS toward the full Swift stdlib suite over increments:
#   - tests/*.swift            our own tests (built here)
#   - tests/prebuilt/*         prebuilt 10.9 test executables dropped in by the build
#                              agent (e.g. the cross-built StdlibUnittest subset)
# Run AFTER build.sh (needs work/toolchain) and package.sh.
set -eu

REPO="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(cat "$REPO/VERSION")"
DIST="${DIST:-$REPO/dist}"
TC="${TC:-$REPO/work/toolchain/usr}"      # prebuilt toolchain fetched by build.sh
SWIFTC="$TC/bin/swiftc"
[ -x "$SWIFTC" ] || { echo "need toolchain swiftc at $SWIFTC (run build.sh first)" >&2; exit 1; }

NAME="mavericks-swift-selftest-$VERSION"
B="$DIST/$NAME"; mkdir -p "$B/bin"

echo ">> compile our test sources for x86_64 / macOS 10.9 (rpath -> /usr/lib/swift)"
for src in "$REPO"/tests/*.swift; do
  [ -f "$src" ] || continue
  n="$(basename "$src" .swift)"
  "$SWIFTC" -target x86_64-apple-macosx10.9 -O \
    -Xlinker -rpath -Xlinker /usr/lib/swift \
    "$src" -o "$B/bin/$n"
  echo "   built: $n"
done

# Prebuilt 10.9 test executables (e.g. the cross-built StdlibUnittest subset) ride along as-is.
if [ -d "$REPO/tests/prebuilt" ]; then
  cp "$REPO"/tests/prebuilt/* "$B/bin/" 2>/dev/null && echo ">> included prebuilt test binaries" || true
fi

[ "$(ls -A "$B/bin" 2>/dev/null)" ] || { echo "no tests built into $B/bin" >&2; exit 1; }

cp "$REPO/tests/run-selftest.sh" "$B/run-selftest.sh"; chmod +x "$B/run-selftest.sh"
[ -f "$REPO/tests/SELFTEST-README.md" ] && cp "$REPO/tests/SELFTEST-README.md" "$B/README.md"

( cd "$DIST" && tar czf "$NAME.tar.gz" "$NAME" && rm -rf "$NAME" )
( cd "$DIST" && shasum -a 256 "$NAME.tar.gz" >> SHA256SUMS )
echo "OK -> $DIST/$NAME.tar.gz  (tests: $(tar tzf "$DIST/$NAME.tar.gz" | grep -c '/bin/[^/]*$'))"
