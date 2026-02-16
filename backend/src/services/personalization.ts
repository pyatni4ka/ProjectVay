import type { Recipe, UserMealHistory } from "../types/contracts.js";

export function personalizeRecipes(recipes: Recipe[], history: UserMealHistory | null): Recipe[] {
  if (!history) {
    return recipes;
  }

  const favoriteCuisines = new Set(history.preferences.favoriteCuisines.map((x) => x.toLowerCase()));
  const dislikedIngredients = new Set(history.preferences.dislikedIngredients.map((x) => x.toLowerCase()));
  const recentlyUsed = new Set(history.meals.slice(-20).map((meal) => meal.recipeId));

  return recipes
    .map((recipe) => {
      let bonus = 0;

      if (recipe.cuisine && favoriteCuisines.has(recipe.cuisine.toLowerCase())) {
        bonus += 0.15;
      }

      if (recipe.ingredients.some((ing) => dislikedIngredients.has(ing.toLowerCase()))) {
        bonus -= 0.25;
      }

      if (recentlyUsed.has(recipe.id)) {
        bonus -= 0.12;
      }

      if (recipe.rating && recipe.rating > 70) {
        bonus += 0.07;
      }

      return { recipe, score: bonus };
    })
    .sort((a, b) => b.score - a.score)
    .map((item) => item.recipe);
}

export function buildUserTasteProfile(history: UserMealHistory): {
  topCuisines: string[];
  avoidedIngredients: string[];
  averageMealTypeShare: Record<string, number>;
} {
  const cuisineCounter = new Map<string, number>();
  const mealTypeCounter = new Map<string, number>();

  for (const meal of history.meals) {
    mealTypeCounter.set(meal.mealType, (mealTypeCounter.get(meal.mealType) ?? 0) + 1);
  }

  for (const cuisine of history.preferences.favoriteCuisines) {
    cuisineCounter.set(cuisine, (cuisineCounter.get(cuisine) ?? 0) + 1);
  }

  const totalMeals = history.meals.length || 1;
  const averageMealTypeShare: Record<string, number> = {};
  for (const [mealType, count] of mealTypeCounter.entries()) {
    averageMealTypeShare[mealType] = count / totalMeals;
  }

  const topCuisines = Array.from(cuisineCounter.entries())
    .sort((a, b) => b[1] - a[1])
    .map(([name]) => name)
    .slice(0, 5);

  return {
    topCuisines,
    avoidedIngredients: history.preferences.dislikedIngredients,
    averageMealTypeShare
  };
}
