import type { 
  RecommendPayload, 
  Recipe, 
  RecipeDifficulty, 
  Season, 
  DietType,
  MealType,
  Nutrition 
} from "../types/contracts.js";
import { nutritionFit, overlapScore } from "../utils/normalize.js";

export type RankedRecipe = {
  recipe: Recipe;
  score: number;
  scoreBreakdown: Record<string, number>;
  matchedFilters: string[];
};

const DIET_WEIGHT = 0.12;
const TIME_WEIGHT = 0.08;
const DIVERSITY_WEIGHT = 0.10;
const SEASON_WEIGHT = 0.05;
const ALLERGEN_WEIGHT = 0.15;

export function rankRecipes(candidates: Recipe[], payload: RecommendPayload): RankedRecipe[] {
  const excludes = new Set((payload.exclude ?? []).map((e) => e.toLowerCase()));
  const excludeRecent = new Set(payload.excludeRecentRecipes ?? []);
  const limit = payload.limit ?? 30;
  const currentSeason = getCurrentSeason();
  
  const ranked = candidates
    .map((recipe) => {
      const matchedFilters: string[] = [];
      let score = 0;
      
      // Base scores (same as before)
      const expiry = overlapScore(recipe.ingredients, payload.expiringSoonKeywords);
      const inStock = overlapScore(recipe.ingredients, payload.ingredientKeywords);
      const nutrition = calculateNutritionScore(recipe.nutrition, payload.targets);
      
      score += 0.22 * expiry + 0.22 * inStock + 0.34 * nutrition;
      if (expiry > 0) matchedFilters.push("expiring");
      if (inStock > 0) matchedFilters.push("in_stock");
      
      // Budget
      const perMeal = payload.budget?.perMeal;
      const budget = !perMeal || !recipe.estimatedCost ? 0.5 : Math.max(0, 1 - recipe.estimatedCost / perMeal);
      score += 0.05 * budget;
      
      // Difficulty filters
      if (payload.difficulty && payload.difficulty.length > 0) {
        if (recipe.difficulty && payload.difficulty.includes(recipe.difficulty)) {
          score += 0.05;
          matchedFilters.push("difficulty");
        }
      }
      
      // Prep time filter
      if (payload.maxPrepTime && recipe.times?.totalMinutes) {
        if (recipe.times.totalMinutes <= payload.maxPrepTime) {
          score += TIME_WEIGHT;
          matchedFilters.push("quick");
        }
      } else if (payload.maxPrepTime) {
        // Estimate if not provided
        const estimatedTime = estimateCookTime(recipe);
        if (estimatedTime <= payload.maxPrepTime) {
          score += TIME_WEIGHT * 0.5;
        }
      }
      
      // Diet filters
      if (payload.diets && payload.diets.length > 0) {
        const recipeDiets = recipe.diets ?? [];
        const hasDietMatch = payload.diets.some(d => recipeDiets.includes(d));
        if (hasDietMatch) {
          score += DIET_WEIGHT;
          matchedFilters.push("diet");
        }
      }
      
      // Season filter
      if (payload.seasons && payload.seasons.length > 0) {
        if (recipe.season === "all" || !recipe.season || payload.seasons.includes(recipe.season)) {
          score += SEASON_WEIGHT;
        } else if (recipe.season === currentSeason) {
          score += SEASON_WEIGHT * 1.5;
          matchedFilters.push("seasonal");
        }
      }
      
      // Meal type filter
      if (payload.mealTypes && payload.mealTypes.length > 0) {
        const recipeMealTypes = recipe.mealTypes ?? ["lunch", "dinner"];
        if (payload.mealTypes.some(mt => recipeMealTypes.includes(mt))) {
          score += 0.05;
        }
      }
      
      // Max calories filter
      if (payload.maxCalories && recipe.caloriesPerServing) {
        if (recipe.caloriesPerServing <= payload.maxCalories) {
          score += 0.03;
        }
      }
      
      // Min protein filter
      if (payload.minProtein && recipe.nutrition?.protein) {
        if (recipe.nutrition.protein >= payload.minProtein) {
          score += 0.03;
        }
      }
      
      // Diversity - avoid recent recipes
      if (excludeRecent.has(recipe.id)) {
        score -= (payload.diversityWeight ?? DIVERSITY_WEIGHT);
      } else {
        score += (payload.diversityWeight ?? DIVERSITY_WEIGHT) * 0.3;
      }
      
      // Cuisine preference
      const preference = payload.cuisine?.some((c) => recipe.tags?.includes(c)) ? 0.05 : 0;
      score += preference;
      
      // Penalties
      const hasDisliked = recipe.ingredients.some((i) => excludes.has(i.toLowerCase()));
      const bonesFlag = payload.avoidBones && recipe.tags?.includes("с костями");
      const penalty = (hasDisliked ? 0.8 : 0) + (bonesFlag ? 0.4 : 0);
      score -= penalty;
      
      // Macro penalty for strict tracking
      const macroDeviation = averageMacroDeviation(payload.targets, recipe.nutrition);
      const nutritionPenalty = macroDeviation <= 0.25 ? 0 : Math.min(1, (macroDeviation - 0.25) * 1.6);
      score -= 0.20 * nutritionPenalty;
      
      return {
        recipe,
        score: Math.max(0, score),
        scoreBreakdown: {
          expiry,
          inStock,
          nutrition,
          macroDeviation,
          budget,
          time: payload.maxPrepTime ? (recipe.times?.totalMinutes ? recipe.times.totalMinutes / payload.maxPrepTime : 0.5) : 0,
          diet: payload.diets ? (recipe.diets?.some(d => payload.diets!.includes(d)) ? 1 : 0) : 0,
          diversity: excludeRecent.has(recipe.id) ? -0.1 : 0.1,
          penalties: -penalty,
          nutritionPenalty: -nutritionPenalty
        },
        matchedFilters
      };
    })
    .sort((a, b) => b.score - a.score);

  // Apply strict filters first
  let filtered = ranked;
  
  if (payload.strictNutrition) {
    const tolerance = (clamp(payload.macroTolerancePercent ?? 25, 5, 60)) / 100;
    const strictMatches = filtered.filter((item) => 
      isWithinTolerance(item.recipe.nutrition, payload.targets, tolerance)
    );
    if (strictMatches.length > 0) {
      filtered = strictMatches;
    }
  }

  return filtered.slice(0, limit);
}

