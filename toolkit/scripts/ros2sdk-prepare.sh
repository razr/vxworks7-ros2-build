#!/usr/bin/env bash
# ros2sdk-prepare.sh - prepare a VANILLA Wind River VxWorks SDK for ROS 2
# development with this toolkit. Run ONCE.
#
#   ./scripts/ros2sdk-prepare.sh /path/to/vanilla/wrsdk-vxworks7-qemu
#
# It:
#   1) copies the SDK delta (sdk_overlay/) into the SDK          [files only]
#   2) (re)installs the host Python tools (colcon, ros2cli, ...) [pip]
#   3) creates the cross-Python venv (crossenv)
#   4) relocates the ROS 2 SDK (export/root/) to this toolkit location
#   5) verifies the result
# Idempotent. The SDK must match the toolkit's arch (see manifest.json).
set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
WRSDK="${1:-${WRSDK:-/wrsdk}}"
OV="$TOOLKIT_DIR/sdk_overlay"
ROOT="$TOOLKIT_DIR/export/root"
REQ="$TOOLKIT_DIR/requirements.txt"
HOSTBIN_REL="vxsdk/host/x86_64-linux/bin"

log() { printf '== %s\n' "$*"; }
die() { printf 'prepare FAILED: %s\n' "$*" >&2; exit 1; }

[ -n "$WRSDK" ] || die "usage: ros2sdk-prepare.sh <vanilla-VxWorks-SDK-dir>"
[ -f "$WRSDK/sdkenv.sh" ] || die "no sdkenv.sh in '$WRSDK' - not a VxWorks SDK"
[ -d "$OV" ]   || die "no sdk_overlay/ in the toolkit"
[ -d "$ROOT" ] || die "no export/root/ (ROS 2 SDK) in the toolkit"
WRSDK="$(cd "$WRSDK" && pwd)"
log "toolkit:  $TOOLKIT_DIR"
log "SDK:  $WRSDK"

# --- 1) copy the SDK delta (files only; preserves symlinks + perms) ---------
log "1) applying SDK delta (sdk_overlay/ -> SDK)"
cp -a "$OV"/. "$WRSDK"/
# the copied pip/python live next to python3.9 (relative) so they resolve as-is.

# --- source the SDK so host python/pip + WIND_* are available ----------------
# sdkenv.sh is not nounset-clean (references WIND_SDK_HOME before setting it),
# so relax -u around it.
# shellcheck disable=SC1091
set +u
source "$WRSDK/sdkenv.sh"
set -u
export WIND_CC_SYSROOT="${WIND_CC_SYSROOT:-$WIND_SDK_CC_SYSROOT}"
PIP="$WRSDK/$HOSTBIN_REL/pip3"
PY="$WRSDK/$HOSTBIN_REL/python3"
[ -x "$PIP" ] || die "pip3 missing after overlay ($PIP)"

# --- 2) install host Python tools (colcon, ros2cli, crossenv, ...) ----------
if [ -f "$REQ" ]; then
  # bootstrap pip into the SDK host python if absent (ensurepip ships with
  # python; offline). The copied pip3 launcher needs the pip MODULE present.
  if ! "$PY" -m pip --version >/dev/null 2>&1; then
    log "2a) bootstrapping pip (python -m ensurepip)"
    "$PY" -m ensurepip --upgrade >/dev/null 2>&1 || die "ensurepip failed (no pip module in SDK python)"
  fi
  log "2) pip install host tools (-r requirements.txt)"
  "$PY" -m pip install -r "$REQ" || die "pip install failed"
else
  log "2) no requirements.txt - skipping host-tool install"
fi

# --- 3) crossenv (cross-Python venv inside the SDK) -------------------------
VENV="$WRSDK/vxsdk/host/x86_64-linux/cross_venv/cross"
SYSROOT_PY="$WIND_CC_SYSROOT/usr/3pp/develop/usr/bin/python3"
if [ ! -f "$VENV/bin/activate" ] && [ -x "$SYSROOT_PY" ]; then
  log "3) creating crossenv -> $VENV"
  "$PY" -m crossenv "$SYSROOT_PY" "$VENV" || log "WARN: crossenv setup failed (only needed for some Python extension builds)"
