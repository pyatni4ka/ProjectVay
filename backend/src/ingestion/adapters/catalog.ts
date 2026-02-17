import { existsSync, readFileSync } from "node:fs";
import type { IngestionAdapter, IngestionContext, IngestionProduct } from "../types.js";

const DEFAULT_CATALOG_CSV = process.env.CATALOG_BARCODES_CSV_PATH ?? "backend/data/catalog-barcodes.csv";

export const catalogAdapter: IngestionAdapter = {
  id: "catalog_app",
  kind: "products",
  licenseRisk: "high",
  ingest: async (context) => {
    if (!existsSync(DEFAULT_CATALOG_CSV)) {
      return { products: [], recipes: [], priceSignals: [], synonyms: [] };
    }

    const csv = readFileSync(DEFAULT_CATALOG_CSV, "utf8");
    const products = parseCatalogCSV(csv, context.maxItemsPerSource).map((product) => ({
      ...product,
      provenance: {
        ...product.provenance,
        capturedAt: context.nowISO
      }
    }));

    return { products, recipes: [], priceSignals: [], synonyms: [] };
  }
};

export function parseCatalogCSV(csv: string, maxItems: number = 2_000): IngestionProduct[] {
  const lines = csv.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) {
    return [];
  }

  const headers = splitSemicolon(lines[0]!);
  const indexByName = new Map(headers.map((name, index) => [name.toLowerCase(), index]));
  const output: IngestionProduct[] = [];

  for (const line of lines.slice(1)) {
    const cols = splitSemicolon(line);
    const barcodeRaw = valueAt(cols, indexByName.get("barcode"));
    const name = valueAt(cols, indexByName.get("name"));
    if (!barcodeRaw || !name) {
      continue;
    }

    output.push({
      sourceRef: barcodeRaw,
      barcode: barcodeRaw.replace(/\D+/g, ""),
      name,
      brand: valueAt(cols, indexByName.get("vendor")),
      category: valueAt(cols, indexByName.get("category")),
      provenance: {
        source: "catalog_app"
      }
    });

    if (output.length >= maxItems) {
      break;
    }
  }

  return output;
}

function splitSemicolon(line: string): string[] {
  return line.split(";").map((item) => item.trim());
}

function valueAt(values: string[], index: number | undefined): string | undefined {
  if (index == null || index < 0 || index >= values.length) {
    return undefined;
  }
  const value = values[index]?.trim();
  return value ? value : undefined;
}
