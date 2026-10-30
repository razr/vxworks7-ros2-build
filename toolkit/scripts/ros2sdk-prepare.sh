#!/usr/bin/env bash
# ros2sdk-prepare.sh - prepare a VANILLA Wind River VxWorks SDK for ROS 2
# development with this kit. Run ONCE.
#
#   ./scripts/ros2sdk-prepare.sh /path/to/vanilla/wrsdk-vxworks7-qemu
#
# It:
#   1) copies the SDK delta (sdk_overlay/) into the SDK          [files only]
#   2) (re)installs the host Python tools (colcon, ros2cli, ...) [pip]
#   3) creates the cross-Python venv (crossenv)
#   4) relocates the ROS 2 SDK (export/root/) to this kit location
#   5) verifies the result
# Idempotent. The SDK must match the kit's arch (see manifest.json).
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
WRSDK="${1:-${WRSDK:-/wrsdk}}"
OV="$KIT_DIR/sdk_overlay"
ROOT="$KIT_DIR/export/root"
REQ="$KIT_DIR/requirements.txt"
HOSTBIN_REL="vxsdk/host/x86_64-linux/bin"

log() { printf '== %s\n' "$*"; }
die() { printf 'prepare FAILED: %s\n' "$*" >&2; exit 1; }

[ -n "$WRSDK" ] || die "usage: ros2sdk-prepare.sh <vanilla-VxWorks-SDK-dir>"
[ -f "$WRSDK/sdkenv.sh" ] || die "no sdkenv.sh in '$WRSDK' - not a VxWorks SDK"
[ -d "$OV" ]   || die "no sdk_overlay/ in the kit"
[ -d "$ROOT" ] || die "no export/root/ (ROS 2 SDK) in the kit"
WRSDK="$(cd "$WRSDK" && pwd)"
log "kit:  $KIT_DIR"
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

# --- 4) relocate the ROS 2 SDK (export/root/) to this kit location -----------------
log "4) relocating export/root/ paths to $ROOT"
SDK_PY_REL='${WIND_SDK_HOME}/vxsdk/host/x86_64-linux/bin/python3'
for f in "$ROOT"/local_setup.sh "$ROOT"/local_setup.bash "$ROOT"/local_setup.zsh; do
  [ -f "$f" ] && sed -i "s#_colcon_python_executable=\"/[^\"]*/python3\"#_colcon_python_executable=\"$SDK_PY_REL\"#" "$f"
done
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

# --- 5) verify --------------------------------------------------------------
log "5) verifying"
[ -f "$WRSDK/vxsdk/sysroot/usr/lib/common/libunixextra.so" ] || die "unixextra not in SDK after overlay"
grep -q 'lunixextra' "$WRSDK/vxsdk/sysroot/cc-conf/default.conf" || die "cc-conf/default.conf missing -lunixextra"
[ -f "$ROOT/share/ament_cmake/cmake/ament_cmakeConfig.cmake" ] || die "export/root/ has no ament_cmake"
ls "$ROOT"/lib/librclcpp.so* >/dev/null 2>&1 || die "export/root/ has no librclcpp"
command -v colcon >/dev/null || log "note: colcon not on PATH yet (source ros2sdkenv.sh)"

log "PASS: SDK prepared. Now:  source $KIT_DIR/scripts/ros2sdkenv.sh"
