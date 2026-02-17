import { normalizeIngredient, normalizeIngredients } from "./ingredientNormalizer.js";
import type {
  IngredientPriceHint,
  PriceEstimateItem,
  PriceEstimateRequest,
  PriceEstimateResponse,
  Recipe
} from "../types/contracts.js";
import type { PriceProvider, PriceQuote } from "./priceProviders/types.js";

const LOCAL_HINT_BASE_CONFIDENCE = 0.75;
const PROVIDER_BASE_CONFIDENCE = 0.55;
const FALLBACK_CONFIDENCE = 0.25;

type PriceSignal = {
  priceRub: number;
  confidence: number;
  source: string;
};

export async function estimateIngredientsPrice(
  request: PriceEstimateRequest,
  providers: PriceProvider[] = []
): Promise<PriceEstimateResponse> {
  const normalizedIngredients = normalizeIngredients(request.ingredients);
  const hintMap = indexHints(request.hints ?? []);

  const items: PriceEstimateItem[] = [];
  const missingIngredients: string[] = [];
  let confidenceWeightedTotal = 0;
  let confidenceWeight = 0;
  let totalEstimatedRub = 0;

  for (const ingredient of normalizedIngredients) {
    const localHintSignal = signalFromHints(hintMap.get(ingredient.normalizedKey) ?? []);
    const providerSignals = await collectProviderSignals(ingredient.normalizedKey, providers);
    const fallbackSignal = localHintSignal || providerSignals.length > 0 ? null : fallbackCategorySignal(ingredient.name);

    const merged = mergeSignals([
      ...(localHintSignal ? [localHintSignal] : []),
      ...providerSignals,
      ...(fallbackSignal ? [fallbackSignal] : [])
    ]);

    if (!merged) {
      missingIngredients.push(ingredient.raw);
      continue;
    }

    const quantityMultiplier = normalizeQuantityMultiplier(ingredient.quantity, ingredient.unit);
    const estimatedPriceRub = round2(merged.priceRub * quantityMultiplier);

    items.push({
      ingredient: ingredient.raw,
      estimatedPriceRub,
      confidence: merged.confidence,
      source: merged.source
    });

    totalEstimatedRub += estimatedPriceRub;
    confidenceWeightedTotal += merged.confidence * estimatedPriceRub;
    confidenceWeight += estimatedPriceRub
  }

  const confidence =
    confidenceWeight > 0
      ? round3(confidenceWeightedTotal / confidenceWeight)
      : 0;

  return {
    items,
    totalEstimatedRub: round2(totalEstimatedRub),
    confidence,
    missingIngredients
  };
}

export async function estimateRecipeCostRub(
  recipe: Recipe,
  hints: IngredientPriceHint[],
  providers: PriceProvider[] = []
): Promise<{ estimatedCostRub: number; confidence: number }> {
  if (typeof recipe.estimatedCost === "number" && Number.isFinite(recipe.estimatedCost) && recipe.estimatedCost > 0) {
    return { estimatedCostRub: round2(recipe.estimatedCost), confidence: 0.8 };
  }

  const result = await estimateIngredientsPrice(
    { ingredients: recipe.ingredients, hints, region: "RU", currency: "RUB" },
    providers
  );
  return {
    estimatedCostRub: result.totalEstimatedRub,
    confidence: result.confidence
  };
}

function indexHints(hints: IngredientPriceHint[]): Map<string, IngredientPriceHint[]> {
  const byKey = new Map<string, IngredientPriceHint[]>();
  for (const hint of hints) {
    const key = normalizeIngredient(hint.ingredient).normalizedKey;
    if (!key) continue;
    const bucket = byKey.get(key) ?? [];
    bucket.push(hint);
    byKey.set(key, bucket);
  }
  return byKey;
}

function signalFromHints(hints: IngredientPriceHint[]): PriceSignal | null {
  if (!hints.length) {
    return null;
  }

  let weightedPrice = 0;
  let weightSum = 0;
  for (const hint of hints) {
    const confidence = clamp01(hint.confidence ?? LOCAL_HINT_BASE_CONFIDENCE);
    weightedPrice += Math.max(0, hint.priceRub) * confidence;
    weightSum += confidence;
  }

  if (weightSum <= 0) {
    return null;
  }

  return {
    priceRub: weightedPrice / weightSum,
    confidence: clamp01(Math.max(LOCAL_HINT_BASE_CONFIDENCE, weightSum / hints.length)),
    source: "local_hints"
  };
}

async function collectProviderSignals(ingredientKey: string, providers: PriceProvider[]): Promise<PriceSignal[]> {
  if (!providers.length) {
    return [];
  }

  const results = await Promise.allSettled(providers.map((provider) => provider.quote(ingredientKey)));
  const signals: PriceSignal[] = [];

  for (const result of results) {
    if (result.status !== "fulfilled" || !result.value) continue;
    const quote = result.value as PriceQuote;
    signals.push({
      priceRub: quote.priceRub,
      confidence: clamp01(quote.confidence || PROVIDER_BASE_CONFIDENCE),
      source: quote.source
    });
  }

  return signals;
}

function mergeSignals(signals: PriceSignal[]): PriceSignal | null {
  if (!signals.length) {
    return null;
  }

  let weightedPrice = 0;
  let weightSum = 0;
  const sourceParts: string[] = [];

  for (const signal of signals) {
    const weight = clamp01(signal.confidence);
    if (weight <= 0) continue;
    weightedPrice += Math.max(0, signal.priceRub) * weight;
    weightSum += weight;
    sourceParts.push(signal.source);
  }

  if (weightSum <= 0) {
    return null;
  }

  return {
    priceRub: weightedPrice / weightSum,
    confidence: clamp01(weightSum / signals.length),
    source: Array.from(new Set(sourceParts)).join("+")
  };
}

function fallbackCategorySignal(name: string): PriceSignal {
  const lower = name.toLowerCase();
  const fallback =
    /(мяс|рыб|кур|говяд|свинин)/.test(lower) ? 180 :
    /(сыр|молок|твор|йогурт)/.test(lower) ? 120 :
    /(круп|рис|греч|макарон|мука)/.test(lower) ? 90 :
    /(фрукт|яблок|банан|цитрус)/.test(lower) ? 80 :
    /(овощ|томат|карто|морков|огурц|лук)/.test(lower) ? 60 :
    70;

  return {
    priceRub: fallback,
    confidence: FALLBACK_CONFIDENCE,
    source: "category_fallback"
  };
}

function normalizeQuantityMultiplier(quantity?: number, unit?: string): number {
  if (!quantity || quantity <= 0) {
    return 1;
  }

  switch (unit) {
    case "kg":
      return quantity;
    case "g":
      return quantity / 1000;
    case "l":
      return quantity;
    case "ml":
      return quantity / 1000;
    case "pcs":
      return quantity;
    case "tbsp":
      return quantity * 0.03;
    case "tsp":
      return quantity * 0.01;
    default:
      return 1;
  }
}

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function round3(value: number): number {
  return Math.round(value * 1000) / 1000;
}
