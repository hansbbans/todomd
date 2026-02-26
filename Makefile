.PHONY: generate build test lint format format-check build-sim build-device archive upload release benchmark ci

PROJECT := TodoMD.xcodeproj
SCHEME := TodoMDApp
SIM_DEST := generic/platform=iOS Simulator
DEVICE_DEST := generic/platform=iOS
ARCHIVE_PATH := build/TodoMDApp.xcarchive
EXPORT_PATH := build/export
IPA_PATH := $(EXPORT_PATH)/TodoMDApp.ipa

generate:
	xcodegen generate

build:
	swift build

test:
	swift test

lint:
	@if command -v swiftlint >/dev/null 2>&1; then swiftlint --strict --config .swiftlint.yml; else echo "swiftlint not installed; skipping"; fi

format:
	@if command -v swiftformat >/dev/null 2>&1; then swiftformat . --config .swiftformat; else echo "swiftformat not installed; skipping"; fi

format-check:
	@if command -v swiftformat >/dev/null 2>&1; then swiftformat . --lint --config .swiftformat; else echo "swiftformat not installed; skipping"; fi

build-sim:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(SIM_DEST)' build

build-device:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DEVICE_DEST)' CODE_SIGNING_ALLOWED=NO build

archive:
	mkdir -p build
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DEVICE_DEST)' -archivePath $(ARCHIVE_PATH) CODE_SIGNING_ALLOWED=NO archive

archive-release:
	mkdir -p build
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination '$(DEVICE_DEST)' -archivePath $(ARCHIVE_PATH) archive

export-ipa:
	@if [ ! -d "$(ARCHIVE_PATH)" ]; then echo "Missing archive at $(ARCHIVE_PATH) (run 'make archive-release' first)"; exit 1; fi
	@export_options="$${EXPORT_OPTIONS_PLIST:-build/ExportOptions.plist}"; \
	if [ ! -f "$$export_options" ]; then echo "Missing export options plist at $$export_options (set EXPORT_OPTIONS_PLIST or create build/ExportOptions.plist)"; exit 1; fi; \
	mkdir -p $(EXPORT_PATH); \
	xcodebuild -exportArchive -archivePath $(ARCHIVE_PATH) -exportPath $(EXPORT_PATH) -exportOptionsPlist "$$export_options"

upload:
	@if [ ! -f "$(IPA_PATH)" ]; then echo "Missing IPA at $(IPA_PATH)"; exit 1; fi
	@if [ -z "$${ASC_KEY_ID:-}" ] || [ -z "$${ASC_ISSUER_ID:-}" ]; then echo "Set ASC_KEY_ID and ASC_ISSUER_ID for TestFlight upload"; exit 1; fi
	xcrun altool --upload-app --type ios --file $(IPA_PATH) --apiKey "$$ASC_KEY_ID" --apiIssuer "$$ASC_ISSUER_ID"

release:
	xcrun agvtool next-version -all
	$(MAKE) generate
	$(MAKE) archive-release
	$(MAKE) export-ipa
	$(MAKE) upload

benchmark:
	swift run TodoMDBenchmarks

benchmark-report:
	mkdir -p docs/benchmarks
	@bin_path="$$(swift build --product TodoMDBenchmarks --show-bin-path)"; \
	"$$bin_path/TodoMDBenchmarks" --counts 500,1000,5000 --changed 10 --json > docs/benchmarks/latest.json; \
	echo "Wrote docs/benchmarks/latest.json"

ci: generate lint format-check test build-sim build-device
