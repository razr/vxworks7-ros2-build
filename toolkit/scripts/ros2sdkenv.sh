#!/usr/bin/env bash
# ros2sdkenv.sh - source this to set up the environment for building ROS 2
# packages against this kit's SDK.
#
#   source ros2sdkenv.sh
#   ros2 pkg create --build-type ament_cmake my_app ...
#   colcon build --mixin vxworks
#
# Must be SOURCED, not executed. Idempotent. Derives everything from the kit
# location, so the kit works wherever it is unpacked.

# --- locate the kit + the VxWorks SDK ---------------------------------------
# Kit dir: honor $TOOLKIT or $KIT (dev container), else derive from this script.
_src="${BASH_SOURCE[0]:-$0}"
KIT_DIR="${TOOLKIT:-${KIT:-$(cd "$(dirname "$_src")/.." && pwd)}}"
export ROS2SDK_KIT="$KIT_DIR"

_err() { echo "ros2sdkenv: $*" >&2; }

[ -d "$KIT_DIR/export/root" ] || { _err "no root/ in $KIT_DIR (the ROS 2 SDK)"; return 1 2>/dev/null || exit 1; }

# The vanilla Wind River SDK is provided by the USER. Resolve it from, in order:
#   $WRSDK (dev container mount / explicit), $WIND_SDK_HOME (already sourced),
#   or a bundled $KIT_DIR/wrsdk (standalone kits that choose to include it).
SDK_DIR="${WRSDK:-${WIND_SDK_HOME:-$KIT_DIR/wrsdk}}"
[ -f "$SDK_DIR/sdkenv.sh" ] || { _err "no VxWorks SDK at '$SDK_DIR' (set WRSDK to your SDK, or mount it)"; return 1 2>/dev/null || exit 1; }

# --- 1) the VxWorks SDK cross toolchain + host tools ------------------------
# shellcheck disable=SC1091
_had_u=$(set +o | grep -q "set -o nounset" && echo 1 || true); set +u
source "$SDK_DIR/sdkenv.sh"
[ -n "${_had_u:-}" ] && set -u || true
export WIND_CC_SYSROOT="${WIND_CC_SYSROOT:-$WIND_SDK_CC_SYSROOT}"

# --- 2) keep TARGET libs out of the HOST build LD_LIBRARY_PATH --------------
export COLCON_EXTENSION_BLOCKLIST=colcon_core.environment.library_path

# --- 3) overlay the ROS 2 SDK (CMake configs on CMAKE_PREFIX_PATH, host tools)
export COLCON_PYTHON_EXECUTABLE="$WIND_SDK_HOME/vxsdk/host/x86_64-linux/bin/python3"
# Sourcing setup.bash runs the ament/colcon library_path.dsv hooks, which PREPEND
# export/root/lib (TARGET VxWorks .so's) to the HOST LD_LIBRARY_PATH. That poisons
# every system binary run in this shell (e.g. `ip`, which then fails to load
# libc.so.1). We don't want target libs on the host loader path at all -- the
# cross-build resolves target libs via CMAKE_FIND_ROOT_PATH/sysroot, not
# LD_LIBRARY_PATH. So snapshot LD_LIBRARY_PATH before sourcing and restore it after.
_saved_ld="${LD_LIBRARY_PATH:-}"
set +u
# shellcheck disable=SC1091
source "$KIT_DIR/export/root/setup.bash"
set -u 2>/dev/null || true
# restore the host loader path (drop whatever setup.bash prepended)
if [ -n "$_saved_ld" ]; then export LD_LIBRARY_PATH="$_saved_ld"; else unset LD_LIBRARY_PATH; fi
unset _saved_ld

# --- 3b) host rclpy stub so the host `ros2` CLI works -----------------------
# export/root's rclpy is a TARGET (VxWorks) build whose C extension can't load
# on the host; the `ros2` CLI imports it eagerly. Prepend a tiny host stub
# (provides just rclpy.executors.ExternalShutdownException) so host-only verbs
# like `ros2 pkg create` work. Verified NOT to affect `colcon build --mixin
# vxworks` (a C++ node build does not import host rclpy).
export PYTHONPATH="$KIT_DIR/host-shims:${PYTHONPATH:-}"

# --- 4) register the vxworks colcon mixin so `--mixin vxworks` works ---------
export COLCON_HOME="$KIT_DIR/.colcon"
mkdir -p "$COLCON_HOME/mixin/default"
cat > "$COLCON_HOME/mixin/default/vxworks.mixin" <<EOF
{
  "build": {
    "vxworks": {
      "cmake-force-configure": true,
      "cmake-args": [
        "-DCMAKE_FIND_ROOT_PATH=$KIT_DIR/export/root",
        "-DCMAKE_BUILD_TYPE:STRING=Release",
        "-DCMAKE_CXX_STANDARD=17",
        "-DCMAKE_TOOLCHAIN_FILE=$WIND_CC_SYSROOT/mk/toolchain.cmake",
        "-DCMAKE_MAKE_PROGRAM:FILEPATH=$WIND_SDK_HOME/vxsdk/host/x86_64-linux/bin/make",
        "-DPython3_EXECUTABLE=$WIND_SDK_HOME/vxsdk/host/x86_64-linux/bin/python3",
        "-DPYTHON_SOABI=cpython-39-vxworks",
        "-DCMAKE_EXE_LINKER_FLAGS=-rpath-link $KIT_DIR/export/root/lib",
        "--no-warn-unused-cli"
      ]
    }
  }
}
EOF

echo "ros2sdkenv: ready."
echo "  kit:    $KIT_DIR"
echo "  SDK:    $WIND_SDK_HOME"
echo "  ROS 2:  $KIT_DIR/export/root  (CMAKE_FIND_ROOT_PATH)"
echo "  mixin:  vxworks  (colcon mixin list)"
