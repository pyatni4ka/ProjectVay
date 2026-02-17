import type {
  IngredientPriceHint,
  MealPlanDay,
  MealPlanEntry,
  MealPlanRequest,
  MealPlanResponse,
  MealType,
  RecommendPayload,
  Recipe,
  Nutrition,
  RecipeDifficulty
} from "../types/contracts.js";
import { rankRecipes, calculateDiversityScore } from "./recommendation.js";

const MEAL_TYPES: MealType[] = ["breakfast", "lunch", "dinner"];
const DAY_NAMES = ["Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"];

export function generateMealPlan(
  candidates: Recipe[],
  request: MealPlanRequest,
  startDate: Date = new Date(),
  options: {
    objective?: "cost_macro" | "balanced";
    macroTolerancePercent?: number;
    ingredientPriceHints?: IngredientPriceHint[];
  } = {}
): MealPlanResponse {
  const daysCount = clampInt(request.days ?? 1, 1, 7);
  const beveragesKcal = Math.max(0, request.beveragesKcal ?? 0);
  const availableIngredients = new Set(request.ingredientKeywords.map(normalize));
  const shoppingListSet = new Set<string>();
  const warnings: string[] = [];

  const effectiveDayKcal = request.targets.kcal ? Math.max(0, request.targets.kcal - beveragesKcal) : undefined;
  const perMealKcal = effectiveDayKcal ? effectiveDayKcal / 3 : undefined;
  const perMealBudget = resolvePerMealBudget(request);

  const recipeHistory = new Set(request.userHistory ?? []);
  const objective = options.objective ?? "balanced";
  const macroTolerance = clampNumber((options.macroTolerancePercent ?? 25) / 100, 0.05, 0.6);
  const hintPriceByIngredient = buildHintPriceMap(options.ingredientPriceHints ?? []);
  const defaultIngredientCost = resolveDefaultIngredientCost(hintPriceByIngredient);

  const macroTargets = {
    protein: request.targets.protein ? request.targets.protein / 3 : undefined,
    fat: request.targets.fat ? request.targets.fat / 3 : undefined,
    carbs: request.targets.carbs ? request.targets.carbs / 3 : undefined
  };

  const recommendPayload: RecommendPayload = {
    ingredientKeywords: request.ingredientKeywords,
    expiringSoonKeywords: request.expiringSoonKeywords,
    targets: {
      kcal: perMealKcal,
      ...macroTargets
    },
    budget: perMealBudget ? { perMeal: perMealBudget } : undefined,
    exclude: request.exclude,
    avoidBones: request.avoidBones,
    cuisine: request.cuisine,
    limit: Math.max(50, daysCount * MEAL_TYPES.length * 5),
    
    // Enhanced filters
    maxPrepTime: request.maxPrepTime,
    difficulty: request.difficulty,
    diets: request.diets,
    excludeRecentRecipes: Array.from(recipeHistory),
    diversityWeight: request.avoidRepetition ? 0.15 : 0.05
  };

  const ranked = rankRecipes(candidates, recommendPayload).map((item) => ({
    recipe: item.recipe,
    score: item.score
  }));
  const baseCandidates = ranked.length > 0
    ? ranked
    : candidates.map((recipe) => ({ recipe, score: 0.3 }));

  if (ranked.length < MEAL_TYPES.length) {
    warnings.push("Недостаточно рецептов для разнообразного плана.");
  }

  const days: MealPlanDay[] = [];
  let estimatedTotalCost = 0;
  let totalNutrition: Nutrition = {};

  const usedRecipeIds = new Set<string>();
  const recipeUsageCount = new Map<string, number>();
  const cuisineUsageCount = new Map<string, number>();
  const recipeCostCache = new Map<string, ResolvedRecipeCost>();

  let strictMacroMeals = 0;
  let relaxedMacroMeals = 0;
  let repeatedRecipeMeals = 0;
  let repeatedCuisineMeals = 0;
  let lowConfidenceCostMeals = 0;
  let optimizerMacroDeviationSum = 0;
  let optimizerCostSum = 0;
  let optimizerEvaluatedMeals = 0;

  for (let dayIndex = 0; dayIndex < daysCount; dayIndex += 1) {
    const entries: MealPlanEntry[] = [];
    let dayKcalTotal = 0;
    let dayProteinTotal = 0;
    let dayFatTotal = 0;
    let dayCarbsTotal = 0;
    let dayCostTotal = 0;
    const dayMissingSet = new Set<string>();
    const dayRecipeIds = new Set<string>();
    let previousCuisine: string | undefined;

    for (let mealIndex = 0; mealIndex < MEAL_TYPES.length; mealIndex += 1) {
      const mealType = MEAL_TYPES[mealIndex]!;
      const remainingMealsInDay = Math.max(1, MEAL_TYPES.length - mealIndex);
      const slotTargets: Nutrition = {
        kcal: effectiveDayKcal
          ? Math.max(0, effectiveDayKcal - dayKcalTotal) / remainingMealsInDay
          : perMealKcal,
        protein: request.targets.protein
          ? Math.max(0, request.targets.protein - dayProteinTotal) / remainingMealsInDay
          : macroTargets.protein,
        fat: request.targets.fat
          ? Math.max(0, request.targets.fat - dayFatTotal) / remainingMealsInDay
          : macroTargets.fat,
        carbs: request.targets.carbs
          ? Math.max(0, request.targets.carbs - dayCarbsTotal) / remainingMealsInDay
          : macroTargets.carbs
      };

      let candidatePool = baseCandidates.filter((item) => !dayRecipeIds.has(item.recipe.id));
      if (candidatePool.length === 0) {
        candidatePool = baseCandidates;
      }

      if (request.avoidRepetition) {
        const noGlobalRepetition = candidatePool.filter((item) => !usedRecipeIds.has(item.recipe.id));
        if (noGlobalRepetition.length > 0) {
          candidatePool = noGlobalRepetition;
        }
      }

      if (candidatePool.length === 0) continue;

      const evaluated = candidatePool.map((item) => {
        const recipe = item.recipe;
        const resolvedCost = resolveRecipeCostCached(
          recipe,
          hintPriceByIngredient,
          defaultIngredientCost,
          recipeCostCache
        );
        const macroDeviation = averageMacroDeviation(slotTargets, recipe.nutrition);
        const repetitionPenalty = repetitionPenaltyScore({
          recipe,
          dayRecipeIds,
          recipeUsageCount,
          cuisineUsageCount,
          previousCuisine
        });
        const conveniencePenalty = conveniencePenaltyScore(recipe, request.maxPrepTime);
        const availabilityPenalty = availabilityPenaltyScore(recipe, availableIngredients);
        const historyPenalty = recipeHistory.has(recipe.id) ? 0.55 : 0;
        const expiringBonus = expiringIngredientBonus(recipe, request.expiringSoonKeywords);
        const baseRankBonus = clampNumber(item.score, 0, 2);

        return {
          item,
          recipe,
          resolvedCost,
          macroDeviation,
          repetitionPenalty,
          conveniencePenalty,
          availabilityPenalty,
          historyPenalty,
          expiringBonus,
          baseRankBonus
        };
      });

      const strictMacroPool = evaluated.filter((item) => item.macroDeviation <= macroTolerance);
      const selectedPool = strictMacroPool.length > 0 ? strictMacroPool : evaluated;
      if (strictMacroPool.length > 0) {
        strictMacroMeals += 1;
      } else {
        relaxedMacroMeals += 1;
      }

      const costValues = selectedPool.map((item) => item.resolvedCost.value).filter((value) => value >= 0);
      const minCost = costValues.length > 0 ? Math.min(...costValues) : 0;
      const maxCost = costValues.length > 0 ? Math.max(...costValues) : 0;

      const weighted = selectedPool.map((item) => {
        const normalizedCost = normalizeCostSignal({
          value: item.resolvedCost.value,
          minCost,
          maxCost,
          perMealBudget
        });
        const lowConfidencePenalty = 1 - item.resolvedCost.confidence;
        const objectiveScore = composeObjectiveScore({
          objective,
          normalizedCost,
          macroDeviation: item.macroDeviation,
          repetitionPenalty: item.repetitionPenalty,
          conveniencePenalty: item.conveniencePenalty,
          availabilityPenalty: item.availabilityPenalty,
          historyPenalty: item.historyPenalty,
          lowConfidencePenalty,
          expiringBonus: item.expiringBonus,
          baseRankBonus: item.baseRankBonus
        });

        return {
          ...item,
          objectiveScore
        };
      });

      weighted.sort((a, b) => {
        if (a.objectiveScore !== b.objectiveScore) {
          return a.objectiveScore - b.objectiveScore;
        }
        if (a.macroDeviation !== b.macroDeviation) {
          return a.macroDeviation - b.macroDeviation;
        }
        return b.item.score - a.item.score;
      });

      const selected = weighted[0];
      if (!selected) continue;

      const recipe = selected.recipe;
      const kcal = recipe.nutrition?.kcal ?? recipe.caloriesPerServing ?? 0;
      const protein = recipe.nutrition?.protein ?? 0;
      const fat = recipe.nutrition?.fat ?? 0;
      const carbs = recipe.nutrition?.carbs ?? 0;
      const estimatedCost = selected.resolvedCost.value;

      dayKcalTotal += kcal;
      dayProteinTotal += protein;
      dayFatTotal += fat;
      dayCarbsTotal += carbs;
      dayCostTotal += estimatedCost;

      const previousRecipeUses = recipeUsageCount.get(recipe.id) ?? 0;
      if (previousRecipeUses > 0) {
        repeatedRecipeMeals += 1;
      }
      recipeUsageCount.set(recipe.id, previousRecipeUses + 1);
      usedRecipeIds.add(recipe.id);

      if (recipe.cuisine) {
        const normalizedCuisine = normalize(recipe.cuisine);
        const previousCuisineUses = cuisineUsageCount.get(normalizedCuisine) ?? 0;
        if (previousCuisineUses > 0) {
          repeatedCuisineMeals += 1;
        }
        cuisineUsageCount.set(normalizedCuisine, previousCuisineUses + 1);
        previousCuisine = normalizedCuisine;
      } else {
        previousCuisine = undefined;
      }

      if (selected.resolvedCost.confidence < 0.45) {
        lowConfidenceCostMeals += 1;
      }
      optimizerMacroDeviationSum += selected.macroDeviation;
      optimizerCostSum += estimatedCost;
      optimizerEvaluatedMeals += 1;
      dayRecipeIds.add(recipe.id);

      entries.push({
        mealType,
        recipe,
        score: selected.item.score,
        estimatedCost,
        kcal,
        protein,
        fat,
        carbs
      });

      const missing = recipe.ingredients
        .map((ingredient) => ingredient.trim())
        .filter((ingredient) => ingredient.length > 0)
        .filter((ingredient) => !availableIngredients.has(normalize(ingredient)));
      for (const ingredient of missing) {
        shoppingListSet.add(ingredient);
        dayMissingSet.add(ingredient);
      }
    }

    const date = new Date(startDate);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() + dayIndex);

    const dayOfWeek = DAY_NAMES[date.getDay()];

    const mealSchedule = request.mealSchedule ? {
      breakfastTime: formatTime(request.mealSchedule.breakfastStart ?? 8 * 60),
      lunchTime: formatTime(request.mealSchedule.lunchStart ?? 13 * 60),
      dinnerTime: formatTime(request.mealSchedule.dinnerStart ?? 19 * 60)
    } : undefined;

    days.push({
      date: date.toISOString().slice(0, 10),
      dayOfWeek,
      entries,
      totals: {
        kcal: round2(dayKcalTotal),
        protein: round2(dayProteinTotal),
        fat: round2(dayFatTotal),
        carbs: round2(dayCarbsTotal),
        estimatedCost: round2(dayCostTotal)
      },
      targets: {
        kcal: effectiveDayKcal ? round2(effectiveDayKcal) : undefined,
        perMealKcal: perMealKcal ? round2(perMealKcal) : undefined,
        protein: macroTargets.protein ? round2(macroTargets.protein) : undefined,
        fat: macroTargets.fat ? round2(macroTargets.fat) : undefined,
        carbs: macroTargets.carbs ? round2(macroTargets.carbs) : undefined
      },
      missingIngredients: Array.from(dayMissingSet).slice(0, 10),
      mealSchedule
    });

    estimatedTotalCost += dayCostTotal;

    totalNutrition.kcal = (totalNutrition.kcal ?? 0) + dayKcalTotal;
    totalNutrition.protein = (totalNutrition.protein ?? 0) + dayProteinTotal;
    totalNutrition.fat = (totalNutrition.fat ?? 0) + dayFatTotal;
    totalNutrition.carbs = (totalNutrition.carbs ?? 0) + dayCarbsTotal;
  }

  const shoppingListGrouped = groupShoppingList(Array.from(shoppingListSet));
  const allRecipes = days.flatMap((day) => day.entries.map((entry) => entry.recipe));
  const diversityScore = calculateDiversityScore(allRecipes);
  const varietyScore = calculateVarietyScore(allRecipes);

  if (beveragesKcal > 0) {
    warnings.push(`Учтён калораж напитков: ${round2(beveragesKcal)} ккал/день.`);
  }

  if (relaxedMacroMeals > 0) {
    warnings.push(
      `Для ${relaxedMacroMeals} приёмов пищи не хватило строгих попаданий по КБЖУ, применён адаптивный допуск.`
    );
  }

  if (lowConfidenceCostMeals > 0) {
    warnings.push(
      `Для ${lowConfidenceCostMeals} приёмов пищи оценка цены построена по fallback-модели (мало локальных цен).`
    );
  }

  if (repeatedRecipeMeals > 0 || repeatedCuisineMeals > 0) {
    warnings.push("Оптимизатор снизил повторяемость, но часть повторов оставлена для соблюдения КБЖУ/бюджета.");
  }

  if (diversityScore < 0.5) {
    warnings.push("Рекомендуем добавить больше разнообразных продуктов для лучшего плана.");
  }

  const averageMacroDeviation = optimizerEvaluatedMeals > 0
    ? optimizerMacroDeviationSum / optimizerEvaluatedMeals
    : 0;
  const averageMealCost = optimizerEvaluatedMeals > 0
    ? optimizerCostSum / optimizerEvaluatedMeals
    : 0;

  return {
    days,
    shoppingList: Array.from(shoppingListSet),
    shoppingListGrouped,
    estimatedTotalCost: round2(estimatedTotalCost),
    totalNutrition: {
      kcal: round2(totalNutrition.kcal ?? 0),
      protein: round2(totalNutrition.protein ?? 0),
      fat: round2(totalNutrition.fat ?? 0),
      carbs: round2(totalNutrition.carbs ?? 0)
    },
    warnings,
    diversityScore: round2(diversityScore),
    varietyScore: round2(varietyScore),
    optimization: {
      objective,
      averageMacroDeviation: round2(averageMacroDeviation),
      averageMealCost: round2(averageMealCost),
      strictMacroMeals,
      relaxedMacroMeals,
      repeatedRecipeMeals,
      repeatedCuisineMeals,
      lowConfidenceCostMeals
    }
  };
}

