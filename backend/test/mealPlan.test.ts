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
