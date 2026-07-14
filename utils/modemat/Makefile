include $(TOPDIR)/rules.mk

PKG_NAME:=modemat
PKG_VERSION:=0
PKG_RELEASE:=1
PKG_SOURCE_PROTO:=git

PKG_MAINTAINER:=ZixLink

include $(INCLUDE_DIR)/package.mk

define Package/modemat
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=RTU325R modemat
	DEPENDS:= 
endef

define Package/modemat/description
	RTU325R board info
endef

#define Build/Compile
#endef

define Package/modemat/install
	$(INSTALL_DIR) $(1)/sbin/
	# install application
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/modemat          $(1)/sbin/
endef

$(eval $(call BuildPackage,modemat))

