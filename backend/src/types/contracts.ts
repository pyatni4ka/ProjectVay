export type Nutrition = {
  kcal?: number;
  protein?: number;
  fat?: number;
  carbs?: number;
};

export type Recipe = {
  id: string;
  title: string;
  imageURL: string;
  sourceName: string;
  sourceURL: string;
  videoURL?: string | null;
  ingredients: string[];
  instructions: string[];
  nutrition?: Nutrition;
  times?: {
    totalMinutes?: number;
  };
  servings?: number;
  cuisine?: string;
  tags?: string[];
  estimatedCost?: number;
};

export type RecommendPayload = {
  ingredientKeywords: string[];
  expiringSoonKeywords: string[];
  targets: Nutrition;
  budget?: { perMeal?: number };
  exclude?: string[];
  avoidBones?: boolean;
  cuisine?: string[];
  limit?: number;
};

export type MealType = "breakfast" | "lunch" | "dinner";

export type MealPlanRequest = {
  days?: number;
  ingredientKeywords: string[];
  expiringSoonKeywords: string[];
  targets: Nutrition;
  beveragesKcal?: number;
  budget?: {
    perDay?: number;
    perMeal?: number;
  };
  exclude?: string[];
  avoidBones?: boolean;
  cuisine?: string[];
};

export type MealPlanEntry = {
  mealType: MealType;
  recipe: Recipe;
  score: number;
  estimatedCost: number;
  kcal: number;
};

export type MealPlanDay = {
  date: string;
  entries: MealPlanEntry[];
  totals: {
    kcal: number;
    estimatedCost: number;
  };
  targets: {
    kcal?: number;
    perMealKcal?: number;
  };
  missingIngredients: string[];
};

export type MealPlanResponse = {
  days: MealPlanDay[];
  shoppingList: string[];
  estimatedTotalCost: number;
  warnings: string[];
};
