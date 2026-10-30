# ROS 2 VxWorks SDK

A development kit for building **ROS 2 applications for VxWorks** and running
them on QEMU.

It ships the **ROS 2 SDK** (`export/root/`) — ROS 2 (rclcpp/rcl/rmw + message packages,
ament_cmake, the host `ros2`/`colcon` tooling) prebuilt for VxWorks — plus a
containerized development environment, a bootable target image, and helper
scripts.

> **You provide the Wind River VxWorks SDK.** This kit does **not** include the
> VxWorks SDK (Wind River licensed). Download/install your vanilla
> `wrsdk-vxworks7-qemu` yourself and point the kit at it (mounted into the dev
> container). The kit is not publicly redistributable together with the SDK.

## What's in the kit

| Path | What |
|------|------|
| `export/root/` | the ROS 2 SDK (build your app against this) |
| `ros2.img` | bootable VxWorks target image (contains the ROS 2 runtime) |
| `docker/vxbuild/`, `docker/vxros2build/` | the project's Dockerfiles (the dev environment) |
| `.devcontainer/` | VS Code Dev Container config |
| `scripts/ros2sdkenv.sh` | source to set up the build env (toolchain + ROS 2 SDK + `vxworks` mixin) |
| `scripts/ros2sdk-prepare.sh` | one-time: relocate the ROS 2 SDK to this location + sanity-check |
| `scripts/run-qemu.sh` | boot `ros2.img`; `--usb <dir>` attaches your binary as `/bd0a` |
| `scripts/extract-deploy.sh` / `make-image.sh` | extract / rebuild `ros2.img` |
| `scripts/generate-manifest.py` | (re)generate `manifest.json` |
| `manifest.json` | what was built: distro, VxWorks release, arch, layer pin, package/patch/ignore lists |
| `repos/` | the exact `.repos` source manifests used (provenance) |

## Quick start — VS Code Dev Container (recommended)

1. Install Docker + the VS Code **Dev Containers** extension.
2. Unpack your vanilla VxWorks SDK and tell the kit where it is — create
   `.devcontainer/.env`:
   ```
   WRSDK=/absolute/path/to/wrsdk-vxworks7-qemu
   ```
3. Open the kit folder in VS Code → **"Dev Containers: Reopen in Container"**.
   It builds the `vxbuild` → `vxros2build` images, mounts your SDK at `/wrsdk`
   and the kit at `/kit`, and sets up the build env on attach.
4. In the container terminal:
   ```bash
   ros2 pkg create --build-type ament_cmake my_app
   # ... add an rclcpp node, deps, C++17 ...
   colcon build --mixin vxworks
   ```

## Quick start — Docker CLI

```bash
# build the dev environment (two stages, as shipped)
docker build -t vxbuild:26.04        docker/vxbuild
docker build -t vxros2build:lyrical  --build-arg BASE_IMAGE=vxbuild:26.04 \
                                     --build-arg ROS_DISTRO=lyrical docker/vxros2build

# run it: mount YOUR vanilla SDK + this kit + your workspace
docker run -it --rm \
  -v /path/to/wrsdk-vxworks7-qemu:/wrsdk \
  -v "$PWD":/kit \
  -v "$PWD/work":/work \
  -e WRSDK=/wrsdk -e KIT=/kit \
  vxros2build:lyrical bash

# inside the container:
source /kit/scripts/ros2sdk-prepare.sh /wrsdk   # once
source /kit/scripts/ros2sdkenv.sh
ros2 pkg create --build-type ament_cmake my_app
colcon build --mixin vxworks
```

## Quick start — on the host (no Docker)

```bash
# install your vanilla VxWorks SDK, then:
export WRSDK=/path/to/wrsdk-vxworks7-qemu
./scripts/ros2sdk-prepare.sh "$WRSDK"      # once
source ./scripts/ros2sdkenv.sh
ros2 pkg create --build-type ament_cmake my_app
colcon build --mixin vxworks
```

`colcon build --mixin vxworks` cross-compiles against the ROS 2 SDK and produces
a **VxWorks RTP** linked against the SDK's libraries (e.g. `librclcpp.so`).

## Run your app on VxWorks/QEMU

Deliver your freshly built binary to the target as a **USB disk** — no image
repack needed:

```bash
# tap0 up: sudo ip tuntap add dev tap0 mode tap
#          sudo ip addr add 192.168.200.254/24 dev tap0; sudo ip link set tap0 up
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

`manifest.json` records the ROS distro, VxWorks release, arch, the
`vxworks7-layer-for-ros2` layer (url + branch + commit), and the exact package /
patch / ignore lists (keys mirror the build's Makefile variables:
`ROS2_PATCH_DIRS`, `ROS_IGNORE_*`, `ROS2_BASE`, `ROS2_EXAMPLES`, `ROS2_RUST`,
`ROS2_MIXINS`). `repos/` holds the `.repos` source manifests (with pinned
commits) that were imported.

## License

Kit scripts and docs: Apache-2.0. The ROS 2 SDK (`root/`) is built from
open-source ROS 2 + the Wind River ROS 2 layer. The **Wind River VxWorks SDK is
not included** and is subject to Wind River's license — obtain it from Wind River.