else
  log "3) crossenv present or sysroot python absent - skipping"
fi

# --- 4) relocate the ROS 2 SDK (export/root/) to this toolkit location -----------------
log "4) relocating export/root/ paths to $ROOT"
SDK_PY_REL='${WIND_SDK_HOME}/vxsdk/host/x86_64-linux/bin/python3'
for f in "$ROOT"/local_setup.sh "$ROOT"/local_setup.bash "$ROOT"/local_setup.zsh; do
  [ -f "$f" ] && sed -i "s#_colcon_python_executable=\"/[^\"]*/python3\"#_colcon_python_executable=\"$SDK_PY_REL\"#" "$f"
done

# Derive the baked build-time export/root once (from vxworks.mixin's FIND_ROOT_PATH)
# and reuse it below for both setup-script and mixin relocation. The base differs
# by build environment (Docker bakes /work/output/export/root; a native build bakes
# the real host tree, e.g. /home/.../vxworks7-ros2-build/output/export/root).
MIXIN_DIR="$ROOT/.colcon/mixin/default"
VXMIXIN0="$MIXIN_DIR/vxworks.mixin"
OLD_ROOT=""
[ -f "$VXMIXIN0" ] && OLD_ROOT="$("$PY" -c 'import json,sys
m=json.load(open(sys.argv[1]))["build"]["vxworks"]["cmake-args"]
for a in m:
    if a.startswith("-DCMAKE_FIND_ROOT_PATH="): print(a.split("=",1)[1]); break' "$VXMIXIN0" 2>/dev/null)"

# 4-prefix-chain) setup.{sh,bash,zsh} bake the absolute build-time prefix into the
# colcon "prefix chain" (_colcon_prefix_chain_sh_COLCON_CURRENT_PREFIX=<build root>).
# Sourcing setup.bash then prepends that DEAD build-tree path to AMENT_PREFIX_PATH,
# which (a) is wrong after relocation and (b) makes colcon-ros-cargo emit Rust
# [patch.crates-io.<crate>] paths pointing at the build tree, not the toolkit. Rewrite
# the baked prefix to THIS toolkit's $ROOT so the chain resolves to the toolkit itself.
if [ -n "$OLD_ROOT" ] && [ "$OLD_ROOT" != "$ROOT" ]; then
  for f in "$ROOT"/setup.sh "$ROOT"/setup.bash "$ROOT"/setup.zsh; do
    [ -f "$f" ] && sed -i "s#${OLD_ROOT}#${ROOT}#g" "$f"
  done
  log "4) prefix-chain in setup.* relocated: $OLD_ROOT -> $ROOT"
fi

# 4a) relocate the colcon mixins (THE single source of truth for --mixin).
# The build bakes absolute build-time paths into them; the base differs by build
# environment (Docker bakes /work/output/export/root + /work/buildspecs/cmake; a
# native build bakes the real host tree, e.g. /home/.../vxworks7-ros2-build/...).
# So we do NOT assume a fixed prefix: we DERIVE the baked roots from the mixin's
# own values and rewrite them to this toolkit + SDK:
#   <baked export/root>        -> $ROOT               (this toolkit's ROS 2 SDK)
#   <baked toolchain dir>      -> $WIND_SDK_HOME's toolchain dir (vxsdk/sysroot/mk)
#   <baked SDK root>           -> $WIND_SDK_HOME      (this prepared SDK)
# The export/root rewrite is the load-bearing one (FIND_ROOT_PATH + -rpath-link);
# the SDK rewrite fixes the toolchain/make/python paths if the toolkit SDK moved.
# (MIXIN_DIR/VXMIXIN0/OLD_ROOT were derived above in step 4.)
if [ -d "$MIXIN_DIR" ] && [ -f "$VXMIXIN0" ]; then
  log "4a) relocating colcon mixins in $MIXIN_DIR"
  # Derive the remaining baked roots from vxworks.mixin (works for /work OR native).
  OLD_TC="$("$PY" -c 'import json,sys,os
