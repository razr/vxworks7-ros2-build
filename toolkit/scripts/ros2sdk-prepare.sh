#!/usr/bin/env bash
# ros2sdk-prepare.sh - prepare a VANILLA Wind River VxWorks SDK for ROS 2
# development with this toolkit. Run ONCE.
#
#   ./scripts/ros2sdk-prepare.sh /path/to/vanilla/wrsdk-vxworks7-qemu
#
# Two separate parts:
#   1) install the SDK overlay into the SDK: runs the overlay's own installer,
#      sdk-overlay/install-sdk-overlay.sh (made by `make sdk-overlay`)
#   2) relocate the ROS 2 SDK (export/root/) to this toolkit location: one
#      function per producer of baked build paths (see below)
# Each part checks its own result. Idempotent. The SDK must match the toolkit's
# arch (see manifest.json).
set -euo pipefail

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
WRSDK="${1:-${WRSDK:-/wrsdk}}"
OV_DIR="$TOOLKIT_DIR/sdk-overlay"
ROOT="$TOOLKIT_DIR/export/root"
HOSTBIN_REL="vxsdk/host/x86_64-linux/bin"

log() { printf '== %s\n' "$*"; }
die() { printf 'prepare FAILED: %s\n' "$*" >&2; exit 1; }

[ -n "$WRSDK" ] || die "usage: ros2sdk-prepare.sh <vanilla-VxWorks-SDK-dir>"
[ -f "$WRSDK/sdkenv.sh" ] || die "no sdkenv.sh in '$WRSDK' - not a VxWorks SDK"
[ -x "$OV_DIR/install-sdk-overlay.sh" ] || die "no sdk-overlay/install-sdk-overlay.sh in the toolkit"
[ -d "$ROOT" ]    || die "no export/root/ (ROS 2 SDK) in the toolkit"
WRSDK="$(cd "$WRSDK" && pwd)"
log "toolkit:  $TOOLKIT_DIR"
log "SDK:  $WRSDK"

# SDK env: host python + WIND_*. sdkenv.sh is not nounset-clean (references
# WIND_SDK_HOME before setting it), so relax -u around it.
# shellcheck disable=SC1091
set +u
source "$WRSDK/sdkenv.sh"
set -u
export WIND_CC_SYSROOT="${WIND_CC_SYSROOT:-$WIND_SDK_CC_SYSROOT}"
PY="$WRSDK/$HOSTBIN_REL/python3"       # installed by the SDK overlay (python_fix)

# =============================================================================
# 1) install the SDK overlay (its own installer, shipped in sdk-overlay/)
# =============================================================================
"$OV_DIR/install-sdk-overlay.sh" "$WRSDK" || die "installing the SDK overlay failed"

# =============================================================================
# 2) relocate the ROS 2 SDK (export/root/) to this toolkit location
# =============================================================================
# The build bakes absolute build-time paths into export/root. One function per
# producer of such paths, each with its own check:
#   colcon_local_setup_relocate    colcon install: local_setup.* prefix + python executable
#   colcon_setup_relocate          colcon install: setup.* prefix chain
#   colcon_package_relocate        colcon install: share/<pkg>/package.* + hook/*
#   python_shebangs_relocate       any installed python script: #!<build SDK python> shebangs
#   ament_package_relocate         ament_package: local_setup.fish + share/<pkg>/local_setup.*, environment/*
#   cmake_install_prefix_relocate  CMake install: *.pc / *Config.cmake with CMAKE_INSTALL_PREFIX
#   vxworks_mixin_relocate         pkg/ros2 vxworks.mixin.template: the colcon mixins
#   ament_vendor_hooks_relocate    ament_vendor: vendor_package_cmake_prefix hooks
#   ament_vendor_prefix_relocate   ament_vendor: the vendor's staging install prefix
#   rust_cargo_config_relocate     pkg/ros2 rust-cargo-config.toml.template
# export_root_check then reports any build-time path still left in a text file.
# The baked roots differ by build environment (Docker bakes /work/..., a native
# build the real host tree), so they are read from the vxworks mixin, not assumed.

MIXIN_DIR="$ROOT/.colcon/mixin/default"
VXMIXIN="$MIXIN_DIR/vxworks.mixin"