function formatTime(minutesFromMidnight: number): string {
  const hours = Math.floor(minutesFromMidnight / 60);
  const mins = minutesFromMidnight % 60;
  return `${hours.toString().padStart(2, "0")}:${mins.toString().padStart(2, "0")}`;
}

function groupShoppingList(items: string[]): Record<string, string[]> {
  const groups: Record<string, string[]> = {
    "Овощи и фрукты": [],
    "Молочные": [],
    "Мясо и рыба": [],
    "Крупы и мучное": [],
    "Специи": [],
    "Другое": []
  };
  
  const keywords: Record<string, string[]> = {
    "Овощи и фрукты": ["помидор", "огурец", "картофель", "морковь", "лук", "чеснок", "яблок", "банан", "апельсин", "лимон", "зелень", "салат", "капуста", "перец", "свекла"],
    "Молочные": ["молоко", "кефир", "йогурт", "сыр", "творог", "сметана", "сливки", "масло"],
    "Мясо и рыба": ["мясо", "курица", "говядина", "свинина", "рыба", "фарш", "колбаса", "сосиск"],
    "Крупы и мучное": ["рис", "гречка", "макарон", "мука", "хлеб", "овсянка", "крупа"],
    "Специи": ["соль", "перец", "специя", "приправа", "соевый соус"]
  };
  
  for (const item of items) {
    const lowerItem = item.toLowerCase();
    let added = false;
    
    for (const [category, words] of Object.entries(keywords)) {
      if (words.some(w => lowerItem.includes(w))) {
        groups[category].push(item);
        added = true;
        break;
      }
    }
    
    if (!added) {
      groups["Другое"].push(item);
    }
  }
  
  // Remove empty groups
  for (const key of Object.keys(groups)) {
    if (groups[key].length === 0) {
      delete groups[key];
    }
  }
  
  return groups;
}

