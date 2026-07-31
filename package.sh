#!/bin/sh
# Package $OUT (from build.sh) into a distributable .pkg.
# pkgbuild -> flat component pkg, then the SHARED set_install_floor.sh helper
# (mavericks-shared-cmake) wraps it with a 10.9.5 install floor + self-checks it.
#
# NOTE: trackpad2's BundleIsVersionChecked dance does NOT apply -- that guards *bundle*
# components; our payload is a plain libswiftCore.dylib (a file), always installed.
set -eu

OUT="${OUT:-$PWD/out}"
DIST="${DIST:-$PWD/dist}"
# The full version: reuses VERSION if the workflow already resolved it this run, else derives it
# from UPSTREAM_VERSION + the shipped tags. Never a committed file.
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/UPSTREAM_VERSION" ] || sh "$HERE/scripts/derive-upstream-version.sh" >/dev/null
. "$HERE/msc.sh"        # -> $MSC (shared-cmake scripts dir)
VERSION="$(MAVERICKS_ROOT="$HERE" sh "$MSC/resolve-version.sh")"
IDENTIFIER="${PKG_IDENTIFIER:-dev.modernmavericks.swift-runtime}"
NAME="swift-runtime-${VERSION}"
mkdir -p "$DIST"
[ -f "$OUT/usr/lib/swift/libswiftCore.dylib" ] || { echo "no build in $OUT; run build.sh" >&2; exit 1; }

# Locate mavericks-shared-cmake's scripts dir: installed MSC (find_package registry / --prefix), env
# override, or a sibling checkout. Not vendored -- consumed like the siblings. Both set_install_floor
# and stage_updater come from here.
HELPER=""
for c in \
  "${MSC_SCRIPTS:-}/set_install_floor.sh" \
  "${MavericksSharedCMake_SCRIPTS:-}/set_install_floor.sh" \
  "$HOME/.local/share/cmake/MavericksSharedCMake/scripts/set_install_floor.sh" \
  "$PWD/../mavericks-shared-cmake/scripts/set_install_floor.sh" ; do
  [ -n "$c" ] && [ -f "$c" ] && { HELPER="$c"; break; }
done
[ -n "$HELPER" ] || { echo "package: cannot find mavericks-shared-cmake set_install_floor.sh (install MSC or set MSC_SCRIPTS)" >&2; exit 4; }
MSC="$(cd "$(dirname "$HELPER")" && pwd)"

echo ">> resources (welcome + license shown at install)"
RES="$DIST/resources"; mkdir -p "$RES"
cp scripts/resources/Welcome.html "$RES/"
[ -f "$OUT/LICENSE.txt" ] && cp "$OUT/LICENSE.txt" "$RES/" || echo "   (no LICENSE.txt in OUT; build.sh should vendor it)"

echo ">> stage updater app + LaunchAgent + postinstall into the payload (if built)"
UPD_APP="${UPD_APP:-$PWD/build/updater/SwiftUpdater.app}"
set --                                    # pkgbuild gets --scripts only when there IS a postinstall
if [ -d "$UPD_APP" ]; then
  SCR="$DIST/pkg-scripts"; rm -rf "$SCR"; mkdir -p "$SCR"
  sh "$MSC/stage_updater.sh" \
    --stage "$OUT" \
    --app "$UPD_APP" \
    --app-dir "/Library/Application Support/ModernMavericks" \
    --agent-label dev.modernmavericks.swift-updatecheck \
    --scripts-out "$SCR"
  set -- --scripts "$SCR"
else
  echo "   (no updater app at $UPD_APP; packaging runtime only -- build it: cmake --build build/updater)"
fi

echo ">> flat component pkg (payload -> /usr/lib/swift, /usr/local, /Library/LaunchAgents)"
pkgbuild --root "$OUT" --identifier "$IDENTIFIER" --version "$VERSION" \
  "$@" \
  --install-location / "$DIST/swift-runtime-component.pkg"

echo ">> product archive with 10.9.5 floor (shared helper)"
sh "$HELPER" \
  --identifier "$IDENTIFIER" \
  --title "Mavericks Swift Runtime — Swift core runtime for OS X 10.9" \
  --component "$DIST/swift-runtime-component.pkg" \
  --out "$DIST/${NAME}.pkg" \
  --resources "$RES" --welcome Welcome.html --license LICENSE.txt --host-arch x86_64

# The component pkg is an intermediate (no 10.9.5 OS floor -- installing it directly would bypass the
# gate). Only the product archive ships; drop the intermediate so it can't leak into the release glob.
rm -f "$DIST/swift-runtime-component.pkg"

echo ">> checksums"
( cd "$DIST" && shasum -a 256 "${NAME}.pkg" > SHA256SUMS )
cat "$DIST/SHA256SUMS"
echo "OK -> $DIST/${NAME}.pkg"
