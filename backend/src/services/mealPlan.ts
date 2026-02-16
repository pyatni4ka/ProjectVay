import type {
  MealPlanDay,
  MealPlanEntry,
  MealPlanRequest,
  MealPlanResponse,
  MealType,
  RecommendPayload,
  Recipe,
  Nutrition,
  RecipeDifficulty,
  DietType
} from "../types/contracts.js";
import { rankRecipes, calculateDiversityScore } from "./recommendation.js";

const MEAL_TYPES: MealType[] = ["breakfast", "lunch", "dinner"];
const DAY_NAMES = ["Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"];

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
  
  const recipeHistory = new Set(request.userHistory ?? []);

  // Calculate macro targets per meal
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

  const ranked = rankRecipes(candidates, recommendPayload);
  
  if (ranked.length < MEAL_TYPES.length) {
    warnings.push("Недостаточно рецептов для разнообразного плана.");
  }

  const days: MealPlanDay[] = [];
  let estimatedTotalCost = 0;
  let totalNutrition: Nutrition = {};
  
  // Track used recipes for diversity
  const usedRecipeIds = new Set<string>();
  const usedCuisines = new Set<string>();

  for (let dayIndex = 0; dayIndex < daysCount; dayIndex += 1) {
    const entries: MealPlanEntry[] = [];
    let dayKcalTotal = 0;
    let dayProteinTotal = 0;
    let dayFatTotal = 0;
    let dayCarbsTotal = 0;
    let dayCostTotal = 0;
    
    // Calculate remaining macros for the day
    const remainingMeals = MEAL_TYPES.length - entries.length;
    const remainingKcal = effectiveDayKcal ? effectiveDayKcal - dayKcalTotal : undefined;
    const remainingProtein = macroTargets.protein ? macroTargets.protein * remainingMeals : undefined;
    const remainingFat = macroTargets.fat ? macroTargets.fat * remainingMeals : undefined;
    const remainingCarbs = macroTargets.carbs ? macroTargets.carbs * remainingMeals : undefined;

    for (let mealIndex = 0; mealIndex < MEAL_TYPES.length; mealIndex += 1) {
      const mealType = MEAL_TYPES[mealIndex]!;
      
      // Find best recipe for this meal type, avoiding repetition
      const rankedForMeal = ranked.filter(item => {
        if (usedRecipeIds.has(item.recipe.id)) return false;
        if (request.avoidRepetition && usedCuisines.has(item.recipe.cuisine || "")) return false;
        return true;
      });
      
      const rankedOffset = dayIndex * MEAL_TYPES.length + mealIndex;
      let rankedItem = rankedForMeal[rankedOffset] ?? rankedForMeal[rankedOffset % Math.max(rankedForMeal.length, 1)];
      
      // Fallback to original ranked list if needed
      if (!rankedItem) {
        rankedItem = ranked[rankedOffset] ?? ranked[rankedOffset % Math.max(ranked.length, 1)];
      }

      if (!rankedItem) continue;

      const recipe = rankedItem.recipe;
      usedRecipeIds.add(recipe.id);
      if (recipe.cuisine) usedCuisines.add(recipe.cuisine);

      const kcal = recipe.nutrition?.kcal ?? recipe.caloriesPerServing ?? 0;
      const protein = recipe.nutrition?.protein ?? 0;
      const fat = recipe.nutrition?.fat ?? 0;
      const carbs = recipe.nutrition?.carbs ?? 0;
      const estimatedCost = recipe.estimatedCost ?? 0;
      
      dayKcalTotal += kcal;
      dayProteinTotal += protein;
      dayFatTotal += fat;
      dayCarbsTotal += carbs;
      dayCostTotal += estimatedCost;

      entries.push({
        mealType,
        recipe,
        score: rankedItem.score,
        estimatedCost,
        kcal,
        protein,
        fat,
        carbs
      });

      // Collect missing ingredients
      const missing = recipe.ingredients
        .map(ingredient => ingredient.trim())
        .filter(ingredient => ingredient.length > 0)
        .filter(ingredient => !availableIngredients.has(normalize(ingredient)));
      missing.forEach(ing => shoppingListSet.add(ing));
    }

    const date = new Date(startDate);
    date.setHours(0, 0, 0, 0);
    date.setDate(date.getDate() + dayIndex);
    
    const dayOfWeek = DAY_NAMES[date.getDay()];

    // Calculate meal times based on schedule
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
      missingIngredients: Array.from(shoppingListSet).slice(0, 10),
      mealSchedule
    });

    estimatedTotalCost += dayCostTotal;
    
    // Aggregate nutrition
    totalNutrition.kcal = (totalNutrition.kcal ?? 0) + dayKcalTotal;
    totalNutrition.protein = (totalNutrition.protein ?? 0) + dayProteinTotal;
    totalNutrition.fat = (totalNutrition.fat ?? 0) + dayFatTotal;
    totalNutrition.carbs = (totalNutrition.carbs ?? 0) + dayCarbsTotal;
  }

  // Group shopping list by category
  const shoppingListGrouped = groupShoppingList(Array.from(shoppingListSet));
  
  // Calculate diversity score
  const allRecipes = days.flatMap(d => d.entries.map(e => e.recipe));
  const diversityScore = calculateDiversityScore(allRecipes);
  const varietyScore = calculateVarietyScore(allRecipes);

  if (beveragesKcal > 0) {
    warnings.push(`Учтён калораж напитков: ${round2(beveragesKcal)} ккал/день.`);
  }
  
  if (diversityScore < 0.5) {
    warnings.push("Рекомендуем добавить больше разнообразных продуктов для лучшего плана.");
  }

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
    varietyScore: round2(varietyScore)
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
