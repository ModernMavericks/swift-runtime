#!/bin/sh
# build.sh — reproducible from-source build of libswiftCore for macOS 10.9 / x86_64.
#
# Produces: out/libswiftCore.dylib (+ libswiftSwiftOnoneSupport.dylib), minOS 10.9,
# from Swift 6.3.3 swift.org sources, with NO Apple prebuilt runtime bytes redistributed.
#
# Host: macOS with Xcode Command Line Tools (full Xcode NOT required), cmake + ninja + git.
# Cross-target build (host may be arm64; output is x86_64). ~30-60 min from clean on 8 cores.
#
# Everything is PINNED below. Do not float versions — the stdlib is coupled to its compiler.
set -eu

# ---------------------------- PINNED INPUTS ----------------------------------
SWIFT_VERSION="6.3.3"
SWIFT_TAG="swift-6.3.3-RELEASE"
SWIFT_SHA="064859e41d68596f486c5d724401cb370f260409"          # swiftlang/swift @ swift-6.3.3-RELEASE
LLVM_BRANCH="swift/release/6.3"
LLVM_SHA="82cdc19fa54d566969527b56f587ea8ea30bef51"           # swiftlang/llvm-project @ swift/release/6.3
TOOLCHAIN_URL="https://download.swift.org/swift-6.3.3-release/xcode/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE-osx.pkg"
TOOLCHAIN_SHA256="ee82e57774d6650f94aa06302435d6f44a055b9411698db8ecb85d9a3bcc91d0"
DEPLOYMENT="10.9"
ARCH="x86_64"
# -----------------------------------------------------------------------------

HERE="$(cd "$(dirname "$0")" && pwd)"   # script dir (= repo root); capture BEFORE any cd, since $0
                                         # is relative when invoked as ./build.sh and we cd below.
ROOT="$HERE/work"
mkdir -p "$ROOT"; cd "$ROOT"
SDK="$(xcrun --show-sdk-path)"
DI="/Library/Developer/CommandLineTools/usr/bin/dyld_info"

echo "==> 1. toolchain (prebuilt swiftc/clang host tools)"
if [ ! -x toolchain/usr/bin/swiftc ]; then
  curl -fSL -o toolchain.pkg "$TOOLCHAIN_URL"
  echo "${TOOLCHAIN_SHA256}  toolchain.pkg" | shasum -a 256 -c -
  pkgutil --expand toolchain.pkg tc-expand
  mkdir -p toolchain
  ditto -x -z "$(find tc-expand -name Payload | head -1)" toolchain
fi
TC="$ROOT/toolchain/usr"

echo "==> 2. sources (pinned)"
[ -d swift ]        || git clone --depth 1 --branch "$SWIFT_TAG" https://github.com/swiftlang/swift.git swift
[ -d llvm-project ] || git clone --depth 1 --branch "$LLVM_BRANCH" https://github.com/swiftlang/llvm-project.git llvm-project
# verify pins
test "$(git -C swift rev-parse HEAD)" = "$SWIFT_SHA"        || { echo "swift SHA mismatch"; exit 1; }
test "$(git -C llvm-project rev-parse HEAD)" = "$LLVM_SHA"  || { echo "llvm-project SHA mismatch"; exit 1; }
# Defensive: some macOS checkouts fail `git apply` with iconv_open(UTF-8, UTF-8-MAC) on
# unicode paths. Harmless where not needed; prevents a runner-specific patch-apply failure.
git -C swift config core.precomposeunicode false

