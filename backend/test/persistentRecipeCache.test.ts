import test from "node:test";
import assert from "node:assert/strict";
import { PersistentRecipeCache } from "../src/services/persistentRecipeCache.js";
import type { Recipe } from "../src/types/contracts.js";

const sampleRecipe: Recipe = {
  id: "recipe_1",
  title: "Омлет",
  imageURL: "https://example.com/omelet.jpg",
  sourceName: "example.com",
  sourceURL: "https://example.com/recipe/omelet",
  ingredients: ["яйца", "молоко"],
  instructions: ["Взбить", "Пожарить"]
};

test("PersistentRecipeCache stores and returns recipe", () => {
  const cache = new PersistentRecipeCache({
    dbPath: ":memory:",
    ttlSeconds: 600
  });

  cache.set(sampleRecipe.sourceURL, sampleRecipe);

  const loaded = cache.get(sampleRecipe.sourceURL);
  assert.ok(loaded);
  assert.equal(loaded?.id, sampleRecipe.id);
  assert.equal(cache.size(), 1);
});

test("PersistentRecipeCache expires old entries", async () => {
  const cache = new PersistentRecipeCache({
    dbPath: ":memory:",
    ttlSeconds: 1
  });

  cache.set(sampleRecipe.sourceURL, sampleRecipe);
  await new Promise((resolve) => setTimeout(resolve, 1100));

  const loaded = cache.get(sampleRecipe.sourceURL);
  assert.equal(loaded, null);
  assert.equal(cache.size(), 0);
});
