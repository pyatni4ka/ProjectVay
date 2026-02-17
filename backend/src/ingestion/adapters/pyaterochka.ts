import { existsSync, readFileSync } from "node:fs";
import type { IngestionAdapter, IngestionContext, IngestionPriceSignal } from "../types.js";

const DEFAULT_PYATEROCHKA_PRICES_PATH =
  process.env.PYATEROCHKA_PRICES_PATH ?? "backend/data/pyaterochka-prices.json";

export const pyaterochkaAdapter: IngestionAdapter = {
  id: "pyaterochka",
  kind: "prices",
  licenseRisk: "high",
  ingest: async (context) => {
    const priceSignals = loadPriceSignals(DEFAULT_PYATEROCHKA_PRICES_PATH, context.nowISO);
    return { products: [], recipes: [], priceSignals, synonyms: [] };
  }
};

function loadPriceSignals(path: string, fallbackDate: string): IngestionPriceSignal[] {
  if (!existsSync(path)) {
    return [];
  }

  let data: unknown;
  try {
    data = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return [];
  }

  if (!Array.isArray(data)) {
    return [];
  }

  return data.reduce<IngestionPriceSignal[]>((accumulator, item) => {
    if (!item || typeof item !== "object") {
      return accumulator;
    }
    const row = item as Record<string, unknown>;
    const ingredient = String(row.ingredient ?? "").trim().toLowerCase();
    const priceRub = Number(row.priceRub);
    if (!ingredient || !Number.isFinite(priceRub) || priceRub <= 0) {
      return accumulator;
    }
    const confidence = Number.isFinite(Number(row.confidence)) ? Number(row.confidence) : 0.65;
    accumulator.push({
      ingredient,
      normalizedKey: ingredient,
      priceRub,
      confidence: Math.min(Math.max(confidence, 0), 1),
      region: "RU",
      sourceKind: "provider",
      capturedAtISO: String(row.capturedAt ?? fallbackDate)
    });
    return accumulator;
  }, []);
}
