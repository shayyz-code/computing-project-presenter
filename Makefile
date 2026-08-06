PACKAGE_DIR := Packages/PresenterKit
APP_DIR     := App
PROJECT     := $(APP_DIR)/Presenter.xcodeproj
SCHEME      := Presenter
DERIVED     := .build/xcode
APP_BUNDLE  := $(DERIVED)/Build/Products/Debug/Presenter.app
SWIFT_PATHS := $(PACKAGE_DIR)/Sources $(PACKAGE_DIR)/Tests $(APP_DIR)/Presenter

.DEFAULT_GOAL := help

.PHONY: help bootstrap build test lint format run clean

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
