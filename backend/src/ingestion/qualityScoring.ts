import type { IngestionProduct, IngestionRecipe } from "./types.js";

export function scoreProductCompleteness(product: IngestionProduct): number {
  let score = 0;
  if (product.name.trim().length > 1) score += 0.35;
  if (product.barcode && product.barcode.length >= 8) score += 0.25;
  if (product.brand) score += 0.1;
  if (product.category) score += 0.1;
  if (product.nutrition && Object.keys(product.nutrition).length > 0) score += 0.15;
  if (product.provenance && Object.keys(product.provenance).length > 0) score += 0.05;
  return clamp(score, 0, 1);
}

export function scoreRecipeCompleteness(recipe: IngestionRecipe): number {
  let score = 0;
  if (recipe.title.trim().length > 1) score += 0.2;
  if (recipe.sourceURL.startsWith("http")) score += 0.1;
  if (recipe.imageURL) score += 0.1;
  if (recipe.ingredients.length >= 3) score += 0.2;
  if (recipe.instructions.length >= 2) score += 0.2;
  if (recipe.nutrition && Object.keys(recipe.nutrition).length > 0) score += 0.12;
  if (recipe.totalTimeMinutes && recipe.totalTimeMinutes > 0) score += 0.05;
  if (recipe.provenance && Object.keys(recipe.provenance).length > 0) score += 0.03;
  return clamp(score, 0, 1);
}

export function passesMinimumQualityScore(score: number, min: number = 0.35): boolean {
  return score >= min;
}

function clamp(value: number, minValue: number, maxValue: number): number {
  return Math.min(Math.max(value, minValue), maxValue);
}
