.PHONY: generate build run clean

# Generate the Xcode project from project.yml
generate:
	xcodegen generate

# Build the app in Release mode
build: generate
	xcodebuild \
		-project ClaudeGod.xcodeproj \
		-scheme ClaudeGod \
		-configuration Release \
		-derivedDataPath build \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

# Open in Xcode
open: generate
	open ClaudeGod.xcodeproj

# Build and run
run: build
	open "build/Build/Products/Release/Claude God.app"

# Create a DMG
dmg: build
	mkdir -p dmg-contents
	cp -R "build/Build/Products/Release/Claude God.app" dmg-contents/
	ln -sf /Applications dmg-contents/Applications
	hdiutil create \
		-volname "Claude God" \
		-srcfolder dmg-contents \
		-ov \
		-format UDZO \
		ClaudeGod.dmg
	rm -rf dmg-contents

# Clean build artifacts
clean:
	rm -rf build ClaudeGod.xcodeproj ClaudeGod.dmg dmg-contents
