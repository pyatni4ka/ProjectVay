#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import gzip
import io
import re
import sqlite3
import sys
import zipfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, Iterator, Optional

LETTER_RE = re.compile(r"[A-Za-zА-Яа-яЁё]")
SPACE_RE = re.compile(r"\s+")
GENERIC_TOKENS = ("штрих-код", "штрихкод", "barcode", "поиск")

try:
    csv.field_size_limit(sys.maxsize)
except OverflowError:
    csv.field_size_limit(1_000_000_000)


@dataclass
class Candidate:
    barcode: str
    name: str
    brand: Optional[str]
    category: Optional[str]
    source: str
    source_rank: int
    quality_score: int


class CandidateAggregator:
    def __init__(self) -> None:
        self.best_by_barcode: Dict[str, Candidate] = {}
        self.total_seen = 0
        self.total_valid = 0

    def offer(self, candidate: Candidate) -> None:
        self.total_seen += 1
        if not is_valid_name(candidate.name, candidate.barcode):
            return

        self.total_valid += 1
        prev = self.best_by_barcode.get(candidate.barcode)
        if prev is None:
            self.best_by_barcode[candidate.barcode] = candidate
            return

        prev_key = (prev.source_rank, prev.quality_score, len(prev.name))
        next_key = (candidate.source_rank, candidate.quality_score, len(candidate.name))
        if next_key > prev_key:
            self.best_by_barcode[candidate.barcode] = candidate


def normalize_text(value: str) -> str:
    return SPACE_RE.sub(" ", value.strip())


def normalize_barcode(raw: str) -> str:
    return "".join(ch for ch in raw if ch.isdigit())


def normalize_optional(value: Optional[str]) -> Optional[str]:
    if value is None:
        return None
    text = normalize_text(value)
    return text if text else None


def is_valid_name(raw_name: str, barcode: str) -> bool:
    name = normalize_text(raw_name)
    if not name:
        return False

    lower = name.lower()
    if lower == "поиск":
        return False
    if any(token in lower for token in GENERIC_TOKENS):
        return False
    if name == barcode:
        return False

    if LETTER_RE.search(name) is None:
        return False

    digits_only = "".join(ch for ch in name if ch.isdigit())
    if digits_only == barcode and len(name) <= len(barcode) + 4:
        return False

    return True


def compute_quality_score(raw_name: str, barcode: str) -> int:
    name = normalize_text(raw_name)
    letters = sum(1 for ch in name if ch.isalpha())
    score = letters * 2 + min(len(name), 140)

    lower = name.lower()
    if lower.isupper():
        score -= 2
    if barcode in name:
        score -= 20
    if len(name) < 6:
        score -= 10
    if any(token in lower for token in GENERIC_TOKENS):
        score -= 1000

    return score


def parse_uhtt_zip(path: Path, source_rank: int) -> Iterator[Candidate]:
    with zipfile.ZipFile(path, "r") as archive:
        entries = sorted(
            name
            for name in archive.namelist()
            if name.lower().endswith(".csv") and "uhtt_barcode_ref_" in Path(name).name.lower()
        )
        for entry in entries:
            with archive.open(entry, "r") as binary_file:
                with io.TextIOWrapper(binary_file, encoding="utf-8", errors="ignore", newline="") as text_file:
                    reader = csv.reader(text_file, delimiter="\t")
                    for row in reader:
                        if len(row) < 7:
                            continue
                        if row[0].strip().lower() == "id":
                            continue

                        barcode = normalize_barcode(row[1])
                        name = normalize_text(row[2])
                        category = normalize_optional(row[4])
                        brand = normalize_optional(row[6])

                        if not barcode or not name:
                            continue

                        yield Candidate(
                            barcode=barcode,
                            name=name,
                            brand=brand,
                            category=category,
                            source="uhtt",
                            source_rank=source_rank,
                            quality_score=compute_quality_score(name, barcode),
                        )


def parse_catalog_csv_zip(path: Path, source_rank: int) -> Iterator[Candidate]:
    with zipfile.ZipFile(path, "r") as archive:
        target_name = None
        for name in archive.namelist():
            if Path(name).name.lower() == "barcodes.csv":
                target_name = name
                break
        if target_name is None:
            raise RuntimeError(f"barcodes.csv not found in {path}")

        with archive.open(target_name, "r") as binary_file:
            with io.TextIOWrapper(binary_file, encoding="utf-8", errors="ignore", newline="") as text_file:
                reader = csv.DictReader(text_file, delimiter=";")
                for row in reader:
                    barcode = normalize_barcode(row.get("Barcode", ""))
                    name = normalize_text(row.get("Name", ""))
                    brand = normalize_optional(row.get("Vendor"))
                    category = normalize_optional(row.get("Category"))

                    if not barcode or not name:
                        continue

                    yield Candidate(
                        barcode=barcode,
                        name=name,
                        brand=brand,
                        category=category,
                        source="catalog",
                        source_rank=source_rank,
                        quality_score=compute_quality_score(name, barcode),
                    )


