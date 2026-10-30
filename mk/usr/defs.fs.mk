# defs.fs.mk - the `fs` phase: lay out export/deploy from the built packages.
#
# `fs` runs each DEFAULT_BUILD package's `<pkg>.deploy` sub-make, which stages
# that package's runtime files into $(DEPLOY_DIR) and touches a per-package
# $(STAMP_DIR)/<pkg>.deploy stamp. Those stamps are what `image` (defs.image.mk)
# keys off to decide whether ros2.img needs repacking.
#
# Included from the top-level Makefile. Depends on: DEFAULT_BUILD, DEPLOY_DIR,
# STAMP_DIR (from defs.common/packages.mk) and the `all` target.

.PHONY: fs

fs: all
	for p in $(DEFAULT_BUILD); do $(MAKE) -C pkg/$$p $$p.deploy || exit 1; done;
