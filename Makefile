PACKAGE_DIR := Packages/PresenterKit
APP_DIR     := App
PROJECT     := $(APP_DIR)/Sidecar.xcodeproj
SCHEME      := Sidecar
DERIVED     := .build/xcode
APP_BUNDLE  := $(DERIVED)/Build/Products/Debug/Sidecar.app
SWIFT_PATHS := $(PACKAGE_DIR)/Sources $(PACKAGE_DIR)/Tests $(APP_DIR)/Sidecar
BUNDLE_ID   := com.codewithshayy.sidecar

# xcodebuild refuses to combine ad-hoc signing with the hardened runtime, so
# build-signed re-signs the finished bundle instead of signing during the build.
# That also makes the entitlements swappable, which is how the gate gets tested
# with a negative control -- see docs/adr/0005-distribution.md.
#
# First codesigning identity on this machine, or empty. Override to pick another.
# Kept free of parentheses: an unescaped ")" would close make's $(shell ...) early.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning \
                   | grep -m1 '"' | awk '{print $$2}')
# "-" is ad-hoc: no certificate needed, so this target works for contributors
# without one. TCC then keys grants to the cdhash rather than a stable identity.
SIGN_AS       := $(if $(SIGN_IDENTITY),$(SIGN_IDENTITY),-)
ENTITLEMENTS  ?= $(APP_DIR)/Sidecar/Sidecar.entitlements

.DEFAULT_GOAL := help

.PHONY: help bootstrap build build-signed test lint format run clean

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Resolve package dependencies
	swift package --package-path $(PACKAGE_DIR) resolve

build: ## Build the app (Debug, unsigned)
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination 'platform=macOS' \
		-derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO

build-signed: build ## Re-sign the built app with hardened runtime and entitlements
	@# Nested code first, and with the same identity. The hardened runtime turns
	@# on library validation, so a Debug build whose Sidecar.debug.dylib is still
	@# linker-signed under no team aborts at launch with "Library not loaded".
	codesign --force --options runtime --sign $(SIGN_AS) --timestamp=none \
		$(APP_BUNDLE)/Contents/MacOS/*.dylib
	codesign --force --options runtime \
		--sign $(SIGN_AS) \
		--entitlements $(ENTITLEMENTS) \
		--identifier $(BUNDLE_ID) \
		--timestamp=none \
		$(APP_BUNDLE)
	codesign --verify --deep --strict $(APP_BUNDLE)
	@codesign -dvvv $(APP_BUNDLE) 2>&1 | grep -E '^Identifier|^Authority|flags='
	@codesign -d --entitlements - --xml $(APP_BUNDLE) 2>/dev/null \
		| plutil -p - | grep '=>' || echo '  (no entitlements embedded)'

test: ## Run the package test suite
	swift test --package-path $(PACKAGE_DIR)

lint: ## Check formatting without changing files
	swift format lint --recursive --strict $(SWIFT_PATHS)

format: ## Reformat sources in place
	swift format --in-place --recursive $(SWIFT_PATHS)

run: build ## Build and launch the app
	open $(APP_BUNDLE)

clean: ## Remove build products
	rm -rf $(DERIVED) $(PACKAGE_DIR)/.build
