export type Nutrition = {
  kcal?: number;
  protein?: number;
  fat?: number;
  carbs?: number;
  fiber?: number;
  sugar?: number;
  sodium?: number;
};

export type RecipeDifficulty = "easy" | "medium" | "hard";

export type Season = "spring" | "summer" | "autumn" | "winter" | "all";

export type DietType = 
  | "vegetarian" 
  | "vegan" 
  | "gluten_free" 
  | "dairy_free" 
  | "keto" 
  | "low_carb" 
  | "diabetic"
  | "halal"
  | "kosher";

export type MealType = "breakfast" | "lunch" | "dinner" | "snack";

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
    prepMinutes?: number;
    cookMinutes?: number;
    totalMinutes?: number;
  };
  servings?: number;
  cuisine?: string;
  tags?: string[];
  difficulty?: RecipeDifficulty;
  season?: Season;
  diets?: DietType[];
  estimatedCost?: number;
  caloriesPerServing?: number;
  mealTypes?: MealType[];
  allergens?: string[];
  rating?: number;
  reviewCount?: number;
};

export type NormalizedIngredient = {
  raw: string;
  normalizedKey: string;
  name: string;
  quantity?: number;
  unit?: string;
};

export type RecipeQualityReport = {
  hasImage: boolean;
  hasNutrition: boolean;
  hasServings: boolean;
  hasTotalTime: boolean;
  ingredientCount: number;
  instructionCount: number;
  score: number;
  missingFields: string[];
};

export type RecipeParseRequest = {
  url: string;
};

export type RecipeParseResponse = {
  recipe: Recipe;
  normalizedIngredients: NormalizedIngredient[];
  quality: RecipeQualityReport;
  diagnostics: string[];
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
  strictNutrition?: boolean;
  macroTolerancePercent?: number;
  
  // New filters
  maxPrepTime?: number;
  difficulty?: RecipeDifficulty[];
  diets?: DietType[];
  seasons?: Season[];
  mealTypes?: MealType[];
  maxCalories?: number;
  minProtein?: number;
  
  // Diversity
  excludeRecentRecipes?: string[];
  diversityWeight?: number;
};

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
  
  // New
  mealSchedule?: {
    breakfastStart?: number;
    breakfastEnd?: number;
    lunchStart?: number;
    lunchEnd?: number;
    dinnerStart?: number;
    dinnerEnd?: number;
  };
  maxPrepTime?: number;
  difficulty?: RecipeDifficulty[];
  diets?: DietType[];
  balanceMacros?: boolean;
  avoidRepetition?: boolean;
  userHistory?: string[];
};

export type MealPlanEntry = {
  mealType: MealType;
  recipe: Recipe;
  score: number;
  estimatedCost: number;
  kcal: number;
  protein: number;
  fat: number;
  carbs: number;
};

export type MealPlanDay = {
  date: string;
  dayOfWeek?: string;
  entries: MealPlanEntry[];
  totals: {
    kcal: number;
    protein: number;
    fat: number;
    carbs: number;
    estimatedCost: number;
  };
  targets: {
    kcal?: number;
    perMealKcal?: number;
    protein?: number;
    fat?: number;
    carbs?: number;
  };
  missingIngredients: string[];
  mealSchedule?: {
    breakfastTime?: string;
    lunchTime?: string;
    dinnerTime?: string;
  };
};

export type MealPlanResponse = {
  days: MealPlanDay[];
  shoppingList: string[];
  shoppingListGrouped?: Record<string, string[]>;
  estimatedTotalCost: number;
  estimatedSavingsRub?: number;
  totalNutrition: Nutrition;
  warnings: string[];
  ingredientSubstitutions?: IngredientSubstitution[];
  recommendationReasons?: RecipeRecommendationReason[];
  diversityScore?: number;
  varietyScore?: number;
  optimization?: {
    objective: "cost_macro" | "balanced";
    profile: "economy_aggressive" | "balanced" | "macro_precision";
    averageMacroDeviation: number;
    averageMealCost: number;
    strictMacroMeals: number;
    relaxedMacroMeals: number;
    repeatedRecipeMeals: number;
    repeatedCuisineMeals: number;
    lowConfidenceCostMeals: number;
  };
};

export type IngredientPriceHint = {
  ingredient: string;
  priceRub: number;
  confidence?: number;
  source?: "receipt" | "history" | "category_fallback" | "provider";
  capturedAt?: string;
};

export type PriceEstimateRequest = {
  ingredients: string[];
  hints?: IngredientPriceHint[];
  region?: string;
  currency?: string;
};

export type PriceEstimateItem = {
  ingredient: string;
  estimatedPriceRub: number;
  confidence: number;
  source: string;
};

export type PriceEstimateResponse = {
  items: PriceEstimateItem[];
  totalEstimatedRub: number;
  confidence: number;
  missingIngredients: string[];
};

export type SmartMealPlanRequest = MealPlanRequest & {
  objective?: "cost_macro" | "balanced";
  optimizerProfile?: "economy_aggressive" | "balanced" | "macro_precision";
  macroTolerancePercent?: number;
  ingredientPriceHints?: IngredientPriceHint[];
};

export type SmartMealPlanResponse = MealPlanResponse & {
  objective: "cost_macro" | "balanced";
  optimizerProfile: "economy_aggressive" | "balanced" | "macro_precision";
  costConfidence: number;
  priceExplanation: string[];
};

export type RecipeRecommendationReason = {
  recipeId: string;
  reasons: string[];
};

export type IngredientSubstitution = {
  ingredient: string;
  substitute: string;
  reason: "price" | "availability";
  estimatedSavingsRub?: number;
};

// External API types
export type ExternalRecipeProvider = "edamam" | "spoonacular" | "internal";

export type ExternalRecipeSearchParams = {
  query?: string;
  ingredients?: string[];
  diet?: DietType;
  cuisine?: string;
  mealType?: MealType;
  maxCalories?: number;
  minProtein?: number;
};

export type ExternalRecipeResponse = {
  provider: ExternalRecipeProvider;
  recipes: Recipe[];
  totalResults: number;
  page: number;
};

// User history types
export type UserMealHistory = {
  userId: string;
  meals: {
    date: string;
    recipeId: string;
    mealType: MealType;
    rating?: number;
  }[];
  preferences: {
    favoriteCuisines: string[];
    dislikedIngredients: string[];
    dietTypes: DietType[];
  };
};

export type UserFeedbackEventType =
  | "recipe_view"
  | "recipe_save"
  | "recipe_cook"
  | "recipe_like"
  | "recipe_dislike"
  | "meal_plan_accept";

export type UserFeedbackEvent = {
  userId: string;
  recipeId: string;
  eventType: UserFeedbackEventType;
  timestamp?: string;
  value?: number;
};

export type UserTasteProfile = {
  userId: string;
  topIngredients: string[];
  topCuisines: string[];
  preferredMealTypes: MealType[];
  dislikedRecipeIds: string[];
  confidence: number;
  totalEvents: number;
};

export type RecommendV2Payload = RecommendPayload & {
  userId?: string;
  includeReasons?: boolean;
};

export type RecommendV2Item = {
  recipe: Recipe;
  score: number;
  reasons: string[];
  scoreBreakdown: Record<string, number>;
};
