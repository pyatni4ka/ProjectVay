import { Router } from "express";
import { defaultRecipeSourceWhitelist, recipeSourceWhitelistFromEnv } from "../../config/recipeSources.js";
import { mockRecipes } from "../../data/mockRecipes.js";
import { generateMealPlan } from "../../services/mealPlan.js";
import { rankRecipes } from "../../services/recommendation.js";
import { CacheStore } from "../../services/cacheStore.js";
import { PersistentRecipeCache } from "../../services/persistentRecipeCache.js";
import { fetchAndParseRecipe, RecipeScraperError } from "../../services/recipeScraper.js";
import { RecipeIndex } from "../../services/recipeIndex.js";
import { isURLAllowedByWhitelist, parseRecipeURL } from "../../services/sourcePolicy.js";
import { lookupBarcode, type BarcodeLookupResult } from "../../services/barcodeLookup.js";
import { searchExternalRecipes } from "../../services/externalRecipes.js";
import { personalizeRecipes, buildUserTasteProfile } from "../../services/personalization.js";
import { getEnv } from "../../config/env.js";
import type { MealPlanRequest, RecommendPayload, Recipe, UserMealHistory } from "../../types/contracts.js";

const router = Router();
const env = getEnv();
const recipeCacheTTLSeconds = env.RECIPE_CACHE_TTL_SECONDS;
const recipeCache = new CacheStore<Recipe>(recipeCacheTTLSeconds * 1000, 10_000);
const barcodeLookupCacheTTLSeconds = Number(process.env.BARCODE_LOOKUP_CACHE_TTL_SECONDS ?? 60 * 60 * 24);
const barcodeLookupCache = new CacheStore<BarcodeLookupResult>(barcodeLookupCacheTTLSeconds * 1000, 25_000);
const persistentRecipeCache = makePersistentRecipeCache();
const recipeIndex = new RecipeIndex(mockRecipes);
for (const recipe of persistentRecipeCache?.listActive(10_000) ?? []) {
  recipeIndex.upsert(recipe);
}
const sourceWhitelist = recipeSourceWhitelistFromEnv(process.env.RECIPE_SOURCE_WHITELIST, defaultRecipeSourceWhitelist);

const fetchRateLimitState = new Map<string, { count: number; resetAt: number }>();
const FETCH_RATE_LIMIT_WINDOW_MS = Number(process.env.RECIPE_FETCH_RATE_WINDOW_MS ?? 60_000);
const FETCH_RATE_LIMIT_MAX = Number(process.env.RECIPE_FETCH_RATE_MAX ?? 30);
const barcodeRateLimitState = new Map<string, { count: number; resetAt: number }>();
const BARCODE_RATE_LIMIT_WINDOW_MS = Number(process.env.BARCODE_LOOKUP_RATE_WINDOW_MS ?? 60_000);
const BARCODE_RATE_LIMIT_MAX = Number(process.env.BARCODE_LOOKUP_RATE_MAX ?? 120);
const userHistoryStore = new Map<string, UserMealHistory>();

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

router.get("/recipes/filter", async (req, res) => {
  const query = String(req.query.q ?? "");
  const includeExternal = parseBoolean(String(req.query.external ?? "true"), true);
  const cuisine = String(req.query.cuisine ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
  const maxPrepTime = toOptionalNumber(req.query.maxPrepTime);
  const maxCalories = toOptionalNumber(req.query.maxCalories);
  const minProtein = toOptionalNumber(req.query.minProtein);
  const difficulty = toOptionalStringArray(req.query.difficulty)?.filter((item): item is "easy" | "medium" | "hard" =>
    ["easy", "medium", "hard"].includes(item)
  );
  const diet = toOptionalStringArray(req.query.diet);

  const localCandidates = recipeIndex.search({ query, cuisine, limit: 100 });

  const payload: RecommendPayload = {
    ingredientKeywords: query ? [query] : [],
    expiringSoonKeywords: [],
    targets: {},
    cuisine,
    maxPrepTime: maxPrepTime ?? undefined,
    maxCalories: maxCalories ?? undefined,
    minProtein: minProtein ?? undefined,
    difficulty,
    diets: diet as any,
    limit: 100
  };

  let candidates = rankRecipes(localCandidates, payload).map((item) => item.recipe);

  if (includeExternal) {
    const external = await searchExternalRecipes({
      query,
      ingredients: query ? [query] : undefined,
      cuisine: cuisine[0],
      maxCalories: maxCalories ?? undefined,
      limit: 30
    });
    const merged = dedupeRecipes([...candidates, ...external.recipes]);
    candidates = rankRecipes(merged, payload).map((item) => item.recipe);
  }

  res.json({
    items: candidates.slice(0, 50),
    total: candidates.length
  });
});

router.post("/recipes/recommend", (req, res) => {
  const payload = normalizeRecommendPayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_recommend_payload" });
  }
  const items = rankRecipes(recipeIndex.all(), payload);
  res.json({ items });
});

