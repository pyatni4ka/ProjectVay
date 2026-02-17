import type { Recipe, RecipeQualityReport } from "../types/contracts.js";

export function buildRecipeQualityReport(recipe: Recipe): RecipeQualityReport {
  const hasNutrition = Boolean(
    recipe.nutrition && (
      recipe.nutrition.kcal != null ||
      recipe.nutrition.protein != null ||
      recipe.nutrition.fat != null ||
      recipe.nutrition.carbs != null ||
      recipe.nutrition.fiber != null ||
      recipe.nutrition.sugar != null ||
      recipe.nutrition.sodium != null
    )
  );

  const hasImage = Boolean(recipe.imageURL);
  const hasServings = (recipe.servings ?? 0) > 0;
  const hasTotalTime = (recipe.times?.totalMinutes ?? 0) > 0;
  const ingredientCount = recipe.ingredients.length;
  const instructionCount = recipe.instructions.length;

  const missingFields: string[] = [];
  if (!hasImage) missingFields.push("image");
  if (!hasNutrition) missingFields.push("nutrition");
  if (!hasServings) missingFields.push("servings");
  if (!hasTotalTime) missingFields.push("time");
  if (ingredientCount === 0) missingFields.push("ingredients");
  if (instructionCount === 0) missingFields.push("instructions");

  const score = clamp01(
    (hasImage ? 0.2 : 0) +
      (hasNutrition ? 0.2 : 0) +
      (hasServings ? 0.15 : 0) +
      (hasTotalTime ? 0.15 : 0) +
      Math.min(0.15, ingredientCount * 0.015) +
      Math.min(0.15, instructionCount * 0.015)
  );

  return {
    hasImage,
    hasNutrition,
    hasServings,
    hasTotalTime,
    ingredientCount,
    instructionCount,
    score: round3(score),
    missingFields
  };
}

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}

function round3(value: number): number {
  return Math.round(value * 1000) / 1000;
}