def parse_openfacts_gzip(path: Path, source: str, source_rank: int) -> Iterator[Candidate]:
    with gzip.open(path, "rt", encoding="utf-8", errors="ignore", newline="") as text_file:
        reader = csv.DictReader(text_file, delimiter="\t")
        for row in reader:
            barcode = normalize_barcode(row.get("code", ""))
            if not barcode:
                continue

            name = (
                normalize_optional(row.get("product_name"))
                or normalize_optional(row.get("generic_name"))
                or normalize_optional(row.get("abbreviated_product_name"))
            )
            if not name:
                continue

            brand_raw = normalize_optional(row.get("brands"))
            brand = None
            if brand_raw:
                brand = normalize_optional(brand_raw.split(",")[0])

            category_raw = normalize_optional(row.get("categories"))
            category = None
            if category_raw:
                category = normalize_optional(category_raw.split(",")[0])

            yield Candidate(
                barcode=barcode,
                name=name,
                brand=brand,
                category=category,
                source=source,
                source_rank=source_rank,
                quality_score=compute_quality_score(name, barcode),
            )


def build_index(raw_dir: Path, output_db: Path, include_off_food: bool) -> None:
    output_db.parent.mkdir(parents=True, exist_ok=True)

    aggregator = CandidateAggregator()

    uhtt_archives = sorted(raw_dir.glob("*uhtt*.zip"))
    if uhtt_archives:
        for archive in uhtt_archives:
            print(f"[uhtt] parsing {archive}", file=sys.stderr)
            for candidate in parse_uhtt_zip(archive, source_rank=300):
                aggregator.offer(candidate)
    else:
        print("[warn] UHTT archive not found (*.zip)", file=sys.stderr)

    catalog_csv_zip = raw_dir / "catalog-barcodes-csv.zip"
    if catalog_csv_zip.exists():
        print(f"[catalog] parsing {catalog_csv_zip}", file=sys.stderr)
        for candidate in parse_catalog_csv_zip(catalog_csv_zip, source_rank=200):
            aggregator.offer(candidate)
    else:
        print("[warn] catalog-barcodes-csv.zip not found", file=sys.stderr)

    openfacts_sources = [
        (raw_dir / "openbeautyfacts-products.csv.gz", "open_beauty_facts", 100),
        (raw_dir / "openpetfoodfacts-products.csv.gz", "open_pet_food_facts", 100),
        (raw_dir / "openproductsfacts-products.csv.gz", "open_products_facts", 100),
    ]

    if include_off_food:
        openfacts_sources.append((raw_dir / "openfoodfacts-products.csv.gz", "open_food_facts", 100))

    for path, source, rank in openfacts_sources:
        if not path.exists():
            print(f"[warn] source file not found: {path.name}", file=sys.stderr)
            continue

        print(f"[{source}] parsing {path}", file=sys.stderr)
        for candidate in parse_openfacts_gzip(path, source=source, source_rank=rank):
            aggregator.offer(candidate)

    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    connection = sqlite3.connect(output_db)
    try:
        cursor = connection.cursor()
        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS products (
                barcode TEXT NOT NULL,
                name TEXT NOT NULL,
                brand TEXT,
                category TEXT,
                source TEXT NOT NULL,
                source_rank INTEGER NOT NULL,
                quality_score INTEGER NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        cursor.execute("DELETE FROM products")

        rows = [
            (
                barcode,
                candidate.name,
                candidate.brand,
                candidate.category or "Продукты",
                candidate.source,
                candidate.source_rank,
                candidate.quality_score,
                now,
            )
            for barcode, candidate in aggregator.best_by_barcode.items()
        ]

        cursor.executemany(
            """
            INSERT INTO products (
                barcode,
                name,
                brand,
                category,
                source,
                source_rank,
                quality_score,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )

        cursor.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)")
        cursor.execute(
            "CREATE INDEX IF NOT EXISTS idx_products_source_rank_quality ON products(source_rank DESC, quality_score DESC)"
        )
        connection.commit()
    finally:
        connection.close()

    print(
        (
            "[ok] built index: "
            f"{output_db} | seen={aggregator.total_seen} valid={aggregator.total_valid} "
            f"unique={len(aggregator.best_by_barcode)}"
        ),
        file=sys.stderr,
    )


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    ios_dir = script_dir.parent

    parser = argparse.ArgumentParser(description="Build local barcode lookup SQLite index from external datasets.")
    parser.add_argument(
        "--raw-dir",
        type=Path,
        default=ios_dir / "DataSources" / "External" / "raw",
        help="Directory containing raw dataset archives/files.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ios_dir / "DataSources" / "External" / "index" / "barcode_local_index.sqlite",
        help="Output SQLite file path.",
    )
    parser.add_argument(
        "--include-off-food",
        action="store_true",
        help="Include openfoodfacts-products.csv.gz source.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    raw_dir = args.raw_dir.resolve()
    output = args.output.resolve()

    if not raw_dir.exists():
        print(f"[error] raw directory does not exist: {raw_dir}", file=sys.stderr)
        return 1

    build_index(raw_dir=raw_dir, output_db=output, include_off_food=args.include_off_food)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
