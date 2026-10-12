include $(TOPDIR)/rules.mk

PKG_NAME:=adio-controller
PKG_VERSION:=0
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/adio-controller

include $(INCLUDE_DIR)/package.mk

define Package/adio-controller
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Analog/Digital IO Controller
  DEPENDS:=
endef

define Package/adio-controller/description
	Analog/Digital IO Controller
endef

define Package/adio-controller/conffiles
/etc/config/adio-controller
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/adio-controller/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/share/lua/adio-controller/
	$(INSTALL_DIR) $(1)/usr/share/lua/adio-controller/copas/
	$(INSTALL_DIR) $(1)/usr/share/lua/adio-controller/xavante/
	
	$(CP) ./files/adio-controller.config $(1)/etc/config/adio-controller
	
	$(INSTALL_DATA) ./src/*.lua          $(1)/usr/share/lua/adio-controller/
	$(INSTALL_DATA) ./src/copas/*.lua    $(1)/usr/share/lua/adio-controller/copas/
	$(INSTALL_DATA) ./src/xavante/*.lua  $(1)/usr/share/lua/adio-controller/xavante/
	
	chmod +x $(1)/usr/share/lua/adio-controller/main.lua
	
	$(INSTALL_BIN) ./files/adio-controller.init $(1)/etc/init.d/adio-controller
endef

$(eval $(call BuildPackage,adio-controller))
