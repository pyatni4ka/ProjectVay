import { existsSync, readFileSync } from "node:fs";
import type { IngestionAdapter, IngestionContext, IngestionProduct } from "../types.js";

const DEFAULT_UHTT_TSV = process.env.UHTT_REFERENCE_TSV_PATH ?? "backend/data/uhtt-reference.tsv";

export const uhttAdapter: IngestionAdapter = {
  id: "uhtt_reference",
  kind: "products",
  licenseRisk: "high",
  ingest: async (context) => {
    if (!existsSync(DEFAULT_UHTT_TSV)) {
      return { products: [], recipes: [], priceSignals: [], synonyms: [] };
    }

    const tsv = readFileSync(DEFAULT_UHTT_TSV, "utf8");
    const products = parseUHTTTSV(tsv, context.maxItemsPerSource).map((product) => ({
      ...product,
      provenance: {
        ...product.provenance,
        capturedAt: context.nowISO
      }
    }));

    return { products, recipes: [], priceSignals: [], synonyms: [] };
  }
};

export function parseUHTTTSV(tsv: string, maxItems: number = 2_000): IngestionProduct[] {
  const lines = tsv.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length === 0) {
    return [];
  }

  const output: IngestionProduct[] = [];
  for (const line of lines.slice(1)) {
    const cols = line.split("\t");
    const barcode = cols[1]?.trim();
    const name = cols[2]?.trim();
    if (!barcode || !name) {
      continue;
    }

    output.push({
      sourceRef: cols[0]?.trim() || barcode,
      barcode: barcode.replace(/\D+/g, ""),
      name,
      category: cols[4]?.trim() || undefined,
      brand: cols[6]?.trim() || undefined,
      provenance: {
        source: "uhtt_reference"
      }
    });

    if (output.length >= maxItems) {
      break;
    }
  }

  return output;
}