router.post("/user/history", (req, res) => {
  if (!isRecord(req.body)) {
    return res.status(400).json({ error: "invalid_history_payload" });
  }

  const userId = String(req.body.userId ?? "").trim();
  if (!userId) {
    return res.status(400).json({ error: "userId is required" });
  }

  const history: UserMealHistory = {
    userId,
    meals: Array.isArray(req.body.meals)
      ? req.body.meals
        .filter((item): item is { date: string; recipeId: string; mealType: "breakfast" | "lunch" | "dinner" | "snack"; rating?: number } =>
          isRecord(item) && typeof item.date === "string" && typeof item.recipeId === "string" && typeof item.mealType === "string"
        )
      : [],
    preferences: {
      favoriteCuisines: toStringArray((req.body.preferences as any)?.favoriteCuisines),
      dislikedIngredients: toStringArray((req.body.preferences as any)?.dislikedIngredients),
      dietTypes: toStringArray((req.body.preferences as any)?.dietTypes) as any
    }
  };

  userHistoryStore.set(userId, history);
  res.json({ ok: true, savedMeals: history.meals.length });
});

router.get("/user/:userId/taste-profile", (req, res) => {
  const userId = String(req.params.userId ?? "").trim();
  const history = userHistoryStore.get(userId);
  if (!history) {
    return res.status(404).json({ error: "history_not_found" });
  }

  const profile = buildUserTasteProfile(history);
  return res.json(profile);
});

router.post("/recipes/recommend/personalized", (req, res) => {
  const payload = normalizeRecommendPayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_recommend_payload" });
  }

  const userId = String(req.body?.userId ?? "").trim();
  const history = userId ? userHistoryStore.get(userId) ?? null : null;

  const ranked = rankRecipes(recipeIndex.all(), payload);
  const personalized = personalizeRecipes(
    ranked.map((item) => item.recipe),
    history
  );

  return res.json({
    items: personalized.slice(0, payload.limit ?? 30),
    personalizationApplied: Boolean(history)
  });
});

router.get("/recipes/external/search", async (req, res) => {
  const query = String(req.query.q ?? "").trim();
  if (!query) {
    return res.status(400).json({ error: "q is required" });
  }

  const response = await searchExternalRecipes({
    query,
    ingredients: String(req.query.ingredients ?? "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean),
    cuisine: toOptionalString(req.query.cuisine),
    mealType: toOptionalString(req.query.mealType) as any,
    diet: toOptionalString(req.query.diet) as any,
    maxCalories: toOptionalNumber(req.query.maxCalories),
    limit: toOptionalNumber(req.query.limit) ?? 20
  });

  return res.json(response);
});

router.post("/recipes/fetch", async (req, res, next) => {
  try {
    const rateLimitKey = requestRateLimitKey(req);
    if (!consumeRateLimit(fetchRateLimitState, rateLimitKey, FETCH_RATE_LIMIT_MAX, FETCH_RATE_LIMIT_WINDOW_MS)) {
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
    persistentCacheEnabled: persistentRecipeCache?.isPersistent ?? false
  });
});

router.post("/meal-plan/generate", async (req, res) => {
  const payload = normalizeMealPlanPayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_meal_plan_payload" });
  }

  let pool = recipeIndex.all();
  const includeExternal = Boolean(req.body?.includeExternal);
  if (includeExternal) {
    const external = await searchExternalRecipes({
      query: payload.ingredientKeywords.join(" "),
      ingredients: payload.ingredientKeywords,
      cuisine: payload.cuisine?.[0],
      maxCalories: payload.targets.kcal,
      limit: 40
    });
    pool = dedupeRecipes([...pool, ...external.recipes]);
  }

  const plan = generateMealPlan(pool, payload);
  res.json(plan);
});

router.post("/meal-plan/optimize", (req, res) => {
  const payload = normalizeMealPlanPayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_meal_plan_payload" });
  }

  const optimizedPayload: MealPlanRequest = {
    ...payload,
    avoidRepetition: true,
    balanceMacros: true,
    maxPrepTime: payload.maxPrepTime ?? 45,
    days: payload.days ?? 7
  };

  const plan = generateMealPlan(recipeIndex.all(), optimizedPayload);
  return res.json({
    ...plan,
    optimization: {
      avoidRepetition: true,
      balancedMacros: true,
      maxPrepTime: optimizedPayload.maxPrepTime
    }
  });
});

router.get("/barcode/lookup", async (req, res) => {
  const code = String(req.query.code ?? "");
  if (!code) {
    return res.status(400).json({ error: "code is required" });
  }

  const normalizedCode = code.trim();
  if (!normalizedCode) {
    return res.status(400).json({ error: "code is required" });
  }

  const rateLimitKey = requestRateLimitKey(req);
  if (!consumeRateLimit(barcodeRateLimitState, rateLimitKey, BARCODE_RATE_LIMIT_MAX, BARCODE_RATE_LIMIT_WINDOW_MS)) {
    return res.status(429).json({ error: "rate_limited", retryInSeconds: Math.ceil(BARCODE_RATE_LIMIT_WINDOW_MS / 1000) });
  }

  const cached = barcodeLookupCache.get(normalizedCode);
  if (cached) {
    return res.json(cached);
  }

  const result = await lookupBarcode({
    code: normalizedCode,
    eanDBApiKey: process.env.EAN_DB_API_KEY,
    eanDBApiURL: process.env.EAN_DB_API_URL,
    enableOpenFoodFacts: parseBoolean(process.env.BARCODE_ENABLE_OPEN_FOOD_FACTS, true),
    enableBarcodeListRu: parseBoolean(process.env.BARCODE_ENABLE_BARCODE_LIST_RU, true),
    timeoutMs: Number(process.env.BARCODE_LOOKUP_TIMEOUT_MS ?? 3_000)
  });

  barcodeLookupCache.set(normalizedCode, result);
  return res.json(result);
});

