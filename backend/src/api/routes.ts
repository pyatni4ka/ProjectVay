import { Router } from "express";
import { mockRecipes } from "../data/mockRecipes.js";
import { rankRecipes } from "../services/recommendation.js";
import { CacheStore } from "../services/cacheStore.js";
import { fetchAndParseRecipe } from "../services/recipeScraper.js";
import type { RecommendPayload, Recipe } from "../types/contracts.js";

const router = Router();
const recipeCache = new CacheStore<Recipe>(1000 * 60 * 60 * 24 * 7);

router.get("/recipes/search", (req, res) => {
  const q = String(req.query.q ?? "").toLowerCase();
  const items = mockRecipes.filter((r) => r.imageURL && (q.length === 0 || r.title.toLowerCase().includes(q)));
  res.json({ items });
});

router.post("/recipes/recommend", (req, res) => {
  const payload = req.body as RecommendPayload;
  const items = rankRecipes(mockRecipes, payload);
  res.json({ items });
});

router.post("/recipes/fetch", async (req, res, next) => {
  try {
    const url = String(req.body?.url ?? "");
    if (!url) {
      return res.status(400).json({ error: "url is required" });
    }

    const cached = recipeCache.get(url);
    if (cached) {
      return res.json(cached);
    }

    const parsed = await fetchAndParseRecipe(url);
    if (!parsed.imageURL) {
      return res.status(422).json({ error: "Recipe has no image" });
    }

    recipeCache.set(url, parsed);
    return res.json(parsed);
  } catch (error) {
    next(error);
  }
});

router.get("/barcode/lookup", (req, res) => {
  const code = String(req.query.code ?? "");
  if (!code) {
    return res.status(400).json({ error: "code is required" });
  }

  const found = code === "4601234567890";
  res.json({
    found,
    provider: found ? "mock-rf-provider" : null,
    product: found
      ? {
          barcode: code,
          name: "Молоко 2.5%",
          brand: "Пример",
          category: "Молочные продукты"
        }
      : null
  });
});

export default router;
