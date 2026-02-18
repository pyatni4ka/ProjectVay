/**
 * Weekly Autopilot Service
 *
 * Wraps the existing generateMealPlan() into a higher-level WeeklyAutopilotResponse
 * that adds: planId, mealSlotTargets, shoppingListWithQuantities, budgetProjection,
 * explanationTags, and nutritionConfidence per day entry.
 *
 * Also provides:
 *  - generateReplaceCandidates() — top-N alternatives for a single meal slot
 *  - adaptPlanAfterDeviation()   — rebuilds remaining plan after cheat/ate-out
 */

import type {
  AdaptPlanRequest,
  AdaptPlanResponse,
  BudgetProjection,
  BudgetProjectionItem,
  BudgetStrictness,
  ExplanationTag,
  MealPlanEntry,
  SmartMealPlanRequest,
  MealSlotTarget,
  NutritionConfidence,
  Recipe,
  ReplaceMealCandidate,
  ReplaceMealRequest,
  ReplaceMealResponse,
  ShoppingItemQuantity,
  WeeklyAutopilotDay,
  WeeklyAutopilotDayEntry,
  WeeklyAutopilotRequest,
  WeeklyAutopilotResponse,
  Nutrition,
} from "../types/contracts.js";
import { generateMealPlan } from "./mealPlan.js";
import { rankRecipes } from "./recommendation.js";

// ---------------------------------------------------------------------------
// Public: generate full weekly autopilot plan
// ---------------------------------------------------------------------------

export function generateWeeklyAutopilot(
  candidates: Recipe[],
  request: WeeklyAutopilotRequest
): WeeklyAutopilotResponse {
  const seed = request.seed ?? Date.now();
  const days = Math.min(Math.max(request.days ?? 7, 1), 7);
  const mealsPerDay = Math.min(Math.max(request.mealsPerDay ?? 3, 2), 6);
  const startDate = request.startDate ?? new Date().toISOString().slice(0, 10);

  // Build base request for underlying generator
  const baseRequest: SmartMealPlanRequest = {
    days,
    startDate,
    mealsPerDay,
    includeSnacks: request.includeSnacks,
    ingredientKeywords: request.ingredientKeywords,
    expiringSoonKeywords: request.expiringSoonKeywords,
    targets: request.targets,
    beveragesKcal: request.beveragesKcal,
    budget: request.budget,
    exclude: [
      ...(request.exclude ?? []),
      ...(request.constraints?.dislikes ?? []),
    ],
    avoidBones: request.avoidBones,
    cuisine: request.cuisine,
    mealSchedule: request.mealSchedule,
    maxPrepTime: resolveMaxPrepTime(request.effortLevel),
    diets: request.constraints?.diets,
    avoidRepetition: true,
    balanceMacros: true,
    userHistory: request.userHistory,
    ingredientPriceHints: request.ingredientPriceHints,
    objective: request.objective ?? "cost_macro",
    optimizerProfile: request.optimizerProfile ?? "balanced",
    macroTolerancePercent: request.macroTolerancePercent,
  };

  const basePlan = generateMealPlan(candidates, baseRequest, new Date(startDate), {
    objective: request.objective ?? "cost_macro",
    optimizerProfile: request.optimizerProfile ?? "balanced",
    macroTolerancePercent: request.macroTolerancePercent,
    ingredientPriceHints: request.ingredientPriceHints,
  });

  // Build per-day autopilot entries
  const autopilotDays: WeeklyAutopilotDay[] = basePlan.days.map((day) => {
    const dayTargets = request.targets;
    const mealSlotKeys = buildMealSlotKeys(day.entries);
    const mealTargets: Record<string, MealSlotTarget> = {};

    for (const entry of day.entries) {
      const slotKey = entry.mealType;
      mealTargets[slotKey] = {
        mealSlotKey: slotKey,
        kcal: dayTargets.kcal ? Math.round(dayTargets.kcal / mealsPerDay) : undefined,
        protein: dayTargets.protein ? Math.round(dayTargets.protein / mealsPerDay) : undefined,
        fat: dayTargets.fat ? Math.round(dayTargets.fat / mealsPerDay) : undefined,
        carbs: dayTargets.carbs ? Math.round(dayTargets.carbs / mealsPerDay) : undefined,
      };
    }

    const budgetPerDay = resolveDayBudget(request.budget, days);
    const dayBudget: BudgetProjectionItem = {
      target: budgetPerDay ?? 0,
      actual: round2(day.totals.estimatedCost),
      delta: round2(day.totals.estimatedCost - (budgetPerDay ?? 0)),
    };

    const autopilotEntries: WeeklyAutopilotDayEntry[] = day.entries.map((entry) => {
      const slotTarget = mealTargets[entry.mealType];
      const tags = computeExplanationTags(entry, request, slotTarget);
      const confidence = computeNutritionConfidence(entry.recipe);
      return {
        ...entry,
        mealSlotKey: entry.mealType,
        explanationTags: tags,
        nutritionConfidence: confidence,
      };
    });

    return {
      date: day.date,
      dayOfWeek: day.dayOfWeek,
      entries: autopilotEntries,
      totals: day.totals,
      dayTargets,
      mealTargets,
      dayBudget,
      missingIngredients: day.missingIngredients,
    };
  });

  const shoppingWithQty = buildShoppingListWithQuantities(
    autopilotDays,
    request.inventorySnapshot ?? []
  );
  const budgetProjection = buildBudgetProjection(
    autopilotDays,
    request.budget,
    days
  );

  // Overall confidence: lowest confidence across all entries
  const allEntries = autopilotDays.flatMap((d) => d.entries);
  const overallConfidence = resolveOverallConfidence(allEntries);
  const allTags = dedupeArray(allEntries.flatMap((e) => e.explanationTags));

  return {
    planId: generatePlanId(seed),
    startDate,
    days: autopilotDays,
    shoppingListWithQuantities: shoppingWithQty,
    shoppingListGrouped: basePlan.shoppingListGrouped ?? {},
    budgetProjection,
    estimatedTotalCost: round2(basePlan.estimatedTotalCost),
    warnings: basePlan.warnings,
    nutritionConfidence: overallConfidence,
    explanationTags: allTags,
    planningContext: request,
  };
}

