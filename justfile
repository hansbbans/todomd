set shell := ["/bin/zsh", "-lc"]

project := "TodoMD.xcodeproj"
scheme := "TodoMDApp"
sim_destination := "generic/platform=iOS Simulator"
device_destination := "generic/platform=iOS"
archive_path := "build/TodoMDApp.xcarchive"
export_path := "build/export"
ipa_path := "{{export_path}}/TodoMDApp.ipa"

generate:
  xcodegen generate

build:
  swift build

test:
  swift test

lint:
  if command -v swiftlint >/dev/null 2>&1; then swiftlint --strict --config .swiftlint.yml; else echo "swiftlint not installed; skipping"; fi

format:
  if command -v swiftformat >/dev/null 2>&1; then swiftformat . --config .swiftformat; else echo "swiftformat not installed; skipping"; fi

format-check:
  if command -v swiftformat >/dev/null 2>&1; then swiftformat . --lint --config .swiftformat; else echo "swiftformat not installed; skipping"; fi

build-sim:
  xcodebuild -project {{project}} -scheme {{scheme}} -configuration Debug -destination '{{sim_destination}}' build

build-device:
  xcodebuild -project {{project}} -scheme {{scheme}} -configuration Release -destination '{{device_destination}}' CODE_SIGNING_ALLOWED=NO build

archive:
  mkdir -p build
  xcodebuild -project {{project}} -scheme {{scheme}} -configuration Release -destination '{{device_destination}}' -archivePath {{archive_path}} CODE_SIGNING_ALLOWED=NO archive

archive-release:
  mkdir -p build
  xcodebuild -project {{project}} -scheme {{scheme}} -configuration Release -destination '{{device_destination}}' -archivePath {{archive_path}} archive

export-ipa:
  if [ ! -d {{archive_path}} ]; then echo "Missing archive at {{archive_path}} (run 'just archive-release' first)"; exit 1; fi
  export_options="${EXPORT_OPTIONS_PLIST:-build/ExportOptions.plist}"
  if [ ! -f "$export_options" ]; then echo "Missing export options plist at $export_options (set EXPORT_OPTIONS_PLIST or create build/ExportOptions.plist)"; exit 1; fi
  mkdir -p {{export_path}}
  xcodebuild -exportArchive -archivePath {{archive_path}} -exportPath {{export_path}} -exportOptionsPlist "$export_options"

upload:
  if [ ! -f {{ipa_path}} ]; then echo "Missing IPA at {{ipa_path}}"; exit 1; fi
  if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then echo "Set ASC_KEY_ID and ASC_ISSUER_ID for TestFlight upload"; exit 1; fi
  xcrun altool --upload-app --type ios --file {{ipa_path}} --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

release:
  xcrun agvtool next-version -all
  just generate
  just archive-release
  just export-ipa
  just upload

benchmark:
  swift run TodoMDBenchmarks

benchmark-report:
  mkdir -p docs/benchmarks
  bin_path="$$(swift build --product TodoMDBenchmarks --show-bin-path)"
  "$$bin_path/TodoMDBenchmarks" --counts 500,1000,5000 --changed 10 --json > docs/benchmarks/latest.json
  echo "Wrote docs/benchmarks/latest.json"

ci:
  just generate
  just lint
  just format-check
  just test
  just build-sim
  just build-device
