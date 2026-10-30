<!-- toolkit/RELEASE_NOTES.in.md
     Curated notes appended to the auto-generated per-kit RELEASE_NOTES.md by
     make-toolkit.sh. Identity/contents are auto-generated; keep this TLDR. -->

## Use

1. Install the Wind River VxWorks SDK (not shipped).
2. `./scripts/ros2sdk-prepare.sh <sdk>` — apply the overlay (once).
3. `source ./scripts/ros2sdkenv.sh`
4. `ros2 pkg create ...` + `colcon build --mixin vxworks`
5. `./scripts/run-qemu.sh --usb <bindir>`

See `README.md` for details.

## Features

- C++17
- Python 3.9
- Rust 1.85
- `colcon build --mixin vxworks` cross-build → VxWorks RTP
- run on QEMU (binary via USB `/bd0a`, no image repack)
- VS Code dev container + build/run tasks
- extensible — build more ROS 2 packages on top of `export/root`

## Known limitations

- `export/root` not fully relocatable (build-time path in some cmake/ament/`.pc`).
- Host `ros2` CLI uses a tiny rclpy shim (target rclpy can't load on host).
- `run-qemu.sh` needs `tap0` @ `192.168.200.254` (root, set up once).
- VS Code: edit + build + run; in-editor RTP debug not wired.
