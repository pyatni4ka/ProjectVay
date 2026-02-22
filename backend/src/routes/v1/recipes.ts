import { Router } from "express";
import { defaultRecipeSourceWhitelist, recipeSourceWhitelistFromEnv } from "../../config/recipeSources.js";
import { mockRecipes } from "../../data/mockRecipes.js";
import { generateMealPlan } from "../../services/mealPlan.js";
import { generateWeeklyAutopilot, generateReplaceCandidates, adaptPlanAfterDeviation } from "../../services/weeklyAutopilot.js";
import { rankRecipes, rankRecipesV2 } from "../../services/recommendation.js";
import { CacheStore } from "../../services/cacheStore.js";
import { PersistentRecipeCache } from "../../services/persistentRecipeCache.js";
import { fetchAndParseRecipe, fetchAndParseRecipeDetailed, RecipeScraperError } from "../../services/recipeScraper.js";
import { RecipeIndex } from "../../services/recipeIndex.js";
import { isURLAllowedByWhitelist, parseRecipeURL } from "../../services/sourcePolicy.js";
import { lookupBarcode, type BarcodeLookupResult } from "../../services/barcodeLookup.js";
import { searchExternalRecipes } from "../../services/externalRecipes.js";
import { estimateIngredientsPrice } from "../../services/priceEstimator.js";
import { buildRecommendationReasons } from "../../services/recommendationExplanation.js";
import { UserFeedbackStore } from "../../services/userFeedbackStore.js";
import { suggestIngredientSubstitutions } from "../../services/ingredientSubstitutions.js";
import { getEnv } from "../../config/env.js";
import type {
  MealPlanRequest,
  PriceEstimateRequest,
  RecommendPayload,
  Recipe,
  SmartMealPlanRequest,
  UserFeedbackEvent,
  WeeklyAutopilotRequest,
  ReplaceMealRequest,
  AdaptPlanRequest,
} from "../../types/contracts.js";

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
const userFeedbackStore = makeUserFeedbackStore();

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

  const historyEvents = Array.isArray(req.body.meals)
    ? req.body.meals
      .filter((item): item is { date: string; recipeId: string; mealType: "breakfast" | "lunch" | "dinner" | "snack"; rating?: number } =>
        isRecord(item) && typeof item.date === "string" && typeof item.recipeId === "string" && typeof item.mealType === "string"
      )
      .map((meal) => ({
        userId,
        recipeId: meal.recipeId,
        eventType: (meal.rating != null && meal.rating < 3 ? "recipe_dislike" : "recipe_cook") as UserFeedbackEvent["eventType"],
        timestamp: meal.date,
        value: meal.rating != null ? Math.max(-2, Math.min(2, meal.rating - 3)) : undefined
      }))
    : [];

  const saved = userFeedbackStore?.appendEvents(userId, historyEvents) ?? 0;
  res.json({ ok: true, savedMeals: saved });
});

router.get("/user/:userId/taste-profile", (req, res) => {
  const userId = String(req.params.userId ?? "").trim();
  if (!userId) return res.status(400).json({ error: "userId is required" });
  if (!userFeedbackStore) return res.status(503).json({ error: "storage_unavailable" });

  const profile = userFeedbackStore.buildTasteProfile(userId, recipeIndex.all());
  return res.json(profile);
});

router.post("/user/events", (req, res) => {
  if (!isRecord(req.body)) {
    return res.status(400).json({ error: "invalid_events_payload" });
  }

  const userId = String(req.body.userId ?? "").trim();
  if (!userId) {
    return res.status(400).json({ error: "userId is required" });
  }
  if (!userFeedbackStore) {
    return res.status(503).json({ error: "storage_unavailable" });
  }

  const events = Array.isArray(req.body.events) ? req.body.events : [];
  const saved = userFeedbackStore.appendEvents(userId, events as Array<Partial<UserFeedbackEvent>>);
  return res.json({ ok: true, saved });
});

router.get("/user/:userId/profile", (req, res) => {
  const userId = String(req.params.userId ?? "").trim();
  if (!userId) return res.status(400).json({ error: "userId is required" });
  if (!userFeedbackStore) return res.status(503).json({ error: "storage_unavailable" });

  const profile = userFeedbackStore.buildTasteProfile(userId, recipeIndex.all());
  return res.json(profile);
});

