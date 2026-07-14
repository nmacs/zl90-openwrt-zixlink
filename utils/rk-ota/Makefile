include $(TOPDIR)/rules.mk

PKG_NAME:=rk-ota
PKG_VERSION:=0
PKG_RELEASE:=1
PKG_SOURCE_PROTO:=git

PKG_MAINTAINER:=ZixLink

include $(INCLUDE_DIR)/package.mk

define Package/rk-ota
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=Router Update utility
	DEPENDS:= +libopenssl +libstdcpp +zlib
endef

TARGET_LDFLAGS += -L$(STAGING_DIR)/usr/lib

define Package/rk-ota/description
	Router update utility
endef

#define Build/Compile
#endef

define Package/rk-ota/install
	$(INSTALL_DIR) $(1)/sbin/

	# install application
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/rk-ota          $(1)/sbin/
endef

$(eval $(call BuildPackage,rk-ota))

