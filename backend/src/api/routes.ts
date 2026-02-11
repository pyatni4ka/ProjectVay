import { Router } from "express";
import { defaultRecipeSourceWhitelist, recipeSourceWhitelistFromEnv } from "../config/recipeSources.js";
import { mockRecipes } from "../data/mockRecipes.js";
import { generateMealPlan } from "../services/mealPlan.js";
import { rankRecipes } from "../services/recommendation.js";
import { CacheStore } from "../services/cacheStore.js";
import { PersistentRecipeCache } from "../services/persistentRecipeCache.js";
import { fetchAndParseRecipe, RecipeScraperError } from "../services/recipeScraper.js";
import { RecipeIndex } from "../services/recipeIndex.js";
import { lookupBarcode, type BarcodeLookupResult } from "../services/barcodeLookup.js";
import { isURLAllowedByWhitelist, parseRecipeURL } from "../services/sourcePolicy.js";
import type { MealPlanRequest, RecommendPayload, Recipe } from "../types/contracts.js";

const router = Router();
const recipeCacheTTLSeconds = Number(process.env.RECIPE_CACHE_TTL_SECONDS ?? 60 * 60 * 24 * 7);
const recipeCache = new CacheStore<Recipe>(recipeCacheTTLSeconds * 1000, 10_000);
const persistentRecipeCache = makePersistentRecipeCache();
const recipeIndex = new RecipeIndex(mockRecipes);
for (const recipe of persistentRecipeCache?.listActive(10_000) ?? []) {
  recipeIndex.upsert(recipe);
}
const sourceWhitelist = recipeSourceWhitelistFromEnv(process.env.RECIPE_SOURCE_WHITELIST, defaultRecipeSourceWhitelist);
const barcodeLookupCacheTTLSeconds = Number(process.env.BARCODE_LOOKUP_CACHE_TTL_SECONDS ?? 60 * 60 * 24);
const barcodeLookupCache = new CacheStore<BarcodeLookupResult>(barcodeLookupCacheTTLSeconds * 1000, 20_000);

const fetchRateLimitState = new Map<string, { count: number; resetAt: number }>();
const FETCH_RATE_LIMIT_WINDOW_MS = Number(process.env.RECIPE_FETCH_RATE_WINDOW_MS ?? 60_000);
const FETCH_RATE_LIMIT_MAX = Number(process.env.RECIPE_FETCH_RATE_MAX ?? 30);
const barcodeLookupRateLimitState = new Map<string, { count: number; resetAt: number }>();
const BARCODE_LOOKUP_RATE_LIMIT_WINDOW_MS = Number(process.env.BARCODE_LOOKUP_RATE_WINDOW_MS ?? 60_000);
const BARCODE_LOOKUP_RATE_LIMIT_MAX = Number(process.env.BARCODE_LOOKUP_RATE_MAX ?? 120);

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

    const persisted = persistentRecipeCache?.get(normalizedURL);
    if (persisted) {
      recipeCache.set(normalizedURL, persisted);
      recipeIndex.upsert(persisted);
      return res.json(persisted);
    }

    const parsed = await fetchAndParseRecipe(normalizedURL);
    if (!parsed.imageURL) {
      return res.status(422).json({ error: "Recipe has no image" });
    }

    recipeCache.set(normalizedURL, parsed);
    persistentRecipeCache?.set(normalizedURL, parsed);
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
    cacheSize: recipeCache.size(),
    persistentCacheSize: persistentRecipeCache?.size() ?? 0,
    persistentCacheEnabled: Boolean(persistentRecipeCache)
  });
});

router.post("/meal-plan/generate", (req, res) => {
  const payload = normalizeMealPlanPayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_meal_plan_payload" });
  }

  const plan = generateMealPlan(recipeIndex.all(), payload);
  res.json(plan);
});

router.get("/barcode/lookup", (req, res) => {
  const code = String(req.query.code ?? "");
  if (!code) {
    return res.status(400).json({ error: "code is required" });
  }

  const rateLimitKey = requestRateLimitKey(req);
  if (!consumeRateLimit(barcodeLookupRateLimitState, rateLimitKey, BARCODE_LOOKUP_RATE_LIMIT_MAX, BARCODE_LOOKUP_RATE_LIMIT_WINDOW_MS)) {
    return res.status(429).json({ error: "rate_limited", retryInSeconds: Math.ceil(BARCODE_LOOKUP_RATE_LIMIT_WINDOW_MS / 1000) });
  }

  const cached = barcodeLookupCache.get(code);
  if (cached) {
    return res.json(cached);
  }

  void (async () => {
    const result = await lookupBarcode(code, {
      eanDbApiKey: process.env.EAN_DB_API_KEY,
      eanDbEndpoint: process.env.EAN_DB_API_URL,
      openFoodFactsEnabled: process.env.BARCODE_ENABLE_OPEN_FOOD_FACTS !== "false"
    });
    barcodeLookupCache.set(code, result);
    return res.json(result);
  })().catch((error: unknown) => {
    console.error(error);
    return res.status(502).json({ error: "barcode_lookup_failed" });
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
  return consumeRateLimit(fetchRateLimitState, key, FETCH_RATE_LIMIT_MAX, FETCH_RATE_LIMIT_WINDOW_MS);
}

function consumeRateLimit(
  state: Map<string, { count: number; resetAt: number }>,
  key: string,
  max: number,
  windowMs: number
): boolean {
  if (max <= 0) {
    return true;
  }

  const now = Date.now();
  const existing = state.get(key);
  if (!existing || existing.resetAt <= now) {
    state.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }

  if (existing.count >= max) {
    return false;
  }

  existing.count += 1;
  state.set(key, existing);
  return true;
}

function makePersistentRecipeCache(): PersistentRecipeCache | null {
  const dbPath = process.env.RECIPE_CACHE_DB_PATH ?? "data/recipe-cache.sqlite";
  try {
    return new PersistentRecipeCache({
      dbPath,
      ttlSeconds: recipeCacheTTLSeconds
    });
  } catch (error) {
    console.error("[recipe-cache] failed to init persistent cache", error);
    return null;
  }
}

function normalizeMealPlanPayload(body: unknown): MealPlanRequest | null {
  if (!isRecord(body)) {
    return null;
  }

  const ingredientKeywords = toStringArray(body.ingredientKeywords);
  const expiringSoonKeywords = toStringArray(body.expiringSoonKeywords);
  if (ingredientKeywords.length === 0 && expiringSoonKeywords.length === 0) {
    return null;
  }

  const targets = isRecord(body.targets) ? body.targets : {};

  return {
    days: toOptionalNumber(body.days),
    ingredientKeywords,
    expiringSoonKeywords,
    targets: {
      kcal: toOptionalNumber(targets.kcal),
      protein: toOptionalNumber(targets.protein),
      fat: toOptionalNumber(targets.fat),
      carbs: toOptionalNumber(targets.carbs)
    },
    beveragesKcal: toOptionalNumber(body.beveragesKcal),
    budget: isRecord(body.budget)
      ? {
          perDay: toOptionalNumber(body.budget.perDay),
          perMeal: toOptionalNumber(body.budget.perMeal)
        }
      : undefined,
    exclude: toOptionalStringArray(body.exclude),
    avoidBones: typeof body.avoidBones === "boolean" ? body.avoidBones : undefined,
    cuisine: toOptionalStringArray(body.cuisine)
  };
}

function toStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function toOptionalStringArray(value: unknown): string[] | undefined {
  const array = toStringArray(value);
  return array.length > 0 ? array : undefined;
}

function toOptionalNumber(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
