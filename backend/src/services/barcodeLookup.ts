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
  enableBarcodeListRu?: boolean;
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

  if (options.enableBarcodeListRu !== false) {
    const barcodeListRuProduct = await lookupBarcodeListRu({ code, fetchImpl, timeoutMs });
    if (barcodeListRuProduct) {
      return {
        found: true,
        provider: "barcode_list_ru",
        product: barcodeListRuProduct
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

type BarcodeListRuLookupInput = {
  code: string;
  fetchImpl: FetchLike;
  timeoutMs: number;
};

async function lookupBarcodeListRu(input: BarcodeListRuLookupInput): Promise<BarcodeLookupProduct | null> {
  const searchURL = `https://barcode-list.ru/barcode/RU/%D0%9F%D0%BE%D0%B8%D1%81%D0%BA.htm?barcode=${encodeURIComponent(input.code)}`;
  const html = await fetchHTML(searchURL, input.fetchImpl, input.timeoutMs);
  if (!html) {
    return null;
  }
  return parseBarcodeListRuHTML(html, input.code);
}

export function parseBarcodeListRuHTML(html: string, fallbackBarcode: string): BarcodeLookupProduct | null {
  // Extract product name from <title> or og:title: "Штрихкод ... - ProductName"
  const name = extractTitleProductName(html);
  if (!name) {
    return null;
  }

  const brand = extractMetaContent(html, "name", "brand");
  const category = extractBreadcrumbCategory(html) ?? "Продукты";

  return {
    barcode: fallbackBarcode,
    name,
    brand: brand ?? undefined,
    category
  };
}

function extractTitleProductName(html: string): string | null {
  // Common generic patterns to ignore
  const isGeneric = (s: string) => {
    const lower = s.toLowerCase();
    return lower.startsWith("штрих-код") || lower.startsWith("штрихкод") || lower.startsWith("barcode") || lower === "поиск";
  };

  // Try og:title first: <meta property="og:title" content="Штрихкод 460... - Название">
  const ogTitle = extractMetaContent(html, "property", "og:title");
  if (ogTitle) {
    const dashIndex = ogTitle.indexOf(" - ");
    if (dashIndex >= 0) {
      const name = ogTitle.slice(dashIndex + 3).trim();
      if (name && !isGeneric(name)) return name;
    }
  }

  // Fallback: <title> tag
  const titleMatch = html.match(/<title[^>]*>([^<]+)<\/title>/i);
  if (titleMatch) {
    const titleContent = titleMatch[1]!.trim();
    // Check for " - " split first
    const dashIndex = titleContent.indexOf(" - ");
    if (dashIndex >= 0) {
      const name = titleContent.slice(dashIndex + 3).trim();
      if (name && !isGeneric(name)) return name;
    }
    // If no dash, check if the whole title is just a code
    else if (!isGeneric(titleContent)) {
      return titleContent;
    }
  }

  // Fallback: <h1> tag
  const h1Match = html.match(/<h1[^>]*>([^<]+)<\/h1>/i);
  if (h1Match) {
    const name = h1Match[1]!.trim();
    if (name.length > 3 && !isGeneric(name)) return name;
  }

  return null;
}

function extractMetaContent(html: string, attrName: string, attrValue: string): string | null {
  // Matches <meta property="og:title" content="..." /> or <meta name="brand" content="..." />
  const pattern = new RegExp(`<meta[^>]+${attrName}="${attrValue}"[^>]+content="([^"]*)"`, "i");
  const match = html.match(pattern);
  if (!match) {
    // Try reversed attribute order: content before property
    const reversed = new RegExp(`<meta[^>]+content="([^"]*)"[^>]+${attrName}="${attrValue}"`, "i");
    const revMatch = html.match(reversed);
    if (revMatch) {
      const value = revMatch[1]!.trim();
      return value || null;
    }
    return null;
  }
  const value = match[1]!.trim();
  return value || null;
}

function extractBreadcrumbCategory(html: string): string | null {
  const pattern = /class="breadcrumb[^"]*"[^>]*>[^<]*<a[^>]*>([^<]+)<\/a>/gi;
  let lastCategory: string | null = null;
  let m: RegExpExecArray | null;
  while ((m = pattern.exec(html)) !== null) {
    const value = m[1]!.trim();
    if (value) lastCategory = value;
  }
  return lastCategory;
}

async function fetchHTML(url: string, fetchImpl: FetchLike, timeoutMs: number): Promise<string | null> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(url, {
      method: "GET",
      signal: controller.signal,
      headers: {
        "Accept": "text/html",
        "User-Agent": "Mozilla/5.0 (compatible; ProjectVay/1.0)",
        "Accept-Language": "ru-RU,ru;q=0.9"
      }
    });
    if (!response.ok) return null;
    return await response.text();
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
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