function calculateNutritionScore(nutrition: Nutrition | undefined, targets: Nutrition): number {
  if (!nutrition) return 0.5;
  
  let score = 0;
  let count = 0;
  
  const checks: Array<[number | undefined, number | undefined]> = [
    [targets.kcal, nutrition.kcal],
    [targets.protein, nutrition.protein],
    [targets.fat, nutrition.fat],
    [targets.carbs, nutrition.carbs]
  ];
  
  for (const [target, actual] of checks) {
    if (!target || target <= 0) continue;
    if (!actual || actual < 0) continue;
    
    const diff = Math.abs(target - actual) / Math.max(target, 1);
    const fit = Math.max(0, 1 - diff);
    score += fit;
    count++;
  }
  
  return count > 0 ? score / count : 0.5;
}

function estimateCookTime(recipe: Recipe): number {
  // Estimate based on number of ingredients and instructions
  const ingredientCount = recipe.ingredients.length;
  const instructionCount = recipe.instructions.length;
  
  // Base time: 15 min prep + 30 min cooking per 4 ingredients + 10 min per instruction
  return 15 + (ingredientCount / 4) * 30 + instructionCount * 10;
}

function getCurrentSeason(): Season {
  const month = new Date().getMonth();
  if (month >= 2 && month <= 4) return "spring";
  if (month >= 5 && month <= 7) return "summer";
  if (month >= 8 && month <= 10) return "autumn";
  return "winter";
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

    const diff = Math.abs(target - actual) / Math.max(target, 1);
    sum += diff;
    count++;
  }

  return count > 0 ? sum / count : 0.6;
}

function isWithinTolerance(
  nutrition: Nutrition | undefined,
  targets: Nutrition,
  tolerance: number
): boolean {
  if (!nutrition) return false;

  const checks: Array<[number | undefined, number | undefined]> = [
    [targets.kcal, nutrition.kcal],
    [targets.protein, nutrition.protein],
    [targets.fat, nutrition.fat],
    [targets.carbs, nutrition.carbs]
  ];

  for (const [target, actual] of checks) {
    if (!target || target <= 0) continue;
    if (!actual || actual < 0) return false;

    const deviation = Math.abs(actual - target) / Math.max(target, 1);
    if (deviation > tolerance) return false;
  }

  return true;
}

function clamp(value: number, minValue: number, maxValue: number): number {
  return Math.min(Math.max(value, minValue), maxValue);
}

export function calculateDiversityScore(recipes: Recipe[]): number {
  if (recipes.length <= 1) return 1.0;
  
  const cuisines = new Set<string>();
  const mealTypes = new Set<string>();
  
  for (const recipe of recipes) {
    if (recipe.cuisine) cuisines.add(recipe.cuisine);
    if (recipe.mealTypes) recipe.mealTypes.forEach(mt => mealTypes.add(mt));
  }
  
  const uniqueRatio = (cuisines.size + mealTypes.size) / (recipes.length * 2);
  return Math.min(1, uniqueRatio);
}