// ---------------------------------------------------------------------------
// Public: generate replacement candidates for a single meal slot
// ---------------------------------------------------------------------------

export function generateReplaceCandidates(
  candidates: Recipe[],
  req: ReplaceMealRequest
): ReplaceMealResponse {
  const { currentPlan, dayIndex, mealSlot, sortMode = "cheap", topN = 5 } = req;

  const targetDay = currentPlan.days[dayIndex];
  if (!targetDay) {
    return {
      candidates: [],
      updatedPlanPreview: currentPlan,
      why: ["День не найден в плане."],
    };
  }

  const currentEntry = targetDay.entries.find((e) => e.mealType === mealSlot);
  const slotTarget = targetDay.mealTargets[mealSlot];

  // Build exclude list: current recipe + constraint exclusions
  const excludeIds = new Set<string>([
    ...(currentEntry ? [currentEntry.recipe.id] : []),
    ...(req.constraints?.dislikes ?? []),
  ]);

  const inventorySet = new Set((req.inventorySnapshot ?? []).map((s) => s.toLowerCase()));
  const expiringSoon = currentPlan.planningContext?.expiringSoonKeywords ?? [];

  // Rank all candidates for this slot
  const rankedItems = rankRecipes(
    candidates.filter((r) => !excludeIds.has(r.id)),
    {
      ingredientKeywords: currentPlan.planningContext?.ingredientKeywords ?? [],
      expiringSoonKeywords: expiringSoon,
      targets: slotTarget ?? currentPlan.planningContext?.targets ?? {},
      budget: req.budget ? { perMeal: resolvePerMealBudget(req.budget) } : undefined,
      exclude: Array.from(excludeIds),
      diets: req.constraints?.diets,
      limit: 50,
    }
  );

  // Score for the requested sort mode
  const scored = rankedItems.map((item) => ({
    ...item,
    sortScore: computeReplaceSortScore(item.recipe, sortMode, expiringSoon, inventorySet, req.budget),
  }));

  scored.sort((a, b) => {
    if (a.sortScore !== b.sortScore) return a.sortScore - b.sortScore;
    // tie-breaker: macro deviation, then confidence, then recipe id
    const aDev = slotTarget ? macroDev(item(a.recipe), slotTarget) : 0;
    const bDev = slotTarget ? macroDev(item(b.recipe), slotTarget) : 0;
    if (aDev !== bDev) return aDev - bDev;
    return a.recipe.id < b.recipe.id ? -1 : 1;
  });

  const topCandidates: ReplaceMealCandidate[] = scored.slice(0, Math.min(topN, 7)).map((item) => {
    const recipe = item.recipe;
    const mDelta = computeMacroDelta(currentEntry, recipe);
    const cDelta = computeCostDelta(currentEntry, recipe);
    const tDelta = computeTimeDelta(currentEntry, recipe);
    const tags = computeTagsForCandidate(recipe, expiringSoon, inventorySet, req.budget);
    const confidence = computeNutritionConfidence(recipe);
    return {
      recipe,
      mealSlotKey: mealSlot,
      macroDelta: mDelta,
      costDelta: cDelta,
      timeDelta: tDelta,
      tags,
      nutritionConfidence: confidence,
    };
  });

  // Build updated plan preview by swapping the meal
  const updatedPlanPreview = applyReplacementToPreview(
    currentPlan,
    dayIndex,
    mealSlot,
    topCandidates[0]
  );

  const why = buildReplaceWhy(sortMode, topCandidates[0]);

  return { candidates: topCandidates, updatedPlanPreview, why };
}