echo "==> 3. SOURCE PATCHES (five; all in ./patches, applied in order)"
#  0001 unsized operator delete  — 10.9's libc++ lacks __ZdlPvm (sized delete).
#       Safe: IRGen (the only consumer needing sized dealloc) isn't built here.
#  0002 os-version 10.9 fallback — guards os_system_version_get_current_version
#       (macOS 10.10, called unguarded by the availability backing) with a
#       CoreFoundation plist fallback so `if #available` works instead of aborting
#       under 10.9's dyld. Turns an unguarded weak import into a guarded one.
#  0003 guard objc_readClassPair (macOS 10.11) in swift_instantiateObjCClass AND
#       do the minimal in-place objc4-532 realization of runtime-instantiated
#       generic classes when it is absent (calloc class_rw_t, RW_REALIZED,
#       rw->ro=ro, empty cache/vtable, install into data_NEVER_USE) so the ObjC
#       runtime can read/message them on 10.9. (Replaces the earlier broken "skip".)
#  0004 realization-aware getROData — objc4-532 realizes classes eagerly at image
#       load, so a class's Data word may be a class_rw_t; follow rw->ro when
#       RW_REALIZED is set. Both overloads. Fixes garbage ro reads on 10.9.
#  0005 objc-super instance size — in initClassFieldOffsetVector, on the
#       readClassPair-absent (10.9/10.10) runtime, size a subclass from
#       class_getInstanceSize(super) when the objc-super branch would otherwise
#       under-size it (static Swift super's is-swift bit not observed on 10.9).
#  0007 is-swift mask legacy bit — SWIFT_CLASS_IS_SWIFT_MASK=1 for sub-10.14.4
#       Apple targets. The 6.3.3 compiler tags static classes with the LEGACY
#       is-swift bit (bit 0 / value 1) when targeting <10.14.4; a runtime that
#       hardcodes bit 1 (value 2) then reads every static Swift class as
#       isTypeMetadata()==false -> mangled reflection names, and is the root of
#       0005's superIsTypeMetadata==0. Confirmed safe on real 10.9.5 (pure-objc
#       classes leave data low bits free). This is the ROOT fix 0005 symptom-patched.
# Patches are --no-prefix format; apply with -p0.
PATCHES_DIR="$HERE/patches"
for p in "$PATCHES_DIR"/0001-*.patch "$PATCHES_DIR"/0002-*.patch "$PATCHES_DIR"/0003-*.patch \
         "$PATCHES_DIR"/0004-*.patch "$PATCHES_DIR"/0005-*.patch "$PATCHES_DIR"/0007-*.patch; do
  git -C swift apply -p0 --check "$p" && git -C swift apply -p0 "$p" || { echo "patch failed: $p"; exit 1; }
done
grep -q 'fno-sized-deallocation' swift/CMakeLists.txt || { echo "patch 0001 not applied"; exit 1; }
grep -q 'CFPropertyListCreateWithStream' swift/stdlib/public/stubs/Availability.mm || { echo "patch 0002 not applied"; exit 1; }
grep -q 'mav_minimalRealize' swift/stdlib/public/runtime/SwiftObject.mm || { echo "patch 0003 (realization) not applied"; exit 1; }
grep -q 'mav_roFromClassData' swift/stdlib/public/runtime/Metadata.cpp || { echo "patch 0004 (getROData) not applied"; exit 1; }
grep -q 'class_getInstanceSize((Class)const_cast' swift/stdlib/public/runtime/Metadata.cpp || { echo "patch 0005 (objc-super size) not applied"; exit 1; }
grep -q 'ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 101404' swift/include/swift/Runtime/Config.h || { echo "patch 0007 (is-swift mask) not applied"; exit 1; }
# de-instrumented: no debug logging must ship
! grep -rq 'getenv("MAV_' swift/stdlib/public/runtime/ || { echo "MAV debug logging leaked into patches"; exit 1; }

echo "==> 4. LLVM: cmake package + tablegen ONLY (libswiftCore does not link LLVM)"
if [ ! -x llvm-build/bin/llvm-tblgen ]; then
  cmake -G Ninja -S llvm-project/llvm -B llvm-build \
    -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang \
    -DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
    -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF
  ninja -C llvm-build llvm-tblgen clang-tblgen llvm-config intrinsics_gen clang-tablegen-targets
fi
LLVMB="$ROOT/llvm-build"

