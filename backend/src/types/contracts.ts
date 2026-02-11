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
