import { getEnv } from "../config/env.js";
import type { DietType, ExternalRecipeResponse, ExternalRecipeSearchParams, MealType, Recipe } from "../types/contracts.js";

type FetchRecipeOptions = {
  query?: string;
  ingredients?: string[];
  limit?: number;
  cuisine?: string;
  mealType?: MealType;
  diet?: DietType;
  maxCalories?: number;
};

const DEFAULT_LIMIT = 20;

export async function searchExternalRecipes(options: FetchRecipeOptions): Promise<ExternalRecipeResponse> {
  const env = getEnv();
  if (!env.EXTERNAL_RECIPES_ENABLED) {
    return { provider: "internal", recipes: [], totalResults: 0, page: 1 };
  }

  const [edamam, spoonacular] = await Promise.all([
    searchEdamam(options).catch(() => []),
    searchSpoonacular(options).catch(() => [])
  ]);

  const recipes = dedupeBySourceUrl([...edamam, ...spoonacular]).slice(0, options.limit ?? DEFAULT_LIMIT);

  return {
    provider: edamam.length >= spoonacular.length ? "edamam" : "spoonacular",
    recipes,
    totalResults: recipes.length,
    page: 1
  };
}

async function searchEdamam(options: FetchRecipeOptions): Promise<Recipe[]> {
  const env = getEnv();
  if (!env.EDAMAM_APP_ID || !env.EDAMAM_APP_KEY) {
    return [];
  }

  const query = normalizeQuery(options);
  if (!query) {
    return [];
  }

  const url = new URL("https://api.edamam.com/api/recipes/v2");
  url.searchParams.set("type", "public");
  url.searchParams.set("app_id", env.EDAMAM_APP_ID);
  url.searchParams.set("app_key", env.EDAMAM_APP_KEY);
  url.searchParams.set("q", query);
  url.searchParams.set("random", "false");
  url.searchParams.set("field", "uri");
  url.searchParams.append("field", "label");
  url.searchParams.append("field", "image");
  url.searchParams.append("field", "url");
  url.searchParams.append("field", "ingredientLines");
  url.searchParams.append("field", "totalTime");
  url.searchParams.append("field", "cuisineType");
  url.searchParams.append("field", "mealType");
  url.searchParams.append("field", "dietLabels");
  url.searchParams.append("field", "healthLabels");
  url.searchParams.append("field", "totalNutrients");

  if (options.cuisine) {
    url.searchParams.set("cuisineType", options.cuisine);
  }
  if (options.mealType) {
    url.searchParams.set("mealType", mapMealTypeToEdamam(options.mealType));
  }
  if (options.maxCalories) {
    url.searchParams.set("calories", `0-${Math.max(50, Math.round(options.maxCalories))}`);
  }

  const response = await fetch(url);
  if (!response.ok) {
    return [];
  }

  const data = await response.json();
  const hits = Array.isArray(data?.hits) ? data.hits : [];

  return hits
    .map((hit: any) => mapEdamamRecipe(hit?.recipe))
    .filter((item: Recipe | null): item is Recipe => item !== null)
    .slice(0, options.limit ?? DEFAULT_LIMIT);
}

async function searchSpoonacular(options: FetchRecipeOptions): Promise<Recipe[]> {
  const env = getEnv();
  if (!env.SPOONACULAR_API_KEY) {
    return [];
  }

  const query = normalizeQuery(options);
  if (!query) {
    return [];
  }

  const url = new URL("https://api.spoonacular.com/recipes/complexSearch");
  url.searchParams.set("apiKey", env.SPOONACULAR_API_KEY);
  url.searchParams.set("query", query);
  url.searchParams.set("number", String(Math.min(30, options.limit ?? DEFAULT_LIMIT)));
  url.searchParams.set("addRecipeNutrition", "true");
  url.searchParams.set("addRecipeInformation", "true");
  url.searchParams.set("fillIngredients", "true");

  if (options.cuisine) {
    url.searchParams.set("cuisine", options.cuisine);
  }
  if (options.maxCalories) {
    url.searchParams.set("maxCalories", String(Math.max(50, Math.round(options.maxCalories))));
  }

  const response = await fetch(url);
  if (!response.ok) {
    return [];
  }

  const data = await response.json();
  const results = Array.isArray(data?.results) ? data.results : [];

  return results
    .map((recipe: any) => mapSpoonacularRecipe(recipe))
    .filter((item: Recipe | null): item is Recipe => item !== null)
    .slice(0, options.limit ?? DEFAULT_LIMIT);
}

function mapEdamamRecipe(recipe: any): Recipe | null {
  if (!recipe || typeof recipe !== "object") {
    return null;
  }

  const sourceURL = typeof recipe.url === "string" ? recipe.url : null;
  const title = typeof recipe.label === "string" ? recipe.label : null;
  const imageURL = typeof recipe.image === "string" ? recipe.image : null;

  if (!sourceURL || !title || !imageURL) {
    return null;
  }

  return {
    id: normalizeExternalId(recipe.uri ?? sourceURL),
    title,
    sourceName: "Edamam",
    sourceURL,
    imageURL,
    ingredients: Array.isArray(recipe.ingredientLines) ? recipe.ingredientLines.filter((x: unknown) => typeof x === "string") : [],
    instructions: [],
    nutrition: {
      kcal: numeric(recipe.totalNutrients?.ENERC_KCAL?.quantity),
      protein: numeric(recipe.totalNutrients?.PROCNT?.quantity),
      fat: numeric(recipe.totalNutrients?.FAT?.quantity),
      carbs: numeric(recipe.totalNutrients?.CHOCDF?.quantity)
    },
    cuisine: Array.isArray(recipe.cuisineType) ? recipe.cuisineType[0] : undefined,
    mealTypes: Array.isArray(recipe.mealType) ? recipe.mealType.map(mapEdamamMealType).filter(Boolean) as MealType[] : undefined,
    times: {
      totalMinutes: numeric(recipe.totalTime)
    },
    diets: mapDietsFromLabels(recipe.dietLabels, recipe.healthLabels),
    season: "all",
    difficulty: difficultyFromTime(numeric(recipe.totalTime))
  };
}