echo "==> 5. Swift STDLIB-ONLY configure (prebuilt toolchain as native tools)"
cmake -G Ninja -S swift -B stdlib-build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$TC/bin/clang" -DCMAKE_CXX_COMPILER="$TC/bin/clang++" \
  -DLLVM_DIR="$LLVMB/lib/cmake/llvm" -DClang_DIR="$LLVMB/lib/cmake/clang" \
  -DLLVM_TABLEGEN="$LLVMB/bin/llvm-tblgen" -DCLANG_TABLEGEN="$LLVMB/bin/clang-tblgen" \
  -DSWIFT_INCLUDE_TOOLS=OFF \
  -DSWIFT_BUILD_STDLIB=ON -DSWIFT_BUILD_DYNAMIC_STDLIB=ON -DSWIFT_BUILD_STATIC_STDLIB=OFF \
  -DSWIFT_BUILD_SDK_OVERLAY=OFF -DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=OFF -DSWIFT_BUILD_STATIC_SDK_OVERLAY=OFF \
  -DSWIFT_BUILD_REMOTE_MIRROR=OFF -DSWIFT_BUILD_SOURCEKIT=OFF -DSWIFT_BUILD_SWIFT_SYNTAX=OFF \
  -DSWIFT_INCLUDE_TESTS=OFF -DSWIFT_INCLUDE_DOCS=OFF \
  -DSWIFT_BUILD_PERF_TESTSUITE=OFF -DSWIFT_BUILD_EXAMPLES=OFF \
  -DSWIFT_SDKS="OSX" \
  -DSWIFT_HOST_VARIANT_SDK=OSX -DSWIFT_HOST_VARIANT_ARCH="$(uname -m)" \
  -DSWIFT_PRIMARY_VARIANT_SDK=OSX -DSWIFT_PRIMARY_VARIANT_ARCH="$ARCH" \
  -DSWIFT_DARWIN_SUPPORTED_ARCHS="$ARCH" \
  -DSWIFT_DARWIN_DEPLOYMENT_VERSION_OSX="$DEPLOYMENT" \
  -DSWIFT_THREADING_PACKAGE="OSX:pthreads" \
  -DSWIFT_NATIVE_SWIFT_TOOLS_PATH="$TC/bin" -DSWIFT_NATIVE_CLANG_TOOLS_PATH="$TC/bin" \
  -DSWIFT_EXPERIMENTAL_EXTRA_FLAGS="-Xfrontend;-disable-availability-checking"

echo "==> 6. build libswiftCore (+ SwiftOnoneSupport)"
ninja -C stdlib-build swiftCore-macosx-$ARCH swiftSwiftOnoneSupport-macosx-$ARCH

echo "==> 7. stage output (install layout: out/usr/lib/swift/ so package.sh's pkgbuild --root works)"
REPO="$HERE"
OUT="$REPO/out"; DEST="$OUT/usr/lib/swift"; mkdir -p "$DEST"
CORE="$DEST/libswiftCore.dylib"
cp stdlib-build/lib/swift/macosx/$ARCH/libswiftCore.dylib "$CORE"
cp stdlib-build/lib/swift/macosx/$ARCH/libswiftSwiftOnoneSupport.dylib "$DEST/" 2>/dev/null || true
# vendor the license into OUT so package.sh can show it at install time
cp "$REPO/LICENSE" "$OUT/LICENSE.txt"

echo "==> 8. self pre-flight (must show minOS 10.9 and NO os_unfair_lock)"
arch -x86_64 "$DI" -platform "$CORE" | sed -n '3,4p'
if arch -x86_64 "$DI" -imports "$CORE" | grep -q 'os_unfair_lock'; then
  echo "FAIL: os_unfair_lock still imported"; exit 1
fi
# objc_readClassPair must be present only as a *weak* import (guarded), never hard.
if arch -x86_64 "$DI" -imports "$CORE" | grep 'objc_readClassPair' | grep -qv '\[weak-import\]'; then
  echo "FAIL: objc_readClassPair is a HARD import"; exit 1
fi
# release build must carry no debug-logging leftovers.
if strings "$CORE" | grep -q 'MAV_'; then
  echo "FAIL: debug (MAV_) strings present in shipped dylib"; exit 1
fi
echo "OK: no os_unfair_lock; objc_readClassPair weak-guarded; no debug strings; staged in $OUT"
