import test from "node:test";
import assert from "node:assert/strict";
import { rankRecipes } from "../src/services/recommendation.js";
import { mockRecipes } from "../src/data/mockRecipes.js";
import type { Recipe } from "../src/types/contracts.js";

test("rankRecipes penalizes disliked ingredients", () => {
  const ranked = rankRecipes(mockRecipes, {
    ingredientKeywords: ["яйца", "молоко"],
    expiringSoonKeywords: ["яйца"],
    targets: { kcal: 400, protein: 25, fat: 20, carbs: 20 },
    budget: { perMeal: 250 },
    exclude: ["кускус"],
    avoidBones: true,
    limit: 10
  });

  assert.equal(ranked[0]?.recipe.id, "r_omelet");
  assert.ok(ranked.find((r) => r.recipe.id === "r_couscous")!.score < ranked[0]!.score);
});

test("rankRecipes prefers recipes closer to target macros", () => {
  const candidates: Recipe[] = [
    {
      id: "macro_close",
      title: "Близко к таргету",
      imageURL: "https://images.example/macro-close.jpg",
      sourceName: "example.ru",
      sourceURL: "https://example.ru/macro-close",
      ingredients: ["курица", "рис"],
      instructions: ["Приготовить"],
      nutrition: { kcal: 610, protein: 40, fat: 20, carbs: 55 },
      estimatedCost: 240
    },
    {
      id: "macro_far",
      title: "Далеко от таргета",
      imageURL: "https://images.example/macro-far.jpg",
      sourceName: "example.ru",
      sourceURL: "https://example.ru/macro-far",
      ingredients: ["курица", "рис"],
      instructions: ["Приготовить"],
      nutrition: { kcal: 980, protein: 8, fat: 55, carbs: 120 },
      estimatedCost: 240
    }
  ];

  const ranked = rankRecipes(candidates, {
    ingredientKeywords: ["курица", "рис"],
    expiringSoonKeywords: [],
    targets: { kcal: 620, protein: 42, fat: 22, carbs: 58 },
    budget: { perMeal: 300 },
    exclude: [],
    avoidBones: false,
    limit: 10
  });

  assert.equal(ranked[0]?.recipe.id, "macro_close");
  assert.ok((ranked[0]?.score ?? 0) > (ranked[1]?.score ?? 0));
  assert.ok((ranked[1]?.scoreBreakdown.macroDeviation ?? 0) > (ranked[0]?.scoreBreakdown.macroDeviation ?? 0));
});
