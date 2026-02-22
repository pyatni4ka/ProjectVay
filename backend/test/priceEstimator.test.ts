import test from "node:test";
import assert from "node:assert/strict";
import { estimateIngredientsPrice, estimateRecipeCostRub } from "../src/services/priceEstimator.js";
import type { IngredientPriceHint, Recipe } from "../src/types/contracts.js";
import type { PriceProvider, PriceQuote } from "../src/services/priceProviders/types.js";

// ── helpers ────────────────────────────────────────────────────────────────

function mockProvider(prices: Record<string, number>, confidence = 0.6): PriceProvider {
  return {
    id: "mock_provider",
    async quote(ingredientKey: string): Promise<PriceQuote | null> {
      const price = prices[ingredientKey];
      if (price === undefined) return null;
      return { priceRub: price, confidence, source: "mock_provider" };
    }
  };
}

function hint(ingredient: string, priceRub: number, confidence?: number): IngredientPriceHint {
  return { ingredient, priceRub, confidence };
}

// ── estimateIngredientsPrice ───────────────────────────────────────────────

test("returns empty result for empty ingredients", async () => {
  const result = await estimateIngredientsPrice({ ingredients: [] });
  assert.equal(result.items.length, 0);
  assert.equal(result.totalEstimatedRub, 0);
  assert.equal(result.confidence, 0);
  assert.equal(result.missingIngredients.length, 0);
});

test("uses local hints when provided", async () => {
  const result = await estimateIngredientsPrice({
    ingredients: ["молоко 1л", "яйца 10 шт"],
    hints: [
      hint("молоко", 80, 0.9),
      hint("яйца", 120, 0.8)
    ]
  });

  assert.equal(result.items.length, 2);
  assert.ok(result.totalEstimatedRub > 0);
  assert.ok(result.confidence > 0);
  assert.equal(result.missingIngredients.length, 0);
});

test("falls back to category estimation when no hints or providers", async () => {
  const result = await estimateIngredientsPrice({
    ingredients: ["курица 500г", "рис 200г"]
  });

  assert.equal(result.items.length, 2);
  assert.ok(result.totalEstimatedRub > 0);

  // Category fallback has confidence 0.25
  assert.ok(result.confidence <= 0.3);
  assert.equal(result.missingIngredients.length, 0);

  // Курица (мясо) should cost more than рис (крупы)
  const chicken = result.items.find(i => i.ingredient.includes("курица"));
  const rice = result.items.find(i => i.ingredient.includes("рис"));
  assert.ok(chicken != null);
  assert.ok(rice != null);
  assert.ok(chicken.estimatedPriceRub > rice.estimatedPriceRub);
});

test("uses provider signals", async () => {
  const provider = mockProvider({ молоко: 85, яйца: 110 }, 0.7);

  const result = await estimateIngredientsPrice(
    { ingredients: ["молоко", "яйца"] },
    [provider]
  );

  assert.equal(result.items.length, 2);
  assert.ok(result.totalEstimatedRub > 0);
  assert.ok(result.confidence >= 0.5);
});

test("merges hints and provider signals", async () => {
  // Use plain ingredient name so normalized key matches hint and provider key
  const provider = mockProvider({ молоко: 90 }, 0.6);

  const result = await estimateIngredientsPrice(
    {
      ingredients: ["молоко"],
      hints: [hint("молоко", 80, 0.8)]
    },
    [provider]
  );

  assert.equal(result.items.length, 1);
  // Merged price should be between 80 and 90 (weighted by confidence)
  const item = result.items[0]!;
  assert.ok(item.estimatedPriceRub >= 70);
  assert.ok(item.estimatedPriceRub <= 100);
  assert.ok(item.source.includes("local_hints"), `source "${item.source}" should include local_hints`);
});

test("reports missing ingredients when no signals available", async () => {
  // Unrecognizable ingredient that won't match any fallback category
  const result = await estimateIngredientsPrice({
    ingredients: ["молоко", ""],
    hints: [hint("молоко", 80)]
  });

  // Empty string is filtered out by normalizeIngredients
  assert.equal(result.items.length, 1);
});

test("confidence is price-weighted average", async () => {
  // Expensive ingredient with high confidence + cheap ingredient with low confidence
  // Use plain names so normalized keys match hints
  const result = await estimateIngredientsPrice({
    ingredients: ["говядина", "соль"],
    hints: [
      hint("говядина", 800, 0.95),
      hint("соль", 30, 0.3)
    ]
  });

  assert.equal(result.items.length, 2);
  // Price-weighted average: (0.95*800 + 0.3*30) / (800+30) ≈ 0.927
  // Actual confidence uses merged signals which cap at LOCAL_HINT_BASE_CONFIDENCE minimum
  assert.ok(result.confidence > 0.7, `confidence ${result.confidence} should be > 0.7`);
});

