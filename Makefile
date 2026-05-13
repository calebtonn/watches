# Watches — build/install scaffolding
#
# Build/install scaffolding patterns informed by:
#   davenicoll/swiss-railway-clock-screensaver (MIT)
#   https://github.com/davenicoll/swiss-railway-clock-screensaver
# Re-implemented for the Watches project.

.PHONY: project build install-dev test clean

PRODUCT      := Watches
BUNDLE       := $(PRODUCT).saver
SCHEME       := $(PRODUCT)
BUILD_DIR    := build
INSTALL_DIR  := $(HOME)/Library/Screen\ Savers

# Regenerate Xcode project from project.yml (xcodegen).
# Watches.xcodeproj is gitignored — this is the canonical regeneration step.
project:
	xcodegen generate

# Build the .saver bundle (Release, ad-hoc signed).
# Requires Xcode.app — Command Line Tools alone are insufficient.
build: project
	xcodebuild -project $(PRODUCT).xcodeproj \
	           -scheme $(SCHEME) \
	           -configuration Release \
	           -derivedDataPath $(BUILD_DIR) \
	           CODE_SIGN_IDENTITY="-" \
	           build

# Install the freshly-built bundle into ~/Library/Screen Savers/
# for live testing in System Settings → Screen Saver.
install-dev: build
	rm -rf $(INSTALL_DIR)/$(BUNDLE)
	cp -R $(BUILD_DIR)/Build/Products/Release/$(BUNDLE) $(INSTALL_DIR)/
	@echo ""
	@echo "Installed $(BUNDLE) to $(INSTALL_DIR)"
	@echo "Open System Settings -> Screen Saver to select."

# Run the XCTest suite (WatchesTests). Suite covers pure render math only
# per ADR-001 / D12 (test boundary). Target: ~20 tests, <1s suite duration.
test: project
	xcodebuild -project $(PRODUCT).xcodeproj \
	           -scheme $(SCHEME) \
	           -destination 'platform=macOS' \
	           test

# Remove generated build artifacts and the generated Xcode project.
clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(PRODUCT).xcodeproj
