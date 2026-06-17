ARCHS = arm64
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = DebugOverlay

DebugOverlay_FILES = Tweak.xm
DebugOverlay_FRAMEWORKS = UIKit Foundation
DebugOverlay_LIBRARIES = sqlite3
DebugOverlay_CFLAGS = -fobjc-arc
DebugOverlay_LDFLAGS = -Wl,-install_name,@executable_path/Frameworks/DebugOverlay.dylib

include $(THEOS_MAKE_PATH)/library.mk