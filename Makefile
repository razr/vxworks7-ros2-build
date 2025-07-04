export TOP_BUILDDIR?=$(CURDIR)/output
export WIND_USR_MK=$(CURDIR)/mk/usr
export PACKAGE_DIR=$(CURDIR)/pkg
export BUILDSPECS_DIR=$(CURDIR)/buildspecs

include $(WIND_USR_MK)/defs.common.mk
include $(WIND_USR_MK)/defs.packages.mk
include $(WIND_USR_MK)/defs.vxworks.mk

DEFAULT_BUILD ?= sdk unixextra asio tinyxml2 eigen libxml2 libxslt ros2 pyyaml netifaces

ifeq ($(ROS_DISTRO),)
ifeq ($(filter ros2,$(DEFAULT_BUILD)),ros2)
ifeq (,$(filter create_package,$(MAKECMDGOALS)))
  $(error Please export ROS_DISTRO)
endif
endif
endif

.PHONY: clean_buildstamps create_package

all: $(DOWNLOADS_DIR) $(STAMP_DIR) $(EXPORT_DIR)
	for p in $(DEFAULT_BUILD); do $(MAKE) -C pkg/$$p $$p.install || exit 1; done;

$(EXPORT_DIR):
	@mkdir -p $(ROOT_DIR)
	@mkdir -p $(DEPLOY_DIR)/bin
	@mkdir -p $(DEPLOY_DIR)/lib

$(DOWNLOADS_DIR):
	@mkdir -p $(DOWNLOADS_DIR)

$(STAMP_DIR):
	@mkdir -p $(STAMP_DIR)

clean_buildstamps:
	for p in $(DEFAULT_BUILD); do rm -rf $(STAMP_DIR)/$$p.*; done;

distclean: clean
	@rm -rf $(DOWNLOADS_DIR)
	@rm -rf $(BUILD_DIR)
	@rm -rf $(EXPORT_DIR)

clean: clean_buildstamps
	for p in $(DEFAULT_BUILD); do rm -rf $(BUILD_DIR)/$$p; done;

fs: all
	for p in $(DEFAULT_BUILD); do $(MAKE) -C pkg/$$p $$p.deploy || exit 1; done;

image: fs
	dd if=/dev/zero of=$(TOP_BUILDDIR)/ros2.img count=2048 bs=1M
	mkfs.vfat -F 32 $(TOP_BUILDDIR)/ros2.img
	mkdir -p $(TOP_BUILDDIR)/mount
	fusefat -o rw+ $(TOP_BUILDDIR)/ros2.img $(TOP_BUILDDIR)/mount
	find $(TOP_BUILDDIR)/export/deploy -type d -name '__pycache__' -exec rm -rf {} +
	cp --no-preserve=ownership -r -L $(TOP_BUILDDIR)/export/deploy/* $(TOP_BUILDDIR)/mount/. 2>/dev/null
	fusermount -u $(TOP_BUILDDIR)/mount

create_package:
	$(call pkg_create)

info:
	@$(ECHO) "DEFAULT_BUILD:      $(DEFAULT_BUILD)"
	@$(ECHO) "WIND RELEASE:       $(WIND_RELEASE_ID)"
	@$(ECHO) "ROS DISTRO:         $(ROS_DISTRO)"
	@$(ECHO) "TARGET BSP:         $(TGT_BSP)"
	@$(ECHO) "TARGET ARCH:        $(TGT_ARCH)"
	@$(ECHO) "TARGET PYTHON:      Python3.$(TGT_PYTHON_MINOR)"
	@$(ECHO) "HOST PYTHON:        `which python3`"
	@$(ECHO) "CMAKE:              `which cmake`"
	@$(ECHO) "CURDIR:             $(CURDIR)"
	@$(ECHO) "DOWNLOADS_DIR:      $(DOWNLOADS_DIR)"
	@$(ECHO) "PACKAGE_DIR:        $(PACKAGE_DIR)"
	@$(ECHO) "BUILD_DIR:          $(BUILD_DIR)"
	@$(ECHO) "EXPORT_DIR:         $(EXPORT_DIR)"
	@$(ECHO) "ROOT_DIR:           $(ROOT_DIR)"
	@$(ECHO) "DEPLOY_DIR:         $(DEPLOY_DIR)"
	@$(ECHO) "WIND_CC_SYSROOT:    $(WIND_CC_SYSROOT)"
	@$(ECHO) "WIND_SDK_HOST_TOOLS:$(WIND_SDK_HOST_TOOLS)"
	@$(ECHO) "3PP_DEPLOY_DIR:     $(3PP_DEPLOY_DIR)"
	@$(ECHO) "3PP_DEVELOP_DIR:    $(3PP_DEVELOP_DIR)"

