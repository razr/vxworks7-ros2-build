#!/usr/bin/env bash
# make-sdk-overlay.sh - generate the SDK overlay: the delta that turns a vanilla
# VxWorks SDK into the SDK this build used. Invoked by `make fs`
# (mk/usr/defs.toolkit.mk::build_sdk_overlay) with these vars in the environment:
#
#   TOP_BUILDDIR PACKAGE_DIR BUILDSPECS_DIR WIND_CC_SYSROOT WIND_SDK_HOME
#   SDK_OVERLAY_DIR SDK_OVERLAY_JSON
#
# Output (a build output, like export/root and ros2.img; `make toolkit` packs it):
#   $SDK_OVERLAY_DIR/   - the SDK delta, generated from the build inputs
#                         (buildspecs/cmake, pkg/sdk/files, built unixextra, the
#                         patched SDK's host bin + rust) - NOT from a diff.
#   $SDK_OVERLAY_JSON   - inventory: files to copy, SDK files to move aside.
set -euo pipefail

log()  { printf '  sdk-overlay: %s\n' "$*"; }
die()  { printf 'sdk-overlay FAILED: %s\n' "$*" >&2; exit 1; }
need() { [ -n "${!1:-}" ] || die "env var $1 is required (run via 'make fs')"; }

for v in TOP_BUILDDIR PACKAGE_DIR BUILDSPECS_DIR WIND_CC_SYSROOT WIND_SDK_HOME \
         SDK_OVERLAY_DIR SDK_OVERLAY_JSON; do need "$v"; done

OV="$SDK_OVERLAY_DIR"
OV_JSON="$SDK_OVERLAY_JSON"
HOSTBIN_REL="vxsdk/host/x86_64-linux/bin"
SYSROOT_REL="vxsdk/sysroot"
UNIXEXTRA_SRC="$TOP_BUILDDIR/build/unixextra/src"
SDK_HOSTBIN="$WIND_SDK_HOME/$HOSTBIN_REL"

rm -rf "$OV" "$OV_JSON"; mkdir -p "$OV"

# --- 1) sdk_overlay/ from the build inputs ----------------------------------
log "1) building sdk_overlay/"

# 1a) cmake toolchain + Platform  <- buildspecs/cmake (repo)
install -D -m0644 "$BUILDSPECS_DIR/cmake/toolchain.cmake"        "$OV/$SYSROOT_REL/mk/toolchain.cmake"
install -D -m0644 "$BUILDSPECS_DIR/cmake/Platform/VxWorks.cmake" "$OV/$SYSROOT_REL/mk/Platform/VxWorks.cmake"

# 1b) defs.autotools.mk  <- pkg/sdk/files (repo)
install -D -m0644 "$PACKAGE_DIR/sdk/files/defs.autotools.mk"     "$OV/$SYSROOT_REL/mk/defs.autotools.mk"

# 1c) unixextra lib + the EXACTLY 7 headers it installs  <- built unixextra src
[ -d "$UNIXEXTRA_SRC" ] || die "unixextra build dir missing: $UNIXEXTRA_SRC (run 'make' first)"
install -D -m0644 "$UNIXEXTRA_SRC/libunixextra.a"    "$OV/$SYSROOT_REL/usr/lib/common/libunixextra.a"
install -D -m0755 "$UNIXEXTRA_SRC/libunixextra.so.1" "$OV/$SYSROOT_REL/usr/lib/common/libunixextra.so.1"
ln -sf libunixextra.so.1 "$OV/$SYSROOT_REL/usr/lib/common/libunixextra.so"
UX_H="$OV/$SYSROOT_REL/usr/h/published/UTILS_UNIX"
# Overlay ONLY the UTILS_UNIX headers unixextra ACTUALLY installed into the SDK
# sysroot -- do NOT hardcode the list from $UNIXEXTRA_SRC. unixextra's install is
# version-aware (pkg/unixextra/Makefile: for WIND_RELEASE_ID major > 23 it drops
# pthread_getname.c from SOURCES, so pthread.h is NOT installed because VxWorks
# libc already provides pthread_getname_np/pthread_setname_np). Copying a fixed
# list from the source tree re-introduced a stale pthread.h whose const-char*
# signature conflicts with libc/public pthread.h and breaks find_package(Threads)
# (e.g. libxml2_vendor). Mirroring the installed set keeps the toolkit in lockstep
# with unixextra's own version logic -- no duplicated MAJOR_VERSION check to drift.
UX_SYSROOT_H="$WIND_CC_SYSROOT/usr/h/published/UTILS_UNIX"
[ -d "$UX_SYSROOT_H" ] || die "unixextra headers not installed in sysroot: $UX_SYSROOT_H (run 'make unixextra' first)"
( cd "$UX_SYSROOT_H" && find . -name '*.h' -print ) | while IFS= read -r rel; do
  install -D -m0644 "$UX_SYSROOT_H/$rel" "$UX_H/$rel"