export default router;

function requestRateLimitKey(req: { ip?: string; headers: Record<string, unknown> }): string {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim()) {
    return forwarded.split(",")[0]!.trim();
  }
  return req.ip ?? "unknown";
}

function consumeRateLimit(
  state: Map<string, { count: number; resetAt: number }>,
  key: string,
  maxPerWindow: number,
  windowMs: number
): boolean {
  if (maxPerWindow <= 0) {
    return true;
  }

  const now = Date.now();
  const existing = state.get(key);
  if (!existing || existing.resetAt <= now) {
    state.set(key, { count: 1, resetAt: now + windowMs });
    return true;
  }

  if (existing.count >= maxPerWindow) {
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
    cuisine: toOptionalStringArray(body.cuisine),
    mealSchedule: isRecord(body.mealSchedule)
      ? {
        breakfastStart: toOptionalNumber(body.mealSchedule.breakfastStart),
        breakfastEnd: toOptionalNumber(body.mealSchedule.breakfastEnd),
        lunchStart: toOptionalNumber(body.mealSchedule.lunchStart),
        lunchEnd: toOptionalNumber(body.mealSchedule.lunchEnd),
        dinnerStart: toOptionalNumber(body.mealSchedule.dinnerStart),
        dinnerEnd: toOptionalNumber(body.mealSchedule.dinnerEnd)
      }
      : undefined,
    maxPrepTime: toOptionalNumber(body.maxPrepTime),
    difficulty: toOptionalStringArray(body.difficulty) as any,
    diets: toOptionalStringArray(body.diets) as any,
    balanceMacros: toOptionalBoolean(body.balanceMacros),
    avoidRepetition: toOptionalBoolean(body.avoidRepetition),
    userHistory: toOptionalStringArray(body.userHistory)
  };
}

function normalizeRecommendPayload(body: unknown): RecommendPayload | null {
  if (!isRecord(body)) {
    return null;
  }

  const ingredientKeywords = toStringArray(body.ingredientKeywords);
  const expiringSoonKeywords = toStringArray(body.expiringSoonKeywords);
  if (ingredientKeywords.length === 0 && expiringSoonKeywords.length === 0) {
    return null;
  }

  const targets = isRecord(body.targets) ? body.targets : {};
  const limit = toOptionalNumber(body.limit);

  return {
    ingredientKeywords,
    expiringSoonKeywords,
    targets: {
      kcal: toOptionalNumber(targets.kcal),
      protein: toOptionalNumber(targets.protein),
      fat: toOptionalNumber(targets.fat),
      carbs: toOptionalNumber(targets.carbs)
    },
    budget: isRecord(body.budget)
      ? {
        perMeal: toOptionalNumber(body.budget.perMeal)
      }
      : undefined,
    exclude: toOptionalStringArray(body.exclude),
    avoidBones: toOptionalBoolean(body.avoidBones),
    cuisine: toOptionalStringArray(body.cuisine),
    limit: limit ? Math.max(1, Math.min(Math.floor(limit), 100)) : undefined,
    strictNutrition: toOptionalBoolean(body.strictNutrition),
    macroTolerancePercent: toOptionalNumber(body.macroTolerancePercent),
    maxPrepTime: toOptionalNumber(body.maxPrepTime),
    difficulty: toOptionalStringArray(body.difficulty) as any,
    diets: toOptionalStringArray(body.diets) as any,
    seasons: toOptionalStringArray(body.seasons) as any,
    mealTypes: toOptionalStringArray(body.mealTypes) as any,
    maxCalories: toOptionalNumber(body.maxCalories),
    minProtein: toOptionalNumber(body.minProtein),
    excludeRecentRecipes: toOptionalStringArray(body.excludeRecentRecipes),
    diversityWeight: toOptionalNumber(body.diversityWeight)
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

function toOptionalString(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
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

function toOptionalBoolean(value: unknown): boolean | undefined {
  if (typeof value === "boolean") {
    return value;
  }

  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    if (["1", "true", "yes", "on"].includes(normalized)) {
      return true;
    }
    if (["0", "false", "no", "off"].includes(normalized)) {
      return false;
    }
  }

  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function parseBoolean(value: string | undefined, fallback: boolean): boolean {
  if (!value) {
    return fallback;
  }

  const normalized = value.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(normalized)) {
    return false;
  }
  return fallback;
}

function dedupeRecipes(items: Recipe[]): Recipe[] {
  const byId = new Map<string, Recipe>();
  for (const item of items) {
    byId.set(item.id, item);
  }
  return Array.from(byId.values());
}
