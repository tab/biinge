SCHEME      = Biinge
PROJECT     = Biinge.xcodeproj
DERIVED     = build/dd
DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro

.PHONY: build
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build

.PHONY: test
test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(DESTINATION)' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO test -only-testing:BiingeTests

.PHONY: lint
lint:
	@which swiftlint >/dev/null 2>&1 && swiftlint || echo "swiftlint not installed; skipping"

.PHONY: clean
clean:
	rm -rf build
