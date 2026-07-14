#
# Copyright (C) 2015 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=lua-zlib
PKG_VERSION:=v1.2
PKG_RELEASE:=1
PKG_MAINTAINER:=Brian Maher
PKG_LICENSE:=MIT

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/brimworks/lua-zlib
PKG_MIRROR_HASH:=614a1c9328fa6c0dc85255999a24c4ace5efb3652989897f36a81b5f88aca71e
PKG_SOURCE_PROTO:=git
PKG_SOURCE_VERSION:=a305d98f473d0a253b6fd740ce60d7d5a5f1cda0
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/lua-zlib
  SUBMENU:=Lua
  SECTION:=lang
  CATEGORY:=Languages
  TITLE:=Lua zlib binding
  URL:=https://github.com/brimworks/lua-zlib
  DEPENDS:= +lua +zlib
endef

define Package/lua-zlib/description
	Simple streaming interface to zlib for Lua. 
endef

TARGET_CFLAGS += $(FPIC) -O2 -std=gnu99 -DLZLIB_COMPAT
TARGET_LDFLAGS += -lz -llua -lm -shared $(FPIC)

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) \
		-c $(PKG_BUILD_DIR)/lua_zlib.c \
		-o $(PKG_BUILD_DIR)/lua_zlib.o
	$(TARGET_CC) $(TARGET_LDFLAGS) \
		$(PKG_BUILD_DIR)/lua_zlib.o \
		-o $(PKG_BUILD_DIR)/zlib.so
endef

define Package/lua-zlib/install
	$(INSTALL_DIR) $(1)/usr/lib/lua
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/zlib.so $(1)/usr/lib/lua/
endef

$(eval $(call BuildPackage,lua-zlib))
