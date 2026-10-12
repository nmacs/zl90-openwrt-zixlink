include $(TOPDIR)/rules.mk

PKG_NAME:=modem
PKG_VERSION:=0
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/modem


include $(INCLUDE_DIR)/package.mk

define Package/modem
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Manage cellular connection
  DEPENDS:=
endef

define Package/modem/description
	Manage cellular connection and keep it online.
endef

define Package/modem/conffiles
/etc/config/modem
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/modem/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/lib/functions
	$(INSTALL_DIR) $(1)/usr/share/lua/modem/
	
	$(CP) ./files/modem.config $(1)/etc/config/modem
	
	$(INSTALL_BIN) ./src/*.lua $(1)/usr/share/lua/modem/
	$(INSTALL_BIN) ./files/modem.sh $(1)/lib/functions/modem.sh
	$(INSTALL_BIN) ./files/modem_detect.sh $(1)/lib/functions/modem_detect.sh
	
	$(INSTALL_BIN) ./files/modem.init $(1)/etc/init.d/modem
	$(INSTALL_BIN) ./files/modem_ubus.init $(1)/etc/init.d/modem_ubus
	
	$(INSTALL_DIR) $(1)/lib/netifd/proto
	$(INSTALL_BIN) ./files/lib/netifd/proto/mm_dualsim.sh $(1)/lib/netifd/proto
endef

$(eval $(call BuildPackage,modem))
