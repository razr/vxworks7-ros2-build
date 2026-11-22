# ROS 2 VxWorks Toolkit

A toolkit for building **ROS 2 applications for VxWorks** and running them on
QEMU.

It ships:

- the **ROS 2 SDK** (`export/root/`) prebuilt for VxWorks
- the **SDK overlay** (`sdk-overlay/`) — the changes installed into a vanilla VxWorks SDK
  by its own `sdk-overlay/install-sdk-overlay.sh`
- a bootable **target image** (`ros2.img`)
- helper **scripts** (`scripts/`) — prepare, env, build, run on QEMU
- the on-target **tests** (`tests/`) and VS Code tasks (`.vscode/`)

> This toolkit does **not** include the VxWorks SDK (Wind River licensed).
> Download your vanilla VxWorks SDK from <https://labs.windriver.com/vxworks-sdk/> and point the toolkit at it.
> The toolkit is not publicly redistributable together with the SDK.

## Unpack the toolkit

The toolkit ships as a single tarball. Extract it anywhere you like (it is
relocatable); everything below runs from the unpacked directory:

```bash
tar -xf toolkit-<release>-<distro>-<arch>.tar.zst   # or .tar.gz
cd toolkit-<release>-<distro>-<arch>/               # the toolkit root
```

All paths in this document are relative to that toolkit root.

## What's in the toolkit

| Path | What |
|------|------|
| `export/root/` | the ROS 2 SDK (build your app against this) |
| `ros2.img` | bootable VxWorks target image (contains the ROS 2 runtime) |
| `scripts/ros2sdkenv.sh` | source to set up the build env (toolchain + ROS 2 SDK + `vxworks` mixin) |
| `scripts/ros2sdk-prepare.sh` | one-time: relocate the ROS 2 SDK to this location + sanity-check |
| `scripts/selftest-build.sh` | build a C++/Rust/Python hello node and stage it on a USB dir to verify the toolkit (`--lang`) |
| `scripts/run-qemu.sh` | boot `ros2.img`; `--usb <dir>` attaches your binary as `/bd0a` |
| `scripts/extract-deploy.sh` / `make-image.sh` | extract / rebuild `ros2.img` |
| `scripts/generate-manifest.py` | (re)generate `manifest.json` |
| `tests/` | the on-target tests (Expect, on QEMU): `main_script.exp`, `lib/`, suites `ros2` (the image), `toolkit` (the self-test nodes), `unixextra` |
| `.vscode/tasks.json` | VS Code tasks: colcon build, run on QEMU |
| `manifest.json` | what was built and how it is tested: distro, VxWorks release, arch, layer pin, package/patch/ignore lists, QEMU |
| `AGENTS.md` | instructions for AI coding assistants (Codex, Copilot, Cursor, Claude Code, Kiro, …) |

## Quick start

```bash
# install your vanilla VxWorks SDK, then:
export WRSDK=/path/to/wrsdk-vxworks7-<bsp>
./scripts/ros2sdk-prepare.sh "$WRSDK"      # once
source ./scripts/ros2sdkenv.sh
ros2 pkg create --build-type ament_cmake my_app
colcon build --mixin vxworks
```

`colcon build --mixin vxworks` cross-compiles against the ROS 2 SDK and produces
a **VxWorks RTP** linked against the SDK's libraries (e.g. `librclcpp.so`).

## C++, Rust, Python nodes

```bash
ros2 pkg create --build-type ament_cmake  my_cpp     # C++  (rclcpp)
ros2 pkg create --build-type ament_cargo  my_rust    # Rust (rclrs) — add <depend>rclrs</depend>
ros2 pkg create --build-type ament_python my_py      # Python (rclpy, runs on target)
colcon build --mixin vxworks --packages-select my_cpp
```

Python packages need one extra step after `colcon build`, before you stage
`install/` to the target. It is the same step the image build runs on the ROS 2
runtime in `ros2.img`:

```bash
optimize-python-startup install
```