router.post("/recipes/recommend/v2", async (req, res) => {
  const payload = normalizeRecommendPayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_recommend_payload" });
  }
  if (!env.RECOMMEND_V2_ENABLED) {
    return res.status(404).json({ error: "recommend_v2_disabled" });
  }

  const userId = String(req.body?.userId ?? "").trim();
  const profile = userId && userFeedbackStore
    ? userFeedbackStore.buildTasteProfile(userId, recipeIndex.all())
    : null;

  const ranked = rankRecipesV2(recipeIndex.all(), payload, { tasteProfile: profile });
  const includeReasons = toOptionalBoolean(req.body?.includeReasons) ?? true;

  return res.json({
    items: ranked.slice(0, payload.limit ?? 30).map((item) => ({
      recipe: item.recipe,
      score: item.score,
      reasons: includeReasons ? buildRecommendationReasons({
        recipe: item.recipe,
        scoreBreakdown: item.scoreBreakdown,
        maxReasons: 3
      }) : [],
      scoreBreakdown: item.scoreBreakdown
    })),
    personalizationApplied: Boolean(profile && profile.totalEvents > 0),
    profileConfidence: profile?.confidence ?? 0
  });
});

router.post("/recipes/recommend/personalized", (req, res) => {
  const payload = normalizeRecommendPayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_recommend_payload" });
  }

  const userId = String(req.body?.userId ?? "").trim();
  const profile = userId && userFeedbackStore
    ? userFeedbackStore.buildTasteProfile(userId, recipeIndex.all())
    : null;
  const ranked = rankRecipesV2(recipeIndex.all(), payload, { tasteProfile: profile });
  const personalized = ranked.map((item) => item.recipe);

  return res.json({
    items: personalized.slice(0, payload.limit ?? 30),
    personalizationApplied: Boolean(profile && profile.totalEvents > 0)
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

router.post("/recipes/parse", async (req, res, next) => {
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

    const parsed = await fetchAndParseRecipeDetailed(parsedURL.toString());
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

router.post("/prices/estimate", async (req, res) => {
  const payload = normalizePriceEstimatePayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_price_estimate_payload" });
  }

  const result = await estimateIngredientsPrice(payload);
  return res.json(result);
});

router.get("/prices/compare", async (req, res) => {
  const ingredients = String(req.query.ingredients ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  if (ingredients.length === 0) {
    return res.status(400).json({ error: "ingredients is required" });
  }

  const estimate = await estimateIngredientsPrice({
    ingredients,
    region: "RU",
    currency: "RUB"
  });

  const baseline = estimate.totalEstimatedRub;
  const substitutionHints = suggestIngredientSubstitutions(ingredients, 20);
  const potentialSavingsRub = substitutionHints
    .map((item) => item.estimatedSavingsRub ?? 0)
    .reduce((sum, value) => sum + value, 0);

  return res.json({
    items: estimate.items,
    totalEstimatedRub: baseline,
    estimatedBestCaseRub: Math.max(0, baseline - potentialSavingsRub),
    potentialSavingsRub,
    substitutions: substitutionHints,
    confidence: estimate.confidence,
    missingIngredients: estimate.missingIngredients
  });
});

router.post("/meal-plan/smart-generate", async (req, res) => {
  const payload = normalizeSmartMealPlanPayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_meal_plan_payload" });
  }

  const response = await buildSmartMealPlanResponse(payload, Boolean(req.body?.includeExternal));
  return res.json(response);
});

router.post("/meal-plan/smart-v2", async (req, res) => {
  const payload = normalizeSmartMealPlanPayload(req.body);
  if (!payload) {
    return res.status(400).json({ error: "invalid_meal_plan_payload" });
  }

  const response = await buildSmartMealPlanResponse(payload, Boolean(req.body?.includeExternal), {
    includeRecommendationReasons: true,
    includeSubstitutions: true
  });
  return res.json(response);
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

// ---------------------------------------------------------------------------
// Weekly Autopilot: generate full 7-day plan with per-meal targets, quantities, budget
// ---------------------------------------------------------------------------
router.post("/meal-plan/week", async (req, res) => {
  const body = req.body;
  if (!isRecord(body)) {
    return res.status(400).json({ error: "invalid_request_body" });
  }

  const targets = isRecord(body.targets) ? body.targets : {};
  const budget = isRecord(body.budget) ? body.budget : undefined;
  const constraints = isRecord(body.constraints) ? body.constraints : undefined;

  const payload: WeeklyAutopilotRequest = {
    days: toOptionalNumber(body.days) ?? 7,
    startDate: typeof body.startDate === "string" ? body.startDate : undefined,
    mealsPerDay: toOptionalNumber(body.mealsPerDay) ?? 3,
    includeSnacks: Boolean(body.includeSnacks),
    ingredientKeywords: Array.isArray(body.ingredientKeywords)
      ? body.ingredientKeywords.filter((k: unknown) => typeof k === "string")
      : [],
    expiringSoonKeywords: Array.isArray(body.expiringSoonKeywords)
      ? body.expiringSoonKeywords.filter((k: unknown) => typeof k === "string")
      : [],
    targets: {
      kcal: toOptionalNumber(targets.kcal),
      protein: toOptionalNumber(targets.protein),
      fat: toOptionalNumber(targets.fat),
      carbs: toOptionalNumber(targets.carbs),
    },
    beveragesKcal: toOptionalNumber(body.beveragesKcal),
    budget: budget
      ? {
        perDay: toOptionalNumber(budget.perDay),
        perMeal: toOptionalNumber(budget.perMeal),
        perWeek: toOptionalNumber(budget.perWeek),
        perMonth: toOptionalNumber(budget.perMonth),
        strictness: typeof budget.strictness === "string" ? budget.strictness as "strict" | "soft" : "soft",
        softLimitPct: toOptionalNumber(budget.softLimitPct) ?? 5,
      }
      : undefined,
    exclude: Array.isArray(body.exclude) ? body.exclude.filter((e: unknown) => typeof e === "string") : [],
    avoidBones: Boolean(body.avoidBones),
    cuisine: Array.isArray(body.cuisine) ? body.cuisine.filter((c: unknown) => typeof c === "string") : [],
    effortLevel: typeof body.effortLevel === "string" ? body.effortLevel as "quick" | "standard" | "complex" : "standard",
    seed: toOptionalNumber(body.seed),
    inventorySnapshot: Array.isArray(body.inventorySnapshot) ? body.inventorySnapshot.filter((s: unknown) => typeof s === "string") : [],
    constraints: constraints
      ? {
        diets: Array.isArray(constraints.diets) ? constraints.diets : undefined,
        allergies: Array.isArray(constraints.allergies) ? constraints.allergies : undefined,
        dislikes: Array.isArray(constraints.dislikes) ? constraints.dislikes : undefined,
        favorites: Array.isArray(constraints.favorites) ? constraints.favorites : undefined,
      }
      : undefined,
    objective: typeof body.objective === "string" ? body.objective as "cost_macro" | "balanced" : "cost_macro",
    optimizerProfile: typeof body.optimizerProfile === "string" ? body.optimizerProfile as "economy_aggressive" | "balanced" | "macro_precision" : "balanced",
    macroTolerancePercent: toOptionalNumber(body.macroTolerancePercent) ?? 25,
    healthMetrics: isRecord(body.healthMetrics) ? body.healthMetrics as WeeklyAutopilotRequest["healthMetrics"] : undefined,
  };

  let pool = recipeIndex.all();
  const includeExternal = Boolean(body.includeExternal);
  if (includeExternal) {
    const external = await searchExternalRecipes({
      query: payload.ingredientKeywords.join(" "),
      ingredients: payload.ingredientKeywords,
      cuisine: payload.cuisine?.[0],
      maxCalories: payload.targets.kcal,
      limit: 40,
    });
    pool = dedupeRecipes([...pool, ...external.recipes]);
  }

  const plan = generateWeeklyAutopilot(pool, payload);
  return res.json(plan);
});

// ---------------------------------------------------------------------------
// Replace: get replacement candidates for a single meal slot
// ---------------------------------------------------------------------------
router.post("/meal-plan/replace", (req, res) => {
  const body = req.body;
  if (!isRecord(body) || !isRecord(body.currentPlan)) {
    return res.status(400).json({ error: "invalid_replace_request" });
  }

  const payload: ReplaceMealRequest = {
    planId: typeof body.planId === "string" ? body.planId : undefined,
    currentPlan: body.currentPlan as unknown as ReplaceMealRequest["currentPlan"],
    dayIndex: toOptionalNumber(body.dayIndex) ?? 0,
    mealSlot: typeof body.mealSlot === "string" ? body.mealSlot : "lunch",
    sortMode: typeof body.sortMode === "string" ? body.sortMode as "cheap" | "fast" | "protein" | "expiry" : "cheap",
    topN: toOptionalNumber(body.topN) ?? 5,
    budget: isRecord(body.budget) ? body.budget as ReplaceMealRequest["budget"] : undefined,
    inventorySnapshot: Array.isArray(body.inventorySnapshot)
      ? body.inventorySnapshot.filter((s: unknown) => typeof s === "string")
      : [],
    constraints: isRecord(body.constraints) ? body.constraints as ReplaceMealRequest["constraints"] : undefined,
  };

  const pool = recipeIndex.all();
  const result = generateReplaceCandidates(pool, payload);
  return res.json(result);
});

// ---------------------------------------------------------------------------
// Adapt: rebuild remaining plan after deviation (ate out / cheat / different meal)
// ---------------------------------------------------------------------------
router.post("/meal-plan/adapt", async (req, res) => {
  const body = req.body;
  if (!isRecord(body) || !isRecord(body.currentPlan)) {
    return res.status(400).json({ error: "invalid_adapt_request" });
  }

  const eventType = typeof body.eventType === "string"
    ? body.eventType as "ate_out" | "cheat" | "different_meal"
    : "different_meal";
  const impactEstimate = typeof body.impactEstimate === "string"
    ? body.impactEstimate as "small" | "medium" | "large" | "customMacros"
    : "medium";

  const payload: AdaptPlanRequest = {
    planId: typeof body.planId === "string" ? body.planId : undefined,
    currentPlan: body.currentPlan as unknown as AdaptPlanRequest["currentPlan"],
    planningContext: isRecord(body.planningContext) ? body.planningContext as unknown as AdaptPlanRequest["planningContext"] : undefined,
    eventType,
    impactEstimate,
    customMacros: isRecord(body.customMacros) ? body.customMacros as AdaptPlanRequest["customMacros"] : undefined,
    timestamp: typeof body.timestamp === "string" ? body.timestamp : new Date().toISOString(),
    applyScope: body.applyScope === "week" ? "week" : "day",
  };

  const pool = recipeIndex.all();
  const result = adaptPlanAfterDeviation(pool, payload);
  return res.json(result);
});

// ---------------------------------------------------------------------------
// Cook Now: suggest recipes from current inventory (no plan needed)
// ---------------------------------------------------------------------------
router.post("/recipes/cook-now", (req, res) => {
  const body = req.body;
  if (!isRecord(body)) {
    return res.status(400).json({ error: "invalid_request_body" });
  }

  const inventoryKeywords: string[] = Array.isArray(body.inventoryKeywords)
    ? body.inventoryKeywords.filter((k: unknown) => typeof k === "string")
    : [];
  const expiringSoonKeywords: string[] = Array.isArray(body.expiringSoonKeywords)
    ? body.expiringSoonKeywords.filter((k: unknown) => typeof k === "string")
    : [];
  const maxPrepTime = toOptionalNumber(body.maxPrepTime) ?? 45;
  const limit = toOptionalNumber(body.limit) ?? 7;
  const exclude: string[] = Array.isArray(body.exclude)
    ? body.exclude.filter((e: unknown) => typeof e === "string")
    : [];

  const pool = recipeIndex.all();
  const ranked = rankRecipes(pool, {
    ingredientKeywords: inventoryKeywords,
    expiringSoonKeywords,
    targets: {},
    exclude,
    maxPrepTime,
    limit: limit * 4,
  });

  // Filter to recipes where most ingredients are available
  const inventorySet = new Set(inventoryKeywords.map((s) => s.toLowerCase()));
  const withAvailability = ranked.map((item) => {
    const total = item.recipe.ingredients.length || 1;
    const available = item.recipe.ingredients.filter((ing) =>
      inventorySet.has(ing.toLowerCase().split(" ").slice(0, 2).join(" "))
    ).length;
    return { ...item, availabilityRatio: available / total };
  });

  // Sort: primarily by availability ratio (desc), then score
  withAvailability.sort((a, b) => {
    if (b.availabilityRatio !== a.availabilityRatio) return b.availabilityRatio - a.availabilityRatio;
    return b.score - a.score;
  });

  const results = withAvailability.slice(0, limit).map((item) => ({
    recipe: item.recipe,
    score: item.score,
    availabilityRatio: Math.round(item.availabilityRatio * 100),
    matchedFilters: item.matchedFilters,
  }));

  return res.json({ recipes: results, inventoryCount: inventoryKeywords.length });
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

router.post("/recipes/substitute", (req, res) => {
  const body = req.body;
  if (!isRecord(body) || !Array.isArray(body.ingredients)) {
    return res.status(400).json({ error: "invalid_substitute_request" });
  }
  
  const ingredients = toStringArray(body.ingredients);
  if (ingredients.length === 0) {
    return res.status(400).json({ error: "ingredients array is empty or invalid" });
  }
  
  const limit = toOptionalNumber(body.limit) ?? 8;
  const substitutions = suggestIngredientSubstitutions(ingredients, limit);
  
  return res.json({ substitutions });
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

function makeUserFeedbackStore(): UserFeedbackStore | null {
  const dbPath = env.AI_STORE_DB_PATH || process.env.AI_STORE_DB_PATH || "data/ai-store.sqlite";
  try {
    return new UserFeedbackStore({ dbPath });
  } catch (error) {
    console.error("[user-feedback-store] failed to init", error);
    return null;
  }
}

async function buildSmartMealPlanResponse(
  payload: SmartMealPlanRequest,
  includeExternal: boolean,
  options: {
    includeRecommendationReasons?: boolean;
    includeSubstitutions?: boolean;
  } = {}
) {
  let pool = recipeIndex.all();
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

  const objective = payload.objective ?? "cost_macro";
  const optimizerProfile = payload.optimizerProfile ?? "balanced";
  const plan = generateMealPlan(pool, payload, new Date(), {
    objective,
    optimizerProfile,
    macroTolerancePercent: payload.macroTolerancePercent,
    ingredientPriceHints: payload.ingredientPriceHints
  });

  const estimate = await estimateIngredientsPrice({
    ingredients: plan.shoppingList,
    hints: payload.ingredientPriceHints ?? [],
    region: "RU",
    currency: "RUB"
  });

  const substitutions = options.includeSubstitutions
    ? suggestIngredientSubstitutions(plan.shoppingList)
    : [];
  const estimatedSavingsRub = substitutions
    .map((item) => item.estimatedSavingsRub ?? 0)
    .reduce((sum, value) => sum + value, 0);
  const recommendationReasons = options.includeRecommendationReasons
    ? plan.days
      .flatMap((day) => day.entries)
      .map((entry) => ({
        recipeId: entry.recipe.id,
        reasons: buildRecommendationReasons({
          recipe: entry.recipe,
          scoreBreakdown: {
            nutritionFit: entry.kcal > 0 ? clamp(1 - Math.abs((payload.targets.kcal ?? entry.kcal) - entry.kcal) / Math.max(payload.targets.kcal ?? entry.kcal, 1), 0, 1) : 0.5,
            budgetFit: payload.budget?.perMeal
              ? clamp(1 - entry.estimatedCost / Math.max(payload.budget.perMeal, 1), 0, 1)
              : 0.5,
            availabilityFit: overlap(entry.recipe.ingredients, payload.ingredientKeywords),
            prepTimeFit: payload.maxPrepTime
              ? clamp(1 - Math.max((entry.recipe.times?.totalMinutes ?? 0) - payload.maxPrepTime, 0) / Math.max(payload.maxPrepTime, 1), 0, 1)
              : 0.5,
            personalTasteFit: 0.5,
            cuisineFit: payload.cuisine?.includes(entry.recipe.cuisine ?? "") ? 1 : 0.45
          },
          maxReasons: 3
        })
      }))
    : [];

  return {
    ...plan,
    estimatedSavingsRub,
    ingredientSubstitutions: substitutions,
    recommendationReasons,
    objective,
    optimizerProfile,
    costConfidence: estimate.confidence,
    priceExplanation: [
      `Оценка построена для региона RU, валюта RUB.`,
      `Уверенность по цене: ${(estimate.confidence * 100).toFixed(0)}%.`,
      `Профиль оптимизации: ${optimizerProfile}.`,
      plan.optimization
        ? `Оптимизатор: среднее отклонение КБЖУ ${(plan.optimization.averageMacroDeviation * 100).toFixed(0)}%, средняя цена приёма пищи ${plan.optimization.averageMealCost.toFixed(0)} ₽.`
        : "Оптимизатор: базовый режим.",
      substitutions.length > 0
        ? `Найдено замен по цене/наличию: ${substitutions.length}.`
        : "Замен по цене/наличию не найдено.",
      estimate.missingIngredients.length > 0
        ? `Без ценовых подсказок осталось: ${estimate.missingIngredients.slice(0, 5).join(", ")}`
        : "Все ингредиенты оценены по локальным источникам."
    ]
  };
}

function normalizeMealPlanPayload(body: unknown): MealPlanRequest | null {
  if (!isRecord(body)) {
    return null;
  }

  const ingredientKeywords = toStringArray(body.ingredientKeywords);
  const expiringSoonKeywords = toStringArray(body.expiringSoonKeywords);

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

function normalizeSmartMealPlanPayload(body: unknown): SmartMealPlanRequest | null {
  const base = normalizeMealPlanPayload(body);
  if (!base || !isRecord(body)) {
    return null;
  }

  return {
    ...base,
    objective: toOptionalString(body.objective) === "balanced" ? "balanced" : "cost_macro",
    optimizerProfile: normalizeOptimizerProfile(body.optimizerProfile),
    macroTolerancePercent: toOptionalNumber(body.macroTolerancePercent),
    ingredientPriceHints: normalizeIngredientPriceHints(body.ingredientPriceHints)
  };
}

function normalizePriceEstimatePayload(body: unknown): PriceEstimateRequest | null {
  if (!isRecord(body)) {
    return null;
  }

  const ingredients = toStringArray(body.ingredients);
  if (ingredients.length === 0) {
    return null;
  }

  return {
    ingredients,
    hints: normalizeIngredientPriceHints(body.hints),
    region: toOptionalString(body.region),
    currency: toOptionalString(body.currency)
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

function normalizeIngredientPriceHints(value: unknown): SmartMealPlanRequest["ingredientPriceHints"] {
  if (!Array.isArray(value)) {
    return undefined;
  }

  const items = value
    .filter((entry): entry is Record<string, unknown> => isRecord(entry))
    .map((entry) => {
      const ingredient = toOptionalString(entry.ingredient);
      const priceRub = toOptionalNumber(entry.priceRub);
      if (!ingredient || priceRub == null || priceRub < 0) {
        return null;
      }

      const confidence = toOptionalNumber(entry.confidence);
      const source = toOptionalString(entry.source);
      const capturedAt = toOptionalString(entry.capturedAt);

      return {
        ingredient,
        priceRub,
        confidence: confidence != null ? Math.min(Math.max(confidence, 0), 1) : undefined,
        source: source as any,
        capturedAt
      };
    })
    .filter((entry): entry is NonNullable<typeof entry> => Boolean(entry));

  return items.length > 0 ? items : undefined;
}

function normalizeOptimizerProfile(value: unknown): SmartMealPlanRequest["optimizerProfile"] {
  const profile = toOptionalString(value);
  switch (profile) {
    case "economy_aggressive":
    case "balanced":
    case "macro_precision":
      return profile;
    default:
      return "balanced";
  }
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

function clamp(value: number, minValue: number, maxValue: number): number {
  return Math.min(Math.max(value, minValue), maxValue);
}

function overlap(left: string[], right: string[]): number {
  if (left.length === 0 || right.length === 0) {
    return 0;
  }
  const rightSet = new Set(right.map((item) => item.trim().toLowerCase()).filter(Boolean));
  let matches = 0;
  for (const item of left) {
    if (rightSet.has(item.trim().toLowerCase())) {
      matches += 1;
    }
  }
  return matches / Math.max(left.length, 1);
}

function dedupeRecipes(items: Recipe[]): Recipe[] {
  const byId = new Map<string, Recipe>();
  for (const item of items) {
    byId.set(item.id, item);
  }
  return Array.from(byId.values());
}

export const __routeInternals = {
  normalizeMealPlanPayload,
  normalizeSmartMealPlanPayload,
  normalizePriceEstimatePayload,
  normalizeRecommendPayload
};
