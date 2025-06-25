# Makefile fragment for defs.packages.mk
#
# Copyright (c) 2019 Wind River Systems, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# modification history
# --------------------
# 19may16,brk HLD review changes
# 21mar14,brk created
#

ifeq ($(__packages_defs),)
__packages_defs = TRUE

VPATH             = $(STAMP_DIR)

STAMP_DIR         = $(BUILD_DIR)/.stamp
MAKE_STAMP        = $(TOUCH) $(STAMP_DIR)/$@
CLEAN_STAMP       = $(RM) -f $(STAMP_DIR)/$*.build $(STAMP_DIR)/$*.install
DISTCLEAN_STAMP   = $(RM) -f $(STAMP_DIR)/$*.*

OTHER_UNPACK ?= $(ECHO) "ERROR: Unknown source type, can't extract" ; exit 1
OTHER_CHECKOUT ?= $(ECHO) "ERROR: Unknown protocol type, can't checkout" ; exit 1

#PKG_PATCHES := $(sort $(wildcard *.patch))

PKG_CMAKE_DIR := $(PKG_SRC_DIR)

ifneq ($(PKG_TMPL_URL),)
PKG_TMPL_COMMIT_ID ?= $(shell git ls-remote --symref $(PKG_TMPL_URL) HEAD | awk '/^ref:/ {sub("refs/heads/", "", $$2); print $$2}')
endif
PKG_TMPL_NAME := $(notdir $(basename $(PKG_TMPL_URL)))
PKG_TMPL_DATE := $(shell date +%d%b%y | tr '[:upper:]' '[:lower:]')
PKG_TMPL_YEAR := $(shell date +%Y)
PKG_TMPL_USER := $(shell whoami | cut -c1-3)


define echo_action
	@$(ECHO) "--------------------------------------------------------------------------------"; \
	$(ECHO) "$1"; \
	$(ECHO) "--------------------------------------------------------------------------------";
endef

define pkg_template
# Makefile - for $(PKG_TMPL_NAME)
#
# Copyright (c) $(PKG_TMPL_YEAR) Wind River Systems, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# modification history
# --------------------
# $(PKG_TMPL_DATE),$(PKG_TMPL_USER)  Created
#

include $$(WIND_USR_MK)/defs.common.mk
include $$(WIND_USR_MK)/defs.packages.mk
include $$(WIND_USR_MK)/defs.crossbuild.mk

PKG_NAME = $(PKG_TMPL_NAME)
PKG_COMMIT_ID = $(PKG_TMPL_COMMIT_ID)
PKG_URL = $(PKG_TMPL_URL)
PKG_TYPE = git
PKG_BUILD_DIR = build
PKG_SRC_DIR = src

CMAKE_OPT = -DBUILD_SHARED_LIBS=ON -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

PACKAGES += $(PKG_TMPL_NAME)

PKG_MAKE_INSTALL_OPT=install

include $$(WIND_USR_MK)/defs.cmake.mk
include $$(WIND_USR_MK)/rules.packages.mk
endef

define pkg_create
        @if [ -z "$(PKG_TMPL_URL)" ]; then \
                echo "Error: PKG_TMPL_URL=<package url> is required"; \
                exit 1; \
        fi
	@if [ ! -z "$(PKG_TMPL_NAME)" ]; then \
                if [ -f "pkg/$(PKG_TMPL_NAME)/Makefile" ]; then \
                        echo "Package created at pkg/$(PKG_TMPL_NAME) with PKG_COMMIT_ID=$(PKG_TMPL_COMMIT_ID)"; \
                        echo "DEFAULT_BUILD=$(PKG_TMPL_NAME) make"; \
                else \
                        $(shell mkdir -p pkg/$(PKG_TMPL_NAME)) \
		        $(file >pkg/$(PKG_TMPL_NAME)/Makefile,$(pkg_template)) \
                        echo ""; \
                fi; \
	fi
endef

endif
