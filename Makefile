# Watches — build/install scaffolding
#
# Build/install scaffolding patterns informed by:
#   davenicoll/swiss-railway-clock-screensaver (MIT)
#   https://github.com/davenicoll/swiss-railway-clock-screensaver
# Re-implemented for the Watches project.

.PHONY: project build install-dev test clean snapshot

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

# Render any registered dial offscreen to a PNG. Story 1.5 AC17.
# DIAL/OUT/WIDTH/HEIGHT/DATE override defaults; e.g.
#   make snapshot                                            # default: royale → snapshots/royale.png
#   make snapshot DIAL=asymmetricMoonphase OUT=snapshots/moon.png
#   make snapshot DIAL=royale WIDTH=1600 HEIGHT=1600 DATE=2026-05-13T12:34:56Z
snapshot: project
	xcodebuild -project $(PRODUCT).xcodeproj \
	           -scheme DialSnapshot \
	           -configuration Release \
	           -derivedDataPath $(BUILD_DIR) \
	           CODE_SIGN_IDENTITY="-" \
	           build
	@mkdir -p snapshots
	$(BUILD_DIR)/Build/Products/Release/DialSnapshot \
	  --dial   $(if $(DIAL),$(DIAL),royale) \
	  --output $(if $(OUT),$(OUT),snapshots/$(if $(DIAL),$(DIAL),royale).png) \
	  --width  $(if $(WIDTH),$(WIDTH),1200) \
	  --height $(if $(HEIGHT),$(HEIGHT),1200) \
	  $(if $(DATE),--date $(DATE),)

# Remove generated build artifacts and the generated Xcode project.
clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(PRODUCT).xcodeproj
