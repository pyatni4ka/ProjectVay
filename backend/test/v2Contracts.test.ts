import test from "node:test";
import assert from "node:assert/strict";
import { __routeInternals } from "../src/routes/v1/recipes.js";

test("recommend v2 payload contract stays valid", () => {
  const payload = __routeInternals.normalizeRecommendPayload({
    ingredientKeywords: ["курица", "рис"],
    expiringSoonKeywords: [],
    targets: { kcal: 650, protein: 40, fat: 20, carbs: 60 },
    budget: { perMeal: 280 },
    userId: "u1",
    includeReasons: true
  });

  assert.ok(payload);
  assert.equal(payload?.ingredientKeywords[0], "курица");
  assert.equal(payload?.budget?.perMeal, 280);
});

test("smart meal plan v2 payload contract stays valid", () => {
  const payload = __routeInternals.normalizeSmartMealPlanPayload({
    days: 7,
    ingredientKeywords: ["курица", "рис"],
    expiringSoonKeywords: ["йогурт"],
    targets: { kcal: 2100, protein: 130, fat: 70, carbs: 220 },
    budget: { perDay: 900 },
    objective: "cost_macro",
    optimizerProfile: "balanced",
    ingredientPriceHints: [
      { ingredient: "курица", priceRub: 260, confidence: 0.8 }
    ]
  });

  assert.ok(payload);
  assert.equal(payload?.optimizerProfile, "balanced");
  assert.equal(payload?.ingredientPriceHints?.length, 1);
});

test("prices compare payload uses estimate contract fields", () => {
  const payload = __routeInternals.normalizePriceEstimatePayload({
    ingredients: ["курица", "рис", "лук"],
    region: "RU",
    currency: "RUB"
  });

  assert.ok(payload);
  assert.equal(payload?.ingredients.length, 3);
  assert.equal(payload?.region, "RU");
});
