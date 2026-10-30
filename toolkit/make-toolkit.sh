#!/usr/bin/env bash
# make-toolkit.sh - assemble the ROS 2 VxWorks SDK delivery kit (the `toolkit`
# recipe). Invoked by `make toolkit` (mk/usr/defs.toolkit.mk) with these vars in
# the environment:
#
#   TOP_BUILDDIR EXPORT_DIR ROOT_DIR PACKAGE_DIR BUILDSPECS_DIR
#   ROS_DISTRO WIND_RELEASE_ID TGT_ARCH WIND_CC_SYSROOT WIND_SDK_HOME
#   TOOLKIT_SRC_DIR TOOLKIT_STAGE TOOLKIT_TARBALL
#
# It stages a self-contained kit:
#   sdk_overlay/      - the SDK delta, generated from AUTHORITATIVE sources
#                       (buildspecs/cmake, pkg/sdk/files, built unixextra, the
#                       patched SDK's host bin + rust) - NOT from a diff.
#   sdk_overlay.json  - inventory of the overlay
#   requirements.txt  - host pip tools (colcon/ros2cli/crossenv/...)
#   export/root       - the prebuilt ROS 2 SDK (build apps against this)
#   ros2.img          - bootable VxWorks target image (CONTAINS the target rootfs
#                       that would otherwise be export/deploy; not shipped loose)
#   scripts/ host-shims/ .devcontainer/ .vscode/ README.md  - committed tooling
#   manifest.json     - build recipe (keys == Makefile vars) + layer pin
# then tars it to $TOOLKIT_TARBALL.
set -euo pipefail

log()  { printf '  toolkit: %s\n' "$*"; }
die()  { printf 'toolkit FAILED: %s\n' "$*" >&2; exit 1; }
need() { [ -n "${!1:-}" ] || die "env var $1 is required (run via 'make toolkit')"; }

for v in TOP_BUILDDIR EXPORT_DIR ROOT_DIR PACKAGE_DIR BUILDSPECS_DIR \
         ROS_DISTRO WIND_CC_SYSROOT WIND_SDK_HOME TOOLKIT_SRC_DIR TOOLKIT_STAGE \
         TOOLKIT_TARBALL; do need "$v"; done

STAGE="$TOOLKIT_STAGE"
OV="$STAGE/sdk_overlay"
HOSTBIN_REL="vxsdk/host/x86_64-linux/bin"
SYSROOT_REL="vxsdk/sysroot"
UNIXEXTRA_SRC="$TOP_BUILDDIR/build/unixextra/src"
SDK_HOSTBIN="$WIND_SDK_HOME/$HOSTBIN_REL"

# ---------------------------------------------------------------------------
log "staging at $STAGE"
rm -rf "$STAGE"; mkdir -p "$STAGE"

# --- 1) sdk_overlay/ from AUTHORITATIVE sources -----------------------------
log "1) building sdk_overlay/ (authoritative sources)"

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
for h in fcntl.h fnmatch.h pthread.h string.h termios.h; do
  install -D -m0644 "$UNIXEXTRA_SRC/$h" "$UX_H/$h"
done
install -D -m0644 "$UNIXEXTRA_SRC/sys/file.h"    "$UX_H/sys/file.h"
install -D -m0644 "$UNIXEXTRA_SRC/sys/ttycom.h"  "$UX_H/sys/ttycom.h"

# 1d) cc-conf/default.conf (carries the -lunixextra link edit)  <- patched SDK
grep -q 'lunixextra' "$WIND_CC_SYSROOT/cc-conf/default.conf" \
  || die "patched SDK default.conf has no -lunixextra (is the SDK patched? run 'make sdk')"
install -D -m0644 "$WIND_CC_SYSROOT/cc-conf/default.conf" "$OV/$SYSROOT_REL/cc-conf/default.conf"

# 1e) host bin: pip/python launchers + symlinks + cargo-ament-build  <- patched SDK
install -D -m0755 "$SDK_HOSTBIN/pip3.9"           "$OV/$HOSTBIN_REL/pip3.9"
install -D -m0755 "$SDK_HOSTBIN/cargo-ament-build" "$OV/$HOSTBIN_REL/cargo-ament-build"
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
  log "   (no rust fixups in SDK - skipping; kit without Rust)"
fi