# mixin_arg <prefix>: value of the vxworks mixin cmake-arg starting with <prefix>
mixin_arg() {
  "$PY" -c 'import json,sys; a=[x for x in json.load(open(sys.argv[1]))["build"]["vxworks"]["cmake-args"] if x.startswith(sys.argv[2])]; print(a[0].split("=",1)[1] if a else "")' "$VXMIXIN" "$1"
}

# relocate_files <old> <new> <file>...: replace the literal path <old> by <new>
relocate_files() {
  local old="$1" new="$2"; shift 2
  local re; re="$(printf '%s' "$old" | sed 's/[][\\.*^$|]/\\&/g')"
  [ $# -gt 0 ] || return 0
  sed -i "s|${re}|${new}|g" "$@"
}

# files_with <path> <file>...: those of <file>... that contain the literal <path>
files_with() {
  local p="$1"; shift
  [ $# -gt 0 ] || return 0
  grep -lIF -- "$p" "$@" 2>/dev/null || true
}

ros2_sdk_check() {
  [ -f "$ROOT/share/ament_cmake/cmake/ament_cmakeConfig.cmake" ] || die "ros2 sdk: export/root/ has no ament_cmake"
  ls "$ROOT"/lib/librclcpp.so* >/dev/null 2>&1 || die "ros2 sdk: export/root/ has no librclcpp"
  [ -f "$VXMIXIN" ] || die "ros2 sdk: no vxworks.mixin in export/root/.colcon (toolkit shipped no mixin)"
  # baked build-time roots: export/root, cmake toolchain dir, SDK root
  OLD_ROOT="$(mixin_arg -DCMAKE_FIND_ROOT_PATH=)"
  OLD_TC="$(mixin_arg -DCMAKE_TOOLCHAIN_FILE=)"; OLD_TC="${OLD_TC%/*}"
  OLD_SDK="$(mixin_arg -DCMAKE_MAKE_PROGRAM)"; OLD_SDK="${OLD_SDK%%/vxsdk/*}"
  # the build's output dir (export/root's grandparent): holds the colcon workspace
  OLD_TOP="${OLD_ROOT%/export/root}"; [ "$OLD_TOP" != "$OLD_ROOT" ] || OLD_TOP=""
  NEW_TC="$WIND_SDK_HOME/vxsdk/sysroot/mk"
  log "ros2 sdk: export/root ${OLD_ROOT:-<none>} -> $ROOT"
  log "ros2 sdk: toolchain   ${OLD_TC:-<none>} -> $NEW_TC"
  log "ros2 sdk: SDK         ${OLD_SDK:-<none>} -> $WIND_SDK_HOME"
}

# --- colcon install: local_setup.* --------------------------------------------------
# _colcon_python_executable is the build's host python: use this SDK's python3.
# local_setup.sh also bakes the build's export/root as its default prefix.
colcon_local_setup_relocate() {
  local py='${WIND_SDK_HOME}/vxsdk/host/x86_64-linux/bin/python3' f
  for f in "$ROOT"/local_setup.sh "$ROOT"/local_setup.bash "$ROOT"/local_setup.zsh; do
    [ -f "$f" ] || continue
    sed -i "s#_colcon_python_executable=\"/[^\"]*/python3\"#_colcon_python_executable=\"$py\"#" "$f"
    grep -q '_colcon_python_executable="/' "$f" && die "colcon local_setup: absolute python left in $f"
    if [ -n "$OLD_ROOT" ] && [ "$OLD_ROOT" != "$ROOT" ]; then
      relocate_files "$OLD_ROOT" "$ROOT" "$f"
      grep -qF "$OLD_ROOT" "$f" && die "colcon local_setup: $OLD_ROOT left in $f"
    fi
  done
  # PowerShell (no ${WIND_SDK_HOME} expansion there): this SDK's absolute python
  f="$ROOT/local_setup.ps1"
  if [ -f "$f" ] && [ -n "$OLD_SDK" ] && [ "$OLD_SDK" != "$WIND_SDK_HOME" ]; then
    relocate_files "$OLD_SDK/$HOSTBIN_REL/python" "$WIND_SDK_HOME/$HOSTBIN_REL/python" "$f"
    grep -qF "$OLD_SDK/$HOSTBIN_REL/python" "$f" && die "colcon local_setup: build python left in $f"
  fi
  log "colcon local_setup: python -> $py, prefix -> $ROOT"
}

# --- colcon install: setup.* prefix chain -------------------------------------------
# setup.* bake the build's export/root into the prefix chain; sourcing it would put
# that dead path on AMENT_PREFIX_PATH (and colcon-ros-cargo would emit Rust [patch]
# paths into the build tree). Point the chain at this toolkit's export/root.
colcon_setup_relocate() {
  local f
  [ -n "$OLD_ROOT" ] && [ "$OLD_ROOT" != "$ROOT" ] || { log "colcon setup: nothing to relocate"; return 0; }
  for f in "$ROOT"/setup.sh "$ROOT"/setup.bash "$ROOT"/setup.zsh; do
    [ -f "$f" ] || continue
    sed -i "s#${OLD_ROOT}#${ROOT}#g" "$f"
    grep -qF "$OLD_ROOT" "$f" && die "colcon setup: $OLD_ROOT left in $f"
  done
  log "colcon setup: prefix chain -> $ROOT"
}

# --- colcon install: share/<pkg>/package.* + hook/* --------------------------------
# package.* bake the build's export/root as the package's default prefix; the
# hook/* colcon writes for cargo packages (ament_prefix_path.*) PREPEND it to
# AMENT_PREFIX_PATH unconditionally.
colcon_package_relocate() {
  local files
  [ -n "$OLD_ROOT" ] && [ "$OLD_ROOT" != "$ROOT" ] || { log "colcon package: nothing to relocate"; return 0; }
  mapfile -t files < <(files_with "$OLD_ROOT" "$ROOT"/share/*/package.* "$ROOT"/share/*/hook/*)
  relocate_files "$OLD_ROOT" "$ROOT" "${files[@]}"
  [ -z "$(files_with "$OLD_ROOT" "${files[@]}")" ] || die "colcon package: $OLD_ROOT left in share/<pkg>/package.*, hook/*"
  log "colcon package: ${#files[@]} file(s) -> $ROOT"
}

# --- any installed python script: #!<build SDK python> shebangs -------------------
# Every installed python script whose shebang is the build's host python
# (#!<build SDK>/vxsdk/host/x86_64-linux/bin/python3), whoever installed it (today:
# setuptools via colcon for ament_python packages, bin/ros2, lib/<pkg>/*, ...).
# Point them at this SDK's python3.
python_shebangs_relocate() {
  local old="#!${OLD_SDK}/${HOSTBIN_REL}/python" new="#!${WIND_SDK_HOME}/${HOSTBIN_REL}/python" f n=0
  [ -n "$OLD_SDK" ] && [ "$OLD_SDK" != "$WIND_SDK_HOME" ] || { log "python shebangs: nothing to relocate"; return 0; }
  while IFS= read -r -d '' f; do
    [ "$(head -c ${#old} "$f")" = "$old" ] || continue
    sed -i "1s|^${old}|${new}|" "$f"; n=$((n + 1))
  done < <(grep -rlIZ -F -- "$old" "$ROOT")
  while IFS= read -r -d '' f; do
    [ "$(head -c ${#old} "$f")" = "$old" ] && die "python shebangs: shebang ${old}* left in $f"
  done < <(grep -rlIZ -F -- "$old" "$ROOT")
  log "python shebangs: $n shebang(s) -> ${new}*"
}

# --- ament_package: local_setup.fish + share/<pkg>/local_setup.*, environment/* ----
# ament_package's templates bake the build's export/root as AMENT_CURRENT_PREFIX
# default (prefix-level local_setup.fish, package-level local_setup.*, and the
# environment/ hooks); the prefix-level local_setup.fish also the build's python.
ament_package_relocate() {
  local files fish="$ROOT/local_setup.fish"
  if [ -f "$fish" ] && [ -n "$OLD_SDK" ] && [ "$OLD_SDK" != "$WIND_SDK_HOME" ]; then
    relocate_files "$OLD_SDK/$HOSTBIN_REL/python" "$WIND_SDK_HOME/$HOSTBIN_REL/python" "$fish"
    grep -qF "$OLD_SDK/$HOSTBIN_REL/python" "$fish" && die "ament_package: build python left in $fish"
  fi
  [ -n "$OLD_ROOT" ] && [ "$OLD_ROOT" != "$ROOT" ] || { log "ament_package: nothing to relocate"; return 0; }
  mapfile -t files < <(files_with "$OLD_ROOT" "$fish" "$ROOT"/share/*/local_setup.* "$ROOT"/share/*/environment/*)
  relocate_files "$OLD_ROOT" "$ROOT" "${files[@]}"
  [ -z "$(files_with "$OLD_ROOT" "${files[@]}")" ] || die "ament_package: $OLD_ROOT left in local_setup.* / environment/*"
  log "ament_package: ${#files[@]} file(s) -> $ROOT"
}

# --- CMake install: *.pc / *Config.cmake ---------------------------------------
# Packages that configure_file() their pkg-config / CMake package config with
# CMAKE_INSTALL_PREFIX bake the build's export/root (e.g. bullet, spdlog,
# CycloneDDS .pc; iceoryx, bullet *Config.cmake).
cmake_install_prefix_relocate() {
  local files
  [ -n "$OLD_ROOT" ] && [ "$OLD_ROOT" != "$ROOT" ] || { log "cmake install prefix: nothing to relocate"; return 0; }
  mapfile -t files < <(find "$ROOT/lib" "$ROOT/share" -type f \( -name '*.pc' -o -name '*.cmake' \) \
                         -exec grep -lIF -- "$OLD_ROOT" {} + 2>/dev/null || true)
  relocate_files "$OLD_ROOT" "$ROOT" "${files[@]}"
  [ -z "$(files_with "$OLD_ROOT" "${files[@]}")" ] || die "cmake install prefix: $OLD_ROOT left in *.pc / *.cmake"
  log "cmake install prefix: ${#files[@]} file(s) -> $ROOT"
}

# --- pkg/ros2 vxworks.mixin.template: the colcon mixins -------------------------
# Order: toolchain dir first (most specific), then export/root, then SDK root.
vxworks_mixin_relocate() {
  local m pair old new
  for m in "$MIXIN_DIR"/*.mixin; do
    [ -f "$m" ] || continue
    [ -n "$OLD_TC" ]   && sed -i "s#${OLD_TC}#${NEW_TC}#g" "$m"
    [ -n "$OLD_ROOT" ] && sed -i "s#${OLD_ROOT}#${ROOT}#g" "$m"
    [ -n "$OLD_SDK" ] && [ "$OLD_SDK" != "$WIND_SDK_HOME" ] && sed -i "s#${OLD_SDK}#${WIND_SDK_HOME}#g" "$m"
  done
  # each baked path against its own new path (equal on a re-run: already relocated);
  # OLD_SDK is not checked: it may equal the new SDK root
  for pair in "${OLD_ROOT}|$ROOT" "${OLD_TC}|$NEW_TC"; do
    old="${pair%%|*}"; new="${pair#*|}"
    [ -n "$old" ] && [ "$old" != "$new" ] && grep -qF "$old" "$VXMIXIN" && \
      die "vxworks mixin: un-relocated build path left: $old"
  done
  "$PY" -c "import json,sys; json.load(open(sys.argv[1]))" "$VXMIXIN" || die "vxworks mixin: not valid JSON"
  grep -q "$ROOT" "$VXMIXIN" || die "vxworks mixin: does not point at this toolkit's export/root ($ROOT)"
  log "vxworks mixin: relocated ($(ls "$MIXIN_DIR"/*.mixin | wc -l) mixin file(s))"
}

# --- ament_vendor: vendor_package_cmake_prefix hooks -------------------------------
# A vendor's hook adds opt/<pkg> to CMAKE_PREFIX_PATH; the layer installs vendors
# into the root, so opt/<pkg> does not exist (colcon warns). Empty those hooks.
ament_vendor_hooks_relocate() {
  local d f pkg n=0
  for d in "$ROOT"/share/*/environment; do
    [ -d "$d" ] || continue
    pkg="$(basename "$(dirname "$d")")"
    [ -d "$ROOT/opt/$pkg" ] && continue
    for f in "$d"/vendor_package_cmake_prefix.sh "$d"/vendor_package_cmake_prefix.dsv; do
      [ -s "$f" ] || continue
      : > "$f"; n=$((n + 1))
    done
  done
  log "ament_vendor hooks: emptied $n hook(s) pointing at a missing opt/<pkg>"
}

# --- ament_vendor: the vendor's staging install prefix -------------------------------
# ament_vendor installs the vendored project into a staging prefix
# <ws>/build/<pkg>/<name>_install, then copies it into export/root. Whatever the
# project baked from its prefix (.pc, xml2-config, xsltConf.sh, libtool .la) still
# names that staging dir: point it at export/root.
ament_vendor_prefix_relocate() {
  local files f re n=0
  [ -n "$OLD_TOP" ] || { log "ament_vendor prefix: no build output dir known (nothing to relocate)"; return 0; }
  re="$(printf '%s' "$OLD_TOP" | sed 's/[][\\.*^$|+?(){}]/\\&/g')/build/[^\"' :;]*/build/[^/\"' :;]*/[^/\"' :;]*_install"
  mapfile -t files < <(grep -rlIE -- "$re" "$ROOT" 2>/dev/null || true)
  for f in "${files[@]}"; do sed -i -E "s|${re}|${ROOT}|g" "$f"; n=$((n + 1)); done
  [ -z "$(grep -rlIE -- "$re" "$ROOT" 2>/dev/null)" ] || die "ament_vendor prefix: staging prefix left under $ROOT"
  log "ament_vendor prefix: $n file(s) -> $ROOT"
}

# --- pkg/ros2 rust-cargo-config.toml.template: the Rust workspace cargo config -----
# The ROS 2 part of the cargo config ([patch.crates-io] libloading + install-lib
# -L/-rpath-link), as the main build drops at $WS/src/.cargo/config.toml, rendered
# to this toolkit's paths at $TOOLKIT_DIR/.cargo/config.toml (to copy into a
# workspace .cargo/; NOT a CARGO_HOME). The generic VxWorks flags come from the
# SDK's own cargo config (CARGO_HOME from sdkenv.sh); cargo merges the two.
rust_cargo_config_relocate() {
  local tmpl="$TOOLKIT_DIR/scripts/rust-cargo-config.toml.template" out="$TOOLKIT_DIR/.cargo/config.toml"
  if [ ! -f "$tmpl" ]; then log "rust cargo config: no template (toolkit without Rust)"; return 0; fi
  if [ ! -d "$ROOT/share/rclrs/rust" ]; then
    log "rust cargo config: no Rust crate sources in export/root (share/rclrs/rust) - toolkit has no Rust support"
    return 0
  fi
  command -v envsubst >/dev/null 2>&1 || { log "rust cargo config: WARN: envsubst missing - not rendered"; return 0; }
  mkdir -p "$(dirname "$out")"
  ROOT_DIR="$ROOT" ROS2_RUST_CRATES_DIR="$WIND_CC_SYSROOT/usr/rust/vxworks-crates" \
    envsubst '${ROOT_DIR} ${ROS2_RUST_CRATES_DIR}' < "$tmpl" > "$out"
  grep -q '\${' "$out" && die "rust cargo config: unrendered variables left in $out"
  log "rust cargo config: rendered -> $out"
}

# --- all producers: any build-time path left in a text file of export/root ----
# Reports (does not fail): a path no producer function above handles yet.
export_root_check() {
  local p left
  for p in "$OLD_ROOT" "$OLD_TOP" "$OLD_SDK"; do
    [ -n "$p" ] && [ "$p" != "$ROOT" ] && [ "$p" != "$WIND_SDK_HOME" ] || continue
    [ "$p" = "$OLD_TOP" ] && [ "${ROOT#"$OLD_TOP"/}" != "$ROOT" ] && continue
    left="$(grep -rlIF -- "$p" "$ROOT" 2>/dev/null || true)"
    [ -z "$left" ] && continue
    log "export/root: WARN: $(printf '%s\n' "$left" | wc -l) file(s) still contain $p, e.g.:"
    printf '%s\n' "$left" | head -5 | sed "s|^$ROOT/|   |"
  done
  log "export/root: build-time paths checked"
}

ros2_sdk_check
colcon_local_setup_relocate
colcon_setup_relocate
colcon_package_relocate
python_shebangs_relocate
ament_package_relocate
cmake_install_prefix_relocate
vxworks_mixin_relocate
ament_vendor_hooks_relocate
ament_vendor_prefix_relocate
rust_cargo_config_relocate
export_root_check
command -v colcon >/dev/null || log "note: colcon not on PATH yet (source ros2sdkenv.sh)"
log "PASS: SDK prepared. Now:  source $TOOLKIT_DIR/scripts/ros2sdkenv.sh"
