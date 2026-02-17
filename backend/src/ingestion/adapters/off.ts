import { createReadStream, existsSync } from "node:fs";
import { createGunzip } from "node:zlib";
import readline from "node:readline";
import type { IngestionAdapter, IngestionContext, IngestionProduct } from "../types.js";

const DEFAULT_OFF_PATH = process.env.OFF_DATASET_PATH ?? "ios/DataSources/External/raw/openfoodfacts-products.csv.gz";

export const offAdapter: IngestionAdapter = {
  id: "open_food_facts",
  kind: "products",
  licenseRisk: "low",
  ingest: (context) => ingestOFF(context)
};

export async function ingestOFF(context: IngestionContext): Promise<{
  products: IngestionProduct[];
  recipes: [];
  priceSignals: [];
  synonyms: [];
}> {
  if (!existsSync(DEFAULT_OFF_PATH)) {
    return { products: [], recipes: [], priceSignals: [], synonyms: [] };
  }

  const stream = createReadStream(DEFAULT_OFF_PATH).pipe(createGunzip());
  const reader = readline.createInterface({ input: stream, crlfDelay: Infinity });

  const products: IngestionProduct[] = [];
  let headers: string[] = [];
  let indexByName = new Map<string, number>();

  for await (const line of reader) {
    if (!line.trim()) {
      continue;
    }

    if (headers.length === 0) {
      headers = line.split("\t");
      indexByName = new Map(headers.map((name, index) => [name, index]));
      continue;
    }

    const columns = line.split("\t");
    const code = valueAt(columns, indexByName.get("code"));
    const name = valueAt(columns, indexByName.get("product_name")) || valueAt(columns, indexByName.get("generic_name"));
    if (!code || !name) {
      continue;
    }

    const brand = valueAt(columns, indexByName.get("brands"));
    const category = valueAt(columns, indexByName.get("categories"));
    products.push({
      sourceRef: code,
      barcode: digitsOnly(code),
      name,
      brand: brand ? brand.split(",")[0]?.trim() : undefined,
      category: category ? category.split(",")[0]?.trim() : undefined,
      nutrition: {
        kcal_100g: parseNumber(valueAt(columns, indexByName.get("energy-kcal_100g"))),
        protein_100g: parseNumber(valueAt(columns, indexByName.get("proteins_100g"))),
        fat_100g: parseNumber(valueAt(columns, indexByName.get("fat_100g"))),
        carbs_100g: parseNumber(valueAt(columns, indexByName.get("carbohydrates_100g")))
      },
      provenance: {
        source: "open_food_facts",
        capturedAt: context.nowISO
      }
    });

    if (products.length >= context.maxItemsPerSource) {
      break;
    }
  }

  return { products, recipes: [], priceSignals: [], synonyms: [] };
}

export function parseOFFTSVSnapshot(tsv: string, maxItems: number = 100): IngestionProduct[] {
  const lines = tsv.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) return [];

  const headers = lines[0]!.split("\t");
  const indexByName = new Map(headers.map((name, index) => [name, index]));
  const out: IngestionProduct[] = [];

  for (const line of lines.slice(1)) {
    const columns = line.split("\t");
    const code = valueAt(columns, indexByName.get("code"));
    const name = valueAt(columns, indexByName.get("product_name")) || valueAt(columns, indexByName.get("generic_name"));
    if (!code || !name) continue;
    out.push({
      sourceRef: code,
      barcode: digitsOnly(code),
      name,
      provenance: { source: "off_test" }
    });
    if (out.length >= maxItems) break;
  }

  return out;
}

function valueAt(columns: string[], index: number | undefined): string | undefined {
  if (index == null || index < 0 || index >= columns.length) {
    return undefined;
  }
  const value = columns[index]?.trim();
  return value ? value : undefined;
}

function digitsOnly(value: string): string {
  return value.replace(/\D+/g, "");
}

function parseNumber(value: string | undefined): number | undefined {
  if (!value) return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}
