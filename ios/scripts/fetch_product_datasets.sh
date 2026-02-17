#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_DIR="$IOS_DIR/DataSources/External/raw"
INDEX_DIR="$IOS_DIR/DataSources/External/index"

INCLUDE_OFF_FOOD=true
FORCE=false
UHTT_LOCAL_ARCHIVE="${UHTT_LOCAL_ARCHIVE:-/Users/antonpyatnica/Downloads/UhttBarcodeReference-20230913.zip}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--include-off-food] [--skip-off-food] [--force] [--uhtt-local-archive /path/to/UhttBarcodeReference-20230913.zip]

Options:
  --include-off-food         Download en.openfoodfacts.org.products.csv.gz (default behavior)
  --skip-off-food            Skip en.openfoodfacts.org.products.csv.gz
  --force                    Re-download files even if they already exist
  --uhtt-local-archive PATH  Local UHTT zip archive to copy (preferred over network)
  -h, --help                 Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-off-food)
      INCLUDE_OFF_FOOD=true
      shift
      ;;
    --skip-off-food)
      INCLUDE_OFF_FOOD=false
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --uhtt-local-archive)
      UHTT_LOCAL_ARCHIVE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$RAW_DIR" "$INDEX_DIR"

MANIFEST_TSV="$(mktemp)"
trap 'rm -f "$MANIFEST_TSV"' EXIT

record_manifest() {
  local file_name="$1"
  local source_url="$2"
  local license_note="$3"
  local license_risk="$4"
  local full_path="$RAW_DIR/$file_name"

  local downloaded_at
  downloaded_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local size_bytes
  size_bytes="$(stat -f%z "$full_path")"
  local sha256
  sha256="$(shasum -a 256 "$full_path" | awk '{print $1}')"
  local ingestion_source
  ingestion_source="$(resolve_ingestion_source "$file_name")"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$file_name" "$source_url" "$downloaded_at" "$size_bytes" "$sha256" "$license_note" "$license_risk" "$ingestion_source" \
    >> "$MANIFEST_TSV"
}

resolve_ingestion_source() {
  local file_name="$1"
  case "$file_name" in
    uhtt-reference-*.zip)
      echo "uhtt_reference"
      ;;
    catalog-barcodes-*.zip)
      echo "catalog_app"
      ;;
    openfoodfacts-products.csv.gz)
      echo "open_food_facts"
      ;;
    openbeautyfacts-products.csv.gz)
      echo "open_beauty_facts"
      ;;
    openpetfoodfacts-products.csv.gz)
      echo "open_pet_food_facts"
      ;;
    openproductsfacts-products.csv.gz)
      echo "open_products_facts"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

copy_local_file() {
  local src_path="$1"
  local dst_name="$2"
  local source_url="$3"
  local license_note="$4"
  local license_risk="$5"
  local dst_path="$RAW_DIR/$dst_name"

  if [[ -f "$dst_path" && "$FORCE" != true ]]; then
    echo "[skip] $dst_name already exists"
  else
    echo "[copy] $src_path -> $dst_name"
    cp "$src_path" "$dst_path"
  fi

  record_manifest "$dst_name" "$source_url" "$license_note" "$license_risk"
}

download_file() {
  local dst_name="$1"
  local url="$2"
  local license_note="$3"
  local license_risk="$4"
  shift 4

  local dst_path="$RAW_DIR/$dst_name"
  if [[ -f "$dst_path" && "$FORCE" != true ]]; then
    echo "[skip] $dst_name already exists"
    record_manifest "$dst_name" "$url" "$license_note" "$license_risk"
    return
  fi

  local tmp_path
  tmp_path="$(mktemp "$RAW_DIR/${dst_name}.tmp.XXXX")"

  echo "[download] $url"
  curl \
    --fail \
    --location \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 20 \
    --user-agent 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36' \
    "$@" \
    "$url" \
    --output "$tmp_path"

  mv "$tmp_path" "$dst_path"
  record_manifest "$dst_name" "$url" "$license_note" "$license_risk"
}

