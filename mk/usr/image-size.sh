#!/usr/bin/env bash
# image-size.sh <deploy dir> - the size in MB of the FAT32 image for <deploy dir>:
# its content + 10% (FAT32 tables, cluster slack, room for files written on the
# target), at least 64 MB (FAT32 needs 65525 clusters). Used by `make image` (defs.image.mk::build_fs) and the CI image
# step (vxworks-ros2-build.yaml), so both make the same image.
set -euo pipefail
DEPLOY="${1:?usage: image-size.sh <deploy dir>}"
[ -d "$DEPLOY" ] || { echo "image-size: no $DEPLOY" >&2; exit 1; }
kb="$(du -sk "$DEPLOY" | cut -f1)"
mb=$(( kb * 11 / 10 / 1024 ))
echo $(( mb < 64 ? 64 : mb ))
