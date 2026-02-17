import test from "node:test";
import assert from "node:assert/strict";
import { mockRecipes } from "../src/data/mockRecipes.js";
import { generateMealPlan } from "../src/services/mealPlan.js";

test("generateMealPlan creates day plan with 3 meals and shopping list", () => {
  const response = generateMealPlan(mockRecipes, {
    days: 1,
    ingredientKeywords: ["яйца", "молоко"],
    expiringSoonKeywords: ["яйца"],
    targets: { kcal: 1800, protein: 120, fat: 60, carbs: 180 },
    beveragesKcal: 100,
    budget: { perDay: 900 },
    exclude: ["кускус"],
    avoidBones: true
  });

  assert.equal(response.days.length, 1);
  assert.equal(response.days[0]?.entries.length, 3);
  assert.ok(response.estimatedTotalCost >= 0);
  assert.ok(Array.isArray(response.shoppingList));
});

test("generateMealPlan clamps days to supported range", () => {
  const response = generateMealPlan(mockRecipes, {
    days: 99,
    ingredientKeywords: ["яйца"],
    expiringSoonKeywords: [],
    targets: { kcal: 1800 }
  });

  assert.equal(response.days.length, 7);
});

test("smart optimizer profiles trade off cost and macro precision", () => {
  const syntheticRecipes = Array.from({ length: 8 }).map((_, index) => ({
    id: `r${index}`,
    title: `Recipe ${index}`,
    imageURL: "https://images.example/recipe.jpg",
    sourceName: "example.ru",
    sourceURL: `https://example.ru/r${index}`,
    ingredients: ["рис", "яйца"],
    instructions: ["Смешать", "Приготовить"],
    nutrition: {
      kcal: 420 + index * 35,
      protein: 24 + index * 2,
      fat: 14 + index,
      carbs: 50 + index * 3
    },
    estimatedCost: 50 + index * 25,
    tags: ["тест"]
  }));

  const request = {
    days: 1,
    ingredientKeywords: ["рис", "яйца"],
    expiringSoonKeywords: [],
    targets: { kcal: 1800, protein: 120, fat: 60, carbs: 180 },
    exclude: [],
    avoidBones: false,
    cuisine: []
  };

  const economy = generateMealPlan(syntheticRecipes, request, new Date("2026-01-01T00:00:00Z"), {
    objective: "cost_macro",
    optimizerProfile: "economy_aggressive",
    macroTolerancePercent: 25
  });

  const macroPrecision = generateMealPlan(syntheticRecipes, request, new Date("2026-01-01T00:00:00Z"), {
    objective: "cost_macro",
    optimizerProfile: "macro_precision",
    macroTolerancePercent: 25
  });

  assert.equal(economy.optimization?.profile, "economy_aggressive");
  assert.equal(macroPrecision.optimization?.profile, "macro_precision");
  assert.ok(economy.estimatedTotalCost <= macroPrecision.estimatedTotalCost);
  assert.ok((macroPrecision.optimization?.averageMacroDeviation ?? 1) <= (economy.optimization?.averageMacroDeviation ?? 1));
});
