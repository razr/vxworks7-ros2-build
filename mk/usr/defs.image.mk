# defs.image.mk - the `image` phase: pack the bootable FAT32 ros2.img.
#
# Stamp-aware: the real target is the $(TOP_BUILDDIR)/ros2.img FILE, with the
# per-package *.deploy stamps as prerequisites. `image` is a phony alias that
# first runs `fs` (to refresh those stamps) and then rebuilds ros2.img ONLY when
# a *.deploy stamp is newer than the image -- same "up to date" discipline as the
# package steps, so repeated `make image` / `make toolkit` no longer re-dd the
# image when nothing changed.
#
# Included from the top-level Makefile. Depends on: TOP_BUILDDIR, DEPLOY_DIR,
# STAMP_DIR, DEFAULT_BUILD, the python_prepare_deploy macro (defs.python.mk),
# and the `fs` target (defs.fs.mk).

.PHONY: image

IMAGE_DEPLOY_STAMPS = $(addprefix $(STAMP_DIR)/,$(addsuffix .deploy,$(DEFAULT_BUILD)))
ROS2_IMG            = $(TOP_BUILDDIR)/ros2.img

image: fs $(ROS2_IMG)

$(ROS2_IMG): $(IMAGE_DEPLOY_STAMPS)
	dd if=/dev/zero of=$(ROS2_IMG) count=2048 bs=1M
	mkfs.vfat -F 32 $(ROS2_IMG)
	mkdir -p $(TOP_BUILDDIR)/mount
	fusefat -o rw+ $(ROS2_IMG) $(TOP_BUILDDIR)/mount
	# Strip any pre-existing __pycache__ FIRST: build-time caches may be host-arch
	# (e.g. cpython-312) and are useless/garbage on the target. python_prepare_deploy
	# (next line) then regenerates clean target cpython-3$(TGT_PYTHON_MINOR) .pyc.
	find $(TOP_BUILDDIR)/export/deploy -type d -name __pycache__ -prune -exec rm -rf {} +
	# Prepare the deployed python for the target: pre-compile .pyc (unchecked-hash,
	# so the target never recompiles on its slow FS) and rewrite the setuptools
	# EASY-INSTALL console-script shims to importlib.metadata (the pkg_resources
	# shims scan all *.dist-info at startup -- minutes on the target). Both steps
	# are defined in mk/usr/defs.python.mk.
	$(call python_prepare_deploy,$(TOP_BUILDDIR)/export/deploy)
	# Prune build/dev-only artifacts the TARGET never needs at runtime, to cut the
	# fusefat copy's per-file cost (file count dominates the FUSE write time).
	# KEEP *.dist-info / *.egg-info (ros2 run entry-point discovery reads them) and
	# the CPython stdlib test dir ($(TOP_BUILDDIR)/export/deploy/lib/python3.9/test).
	find $(TOP_BUILDDIR)/export/deploy \( -path '*/cmake/*' -o -name '*.cmake' \) -type f -delete
	# remove the now-empty cmake/ dir trees left behind (bottom-up, nested empties)
	find $(TOP_BUILDDIR)/export/deploy -depth -type d -path '*/cmake*' -empty -delete
	find $(TOP_BUILDDIR)/export/deploy/lib -type d \( -name test -o -name tests \) \
	    -not -path '*/python3.*/test' -not -path '*/python3.*/test/*' -exec rm -rf {} +
	find $(TOP_BUILDDIR)/export/deploy/lib -type d -name include -not -path '*/python3.*/*' -exec rm -rf {} +
	find $(TOP_BUILDDIR)/export/deploy \( -name '*.a' -o -name '*.pc' \) -type f -delete
	cp --no-preserve=ownership -r -L $(TOP_BUILDDIR)/export/deploy/* $(TOP_BUILDDIR)/mount/. 2>/dev/null
	fusermount -u $(TOP_BUILDDIR)/mount
