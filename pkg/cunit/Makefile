# Makefile - for ASIO
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
# 26jun18,rcw updated
# 12mar18,akh  created
#
include $(WIND_USR_MK)/defs.common.mk
include $(WIND_USR_MK)/defs.packages.mk
include $(WIND_USR_MK)/defs.crossbuild.mk

PACKAGES += CUnit

PKG_NAME = CUnit
PKG_VER = 2.1.2
PKG_TYPE = git

PKG_URL = https://github.com/pi2p/CUnit.git

PKG_LICENSE = Boost

PKG_BUILD_DIR = src
PKG_SRC_DIR = src

PKG_LIBS := -lunix -lnet

PKG_CONFIGURE_VAR = cd ../$(PKG_SRC_DIR) && libtoolize --force && aclocal && autoheader && automake --force-missing --add-missing && autoconf && cd ../$(PKG_BUILD_DIR) &&
PKG_CONFIGURE_OPT = $(TGT_CONFIGURE_OPT) CPPFLAGS=-I$(BUILD_DIR)/cunit/$(PKG_SRC_DIR)/CUnit/Headers LIBS="$(PKG_LIBS)"
PKG_MAKE_INSTALL_OPT = $(TGT_MAKE_INSTALL_OPT)

include $(WIND_USR_MK)/rules.packages.mk

