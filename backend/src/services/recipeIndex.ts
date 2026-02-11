import type { Recipe } from "../types/contracts.js";

type SearchFilters = {
  query?: string;
  cuisine?: string[];
  limit?: number;
};

export class RecipeIndex {
  private readonly byID = new Map<string, Recipe>();

  constructor(seedRecipes: Recipe[] = []) {
    for (const recipe of seedRecipes) {
      this.upsert(recipe);
    }
  }

  upsert(recipe: Recipe): void {
    if (!recipe.imageURL) {
      return;
    }

    this.byID.set(recipe.id, recipe);
  }

  all(): Recipe[] {
    return Array.from(this.byID.values());
  }

  search(filters: SearchFilters): Recipe[] {
    const query = normalizeQuery(filters.query);
    const cuisines = (filters.cuisine ?? []).map((item) => item.toLowerCase());
    const limit = Math.max(1, Math.min(filters.limit ?? 50, 200));

    const recipes = this.all()
      .filter((recipe) => {
        if (query.length > 0) {
          const haystack = [
            recipe.title,
            recipe.sourceName,
            ...(recipe.ingredients ?? []),
            ...(recipe.tags ?? [])
          ]
            .join(" ")
            .toLowerCase();
          if (!haystack.includes(query)) {
            return false;
          }
        }

        if (cuisines.length > 0) {
          const tags = (recipe.tags ?? []).map((item) => item.toLowerCase());
          if (!cuisines.some((cuisine) => tags.includes(cuisine))) {
            return false;
          }
        }

        return true;
      })
      .slice(0, limit);

    return recipes;
  }
}

function normalizeQuery(value: string | undefined): string {
  return (value ?? "").trim().toLowerCase();
}
