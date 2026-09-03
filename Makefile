APP_NAME := MouseMover
APP_PATH := /Applications/MouseMover.app

.PHONY: install uninstall icon clean

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

icon:
	swift scripts/make-icon.swift

uninstall:
	rm -rf "$(APP_PATH)"

clean:
	swift package clean