UHTT_RELEASE_URL="https://github.com/papyrussolution/UhttBarcodeReference/releases/tag/20230913"
UHTT_ZIP_URL="https://github.com/papyrussolution/UhttBarcodeReference/archive/refs/tags/20230913.zip"
CATALOG_DOWNLOAD_PAGE="https://catalog.app/public-opportunities/download-barcodes"

if [[ -f "$UHTT_LOCAL_ARCHIVE" ]]; then
  copy_local_file \
    "$UHTT_LOCAL_ARCHIVE" \
    "uhtt-reference-20230913.zip" \
    "$UHTT_RELEASE_URL" \
    "UHTT repository does not declare a standard OSI license in metadata." \
    "high"
else
  download_file \
    "uhtt-reference-20230913.zip" \
    "$UHTT_ZIP_URL" \
    "UHTT repository does not declare a standard OSI license in metadata." \
    "high"
fi

download_file \
  "catalog-barcodes-csv.zip" \
  "https://catalog.app/public-opportunities/download-public-file?fileName=barcodes_csv.zip" \
  "catalog.app provides free downloadable barcode exports; explicit OSS license is not stated." \
  "high" \
  --header "Referer: $CATALOG_DOWNLOAD_PAGE" \
  --header 'Accept: */*'

download_file \
  "catalog-barcodes-db.zip" \
  "https://catalog.app/public-opportunities/download-public-file?fileName=barcodes_db.zip" \
  "catalog.app provides free downloadable barcode exports; explicit OSS license is not stated." \
  "high" \
  --header "Referer: $CATALOG_DOWNLOAD_PAGE" \
  --header 'Accept: */*'

download_file \
  "openbeautyfacts-products.csv.gz" \
  "https://static.openbeautyfacts.org/data/en.openbeautyfacts.org.products.csv.gz" \
  "OpenBeautyFacts dump (ODbL/DbCL)." \
  "low"

download_file \
  "openpetfoodfacts-products.csv.gz" \
  "https://static.openpetfoodfacts.org/data/en.openpetfoodfacts.org.products.csv.gz" \
  "OpenPetFoodFacts dump (ODbL/DbCL)." \
  "low"

download_file \
  "openproductsfacts-products.csv.gz" \
  "https://static.openproductsfacts.org/data/en.openproductsfacts.org.products.csv.gz" \
  "OpenProductsFacts dump (ODbL/DbCL)." \
  "low"

if [[ "$INCLUDE_OFF_FOOD" == true ]]; then
  download_file \
    "openfoodfacts-products.csv.gz" \
    "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz" \
    "OpenFoodFacts dump (ODbL/DbCL)." \
    "low"
else
  echo "[skip] openfoodfacts-products.csv.gz (--skip-off-food)"
fi

MANIFEST_PATH="$RAW_DIR/manifest.json"
python3 - "$MANIFEST_TSV" "$MANIFEST_PATH" <<'PY'
import csv
import json
import sys
from datetime import datetime, timezone

tsv_path, output_path = sys.argv[1], sys.argv[2]
entries = []
with open(tsv_path, "r", encoding="utf-8") as handle:
    reader = csv.reader(handle, delimiter="\t")
    for row in reader:
        if len(row) != 8:
            continue
        file_name, source_url, downloaded_at, size_bytes, sha256, license_note, license_risk, ingestion_source = row
        entries.append(
            {
                "file": file_name,
                "url": source_url,
                "downloaded_at": downloaded_at,
                "size": int(size_bytes),
                "sha256": sha256,
                "license_note": license_note,
                "license_risk": license_risk,
                "ingestion_source": ingestion_source,
            }
        )

manifest = {
    "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "datasets": entries,
}

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

echo "[ok] Manifest written: $MANIFEST_PATH"
echo "[ok] Files ready in: $RAW_DIR"
