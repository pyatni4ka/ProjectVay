#!/usr/bin/env python3
from __future__ import annotations

import csv
import gzip
import sqlite3
import subprocess
import tempfile
import zipfile
from pathlib import Path


def _write_uhtt_zip(path: Path) -> None:
    lines = [
        ["1", "4601576009686", "4601576009686", "57", "Продукты", "10", ""],
        ["2", "4601576009686", "МАЙОНЕЗ МОСКОВСКИЙ ПРОВАНСАЛЬ", "57", "Продукты", "10", "МЖК"],
    ]
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        with archive.open("UhttBarcodeReference-20230913/DATA/uhtt_barcode_ref_0001.csv", "w") as handle:
            writer = csv.writer(TextWriter(handle), delimiter="\t", lineterminator="\n")
            writer.writerows(lines)


def _write_catalog_zip(path: Path) -> None:
    rows = [
        ["Id", "Category", "Vendor", "Name", "Article", "Barcode"],
        ["1", "Соусы", "Brand", "МАЙОНЕЗ", "", "4601576009686"],
        ["2", "Соусы", "Brand", "4601576009686", "", "4601576009686"],
    ]
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        with archive.open("barcodes.csv", "w") as handle:
            writer = csv.writer(TextWriter(handle), delimiter=";", lineterminator="\n")
            writer.writerows(rows)


def _write_openfacts_gz(path: Path) -> None:
    headers = ["code", "product_name", "generic_name", "brands", "categories"]
    rows = [
        ["1234567890123", "Штрихкод", "", "", ""],
        ["1234567890123", "Корм для котов", "", "PetBrand", "Корма"],
    ]
    with gzip.open(path, "wt", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(headers)
        writer.writerows(rows)


class TextWriter:
    def __init__(self, binary_handle):
        self.binary_handle = binary_handle

    def write(self, data: str) -> int:
        encoded = data.encode("utf-8")
        self.binary_handle.write(encoded)
        return len(data)


def main() -> int:
    script_path = Path(__file__).resolve().parents[1] / "build_barcode_index.py"

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        raw_dir = tmp_path / "raw"
        raw_dir.mkdir(parents=True)
        output_db = tmp_path / "barcode_local_index.sqlite"

        _write_uhtt_zip(raw_dir / "uhtt-reference-20230913.zip")
        _write_catalog_zip(raw_dir / "catalog-barcodes-csv.zip")
        _write_openfacts_gz(raw_dir / "openbeautyfacts-products.csv.gz")
        _write_openfacts_gz(raw_dir / "openpetfoodfacts-products.csv.gz")
        _write_openfacts_gz(raw_dir / "openproductsfacts-products.csv.gz")

        subprocess.run(
            [
                "python3",
                str(script_path),
                "--raw-dir",
                str(raw_dir),
                "--output",
                str(output_db),
            ],
            check=True,
        )

        connection = sqlite3.connect(output_db)
        try:
            cursor = connection.cursor()
            cursor.execute("SELECT name, source FROM products WHERE barcode = ?", ("4601576009686",))
            row = cursor.fetchone()
            assert row is not None, "missing barcode 4601576009686"
            assert row[0] == "МАЙОНЕЗ МОСКОВСКИЙ ПРОВАНСАЛЬ", row
            assert row[1] == "uhtt", row

            cursor.execute("SELECT name FROM products WHERE barcode = ?", ("1234567890123",))
            row2 = cursor.fetchone()
            assert row2 is not None, "missing barcode 1234567890123"
            assert row2[0] == "Корм для котов", row2
        finally:
            connection.close()

    print("ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