done

# 1d) cc-conf/default.conf (carries the -lunixextra link edit)  <- patched SDK
grep -q 'lunixextra' "$WIND_CC_SYSROOT/cc-conf/default.conf" \
  || die "patched SDK default.conf has no -lunixextra (is the SDK patched? run 'make sdk')"
install -D -m0644 "$WIND_CC_SYSROOT/cc-conf/default.conf" "$OV/$SYSROOT_REL/cc-conf/default.conf"

# 1e) host bin: pip/python launchers + symlinks + cargo-ament-build +
#     optimize-python-startup  <- patched SDK
install -D -m0755 "$SDK_HOSTBIN/pip3.9"           "$OV/$HOSTBIN_REL/pip3.9"
install -D -m0755 "$SDK_HOSTBIN/cargo-ament-build" "$OV/$HOSTBIN_REL/cargo-ament-build"
install -D -m0755 "$SDK_HOSTBIN/optimize-python-startup" "$OV/$HOSTBIN_REL/optimize-python-startup"
ln -sf pip3.9    "$OV/$HOSTBIN_REL/pip"
ln -sf pip3.9    "$OV/$HOSTBIN_REL/pip3"
ln -sf python3.9 "$OV/$HOSTBIN_REL/python"
ln -sf python3.9 "$OV/$HOSTBIN_REL/python3"

# 1f) rust fixups: .cargo/config.toml + patched libloading  <- patched SDK
RUST_SRC="$WIND_CC_SYSROOT/usr/rust"
if [ -f "$RUST_SRC/.cargo/config.toml" ]; then
  install -D -m0644 "$RUST_SRC/.cargo/config.toml" "$OV/$SYSROOT_REL/usr/rust/.cargo/config.toml"
  if [ -d "$RUST_SRC/vxworks-crates/libloading" ]; then
    LL_DST="$OV/$SYSROOT_REL/usr/rust/vxworks-crates/libloading"
    mkdir -p "$LL_DST/src"
    cp -a "$RUST_SRC/vxworks-crates/libloading/src/." "$LL_DST/src/"
    for f in Cargo.toml Cargo.lock LICENSE; do
      [ -f "$RUST_SRC/vxworks-crates/libloading/$f" ] && cp -a "$RUST_SRC/vxworks-crates/libloading/$f" "$LL_DST/$f"
    done
  fi
else
  log "   (no rust fixups in SDK - skipping; toolkit without Rust)"
fi

# --- 2) sdk_overlay.json inventory ------------------------------------------
log "2) sdk_overlay.json"
( cd "$OV" && find . -type f -o -type l ) | sed 's#^\./##' | LC_ALL=C sort > "$TOP_BUILDDIR/.ovlist"
# SDK files the build moved out of the way (pkg/sdk sdk_fix -> 3pp/.removed/<tree>/,
# e.g. the SDK sqlite/libyaml that ROS 2 builds as vendors). Mirrored from what
# the build actually moved, so the list cannot drift from defs.sdk.mk.
RM_ROOT="$WIND_CC_SYSROOT/usr/3pp/.removed"
: > "$TOP_BUILDDIR/.rmlist"
if [ -d "$RM_ROOT" ]; then
  ( cd "$RM_ROOT" && find . -mindepth 2 \( -type f -o -type l \) ) | sed 's#^\./##' \
    | sed "s#^#$SYSROOT_REL/usr/3pp/#" | LC_ALL=C sort > "$TOP_BUILDDIR/.rmlist"
fi
python3 - "$TOP_BUILDDIR/.ovlist" "$OV_JSON" "$TOP_BUILDDIR/.rmlist" <<'PY'
import json, sys
files = [l.strip() for l in open(sys.argv[1]) if l.strip()]
removed = [l.strip() for l in open(sys.argv[3]) if l.strip()]
doc = {
  "description": "Files copied verbatim into the vanilla VxWorks SDK by "
                 "scripts/ros2sdk-prepare.sh (cp -a sdk_overlay/. $WRSDK/), and SDK "
                 "files it moves aside (removed: <3pp>/<tree>/X -> <3pp>/.removed/<tree>/X). "
                 "Paths relative to SDK root.",
  "files": files,
  "removed": removed,
  "pip_requirements": "requirements.txt",
  "crossenv": {"regenerate": True,
               "path": "vxsdk/host/x86_64-linux/cross_venv/cross"},
}
json.dump(doc, open(sys.argv[2], "w"), indent=2)
open(sys.argv[2], "a").write("\n")
PY
rm -f "$TOP_BUILDDIR/.ovlist" "$TOP_BUILDDIR/.rmlist"

log "done: $OV + $OV_JSON"