m=json.load(open(sys.argv[1]))["build"]["vxworks"]["cmake-args"]
for a in m:
    if a.startswith("-DCMAKE_TOOLCHAIN_FILE="): print(os.path.dirname(a.split("=",1)[1])); break' "$VXMIXIN0" 2>/dev/null)"
  # SDK root = parent of the baked vxsdk/ dir, derived from the make-program path.
  OLD_SDK="$("$PY" -c 'import json,sys
m=json.load(open(sys.argv[1]))["build"]["vxworks"]["cmake-args"]
for a in m:
    if a.startswith("-DCMAKE_MAKE_PROGRAM"):
        p=a.split("=",1)[1]
        i=p.find("/vxsdk/");  print(p[:i] if i>0 else "")
        break' "$VXMIXIN0" 2>/dev/null)"
  NEW_TC="$WIND_SDK_HOME/vxsdk/sysroot/mk"
  log "4a)   export/root: ${OLD_ROOT:-<none>} -> $ROOT"
  log "4a)   toolchain  : ${OLD_TC:-<none>} -> $NEW_TC"
  log "4a)   sdk        : ${OLD_SDK:-<none>} -> $WIND_SDK_HOME"
  for m in "$MIXIN_DIR"/*.mixin; do
    [ -f "$m" ] || continue
    # order: toolchain dir first (most specific), then export/root, then SDK root.
    [ -n "$OLD_TC" ]   && sed -i "s#${OLD_TC}#${NEW_TC}#g" "$m"
    [ -n "$OLD_ROOT" ] && sed -i "s#${OLD_ROOT}#${ROOT}#g" "$m"
    [ -n "$OLD_SDK" ] && [ "$OLD_SDK" != "$WIND_SDK_HOME" ] && sed -i "s#${OLD_SDK}#${WIND_SDK_HOME}#g" "$m"
  done
else
  log "4a) WARN: no $MIXIN_DIR/vxworks.mixin - toolkit ships no mixin (--mixin vxworks will be unavailable)"
fi

# rust (.cargo/config.toml) bakes an absolute sysroot path at build time; point it
# at THIS SDK's sysroot so Rust (rclrs) builds work regardless of SDK location.
# prune stale vendor CMAKE_PREFIX_PATH hooks that point at a non-existent
# opt/<pkg> inside export/root (e.g. console_bridge_vendor) -> silences a
# harmless but noisy colcon warning. The vendor libs live in export/root/lib,
# already on CMAKE_PREFIX_PATH via the root, so the opt/ sub-prefix is redundant.
for d in "$ROOT"/share/*/environment; do
  [ -d "$d" ] || continue
  for f in "$d"/vendor_package_cmake_prefix.sh "$d"/vendor_package_cmake_prefix.dsv; do
    [ -f "$f" ] || continue
    pkg="$(basename "$(dirname "$d")")"
    if [ ! -d "$ROOT/opt/$pkg" ]; then
      : > "$f"   # empty the hook (missing opt/<pkg> -> no prefix to add)
    fi
  done
done

CARGO_CFG="$WRSDK/vxsdk/sysroot/usr/rust/.cargo/config.toml"
if [ -f "$CARGO_CFG" ]; then
  sed -i "s#/[^\"= ]*/vxsdk/sysroot#$WIND_CC_SYSROOT#g" "$CARGO_CFG" || true
fi

