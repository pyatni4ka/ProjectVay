import type { IngestionProduct, IngestionRecipe } from "./types.js";

export function dedupeProducts(products: IngestionProduct[]): IngestionProduct[] {
  const byKey = new Map<string, IngestionProduct>();
  for (const product of products) {
    const key = product.barcode?.trim() || normalize(product.name);
    const previous = byKey.get(key);
    if (!previous) {
      byKey.set(key, product);
      continue;
    }

    const previousScore = productSignalStrength(previous);
    const nextScore = productSignalStrength(product);
    if (nextScore >= previousScore) {
      byKey.set(key, product);
    }
  }
  return Array.from(byKey.values());
}

export function dedupeRecipes(recipes: IngestionRecipe[]): IngestionRecipe[] {
  const byKey = new Map<string, IngestionRecipe>();
  for (const recipe of recipes) {
    const key = recipe.sourceURL.trim() || `${normalize(recipe.title)}:${normalize(recipe.sourceName)}`;
    const previous = byKey.get(key);
    if (!previous) {
      byKey.set(key, recipe);
      continue;
    }

    const previousScore = recipeSignalStrength(previous);
    const nextScore = recipeSignalStrength(recipe);
    if (nextScore >= previousScore) {
      byKey.set(key, recipe);
    }
  }
  return Array.from(byKey.values());
}

function productSignalStrength(product: IngestionProduct): number {
  let score = 0;
  if (product.barcode) score += 4;
  if (product.brand) score += 2;
  if (product.category) score += 1;
  if (product.nutrition && Object.keys(product.nutrition).length > 0) score += 2;
  score += Math.min(product.name.length / 24, 3);
  return score;
}

function recipeSignalStrength(recipe: IngestionRecipe): number {
  let score = 0;
  if (recipe.imageURL) score += 2;
  if (recipe.totalTimeMinutes) score += 1;
  if (recipe.nutrition && Object.keys(recipe.nutrition).length > 0) score += 2;
  score += recipe.ingredients.length * 0.2;
  score += recipe.instructions.length * 0.25;
  return score;
}

function normalize(value: string): string {
  return value.trim().toLowerCase();
}
