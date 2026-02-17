import { normalizeIngredient } from "../ingredientNormalizer.js";
import type { IngredientPriceHint } from "../../types/contracts.js";
import type { PriceProvider, PriceQuote } from "./types.js";

export class LocalHintsPriceProvider implements PriceProvider {
  readonly id = "local_hints";
  private readonly byKey = new Map<string, IngredientPriceHint[]>();

  constructor(hints: IngredientPriceHint[]) {
    for (const hint of hints) {
      const key = normalizeIngredient(hint.ingredient).normalizedKey;
      if (!key) continue;
      const bucket = this.byKey.get(key) ?? [];
      bucket.push(hint);
      this.byKey.set(key, bucket);
    }
  }

  async quote(ingredientKey: string): Promise<PriceQuote | null> {
    const hints = this.byKey.get(ingredientKey) ?? [];
    if (!hints.length) {
      return null;
    }

    let weightedPrice = 0;
    let weightSum = 0;
    for (const hint of hints) {
      const confidence = clamp01(hint.confidence ?? 0.75);
      weightedPrice += Math.max(0, hint.priceRub) * confidence;
      weightSum += confidence;
    }

    if (weightSum <= 0) {
      return null;
    }

    return {
      priceRub: round2(weightedPrice / weightSum),
      confidence: clamp01(weightSum / hints.length),
      source: hints[0]?.source ?? "history"
    };
  }
}

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}
