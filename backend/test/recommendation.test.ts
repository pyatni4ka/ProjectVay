import test from "node:test";
import assert from "node:assert/strict";
import { rankRecipes } from "../src/services/recommendation.js";
import { mockRecipes } from "../src/data/mockRecipes.js";

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
