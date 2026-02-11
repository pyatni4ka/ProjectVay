import type { Nutrition } from "../types/contracts.js";

export type BarcodeLookupProduct = {
  barcode: string;
  name: string;
  brand?: string;
  category?: string;
  nutrition?: Nutrition;
};

export type BarcodeLookupResult = {
  found: boolean;
  provider: string | null;
  product: BarcodeLookupProduct | null;
};

export type BarcodeLookupOptions = {
  code: string;
  eanDBApiKey?: string;
  eanDBApiURL?: string;
  enableOpenFoodFacts?: boolean;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
};

type FetchLike = typeof fetch;

const DEFAULT_EAN_DB_API_URL = "https://ean-db.com/api";
const DEFAULT_TIMEOUT_MS = 3_000;

export async function lookupBarcode(options: BarcodeLookupOptions): Promise<BarcodeLookupResult> {
  const code = normalizeCode(options.code);
  if (!code) {
    return notFound();
  }

  const fetchImpl = options.fetchImpl ?? fetch;
  const timeoutMs = normalizeTimeout(options.timeoutMs);

  const eanDBApiKey = sanitizeText(options.eanDBApiKey);
  if (eanDBApiKey) {
    const eanDBURL = sanitizeURL(options.eanDBApiURL) ?? DEFAULT_EAN_DB_API_URL;
    const eanDBProduct = await lookupEANDB({
      code,
      apiKey: eanDBApiKey,
      apiURL: eanDBURL,
      fetchImpl,
      timeoutMs
    });
    if (eanDBProduct) {
      return {
        found: true,
        provider: "ean_db",
        product: eanDBProduct
      };
    }
  }

  if (options.enableOpenFoodFacts !== false) {
    const offProduct = await lookupOpenFoodFacts({ code, fetchImpl, timeoutMs });
    if (offProduct) {
      return {
        found: true,
        provider: "open_food_facts",
        product: offProduct
      };
    }
  }

  return notFound();
}

type EANDBLookupInput = {
  code: string;
  apiKey: string;
  apiURL: string;
  fetchImpl: FetchLike;
  timeoutMs: number;
};

async function lookupEANDB(input: EANDBLookupInput): Promise<BarcodeLookupProduct | null> {
  const endpoint = new URL(input.apiURL);
  endpoint.searchParams.set("barcode", input.code);
  endpoint.searchParams.set("keycode", input.apiKey);

  const data = await fetchJSON(endpoint.toString(), input.fetchImpl, input.timeoutMs);
  if (!data) {
    return null;
  }
  return parseEANDBProduct(data, input.code);
}

type OFFLookupInput = {
  code: string;
  fetchImpl: FetchLike;
  timeoutMs: number;
};

async function lookupOpenFoodFacts(input: OFFLookupInput): Promise<BarcodeLookupProduct | null> {
  const endpoint = `https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(input.code)}.json`;
  const data = await fetchJSON(endpoint, input.fetchImpl, input.timeoutMs);
  if (!data) {
    return null;
  }
  return parseOpenFoodFactsProduct(data, input.code);
}

async function fetchJSON(url: string, fetchImpl: FetchLike, timeoutMs: number): Promise<unknown | null> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(url, {
      method: "GET",
      signal: controller.signal,
      headers: {
        Accept: "application/json"
      }
    });

    if (!response.ok) {
      return null;
    }

    return await response.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

export function parseOpenFoodFactsProduct(payload: unknown, fallbackBarcode: string): BarcodeLookupProduct | null {
  if (!isRecord(payload)) {
    return null;
  }

  const status = numericOrNull(payload.status);
  if (status !== 1) {
    return null;
  }

  const product = isRecord(payload.product) ? payload.product : null;
  if (!product) {
    return null;
  }

  const name = firstText([product.product_name_ru, product.product_name]);
  if (!name) {
    return null;
  }

  const barcode = firstText([product.code]) ?? fallbackBarcode;
  const brand = firstText([firstCSVPart(product.brands)]);
  const category = firstText([firstCSVPart(product.categories)]) ?? "Продукты";

  const nutriments = isRecord(product.nutriments) ? product.nutriments : null;
  const nutrition: Nutrition | undefined = nutriments
    ? compactNutrition({
        kcal: numericOrNull(nutriments["energy-kcal_100g"]),
        protein: numericOrNull(nutriments.proteins_100g),
        fat: numericOrNull(nutriments.fat_100g),
        carbs: numericOrNull(nutriments.carbohydrates_100g)
      })
    : undefined;

  return {
    barcode,
    name,
    brand: brand ?? undefined,
    category,
    nutrition
  };
}

export function parseEANDBProduct(payload: unknown, fallbackBarcode: string): BarcodeLookupProduct | null {
  if (!isRecord(payload)) {
    return null;
  }

  const target = isRecord(payload.product) ? payload.product : payload;

  const name = firstText([target.productName, target.product_name, target.title, target.name]);
  if (!name) {
    return null;
  }

  const brand = firstText([target.brand, target.brandName, target.manufacturer]);
  const category = firstText([target.category, target.categoryName, target.productCategory]) ?? "Продукты";
  const barcode = firstText([target.barcode, target.ean, target.ean13, target.gtin]) ?? fallbackBarcode;

  const nutrition: Nutrition | undefined = compactNutrition({
    kcal: numericOrNull(target.kcal),
    protein: numericOrNull(target.protein),
    fat: numericOrNull(target.fat),
    carbs: numericOrNull(target.carbs)
  });

  return {
    barcode,
    name,
    brand: brand ?? undefined,
    category,
    nutrition
  };
}

function compactNutrition(input: Nutrition): Nutrition | undefined {
  const hasAny = [input.kcal, input.protein, input.fat, input.carbs].some((value) => value !== undefined);
  return hasAny ? input : undefined;
}

function firstCSVPart(value: unknown): string | null {
  const normalized = sanitizeText(value);
  if (!normalized) {
    return null;
  }
  const part = normalized.split(",")[0]?.trim();
  return part && part.length > 0 ? part : null;
}

function firstText(candidates: unknown[]): string | null {
  for (const candidate of candidates) {
    const normalized = sanitizeText(candidate);
    if (normalized) {
      return normalized;
    }
  }
  return null;
}

function sanitizeText(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

function sanitizeURL(value: string | undefined): string | null {
  if (!value) {
    return null;
  }

  try {
    const parsed = new URL(value);
    const scheme = parsed.protocol.toLowerCase();
    if (scheme !== "http:" && scheme !== "https:") {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
}

function normalizeCode(value: string): string {
  return value.trim();
}

function normalizeTimeout(timeoutMs: number | undefined): number {
  const fallback = DEFAULT_TIMEOUT_MS;
  if (typeof timeoutMs !== "number" || !Number.isFinite(timeoutMs)) {
    return fallback;
  }
  return Math.max(500, Math.floor(timeoutMs));
}

function numericOrNull(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function notFound(): BarcodeLookupResult {
  return {
    found: false,
    provider: null,
    product: null
  };
}
