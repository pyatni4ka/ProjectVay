#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_PATH="${1:-${ROOT_DIR}/ios/DataSources/External/index/recipe_catalog.json}"

mkdir -p "$(dirname "${OUTPUT_PATH}")"
"${ROOT_DIR}/ios/scripts/fetch_recipe_seed.py" --output "${OUTPUT_PATH}"