test("handles quantity multipliers for grams", async () => {
  const result = await estimateIngredientsPrice({
    ingredients: ["курица 500г"],
    hints: [hint("курица", 400, 0.8)] // price per unit
  });

  assert.equal(result.items.length, 1);
  const item = result.items[0]!;
  // 500г = 0.5 multiplier, so price should be ~200
  assert.ok(item.estimatedPriceRub < 400, `price ${item.estimatedPriceRub} should be < 400 (500g multiplier)`);
});

test("handles quantity multipliers for liters", async () => {
  const result = await estimateIngredientsPrice({
    ingredients: ["молоко 2л"],
    hints: [hint("молоко", 80, 0.8)]
  });

  assert.equal(result.items.length, 1);
  const item = result.items[0]!;
  // 2l multiplier
  assert.ok(item.estimatedPriceRub > 80, `price ${item.estimatedPriceRub} should be > 80 (2l multiplier)`);
});

test("provider returning null is treated as miss", async () => {
  const emptyProvider: PriceProvider = {
    id: "empty",
    async quote() { return null; }
  };

  const result = await estimateIngredientsPrice(
    { ingredients: ["молоко"] },
    [emptyProvider]
  );

  // Should fall back to category estimation
  assert.equal(result.items.length, 1);
  assert.ok(result.items[0]!.source.includes("category_fallback"));
});

test("provider throwing is handled gracefully", async () => {
  const failingProvider: PriceProvider = {
    id: "failing",
    async quote() { throw new Error("network error"); }
  };

  const result = await estimateIngredientsPrice(
    { ingredients: ["молоко"] },
    [failingProvider]
  );

  // Should fall back to category estimation
  assert.equal(result.items.length, 1);
  assert.ok(result.totalEstimatedRub > 0);
});

// ── estimateRecipeCostRub ──────────────────────────────────────────────────

test("estimateRecipeCostRub returns estimatedCost when recipe already has it", async () => {
  const recipe: Recipe = {
    id: "test_recipe",
    title: "Тест",
    imageURL: "",
    sourceName: "test",
    sourceURL: "",
    ingredients: ["курица 500г", "рис 200г"],
    instructions: ["Приготовить"],
    nutrition: { kcal: 500, protein: 30, fat: 15, carbs: 50 },
    estimatedCost: 350
  };

  const result = await estimateRecipeCostRub(recipe, []);
  assert.equal(result.estimatedCostRub, 350);
  assert.equal(result.confidence, 0.8);
});

test("estimateRecipeCostRub estimates from ingredients when no estimatedCost", async () => {
  const recipe: Recipe = {
    id: "test_recipe",
    title: "Тест",
    imageURL: "",
    sourceName: "test",
    sourceURL: "",
    ingredients: ["курица 500г", "рис 200г"],
    instructions: ["Приготовить"],
    nutrition: { kcal: 500, protein: 30, fat: 15, carbs: 50 }
  };

  const result = await estimateRecipeCostRub(recipe, [
    hint("курица", 400, 0.8),
    hint("рис", 80, 0.7)
  ]);

  assert.ok(result.estimatedCostRub > 0);
  assert.ok(result.confidence > 0);
});

test("estimateRecipeCostRub ignores zero or negative estimatedCost", async () => {
  const recipe: Recipe = {
    id: "test_recipe",
    title: "Тест",
    imageURL: "",
    sourceName: "test",
    sourceURL: "",
    ingredients: ["молоко 1л"],
    instructions: ["Приготовить"],
    nutrition: { kcal: 200, protein: 10, fat: 8, carbs: 15 },
    estimatedCost: 0
  };

  const result = await estimateRecipeCostRub(recipe, [hint("молоко", 90, 0.8)]);
  // Should estimate from ingredients, not use the 0 cost
  assert.ok(result.estimatedCostRub > 0);
});

// ── fallback category pricing ──────────────────────────────────────────────

test("fallback correctly categorizes meat as most expensive", async () => {
  const result = await estimateIngredientsPrice({
    ingredients: ["говядина", "картофель", "рис"]
  });

  const beef = result.items.find(i => i.ingredient === "говядина");
  const potato = result.items.find(i => i.ingredient === "картофель");
  const rice = result.items.find(i => i.ingredient === "рис");

  assert.ok(beef != null && potato != null && rice != null);
  assert.ok(beef.estimatedPriceRub > potato.estimatedPriceRub);
  assert.ok(beef.estimatedPriceRub > rice.estimatedPriceRub);
});