function calculateVarietyScore(recipes: Recipe[]): number {
  if (recipes.length <= 1) return 1.0;
  
  let sameCount = 0;
  for (let i = 1; i < recipes.length; i++) {
    if (recipes[i].title === recipes[i-1].title) {
      sameCount++;
    }
  }
  
  return 1 - (sameCount / (recipes.length - 1));
}

function resolvePerMealBudget(request: MealPlanRequest): number | undefined {
  const direct = request.budget?.perMeal;
  if (direct && direct > 0) return direct;

  const perDay = request.budget?.perDay;
  if (perDay && perDay > 0) return perDay / 3;

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

function clampNumber(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function buildHintPriceMap(hints: IngredientPriceHint[]): Map<string, number> {
  const grouped = new Map<string, number[]>();
  for (const hint of hints) {
    const key = normalize(hint.ingredient);
    if (!key) continue;
    const bucket = grouped.get(key) ?? [];
    bucket.push(Math.max(0, hint.priceRub));
    grouped.set(key, bucket);
  }

  const resolved = new Map<string, number>();
  for (const [key, prices] of grouped.entries()) {
    if (!prices.length) continue;
    const avg = prices.reduce((sum, value) => sum + value, 0) / prices.length;
    resolved.set(key, round2(avg));
  }
  return resolved;
}

type ResolvedRecipeCost = {
  value: number;
  confidence: number;
};

function resolveDefaultIngredientCost(hintPriceByIngredient: Map<string, number>): number {
  const values = Array.from(hintPriceByIngredient.values()).filter((value) => value > 0);
  if (!values.length) return 45;
  const avg = values.reduce((sum, value) => sum + value, 0) / values.length;
  return round2(clampNumber(avg, 20, 120));
}

function resolveRecipeCostCached(
  recipe: Recipe,
  hintPriceByIngredient: Map<string, number>,
  defaultIngredientCost: number,
  cache: Map<string, ResolvedRecipeCost>
): ResolvedRecipeCost {
  const cached = cache.get(recipe.id);
  if (cached) return cached;
  const resolved = resolveRecipeEstimatedCost(recipe, hintPriceByIngredient, defaultIngredientCost);
  cache.set(recipe.id, resolved);
  return resolved;
}

function resolveRecipeEstimatedCost(
  recipe: Recipe,
  hintPriceByIngredient: Map<string, number>,
  defaultIngredientCost: number
): ResolvedRecipeCost {
  if (typeof recipe.estimatedCost === "number" && Number.isFinite(recipe.estimatedCost) && recipe.estimatedCost > 0) {
    return {
      value: round2(recipe.estimatedCost),
      confidence: 0.85
    };
  }

  if (!recipe.ingredients.length) {
    return {
      value: round2(defaultIngredientCost),
      confidence: 0.2
    };
  }

  let total = 0;
  let matched = 0;
  for (const ingredient of recipe.ingredients) {
    const key = normalize(ingredient);
    const price = hintPriceByIngredient.get(key);
    if (price == null) continue;
    total += price;
    matched += 1;
  }

  const totalIngredients = Math.max(1, recipe.ingredients.length);
  const missing = totalIngredients - matched;
  const fallbackTail = missing * (defaultIngredientCost * 0.75);
  const estimated = matched > 0 ? total + fallbackTail : totalIngredients * defaultIngredientCost;
  const confidence = matched > 0
    ? clampNumber((matched / totalIngredients) * 0.8, 0.25, 0.8)
    : 0.2;

  return {
    value: round2(Math.max(0, estimated)),
    confidence: round2(confidence)
  };
}

function normalizeCostSignal(input: {
  value: number;
  minCost: number;
  maxCost: number;
  perMealBudget?: number;
}): number {
  if (input.perMealBudget && input.perMealBudget > 0) {
    return clampNumber(input.value / input.perMealBudget, 0, 2);
  }

  const spread = input.maxCost - input.minCost;
  if (spread <= 0.000_1) return 0.5;
  return clampNumber((input.value - input.minCost) / spread, 0, 1.5);
}

function composeObjectiveScore(input: {
  objective: "cost_macro" | "balanced";
  normalizedCost: number;
  macroDeviation: number;
  repetitionPenalty: number;
  conveniencePenalty: number;
  availabilityPenalty: number;
  historyPenalty: number;
  lowConfidencePenalty: number;
  expiringBonus: number;
  baseRankBonus: number;
}): number {
  const profile = input.objective === "cost_macro"
    ? {
      macro: 0.42,
      cost: 0.26,
      repetition: 0.14,
      convenience: 0.08,
      availability: 0.07,
      history: 0.05,
      confidence: 0.05,
      expiringBonus: 0.06,
      rankBonus: 0.09
    }
    : {
      macro: 0.45,
      cost: 0.12,
      repetition: 0.18,
      convenience: 0.1,
      availability: 0.08,
      history: 0.08,
      confidence: 0.04,
      expiringBonus: 0.08,
      rankBonus: 0.1
    };

  const weighted =
    profile.macro * input.macroDeviation +
    profile.cost * input.normalizedCost +
    profile.repetition * input.repetitionPenalty +
    profile.convenience * input.conveniencePenalty +
    profile.availability * input.availabilityPenalty +
    profile.history * input.historyPenalty +
    profile.confidence * input.lowConfidencePenalty -
    profile.expiringBonus * input.expiringBonus -
    profile.rankBonus * clampNumber(input.baseRankBonus, 0, 2);

  return round2(weighted);
}

function repetitionPenaltyScore(input: {
  recipe: Recipe;
  dayRecipeIds: Set<string>;
  recipeUsageCount: Map<string, number>;
  cuisineUsageCount: Map<string, number>;
  previousCuisine?: string;
}): number {
  const recipeKey = input.recipe.id;
  const recipeRepeats = input.recipeUsageCount.get(recipeKey) ?? 0;
  const cuisineKey = input.recipe.cuisine ? normalize(input.recipe.cuisine) : undefined;
  const cuisineRepeats = cuisineKey ? (input.cuisineUsageCount.get(cuisineKey) ?? 0) : 0;
  const sameAsPreviousCuisine = cuisineKey && input.previousCuisine === cuisineKey ? 1 : 0;
  const sameRecipeInDay = input.dayRecipeIds.has(recipeKey) ? 1 : 0;

  return (
    recipeRepeats * 0.75 +
    cuisineRepeats * 0.32 +
    sameAsPreviousCuisine * 0.35 +
    sameRecipeInDay * 1.25
  );
}

function conveniencePenaltyScore(recipe: Recipe, maxPrepTime?: number): number {
  const totalTime = estimatePreparationMinutes(recipe);
  const difficultyPenalty = recipeDifficultyPenalty(recipe.difficulty);
  const expectedLimit = maxPrepTime && maxPrepTime > 0 ? maxPrepTime : 45;
  const timePenalty = clampNumber((totalTime - expectedLimit) / Math.max(expectedLimit, 1), 0, 2);
  return timePenalty + difficultyPenalty;
}

function estimatePreparationMinutes(recipe: Recipe): number {
  if (recipe.times?.totalMinutes && recipe.times.totalMinutes > 0) {
    return recipe.times.totalMinutes;
  }
  const prep = recipe.times?.prepMinutes ?? 0;
  const cook = recipe.times?.cookMinutes ?? 0;
  if (prep > 0 || cook > 0) {
    return prep + cook;
  }
  const ingredientFactor = recipe.ingredients.length * 2.8;
  const instructionFactor = recipe.instructions.length * 4.2;
  return 12 + ingredientFactor + instructionFactor;
}

function recipeDifficultyPenalty(difficulty: RecipeDifficulty | undefined): number {
  switch (difficulty) {
    case "easy":
      return 0.05;
    case "medium":
      return 0.12;
    case "hard":
      return 0.22;
    default:
      return 0.1;
  }
}

function availabilityPenaltyScore(recipe: Recipe, availableIngredients: Set<string>): number {
  if (!recipe.ingredients.length) return 0.8;
  const total = recipe.ingredients.length;
  const missing = recipe.ingredients
    .map((ingredient) => normalize(ingredient))
    .filter((ingredient) => ingredient.length > 0)
    .filter((ingredient) => !availableIngredients.has(ingredient))
    .length;
  return missing / total;
}

function expiringIngredientBonus(recipe: Recipe, expiringSoonKeywords: string[]): number {
  if (!recipe.ingredients.length || !expiringSoonKeywords.length) return 0;
  const expiringSet = new Set(expiringSoonKeywords.map(normalize));
  if (!expiringSet.size) return 0;
  let matched = 0;
  for (const ingredient of recipe.ingredients) {
    if (expiringSet.has(normalize(ingredient))) {
      matched += 1;
    }
  }
  return matched / recipe.ingredients.length;
}

function averageMacroDeviation(targets: Nutrition, nutrition: Nutrition | undefined): number {
  if (!nutrition) return 0.6;

  const checks: Array<[number | undefined, number | undefined]> = [
    [targets.kcal, nutrition.kcal],
    [targets.protein, nutrition.protein],
    [targets.fat, nutrition.fat],
    [targets.carbs, nutrition.carbs]
  ];

  let sum = 0;
  let count = 0;

  for (const [target, actual] of checks) {
    if (!target || target <= 0) continue;
    if (!actual || actual < 0) return 1;

    sum += Math.abs(target - actual) / Math.max(target, 1);
    count += 1;
  }

  return count > 0 ? sum / count : 0.6;
}
