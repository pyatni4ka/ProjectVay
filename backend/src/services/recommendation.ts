import type { RecommendPayload, Recipe } from "../types/contracts.js";
import { nutritionFit, overlapScore } from "../utils/normalize.js";

export type RankedRecipe = {
  recipe: Recipe;
  score: number;
  scoreBreakdown: Record<string, number>;
};

export function rankRecipes(candidates: Recipe[], payload: RecommendPayload): RankedRecipe[] {
  const excludes = new Set((payload.exclude ?? []).map((e) => e.toLowerCase()));

  return candidates
    .map((recipe) => {
      const expiry = overlapScore(recipe.ingredients, payload.expiringSoonKeywords);
      const inStock = overlapScore(recipe.ingredients, payload.ingredientKeywords);
      const nutrition =
        (nutritionFit(payload.targets.kcal, recipe.nutrition?.kcal) +
          nutritionFit(payload.targets.protein, recipe.nutrition?.protein) +
          nutritionFit(payload.targets.fat, recipe.nutrition?.fat) +
          nutritionFit(payload.targets.carbs, recipe.nutrition?.carbs)) /
        4;

      const perMeal = payload.budget?.perMeal;
      const budget = !perMeal || !recipe.estimatedCost ? 0.5 : Math.max(0, 1 - recipe.estimatedCost / perMeal);
      const macroDeviation = averageMacroDeviation(payload.targets, recipe.nutrition);
      const nutritionPenalty = macroDeviation <= 0.25 ? 0 : Math.min(1, (macroDeviation - 0.25) * 1.6);

      const hasDisliked = recipe.ingredients.some((i) => excludes.has(i.toLowerCase()));
      const bonesFlag = payload.avoidBones && recipe.tags?.includes("с костями");
      const penalty = (hasDisliked ? 0.8 : 0) + (bonesFlag ? 0.4 : 0);

      const preference = payload.cuisine?.some((c) => recipe.tags?.includes(c)) ? 1 : 0;

      const score =
        0.32 * expiry +
        0.27 * inStock +
        0.22 * nutrition +
        0.10 * budget +
        0.05 * preference -
        0.05 * penalty -
        0.08 * nutritionPenalty;

      return {
        recipe,
        score,
        scoreBreakdown: {
          expiry,
          inStock,
          nutrition,
          macroDeviation,
          nutritionPenalty: -nutritionPenalty,
          budget,
          preference,
          penalties: -penalty
        }
      };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, payload.limit ?? 30);
}

function averageMacroDeviation(targets: RecommendPayload["targets"], nutrition: Recipe["nutrition"]): number {
  const checks: Array<[number | undefined, number | undefined]> = [
    [targets.kcal, nutrition?.kcal],
    [targets.protein, nutrition?.protein],
    [targets.fat, nutrition?.fat],
    [targets.carbs, nutrition?.carbs]
  ];

  let sum = 0;
  let count = 0;

  for (const [target, actual] of checks) {
    if (!target || target <= 0) {
      continue;
    }
    if (!actual || actual < 0) {
      return 1;
    }

    const diff = Math.abs(target - actual) / Math.max(target, 1);
    sum += diff;
    count += 1;
  }

  if (!count) {
    return 0.6;
  }

  return sum / count;
}