// ---------------------------------------------------------------------------
// Public: adapt plan after deviation (ate out / cheat / different meal)
// ---------------------------------------------------------------------------

export function adaptPlanAfterDeviation(
  candidates: Recipe[],
  req: AdaptPlanRequest
): AdaptPlanResponse {
  const { currentPlan, eventType, impactEstimate, customMacros, applyScope = "day" } = req;
  const timestamp = req.timestamp ?? new Date().toISOString();
  const todayStr = timestamp.slice(0, 10);

  // Map impact to estimated macro consumption
  const extraConsumed = resolveDeviationMacros(eventType, impactEstimate, customMacros);

  // Find today's index in plan
  const todayIndex = currentPlan.days.findIndex((d) => d.date >= todayStr);
  const splitIndex = todayIndex >= 0 ? todayIndex : 0;

  // Past days are untouched
  const pastDays = currentPlan.days.slice(0, splitIndex);

  // Days to re-plan
  const futureDays = currentPlan.days.slice(splitIndex);
  if (futureDays.length === 0) {
    return {
      updatedRemainingPlan: currentPlan,
      disruptionScore: 0,
      newBudgetProjection: currentPlan.budgetProjection,
      gentleMessage: buildGentleMessage(eventType),
      why: ["Все дни уже прошли — план завершён."],
    };
  }

  // Adjust remaining targets (subtract what was unexpectedly consumed)
  const remainingDays = applyScope === "day" ? futureDays.slice(0, 1) : futureDays;
  const untouchedFuture = applyScope === "day" ? futureDays.slice(1) : [];

  const adjustedTargets = smoothTargetAdjustment(
    currentPlan.planningContext?.targets ?? {},
    extraConsumed,
    remainingDays.length
  );

  const adjustedContext: WeeklyAutopilotRequest = {
    ...(currentPlan.planningContext ?? {}),
    targets: adjustedTargets,
    startDate: remainingDays[0]?.date ?? todayStr,
    days: remainingDays.length,
    ingredientKeywords: currentPlan.planningContext?.ingredientKeywords ?? [],
    expiringSoonKeywords: currentPlan.planningContext?.expiringSoonKeywords ?? [],
  };

  const regenPlan = generateWeeklyAutopilot(candidates, adjustedContext);

  // Merge: past + regened remaining + untouched future
  const mergedDays = [...pastDays, ...regenPlan.days, ...untouchedFuture];

  const updatedPlan: WeeklyAutopilotResponse = {
    ...currentPlan,
    days: mergedDays,
    shoppingListWithQuantities: regenPlan.shoppingListWithQuantities,
    budgetProjection: regenPlan.budgetProjection,
    estimatedTotalCost: round2(mergedDays.reduce((s, d) => s + d.totals.estimatedCost, 0)),
    warnings: [
      ...regenPlan.warnings,
      buildDeviationWarning(eventType, impactEstimate),
    ],
  };

  const disruptionScore = round2(regenPlan.days.length / Math.max(currentPlan.days.length, 1));

  return {
    updatedRemainingPlan: updatedPlan,
    disruptionScore,
    newBudgetProjection: regenPlan.budgetProjection,
    gentleMessage: buildGentleMessage(eventType),
    why: [
      `Пересчитано ${regenPlan.days.length} ${regenPlan.days.length === 1 ? "день" : "дня/дней"} с учётом отклонения.`,
      buildDeviationWhy(eventType, impactEstimate, extraConsumed),
    ],
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function generatePlanId(seed: number): string {
  // Stable ID: short hash of seed + date (not truly random, consistent for same seed)
  return `plan_${seed.toString(36)}_${Date.now().toString(36)}`;
}

function resolveMaxPrepTime(effortLevel?: "quick" | "standard" | "complex"): number {
  switch (effortLevel) {
    case "quick": return 20;
    case "complex": return 90;
    default: return 45;
  }
}

function resolveDayBudget(
  budget: WeeklyAutopilotRequest["budget"],
  days: number
): number | undefined {
  if (!budget) return undefined;
  if (budget.perDay) return budget.perDay;
  if (budget.perWeek) return budget.perWeek / Math.max(days, 1);
  if (budget.perMonth) return budget.perMonth / 30;
  return undefined;
}

function resolvePerMealBudget(budget: WeeklyAutopilotRequest["budget"]): number | undefined {
  if (!budget) return undefined;
  if (budget.perMeal) return budget.perMeal;
  if (budget.perDay) return budget.perDay / 3;
  if (budget.perWeek) return budget.perWeek / (7 * 3);
  return undefined;
}

function computeExplanationTags(
  entry: MealPlanEntry,
  request: WeeklyAutopilotRequest,
  slotTarget?: MealSlotTarget
): ExplanationTag[] {
  const tags: ExplanationTag[] = [];
  const recipe = entry.recipe;

  // cheap: cost within 80% of per-meal budget
  const perMeal = resolvePerMealBudget(request.budget);
  if (perMeal && entry.estimatedCost > 0 && entry.estimatedCost <= perMeal * 0.8) {
    tags.push("cheap");
  }

  // quick: total time <= 20 min
  const totalTime = recipe.times?.totalMinutes ?? (recipe.times?.prepMinutes ?? 0) + (recipe.times?.cookMinutes ?? 0);
  if (totalTime > 0 && totalTime <= 20) {
    tags.push("quick");
  }

  // high_protein: protein meets or exceeds slot target
  if (slotTarget?.protein && entry.protein >= (slotTarget.protein ?? 0) * 0.9) {
    tags.push("high_protein");
  }

  // uses_inventory: any ingredient is in the inventory snapshot
  const inventory = new Set((request.inventorySnapshot ?? []).map((s) => s.toLowerCase()));
  const hasInventoryMatch = recipe.ingredients.some((ing) =>
    inventory.has(ing.toLowerCase().split(" ").slice(0, 2).join(" "))
  );
  if (hasInventoryMatch) {
    tags.push("uses_inventory");
  }

  // expiring_soon: any ingredient is expiring
  const expiringSet = new Set((request.expiringSoonKeywords ?? []).map((s) => s.toLowerCase()));
  const hasExpiringMatch = recipe.ingredients.some((ing) =>
    expiringSet.has(ing.toLowerCase().split(" ").slice(0, 2).join(" "))
  );
  if (hasExpiringMatch) {
    tags.push("expiring_soon");
  }

  // low_effort: easy difficulty or short prep
  if (recipe.difficulty === "easy" || (totalTime > 0 && totalTime <= 25)) {
    tags.push("low_effort");
  }

  return dedupeArray(tags);
}

function computeNutritionConfidence(recipe: Recipe): NutritionConfidence {
  const n = recipe.nutrition;
  if (!n) return "low";
  const present = [n.kcal, n.protein, n.fat, n.carbs].filter((v) => v != null && v > 0).length;
  if (present === 4) return "high";
  if (present >= 2) return "medium";
  return "low";
}

function resolveOverallConfidence(entries: WeeklyAutopilotDayEntry[]): NutritionConfidence {
  if (entries.length === 0) return "low";
  const lowCount = entries.filter((e) => e.nutritionConfidence === "low").length;
  const ratio = lowCount / entries.length;
  if (ratio > 0.5) return "low";
  const medCount = entries.filter((e) => e.nutritionConfidence === "medium").length;
  if (medCount / entries.length > 0.4) return "medium";
  return "high";
}

function buildShoppingListWithQuantities(
  days: WeeklyAutopilotDay[],
  inventorySnapshot: string[]
): ShoppingItemQuantity[] {
  const inventorySet = new Set(inventorySnapshot.map((s) => s.toLowerCase()));
  const accumulated = new Map<string, ShoppingItemQuantity>();

  for (const day of days) {
    for (const entry of day.entries) {
      for (const rawIngredient of entry.recipe.ingredients) {
        const { name, amount, unit } = parseIngredientQuantity(rawIngredient);
        if (!name) continue;
        // Skip if already in inventory
        if (inventorySet.has(name.toLowerCase())) continue;

        const key = name.toLowerCase();
        const existing = accumulated.get(key);
        if (existing) {
          if (existing.unit === unit) {
            existing.amount = round2(existing.amount + amount);
          } else {
            // Different units — mark as approximate
            existing.amount = round2(existing.amount + amount);
            existing.approximate = true;
          }
        } else {
          accumulated.set(key, {
            ingredient: name,
            amount,
            unit,
            approximate: amount === 0,
          });
        }
      }
    }
  }

  return Array.from(accumulated.values()).sort((a, b) =>
    a.ingredient.localeCompare(b.ingredient, "ru")
  );
}

/**
 * Parse a raw ingredient string into structured quantity.
 * Examples: "200 г куриного филе", "2 яйца", "соль"
 */
function parseIngredientQuantity(raw: string): {
  name: string;
  amount: number;
  unit: "g" | "ml" | "piece";
} {
  const clean = raw.trim();
  // Pattern: optional leading number + optional unit + rest
  const match = clean.match(/^(\d+(?:[.,]\d+)?)\s*(г|ml|мл|г\.|шт|шт\.|piece|pieces|g|ml)?\s*(.+)?$/i);
  if (match) {
    const amount = parseFloat((match[1] ?? "0").replace(",", "."));
    const rawUnit = (match[2] ?? "").toLowerCase();
    const name = (match[3] ?? clean).trim();
    const unit = resolveUnit(rawUnit);
    return { name: name || clean, amount, unit };
  }
  return { name: clean, amount: 0, unit: "piece" };
}

function resolveUnit(raw: string): "g" | "ml" | "piece" {
  if (["г", "g", "г.", "грамм", "гр"].includes(raw)) return "g";
  if (["мл", "ml", "литр", "л"].includes(raw)) return "ml";
  return "piece";
}

function buildBudgetProjection(
  days: WeeklyAutopilotDay[],
  budget: WeeklyAutopilotRequest["budget"],
  totalDays: number
): BudgetProjection {
  const strictness: BudgetStrictness = budget?.strictness ?? "soft";
  const softLimitPct = budget?.softLimitPct ?? 5;

  const dayBudget = resolveDayBudget(budget, totalDays) ?? 0;
  const weekBudget = budget?.perWeek ?? (dayBudget * 7);
  const monthBudget = budget?.perMonth ?? (dayBudget * 30);

  const actualTotal = round2(days.reduce((s, d) => s + d.totals.estimatedCost, 0));
  const actualDay = days.length > 0 ? round2(actualTotal / days.length) : 0;
  const projectedWeek = round2(actualDay * 7);
  const projectedMonth = round2(actualDay * 30);

  return {
    day: { target: dayBudget, actual: actualDay, delta: round2(actualDay - dayBudget) },
    week: { target: weekBudget, actual: projectedWeek, delta: round2(projectedWeek - weekBudget) },
    month: { target: monthBudget, actual: projectedMonth, delta: round2(projectedMonth - monthBudget) },
    strictness,
    softLimitPct,
  };
}

function computeReplaceSortScore(
  recipe: Recipe,
  mode: string,
  expiringSoon: string[],
  inventory: Set<string>,
  budget?: WeeklyAutopilotRequest["budget"]
): number {
  switch (mode) {
    case "cheap": {
      const cost = recipe.estimatedCost ?? 999;
      return cost;
    }
    case "fast": {
      const time = recipe.times?.totalMinutes ?? 999;
      return time;
    }
    case "protein": {
      // Higher protein = lower score = sorts first
      return -(recipe.nutrition?.protein ?? 0);
    }
    case "expiry": {
      const expiringSet = new Set(expiringSoon.map((s) => s.toLowerCase()));
      const matched = recipe.ingredients.filter((i) => expiringSet.has(i.toLowerCase().split(" ").slice(0, 2).join(" "))).length;
      return -matched; // More matches = lower score = sorts first
    }
    default:
      return 0;
  }
}

function computeMacroDelta(current: MealPlanEntry | undefined, candidate: Recipe): Nutrition {
  if (!current) return {};
  return {
    kcal: round2((candidate.nutrition?.kcal ?? 0) - current.kcal),
    protein: round2((candidate.nutrition?.protein ?? 0) - current.protein),
    fat: round2((candidate.nutrition?.fat ?? 0) - current.fat),
    carbs: round2((candidate.nutrition?.carbs ?? 0) - current.carbs),
  };
}

function computeCostDelta(current: MealPlanEntry | undefined, candidate: Recipe): number {
  if (!current) return 0;
  return round2((candidate.estimatedCost ?? 0) - current.estimatedCost);
}

function computeTimeDelta(current: MealPlanEntry | undefined, candidate: Recipe): number {
  if (!current) return 0;
  const currentTime = current.recipe.times?.totalMinutes ?? 0;
  const candidateTime = candidate.times?.totalMinutes ?? 0;
  return candidateTime - currentTime;
}

function computeTagsForCandidate(
  recipe: Recipe,
  expiringSoon: string[],
  inventory: Set<string>,
  budget?: WeeklyAutopilotRequest["budget"]
): ExplanationTag[] {
  const tags: ExplanationTag[] = [];
  const perMeal = resolvePerMealBudget(budget);
  if (perMeal && (recipe.estimatedCost ?? Infinity) <= perMeal * 0.8) tags.push("cheap");
  const time = recipe.times?.totalMinutes ?? 999;
  if (time <= 20) tags.push("quick");
  if ((recipe.nutrition?.protein ?? 0) >= 25) tags.push("high_protein");

  const expiringSet = new Set(expiringSoon.map((s) => s.toLowerCase()));
  if (recipe.ingredients.some((i) => expiringSet.has(i.toLowerCase()))) tags.push("expiring_soon");
  if (recipe.ingredients.some((i) => inventory.has(i.toLowerCase()))) tags.push("uses_inventory");
  if (recipe.difficulty === "easy" || time <= 25) tags.push("low_effort");

  return dedupeArray(tags);
}

function applyReplacementToPreview(
  plan: WeeklyAutopilotResponse,
  dayIndex: number,
  mealSlot: string,
  candidate: ReplaceMealCandidate | undefined
): WeeklyAutopilotResponse {
  if (!candidate) return plan;

  const updatedDays = plan.days.map((day, idx) => {
    if (idx !== dayIndex) return day;

    const updatedEntries = day.entries.map((entry): WeeklyAutopilotDayEntry => {
      if (entry.mealType !== mealSlot) return entry;

      const r = candidate.recipe;
      const kcal = r.nutrition?.kcal ?? r.caloriesPerServing ?? 0;
      return {
        ...entry,
        recipe: r,
        kcal,
        protein: r.nutrition?.protein ?? 0,
        fat: r.nutrition?.fat ?? 0,
        carbs: r.nutrition?.carbs ?? 0,
        estimatedCost: r.estimatedCost ?? 0,
        explanationTags: candidate.tags,
        nutritionConfidence: candidate.nutritionConfidence,
      };
    });

    const totals = {
      kcal: round2(updatedEntries.reduce((s, e) => s + e.kcal, 0)),
      protein: round2(updatedEntries.reduce((s, e) => s + e.protein, 0)),
      fat: round2(updatedEntries.reduce((s, e) => s + e.fat, 0)),
      carbs: round2(updatedEntries.reduce((s, e) => s + e.carbs, 0)),
      estimatedCost: round2(updatedEntries.reduce((s, e) => s + e.estimatedCost, 0)),
    };

    return { ...day, entries: updatedEntries, totals };
  });

  return {
    ...plan,
    days: updatedDays,
    estimatedTotalCost: round2(updatedDays.reduce((s, d) => s + d.totals.estimatedCost, 0)),
  };
}

function buildReplaceWhy(sortMode: string, top: ReplaceMealCandidate | undefined): string[] {
  if (!top) return ["Нет подходящих замен."];
  const lines: string[] = [];
  switch (sortMode) {
    case "cheap":
      lines.push("Показаны самые дешёвые варианты, соответствующие ограничениям.");
      break;
    case "fast":
      lines.push("Показаны самые быстрые в приготовлении варианты.");
      break;
    case "protein":
      lines.push("Показаны варианты с максимальным содержанием белка.");
      break;
    case "expiry":
      lines.push("Показаны варианты, использующие продукты с коротким сроком годности.");
      break;
  }
  if (top.costDelta < -10) lines.push(`Экономия: ~${Math.abs(top.costDelta)} ₽.`);
  if ((top.macroDelta.protein ?? 0) > 5) lines.push(`Больше белка: +${top.macroDelta.protein ?? 0} г.`);
  return lines;
}

function resolveDeviationMacros(
  eventType: string,
  impact: string,
  customMacros?: Nutrition
): Nutrition {
  if (customMacros) return customMacros;

  // Estimated extra consumption by event type + size
  const table: Record<string, Record<string, Nutrition>> = {
    ate_out: {
      small: { kcal: 350, protein: 15, fat: 12, carbs: 35 },
      medium: { kcal: 700, protein: 30, fat: 25, carbs: 70 },
      large: { kcal: 1100, protein: 45, fat: 40, carbs: 110 },
    },
    cheat: {
      small: { kcal: 400, protein: 5, fat: 20, carbs: 50 },
      medium: { kcal: 800, protein: 10, fat: 40, carbs: 100 },
      large: { kcal: 1400, protein: 15, fat: 65, carbs: 175 },
    },
    different_meal: {
      small: { kcal: 300, protein: 20, fat: 10, carbs: 30 },
      medium: { kcal: 550, protein: 35, fat: 18, carbs: 55 },
      large: { kcal: 850, protein: 50, fat: 28, carbs: 85 },
    },
  };

  return table[eventType]?.[impact] ?? table.ate_out.medium;
}

function smoothTargetAdjustment(
  baseTargets: Nutrition,
  consumed: Nutrition,
  remainingDays: number
): Nutrition {
  if (remainingDays <= 0) return baseTargets;
  const smooth = Math.max(1, remainingDays);

  return {
    kcal: baseTargets.kcal
      ? Math.max(800, round2(baseTargets.kcal - (consumed.kcal ?? 0) / smooth))
      : undefined,
    protein: baseTargets.protein
      ? Math.max(40, round2(baseTargets.protein - (consumed.protein ?? 0) / smooth))
      : undefined,
    fat: baseTargets.fat
      ? Math.max(20, round2(baseTargets.fat - (consumed.fat ?? 0) / smooth))
      : undefined,
    carbs: baseTargets.carbs
      ? Math.max(50, round2(baseTargets.carbs - (consumed.carbs ?? 0) / smooth))
      : undefined,
  };
}

function buildGentleMessage(eventType: string): string {
  switch (eventType) {
    case "ate_out":
      return "Всё в порядке — поел вне дома? Пересчитали остаток дня без лишнего давления.";
    case "cheat":
      return "Чит-день — это нормально. Адаптировали план на остаток без осуждения.";
    case "different_meal":
      return "Съел что-то другое? Учли это и скорректировали план дальше.";
    default:
      return "План скорректирован с учётом произошедшего. Всё хорошо!";
  }
}

function buildDeviationWarning(eventType: string, impact: string): string {
  const typeLabel = eventType === "ate_out" ? "Поел вне дома" : eventType === "cheat" ? "Чит-день" : "Другой приём";
  const sizeLabel = impact === "small" ? "небольшой" : impact === "medium" ? "средний" : "большой";
  return `${typeLabel} (${sizeLabel}): план на остаток дня пересчитан.`;
}

function buildDeviationWhy(eventType: string, impact: string, consumed: Nutrition): string {
  return `Дополнительно учтено: ~${consumed.kcal ?? 0} ккал, ${consumed.protein ?? 0} г белка. Остаток скорректирован плавно.`;
}

function buildMealSlotKeys(entries: MealPlanEntry[]): string[] {
  return entries.map((e) => e.mealType);
}

function macroDev(recipe: Recipe, target: MealSlotTarget): number {
  const checks = [
    [target.kcal, recipe.nutrition?.kcal],
    [target.protein, recipe.nutrition?.protein],
    [target.fat, recipe.nutrition?.fat],
    [target.carbs, recipe.nutrition?.carbs],
  ] as [number | undefined, number | undefined][];

  let sum = 0;
  let count = 0;
  for (const [t, a] of checks) {
    if (!t || !a) continue;
    sum += Math.abs(t - a) / Math.max(t, 1);
    count += 1;
  }
  return count > 0 ? sum / count : 0.6;
}

// Utility to convert RankedRecipe item to Recipe for macroDev
function item(recipe: Recipe): Recipe {
  return recipe;
}

function dedupeArray<T>(arr: T[]): T[] {
  return [...new Set(arr)];
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}
