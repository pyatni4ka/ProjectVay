import type { MealType, Recipe, UserFeedbackEvent, UserFeedbackEventType, UserTasteProfile } from "../types/contracts.js";

export type StoredUserFeedbackEvent = {
  userId: string;
  recipeId: string;
  eventType: UserFeedbackEventType;
  timestamp: string;
  value?: number;
};

const POSITIVE_EVENT_WEIGHTS: Record<UserFeedbackEventType, number> = {
  recipe_view: 0.2,
  recipe_save: 1.2,
  recipe_cook: 1.5,
  recipe_like: 2.0,
  recipe_dislike: -2.3,
  meal_plan_accept: 1.0
};

export function normalizeUserFeedbackEvents(
  userId: string,
  events: Array<Partial<UserFeedbackEvent>>
): StoredUserFeedbackEvent[] {
  return events.reduce<StoredUserFeedbackEvent[]>((accumulator, event) => {
      const recipeId = String(event.recipeId ?? "").trim();
      const eventType = normalizeEventType(event.eventType);
      if (!recipeId || !eventType) {
        return accumulator;
      }
      const timestamp = event.timestamp ? new Date(event.timestamp).toISOString() : new Date().toISOString();
      const value = Number.isFinite(event.value) ? Number(event.value) : undefined;
      accumulator.push({
        userId,
        recipeId,
        eventType,
        timestamp,
        value
      });
      return accumulator;
    }, []);
}

export function buildTasteProfileFromEvents(
  userId: string,
  events: StoredUserFeedbackEvent[],
  recipes: Recipe[]
): UserTasteProfile {
  const recipeById = new Map(recipes.map((recipe) => [recipe.id, recipe]));
  const ingredientScore = new Map<string, number>();
  const cuisineScore = new Map<string, number>();
  const mealTypeScore = new Map<MealType, number>();
  const dislikedRecipeIds = new Set<string>();

  for (const event of events) {
    const recipe = recipeById.get(event.recipeId);
    if (!recipe) {
      continue;
    }

    const weight = (POSITIVE_EVENT_WEIGHTS[event.eventType] ?? 0) + (event.value ?? 0);
    if (event.eventType === "recipe_dislike" || weight < -1.5) {
      dislikedRecipeIds.add(recipe.id);
    }

    for (const ingredient of recipe.ingredients) {
      const key = ingredient.trim().toLowerCase();
      if (!key) continue;
      ingredientScore.set(key, (ingredientScore.get(key) ?? 0) + weight);
    }

    if (recipe.cuisine) {
      const key = recipe.cuisine.trim().toLowerCase();
      if (key) {
        cuisineScore.set(key, (cuisineScore.get(key) ?? 0) + weight);
      }
    }

    for (const mealType of recipe.mealTypes ?? []) {
      mealTypeScore.set(mealType, (mealTypeScore.get(mealType) ?? 0) + weight);
    }
  }

  const topIngredients = topKeysByScore(ingredientScore, 12);
  const topCuisines = topKeysByScore(cuisineScore, 6);
  const preferredMealTypes = topKeysByScore(mealTypeScore, 3) as MealType[];
  const totalEvents = events.length;
  const confidence = clamp(totalEvents / 40, 0, 1);

  return {
    userId,
    topIngredients,
    topCuisines,
    preferredMealTypes,
    dislikedRecipeIds: Array.from(dislikedRecipeIds),
    confidence,
    totalEvents
  };
}

function normalizeEventType(value: unknown): UserFeedbackEventType | null {
  switch (value) {
    case "recipe_view":
    case "recipe_save":
    case "recipe_cook":
    case "recipe_like":
    case "recipe_dislike":
    case "meal_plan_accept":
      return value;
    default:
      return null;
  }
}

function topKeysByScore<T extends string>(scoreMap: Map<T, number>, limit: number): T[] {
  return Array.from(scoreMap.entries())
    .filter(([, score]) => score > 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([key]) => key);
}

function clamp(value: number, minValue: number, maxValue: number): number {
  return Math.min(Math.max(value, minValue), maxValue);
}