# 4b) Rust (rclrs) WORKSPACE cargo config, rendered to this toolkit's paths.
# make-toolkit.sh staged scripts/rust-cargo-config.toml.template (the ROS 2-specific
# part: [patch.crates-io] libloading + the install-lib -L/-rpath-link flags). This
# is exactly what the MAIN build drops at $WS/src/.cargo/config.toml. The GENERIC
# VxWorks flags (crt-static off, --sysroot, [build] target) come from the SDK's own
# cargo config via CARGO_HOME -- which sdkenv.sh already sets (rustenv.linux ->
# $WIND_CC_SYSROOT/usr/rust/.cargo). Cargo MERGES the two, same as in-place. So we
# only render the ROS 2 part, as a config the user/self-test copies into their
# workspace .cargo/. We stage it at $TOOLKIT_DIR/.cargo/config.toml (a template to
# copy, NOT a CARGO_HOME -- do not point CARGO_HOME here).
RUST_TMPL="$TOOLKIT_DIR/scripts/rust-cargo-config.toml.template"
RUST_CRATES_SRC="$ROOT/share/rclrs/rust"
if [ -f "$RUST_TMPL" ] && [ -d "$RUST_CRATES_SRC" ]; then
  if command -v envsubst >/dev/null 2>&1; then
    log "4b) rendering Rust workspace cargo config -> $TOOLKIT_DIR/.cargo/config.toml"
    mkdir -p "$TOOLKIT_DIR/.cargo"
    ROOT_DIR="$ROOT" \
    ROS2_RUST_CRATES_DIR="$WIND_CC_SYSROOT/usr/rust/vxworks-crates" \
      envsubst '${ROOT_DIR} ${ROS2_RUST_CRATES_DIR}' < "$RUST_TMPL" > "$TOOLKIT_DIR/.cargo/config.toml"
  else
    log "4b) WARN: envsubst missing - Rust workspace cargo config not rendered"
  fi
elif [ -f "$RUST_TMPL" ]; then
  log "4b) no Rust crate sources in export/root (share/rclrs/rust) - toolkit has no Rust support"
fi

# --- 5) verify --------------------------------------------------------------
log "5) verifying"
[ -f "$WRSDK/vxsdk/sysroot/usr/lib/common/libunixextra.so" ] || die "unixextra not in SDK after overlay"
grep -q 'lunixextra' "$WRSDK/vxsdk/sysroot/cc-conf/default.conf" || die "cc-conf/default.conf missing -lunixextra"
[ -f "$ROOT/share/ament_cmake/cmake/ament_cmakeConfig.cmake" ] || die "export/root/ has no ament_cmake"
ls "$ROOT"/lib/librclcpp.so* >/dev/null 2>&1 || die "export/root/ has no librclcpp"
# the vxworks mixin must exist, be relocated (no build-workspace /work/ paths
# left), be valid JSON, and reference paths that now exist on disk.
VXMIXIN="$ROOT/.colcon/mixin/default/vxworks.mixin"
[ -f "$VXMIXIN" ] || die "no vxworks.mixin in export/root/.colcon (toolkit shipped no mixin)"
if grep -q '/work/' "$VXMIXIN"; then
  die "vxworks.mixin still has un-relocated build paths (/work): $(grep -Eo '/work[^"]*' "$VXMIXIN" | head -1)"
fi
"$PY" -c "import json,sys; json.load(open(sys.argv[1]))" "$VXMIXIN" || die "vxworks.mixin is not valid JSON after relocation"
grep -q "$ROOT" "$VXMIXIN" || die "vxworks.mixin does not point at this toolkit's export/root ($ROOT)"
[ -f "$WIND_SDK_HOME/vxsdk/sysroot/mk/toolchain.cmake" ] || die "toolchain.cmake missing at $WIND_SDK_HOME/vxsdk/sysroot/mk (SDK overlay not applied?)"
command -v colcon >/dev/null || log "note: colcon not on PATH yet (source ros2sdkenv.sh)"

log "PASS: SDK prepared. Now:  source $TOOLKIT_DIR/scripts/ros2sdkenv.sh"
