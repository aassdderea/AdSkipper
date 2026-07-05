ARCHS = arm64 arm64e
TARGET = iphone:clang:14.0:11.0

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AdSkipper

AdSkipper_FILES = Tweak.x $(wildcard src/*.m)
AdSkipper_CFLAGS = -fobjc-arc -Isrc
AdSkipper_LDFLAGS = -lz
AdSkipper_FRAMEWORKS = UIKit Foundation CoreGraphics CFNetwork WebKit
AdSkipper_PRIVATE_FRAMEWORKS = BackBoardServices

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"

stage::
	mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support/AdSkipper
	cp rules/default_rules.json $(THEOS_STAGING_DIR)/Library/Application\ Support/AdSkipper/rules.json
	cp rules/domain_blacklist.txt $(THEOS_STAGING_DIR)/Library/Application\ Support/AdSkipper/domain_blacklist.txt
