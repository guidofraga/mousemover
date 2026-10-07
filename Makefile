APP_NAME := MouseMover
APP_PATH := /Applications/MouseMover.app
VERSION := 1.0.0
DIST_DIR := dist
BUNDLE := $(DIST_DIR)/$(APP_NAME).app
ARM64_BIN := .build/arm64-apple-macosx/release/$(APP_NAME)
X86_64_BIN := .build/x86_64-apple-macosx/release/$(APP_NAME)

.PHONY: install uninstall icon clean dist

install:
	swift build -c release
	pkill -x "$(APP_NAME)" 2>/dev/null || true
	rm -rf "$(APP_PATH)"
	mkdir -p "$(APP_PATH)/Contents/MacOS" "$(APP_PATH)/Contents/Resources"
	cp ".build/release/$(APP_NAME)" "$(APP_PATH)/Contents/MacOS/$(APP_NAME)"
	cp "Resources/Info.plist" "$(APP_PATH)/Contents/Info.plist"
	cp "Resources/AppIcon.icns" "$(APP_PATH)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - --identifier com.mousemover.app --requirements '=designated => identifier "com.mousemover.app"' "$(APP_PATH)"
	touch "$(APP_PATH)"
	open "$(APP_PATH)"

dist:
	swift build -c release --triple arm64-apple-macosx12.0
	swift build -c release --triple x86_64-apple-macosx12.0
	rm -rf "$(DIST_DIR)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	lipo -create "$(ARM64_BIN)" "$(X86_64_BIN)" -output "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp "Resources/Info.plist" "$(BUNDLE)/Contents/Info.plist"
	cp "Resources/AppIcon.icns" "$(BUNDLE)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - --identifier com.mousemover.app --requirements '=designated => identifier "com.mousemover.app"' "$(BUNDLE)"
	ditto -c -k --keepParent "$(BUNDLE)" "$(DIST_DIR)/$(APP_NAME)-$(VERSION).zip"
	mkdir -p "$(DIST_DIR)/dmg"
	cp -R "$(BUNDLE)" "$(DIST_DIR)/dmg/"
	ln -s /Applications "$(DIST_DIR)/dmg/Applications"
	hdiutil create -volname "Mouse Mover" -srcfolder "$(DIST_DIR)/dmg" -ov -format UDZO "$(DIST_DIR)/$(APP_NAME)-$(VERSION).dmg"
	rm -rf "$(DIST_DIR)/dmg"

icon:
	swift scripts/make-icon.swift

uninstall:
	rm -rf "$(APP_PATH)"

clean:
	swift package clean