# --- 2) sdk_overlay.json inventory ------------------------------------------
log "2) sdk_overlay.json"
( cd "$OV" && find . -type f -o -type l ) | sed 's#^\./##' | LC_ALL=C sort > "$STAGE/.ovlist"
python3 - "$STAGE/.ovlist" "$STAGE/sdk_overlay.json" <<'PY'
import json, sys
files = [l.strip() for l in open(sys.argv[1]) if l.strip()]
doc = {
  "description": "Files copied verbatim into the vanilla VxWorks SDK by "
                 "scripts/ros2sdk-prepare.sh (cp -a sdk_overlay/. $WRSDK/). "
                 "Paths relative to SDK root.",
  "files": files,
  "pip_requirements": "requirements.txt",
  "crossenv": {"regenerate": True,
               "path": "vxsdk/host/x86_64-linux/cross_venv/cross"},
}
json.dump(doc, open(sys.argv[2], "w"), indent=2)
open(sys.argv[2], "a").write("\n")
PY
rm -f "$STAGE/.ovlist"

# --- 3) requirements.txt (host pip tools) -----------------------------------
log "3) requirements.txt"
install -m0644 "$TOOLKIT_SRC_DIR/requirements.txt" "$STAGE/requirements.txt"

# --- 4) the ROS 2 SDK: export/root + ros2.img ------------------------------
# NOTE: export/deploy is deliberately NOT shipped separately -- it is already
# inside ros2.img (make image packs it there). Shipping it loose would duplicate
# the whole target rootfs. extract-deploy.sh can recover it from ros2.img if a
# user ever needs the loose tree.
log "4) export/root + ros2.img (copying built artifacts; deploy is inside ros2.img)"
[ -d "$ROOT_DIR" ]              || die "export/root missing ($ROOT_DIR) - run 'make'"
[ -f "$TOP_BUILDDIR/ros2.img" ] || die "ros2.img missing - run 'make image'"
mkdir -p "$STAGE/export"
cp -a "$ROOT_DIR"   "$STAGE/export/root"
cp -a "$TOP_BUILDDIR/ros2.img" "$STAGE/ros2.img"

# --- 5) committed tooling (scripts, shims, devcontainer, vscode, README) ----
log "5) scripts/ host-shims/ .devcontainer/ .vscode/ README.md"
cp -a "$TOOLKIT_SRC_DIR/scripts"       "$STAGE/scripts"
cp -a "$TOOLKIT_SRC_DIR/host-shims"    "$STAGE/host-shims"
cp -a "$TOOLKIT_SRC_DIR/.devcontainer" "$STAGE/.devcontainer"
cp -a "$TOOLKIT_SRC_DIR/.vscode"       "$STAGE/.vscode"
install -m0644 "$TOOLKIT_SRC_DIR/README.md" "$STAGE/README.md"
find "$STAGE/host-shims" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true

# --- 6) manifest.json (keys == Makefile vars) + layer pin -------------------
log "6) manifest.json"
PKGMK="$PACKAGE_DIR/ros2/files/$ROS_DISTRO/packages.mk"
GENMANIFEST="$TOOLKIT_SRC_DIR/scripts/generate-manifest.py"
if [ -f "$PKGMK" ] && [ -f "$GENMANIFEST" ]; then
  # generate-manifest.py takes 8 positional args and prints JSON to stdout:
  #   mk ros_distro vx_rel vx_sdk arch layer_url layer_branch layer_commit
  # layer url/branch come from pkg/ros2/Makefile (passed via the env by the
  # toolkit target); the resolved commit is best-effort (empty if unknown).
  python3 "$GENMANIFEST" \
      "$PKGMK" \
      "$ROS_DISTRO" \
      "${WIND_RELEASE_ID:-unknown}" \
      "$(basename "$WIND_SDK_HOME")" \
      "${TGT_ARCH:-unknown}" \
      "${PKG_LAYER_URL:-https://github.com/Wind-River/vxworks7-layer-for-ros2.git}" \
      "${PKG_LAYER_COMMIT_ID:-$ROS_DISTRO-release-${WIND_RELEASE_ID:-}}" \
      "${PKG_LAYER_COMMIT:-}" \
      > "$STAGE/manifest.json" \
    || log "   WARN: manifest generation failed (continuing)"
else
  log "   WARN: no packages.mk or generate-manifest.py - skipping manifest"
fi

# --- 7) tar it --------------------------------------------------------------
log "7) packaging -> $TOOLKIT_TARBALL"
STAGE_PARENT="$(dirname "$STAGE")"
STAGE_BASE="$(basename "$STAGE")"
if command -v zstd >/dev/null 2>&1 && [[ "$TOOLKIT_TARBALL" == *.zst ]]; then
  tar -C "$STAGE_PARENT" -cf - "$STAGE_BASE" | zstd -19 -T0 -q -o "$TOOLKIT_TARBALL" -f
else
  GZ="${TOOLKIT_TARBALL%.zst}.gz"; GZ="${GZ%.tar.gz}.tar.gz"
  tar -C "$STAGE_PARENT" -czf "$GZ" "$STAGE_BASE"
  log "   (zstd absent) wrote $GZ"
fi

log "done. staged: $STAGE"
