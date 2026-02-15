#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/InventoryAI.xcodeproj}"
SCHEME="${SCHEME:-InventoryAI}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=iOS}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/build/InventoryAI.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-$ROOT_DIR/build/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$ROOT_DIR/scripts/exportOptions.ad-hoc.plist}"
GENERATE_PROJECT="${GENERATE_PROJECT:-1}"

if [[ "$GENERATE_PROJECT" == "1" ]]; then
  echo "[build_ipa] Generating Xcode project with xcodegen..."
  xcodegen generate --spec "$ROOT_DIR/project.yml"
fi

if [[ ! -f "$PROJECT_PATH/project.pbxproj" ]]; then
  echo "[build_ipa] Xcode project not found at: $PROJECT_PATH"
  exit 1
fi

if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  echo "[build_ipa] Export options plist not found: $EXPORT_OPTIONS_PLIST"
  echo "[build_ipa] Use template: $ROOT_DIR/scripts/exportOptions.ad-hoc.plist.template"
  exit 1
fi

echo "[build_ipa] Cleaning previous artifacts..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_DIR"

echo "[build_ipa] Archiving app..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "[build_ipa] Exporting IPA..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

echo "[build_ipa] Done."
echo "[build_ipa] Archive: $ARCHIVE_PATH"
echo "[build_ipa] Export dir: $EXPORT_DIR"
echo "[build_ipa] IPA files:"
find "$EXPORT_DIR" -maxdepth 1 -type f -name "*.ipa" -print