function mapSpoonacularRecipe(recipe: any): Recipe | null {
  if (!recipe || typeof recipe !== "object") {
    return null;
  }

  const sourceURL = typeof recipe.sourceUrl === "string" ? recipe.sourceUrl : null;
  const title = typeof recipe.title === "string" ? recipe.title : null;
  const imageURL = typeof recipe.image === "string" ? recipe.image : null;
  if (!sourceURL || !title || !imageURL) {
    return null;
  }

  const nutritionItems = Array.isArray(recipe.nutrition?.nutrients) ? recipe.nutrition.nutrients : [];
  const kcal = findNutrient(nutritionItems, "Calories");
  const protein = findNutrient(nutritionItems, "Protein");
  const fat = findNutrient(nutritionItems, "Fat");
  const carbs = findNutrient(nutritionItems, "Carbohydrates");

  return {
    id: `spoonacular:${recipe.id ?? title.toLowerCase()}`,
    title,
    sourceName: "Spoonacular",
    sourceURL,
    imageURL,
    ingredients: Array.isArray(recipe.extendedIngredients)
      ? recipe.extendedIngredients.map((item: any) => String(item?.name ?? "")).filter(Boolean)
      : [],
    instructions: [],
    nutrition: {
      kcal,
      protein,
      fat,
      carbs
    },
    cuisine: Array.isArray(recipe.cuisines) ? recipe.cuisines[0] : undefined,
    mealTypes: Array.isArray(recipe.dishTypes) ? recipe.dishTypes.map(mapSpoonacularMealType).filter(Boolean) as MealType[] : undefined,
    diets: Array.isArray(recipe.diets) ? recipe.diets.map(mapDietType).filter(Boolean) as DietType[] : undefined,
    times: {
      totalMinutes: numeric(recipe.readyInMinutes)
    },
    servings: numeric(recipe.servings),
    rating: numeric(recipe.spoonacularScore),
    season: "all",
    difficulty: difficultyFromTime(numeric(recipe.readyInMinutes))
  };
}

function normalizeQuery(options: FetchRecipeOptions): string {
  const direct = options.query?.trim();
  if (direct) return direct;
  if (options.ingredients && options.ingredients.length > 0) {
    return options.ingredients.slice(0, 5).join(" ");
  }
  return "";
}

function dedupeBySourceUrl(recipes: Recipe[]): Recipe[] {
  const seen = new Set<string>();
  const result: Recipe[] = [];
  for (const recipe of recipes) {
    if (!recipe.sourceURL || seen.has(recipe.sourceURL)) {
      continue;
    }
    seen.add(recipe.sourceURL);
    result.push(recipe);
  }
  return result;
}

function numeric(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return undefined;
}

function normalizeExternalId(input: string): string {
  return String(input).replace(/[^a-zA-Z0-9:_-]/g, "_");
}

function difficultyFromTime(minutes?: number): Recipe["difficulty"] {
  if (!minutes || minutes <= 0) return "medium";
  if (minutes <= 25) return "easy";
  if (minutes <= 50) return "medium";
  return "hard";
}

function findNutrient(items: any[], key: string): number | undefined {
  const found = items.find((item) => String(item?.name ?? "").toLowerCase() === key.toLowerCase());
  return numeric(found?.amount);
}

function mapEdamamMealType(value: unknown): MealType | null {
  const v = String(value ?? "").toLowerCase();
  if (v.includes("breakfast")) return "breakfast";
  if (v.includes("lunch")) return "lunch";
  if (v.includes("dinner")) return "dinner";
  if (v.includes("snack")) return "snack";
  return null;
}

function mapSpoonacularMealType(value: unknown): MealType | null {
  const v = String(value ?? "").toLowerCase();
  if (["breakfast"].some((x) => v.includes(x))) return "breakfast";
  if (["lunch", "main course"].some((x) => v.includes(x))) return "lunch";
  if (["dinner"].some((x) => v.includes(x))) return "dinner";
  if (["snack", "dessert"].some((x) => v.includes(x))) return "snack";
  return null;
}

function mapMealTypeToEdamam(value: MealType): string {
  switch (value) {
    case "breakfast":
      return "Breakfast";
    case "lunch":
      return "Lunch";
    case "dinner":
      return "Dinner";
    default:
      return "Snack";
  }
}

function mapDietType(value: unknown): DietType | null {
  const v = String(value ?? "").toLowerCase();
  if (v.includes("vegetarian")) return "vegetarian";
  if (v.includes("vegan")) return "vegan";
  if (v.includes("gluten")) return "gluten_free";
  if (v.includes("dairy")) return "dairy_free";
  if (v.includes("keto")) return "keto";
  if (v.includes("low carb")) return "low_carb";
  return null;
}

function mapDietsFromLabels(...labels: unknown[]): DietType[] {
  const result = new Set<DietType>();
  for (const bucket of labels) {
    if (!Array.isArray(bucket)) continue;
    for (const raw of bucket) {
      const mapped = mapDietType(raw);
      if (mapped) result.add(mapped);
    }
  }
  return Array.from(result);
}
