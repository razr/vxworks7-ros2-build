# defs.fs.mk - the `fs` phase: lay out export/deploy from the built packages.
#
# `fs` runs each DEFAULT_BUILD package's `<pkg>.deploy` sub-make, which stages
# that package's runtime files into $(DEPLOY_DIR) and touches a per-package
# $(STAMP_DIR)/<pkg>.deploy stamp. Those stamps are what `image` (defs.image.mk)
# keys off to decide whether ros2.img needs repacking.
#
# Included from the top-level Makefile. Depends on: DEFAULT_BUILD, DEPLOY_DIR,
# STAMP_DIR (from defs.common/packages.mk) and the `all` target. The `fs` phony
# target lives in the top-level Makefile and calls the fs_deploy macro below.

# fs_deploy - stage each DEFAULT_BUILD package's runtime files into $(DEPLOY_DIR)
# (each sub-make touches its $(STAMP_DIR)/<pkg>.deploy stamp). No args.
define fs_deploy
	for p in $(DEFAULT_BUILD); do $(MAKE) -C pkg/$$p $$p.deploy || exit 1; done;
endef
