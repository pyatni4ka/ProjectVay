import type {
  MealPlanDay,
  MealPlanEntry,
  MealPlanRequest,
  MealPlanResponse,
  MealType,
  RecommendPayload,
  Recipe
} from "../types/contracts.js";
import { rankRecipes } from "./recommendation.js";

const MEAL_TYPES: MealType[] = ["breakfast", "lunch", "dinner"];

export function generateMealPlan(
  candidates: Recipe[],
  request: MealPlanRequest,
  startDate: Date = new Date()
): MealPlanResponse {
  const daysCount = clampInt(request.days ?? 1, 1, 7);
  const beveragesKcal = Math.max(0, request.beveragesKcal ?? 0);
  const availableIngredients = new Set(request.ingredientKeywords.map(normalize));
  const shoppingListSet = new Set<string>();
  const warnings: string[] = [];

  const effectiveDayKcal = request.targets.kcal ? Math.max(0, request.targets.kcal - beveragesKcal) : undefined;
  const perMealKcal = effectiveDayKcal ? effectiveDayKcal / 3 : undefined;
  const perMealBudget = resolvePerMealBudget(request);

  const recommendPayload: RecommendPayload = {
    ingredientKeywords: request.ingredientKeywords,
    expiringSoonKeywords: request.expiringSoonKeywords,
    targets: {
      kcal: perMealKcal,
      protein: request.targets.protein ? request.targets.protein / 3 : undefined,
      fat: request.targets.fat ? request.targets.fat / 3 : undefined,
      carbs: request.targets.carbs ? request.targets.carbs / 3 : undefined
    },
    budget: perMealBudget ? { perMeal: perMealBudget } : undefined,
    exclude: request.exclude,
    avoidBones: request.avoidBones,
    cuisine: request.cuisine,
    limit: Math.max(30, daysCount * MEAL_TYPES.length * 4)
  };

  const ranked = rankRecipes(candidates, recommendPayload);
  if (ranked.length < MEAL_TYPES.length) {
    warnings.push("Недостаточно рецептов для разнообразного плана, используются повторы.");
  }

  const days: MealPlanDay[] = [];
  let estimatedTotalCost = 0;

  for (let dayIndex = 0; dayIndex < daysCount; dayIndex += 1) {
    const entries: MealPlanEntry[] = [];
    let dayKcalTotal = 0;
    let dayCostTotal = 0;

    for (let mealIndex = 0; mealIndex < MEAL_TYPES.length; mealIndex += 1) {
      const mealType = MEAL_TYPES[mealIndex]!;
      const rankedOffset = dayIndex * MEAL_TYPES.length + mealIndex;
      const rankedItem = ranked[rankedOffset] ?? ranked[rankedOffset % Math.max(ranked.length, 1)];

      if (!rankedItem) {
        continue;
      }

      const kcal = rankedItem.recipe.nutrition?.kcal ?? 0;
      const estimatedCost = rankedItem.recipe.estimatedCost ?? 0;
      dayKcalTotal += kcal;
      dayCostTotal += estimatedCost;

      entries.push({
        mealType,
        recipe: rankedItem.recipe,
        score: rankedItem.score,
        estimatedCost,
        kcal
      });

      const missing = rankedItem.recipe.ingredients
        .map((ingredient) => ingredient.trim())
        .filter((ingredient) => ingredient.length > 0)
        .filter((ingredient) => !availableIngredients.has(normalize(ingredient)));
      for (const ingredient of missing) {
        shoppingListSet.add(ingredient);
      }
    }

    const date = new Date(startDate);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() + dayIndex);

    const missingIngredients = entries
      .flatMap((entry) => entry.recipe.ingredients)
      .map((ingredient) => ingredient.trim())
      .filter((ingredient) => ingredient.length > 0)
      .filter((ingredient) => !availableIngredients.has(normalize(ingredient)));

    days.push({
      date: date.toISOString().slice(0, 10),
      entries,
      totals: {
        kcal: round2(dayKcalTotal),
        estimatedCost: round2(dayCostTotal)
      },
      targets: {
        kcal: effectiveDayKcal ? round2(effectiveDayKcal) : undefined,
        perMealKcal: perMealKcal ? round2(perMealKcal) : undefined
      },
      missingIngredients: Array.from(new Set(missingIngredients))
    });

    estimatedTotalCost += dayCostTotal;
  }

  if (beveragesKcal > 0) {
    warnings.push(`Учтён калораж напитков: ${round2(beveragesKcal)} ккал/день.`);
  }

  return {
    days,
    shoppingList: Array.from(shoppingListSet),
    estimatedTotalCost: round2(estimatedTotalCost),
    warnings
  };
}

function resolvePerMealBudget(request: MealPlanRequest): number | undefined {
  const direct = request.budget?.perMeal;
  if (direct && direct > 0) {
    return direct;
  }

  const perDay = request.budget?.perDay;
  if (perDay && perDay > 0) {
    return perDay / 3;
  }

  return undefined;
}

function clampInt(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, Math.floor(value)));
}

function normalize(value: string): string {
  return value.trim().toLowerCase();
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}
