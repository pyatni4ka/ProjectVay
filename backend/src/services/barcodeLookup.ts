export type BarcodeLookupProduct = {
  barcode: string;
  name: string;
  brand?: string;
  category: string;
  nutrition?: {
    kcal?: number;
    protein?: number;
    fat?: number;
    carbs?: number;
  };
};

export type BarcodeLookupResult = {
  found: boolean;
  provider: string | null;
  product: BarcodeLookupProduct | null;
};

type FetchLikeResponse = {
  ok: boolean;
  status: number;
  json(): Promise<unknown>;
};

export type FetchLike = (input: string, init?: RequestInit) => Promise<FetchLikeResponse>;

type LookupOptions = {
  eanDbApiKey?: string;
  eanDbEndpoint?: string;
  openFoodFactsEnabled?: boolean;
  fetcher?: FetchLike;
};

export async function lookupBarcode(code: string, options: LookupOptions = {}): Promise<BarcodeLookupResult> {
  const normalizedCode = normalizeBarcode(code);
  if (!normalizedCode) {
    return notFound();
  }

  const fetcher = options.fetcher ?? defaultFetcher;

  const eanDbApiKey = options.eanDbApiKey?.trim();
  if (eanDbApiKey) {
    const eanDb = await lookupEANDB(normalizedCode, eanDbApiKey, options.eanDbEndpoint, fetcher);
    if (eanDb) {
      return {
        found: true,
        provider: "ean_db",
        product: eanDb
      };
    }
  }

  if (options.openFoodFactsEnabled ?? true) {
    const off = await lookupOpenFoodFacts(normalizedCode, fetcher);
    if (off) {
      return {
        found: true,
        provider: "open_food_facts",
        product: off
      };
    }
  }

  return notFound();
}

export function parseOpenFoodFactsProduct(payload: unknown, barcode: string): BarcodeLookupProduct | null {
  if (!isRecord(payload)) {
    return null;
  }

  const status = typeof payload.status === "number" ? payload.status : undefined;
  if (status !== 1) {
    return null;
  }

  const product = isRecord(payload.product) ? payload.product : null;
  if (!product) {
    return null;
  }

  const name = normalizeText(product.product_name_ru) ?? normalizeText(product.product_name);
  if (!name) {
    return null;
  }

  const brand = firstToken(product.brands);
  const category = firstToken(product.categories) ?? "Продукты";

  const nutriments = isRecord(product.nutriments) ? product.nutriments : null;
  const nutrition = nutriments
    ? {
        kcal: asFiniteNumber(nutriments["energy-kcal_100g"]),
        protein: asFiniteNumber(nutriments["proteins_100g"]),
        fat: asFiniteNumber(nutriments["fat_100g"]),
        carbs: asFiniteNumber(nutriments["carbohydrates_100g"])
      }
    : undefined;

  return {
    barcode,
    name,
    brand,
    category,
    nutrition
  };
}

export function parseEANDBProduct(payload: unknown, barcode: string): BarcodeLookupProduct | null {
  if (!isRecord(payload)) {
    return null;
  }

  const title = normalizeText(payload.title);
  if (!title) {
    return null;
  }

  const brand = normalizeText(payload.brand);
  const category = normalizeText(payload.category) ?? "Продукты";

  return {
    barcode,
    name: title,
    brand,
    category
  };
}

function normalizeBarcode(raw: string): string | null {
  const digits = raw.replace(/\D+/g, "");
  if (digits.length < 8 || digits.length > 14) {
    return null;
  }
  return digits;
}

async function lookupOpenFoodFacts(code: string, fetcher: FetchLike): Promise<BarcodeLookupProduct | null> {
  const url = `https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(code)}.json`;
  const response = await safeFetchJSON(url, fetcher);
  if (!response) {
    return null;
  }

  return parseOpenFoodFactsProduct(response, code);
}

async function lookupEANDB(
  code: string,
  apiKey: string,
  endpoint: string | undefined,
  fetcher: FetchLike
): Promise<BarcodeLookupProduct | null> {
  const base = endpoint?.trim() || "https://ean-db.com/api";
  const url = new URL(base);
  url.searchParams.set("barcode", code);
  url.searchParams.set("keycode", apiKey);

  const response = await safeFetchJSON(url.toString(), fetcher);
  if (!response) {
    return null;
  }

  return parseEANDBProduct(response, code);
}

async function safeFetchJSON(url: string, fetcher: FetchLike): Promise<unknown | null> {
  try {
    const response = await fetcher(url, {
      headers: {
        "user-agent": "inventory-ai-backend/1.0"
      }
    });

    if (!response.ok || response.status < 200 || response.status >= 300) {
      return null;
    }

    return await response.json();
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function normalizeText(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : undefined;
}

function firstToken(value: unknown): string | undefined {
  const normalized = normalizeText(value);
  if (!normalized) {
    return undefined;
  }

  const [first] = normalized
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);

  return first;
}

function asFiniteNumber(value: unknown): number | undefined {
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

function notFound(): BarcodeLookupResult {
  return {
    found: false,
    provider: null,
    product: null
  };
}

const defaultFetcher: FetchLike = async (input, init) => {
  const response = await fetch(input, init);
  return {
    ok: response.ok,
    status: response.status,
    json: async () => response.json()
  };
};
