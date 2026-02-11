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

      const hasDisliked = recipe.ingredients.some((i) => excludes.has(i.toLowerCase()));
      const bonesFlag = payload.avoidBones && recipe.tags?.includes("с костями");
      const penalty = (hasDisliked ? 0.8 : 0) + (bonesFlag ? 0.4 : 0);

      const preference = payload.cuisine?.some((c) => recipe.tags?.includes(c)) ? 1 : 0;

      const score = 0.35 * expiry + 0.30 * inStock + 0.15 * nutrition + 0.10 * budget + 0.05 * preference - 0.05 * penalty;

      return {
        recipe,
        score,
        scoreBreakdown: {
          expiry,
          inStock,
          nutrition,
          budget,
          preference,
          penalties: -penalty
        }
      };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, payload.limit ?? 30);
}
