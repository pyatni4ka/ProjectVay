export type LicenseRisk = "low" | "medium" | "high";

export type IngestionContext = {
  nowISO: string;
  runId: string;
  maxItemsPerSource: number;
};

export type IngestionProduct = {
  sourceRef: string;
  barcode?: string;
  name: string;
  brand?: string;
  category?: string;
  nutrition?: Record<string, number | string | null | undefined>;
  provenance: Record<string, unknown>;
};

export type IngestionRecipe = {
  sourceRef: string;
  title: string;
  sourceURL: string;
  sourceName: string;
  imageURL?: string;
  ingredients: string[];
  instructions: string[];
  nutrition?: Record<string, number | string | null | undefined>;
  totalTimeMinutes?: number;
  cuisine?: string;
  tags?: string[];
  provenance: Record<string, unknown>;
};

export type IngestionPriceSignal = {
  ingredient: string;
  normalizedKey: string;
  priceRub: number;
  confidence: number;
  region: string;
  sourceKind: "receipt" | "history" | "provider" | "fallback";
  capturedAtISO: string;
};

export type IngestionAdapterResult = {
  products: IngestionProduct[];
  recipes: IngestionRecipe[];
  priceSignals: IngestionPriceSignal[];
  synonyms: Array<{ normalizedKey: string; synonym: string }>;
};

export type IngestionAdapter = {
  id: string;
  kind: "products" | "recipes" | "prices" | "mixed";
  licenseRisk: LicenseRisk;
  ingest: (context: IngestionContext) => Promise<IngestionAdapterResult>;
};
