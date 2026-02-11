import { Router } from "express";
import { defaultRecipeSourceWhitelist, recipeSourceWhitelistFromEnv } from "../config/recipeSources.js";
import { mockRecipes } from "../data/mockRecipes.js";
import { rankRecipes } from "../services/recommendation.js";
import { CacheStore } from "../services/cacheStore.js";
import { fetchAndParseRecipe, RecipeScraperError } from "../services/recipeScraper.js";
import { RecipeIndex } from "../services/recipeIndex.js";
import { isURLAllowedByWhitelist, parseRecipeURL } from "../services/sourcePolicy.js";
import type { RecommendPayload, Recipe } from "../types/contracts.js";

const router = Router();
const recipeCache = new CacheStore<Recipe>(1000 * 60 * 60 * 24 * 7, 10_000);
const recipeIndex = new RecipeIndex(mockRecipes);
const sourceWhitelist = recipeSourceWhitelistFromEnv(process.env.RECIPE_SOURCE_WHITELIST, defaultRecipeSourceWhitelist);

const fetchRateLimitState = new Map<string, { count: number; resetAt: number }>();
const FETCH_RATE_LIMIT_WINDOW_MS = Number(process.env.RECIPE_FETCH_RATE_WINDOW_MS ?? 60_000);
const FETCH_RATE_LIMIT_MAX = Number(process.env.RECIPE_FETCH_RATE_MAX ?? 30);

router.get("/recipes/search", (req, res) => {
  const q = String(req.query.q ?? "");
  const cuisine = String(req.query.cuisine ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
  const limit = Number(req.query.limit ?? 50);
  const items = recipeIndex.search({ query: q, cuisine, limit });
  res.json({ items });
});

router.post("/recipes/recommend", (req, res) => {
  const payload = req.body as RecommendPayload;
  const items = rankRecipes(recipeIndex.all(), payload);
  res.json({ items });
});

router.post("/recipes/fetch", async (req, res, next) => {
  try {
    const rateLimitKey = requestRateLimitKey(req);
    if (!consumeFetchRateLimit(rateLimitKey)) {
      return res.status(429).json({ error: "rate_limited", retryInSeconds: Math.ceil(FETCH_RATE_LIMIT_WINDOW_MS / 1000) });
    }

    const url = String(req.body?.url ?? "");
    if (!url) {
      return res.status(400).json({ error: "url is required" });
    }

    const parsedURL = parseRecipeURL(url);
    if (!parsedURL) {
      return res.status(400).json({ error: "invalid_url" });
    }

    if (!isURLAllowedByWhitelist(parsedURL, sourceWhitelist)) {
      return res.status(403).json({ error: "source_not_allowed" });
    }

    const normalizedURL = parsedURL.toString();
    const cached = recipeCache.get(normalizedURL);
    if (cached) {
      return res.json(cached);
    }

    const parsed = await fetchAndParseRecipe(normalizedURL);
    if (!parsed.imageURL) {
      return res.status(422).json({ error: "Recipe has no image" });
    }

    recipeCache.set(normalizedURL, parsed);
    recipeIndex.upsert(parsed);
    return res.json(parsed);
  } catch (error) {
    if (error instanceof RecipeScraperError) {
      switch (error.code) {
        case "recipe_not_found":
          return res.status(422).json({ error: "recipe_schema_not_found" });
        case "missing_image":
          return res.status(422).json({ error: "recipe_image_required" });
        case "missing_ingredients":
          return res.status(422).json({ error: "recipe_ingredients_required" });
        case "missing_instructions":
          return res.status(422).json({ error: "recipe_instructions_required" });
        case "timeout":
          return res.status(504).json({ error: "upstream_timeout" });
        default:
          return res.status(502).json({ error: "upstream_fetch_failed" });
      }
    }

    next(error);
  }
});

router.get("/recipes/sources", (_req, res) => {
  res.json({
    sources: sourceWhitelist,
    cacheSize: recipeCache.size()
  });
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

function requestRateLimitKey(req: { ip?: string; headers: Record<string, unknown> }): string {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim()) {
    return forwarded.split(",")[0]!.trim();
  }
  return req.ip ?? "unknown";
}

function consumeFetchRateLimit(key: string): boolean {
  if (FETCH_RATE_LIMIT_MAX <= 0) {
    return true;
  }

  const now = Date.now();
  const existing = fetchRateLimitState.get(key);
  if (!existing || existing.resetAt <= now) {
    fetchRateLimitState.set(key, { count: 1, resetAt: now + FETCH_RATE_LIMIT_WINDOW_MS });
    return true;
  }

  if (existing.count >= FETCH_RATE_LIMIT_MAX) {
    return false;
  }

  existing.count += 1;
  fetchRateLimitState.set(key, existing);
  return true;
}
