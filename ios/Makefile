SCHEME      = Biinge
PROJECT     = Biinge.xcodeproj
DERIVED     = build/dd
DESTINATION_ios   = platform=iOS Simulator,name=iPhone 17 Pro
DESTINATION_macos = platform=macOS
DESTINATION_tvos  = platform=tvOS Simulator,name=Apple TV 4K (3rd generation)
SWIFTLINT_ARGS ?=

# build and test call each platform through recursive $(MAKE), because an
# escaped-colon name silently no-ops as a prerequisite
.PHONY: build
build:
	@$(MAKE) build:ios
	@$(MAKE) build:macos
	@$(MAKE) build:tvos

.PHONY: build\:ios
build\:ios:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION_ios)' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build

.PHONY: build\:macos
build\:macos:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION_macos)' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build

.PHONY: build\:tvos
build\:tvos:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION_tvos)' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build

.PHONY: test
test:
	@$(MAKE) test:ios
	@$(MAKE) test:macos
	@$(MAKE) test:tvos

.PHONY: test\:ios
test\:ios:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION_ios)' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO test -only-testing:BiingeTests

.PHONY: test\:macos
test\:macos:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION_macos)' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO test -only-testing:BiingeTests

.PHONY: test\:tvos
test\:tvos:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION_tvos)' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO test -only-testing:BiingeTests

.PHONY: lint
lint:
	@../.github/scripts/doc-comments.sh ios
	@Scripts/check-platform-depth.sh
	@if which swiftlint >/dev/null 2>&1; then \
		swiftlint lint --strict $(SWIFTLINT_ARGS); \
	else \
		echo "swiftlint not installed; skipping"; \
	fi

.PHONY: clean
clean:
	rm -rf build