It compiles unchecked-hash `.pyc` (the target loads them as-is and never
recompiles on its slow FAT file system) and rewrites the setuptools launchers in
`install/bin` and `install/lib/<pkg>/` to `importlib.metadata`. The original
launchers import `pkg_resources`, which scans every installed package's metadata
at startup (minutes on QEMU) and fails with `DistributionNotFound` for a package
run from `/bd0a`. `optimize-python-startup` is an SDK host tool (on `PATH` after
sourcing `ros2sdkenv.sh`) and runs with the SDK's `python3`, which matches the
target's Python version.

Rust needs the toolkit's Rust support (shipped only if built with `ROS2_RUST`):
the ROS 2 crate sources in `export/root/share/*/rust` + the cargo config
`ros2sdk-prepare.sh` renders. The generic VxWorks cargo settings come from the
SDK (`CARGO_HOME`, set when you source the SDK env).

## Verify the toolkit (self-test)

```bash
./scripts/selftest-build.sh                 # all langs (default); or --lang cpp|rust|python
```

Builds a hello node per language with this toolkit, stages them on a USB dir
(`ros2.img` stays untouched) and prints the on-target command, which boots QEMU
with the USB dir as `/bd0a` and runs the `tests/toolkit` suite
(`test01-cpp-hello`, `test02-rust-hello`, `test03-python-hello`):

```bash
VX_USB=<workdir>/usb expect ./tests/main_script.exp ./ros2.img toolkit
```

The tests need `expect`, `telnet` and `tap0`; `./tests/main_script.exp ./ros2.img`
runs the `ros2` suite against the image itself. Keeps the work dir by default;
`--clean` removes it.

## Run your app on VxWorks/QEMU

Deliver your freshly built binary to the target as a **USB disk** — no image
repack needed:

```bash
# tap0 up (once, needs root):
#   sudo ip tuntap add dev tap0 mode tap
#   sudo ip addr add 192.168.200.254/24 dev tap0
#   sudo ip link set tap0 up
./scripts/run-qemu.sh --usb install/my_app/lib/my_app
```

On the target shell the USB disk is `/bd0a`:

```
-> cmd
[vxWorks *]# /bd0a/my_app
[INFO] [...] [my_app]: Hello, world!
```

Quit QEMU with `Ctrl-A x`.

## Customize the target image

```bash
./scripts/extract-deploy.sh ./deploy      # pull the rootfs out of ros2.img
# edit ./deploy (add binaries, change vxscript, ...)
./scripts/make-image.sh ./deploy ./ros2.img
```

## Provenance / reproducibility

`manifest.json` describes the build this toolkit comes from. Its keys mirror the
build's Makefile variables:

| Key | What |
|-----|------|
| `ros_distro`, `vxworks_release`, `vxworks_sdk`, `arch` | the ROS 2 distro and the SDK it is built against |
| `build` | the `vxworks7-ros2-build` commit (`commit`, `describe`) |
| `layer` | the `vxworks7-layer-for-ros2` layer: `PKG_LAYER_URL`, `PKG_LAYER_COMMIT_ID` (branch), `commit` |
| `ROS2_PATCH_DIRS` | the packages patched from the layer |
| `ROS2_VENDORS`, `ROS2_BASE`, `ROS2_EXAMPLES`, `ROS2_RUST` | what is built: the vendors first, then the rest |
| `ROS_IGNORE_DIRS`, `ROS_IGNORE_TESTING_DIRS`, `ROS_IGNORE_PYTHON_DIRS` | what is not built |
| `ROS2_MIXINS`, `ROS2_RUST_TARGET` | how it is built (the mixins are in `export/root/.colcon/mixin/default/`) |
| `qemu` | the QEMU the image is tested with: `QEMU_REPO`, `QEMU_RELEASE` (`host` = the host's distro QEMU), `QEMU_BIN` |

## License

Toolkit scripts and docs: Apache-2.0. The ROS 2 SDK (`export/root/`) is built
from open-source ROS 2 + the Wind River ROS 2 layer. The **Wind River VxWorks SDK
is not included** and is subject to Wind River's license — download it from
<https://labs.windriver.com/vxworks-sdk/>.
