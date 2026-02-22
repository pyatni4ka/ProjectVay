import test from "node:test";
import assert from "node:assert/strict";
import {
  buildTasteProfileFromEvents,
  normalizeUserFeedbackEvents,
  type StoredUserFeedbackEvent
} from "../src/services/personalizationModel.js";
import type { Recipe } from "../src/types/contracts.js";

// ── helpers ────────────────────────────────────────────────────────────────

function makeRecipe(overrides: Partial<Recipe> & { id: string }): Recipe {
  return {
    title: overrides.id,
    imageURL: "",
    sourceName: "test",
    sourceURL: "",
    ingredients: [],
    instructions: ["Приготовить"],
    nutrition: { kcal: 400, protein: 25, fat: 15, carbs: 45 },
    ...overrides
  };
}

function event(
  recipeId: string,
  eventType: StoredUserFeedbackEvent["eventType"],
  value?: number
): StoredUserFeedbackEvent {
  return {
    userId: "u1",
    recipeId,
    eventType,
    timestamp: new Date().toISOString(),
    value
  };
}

// ── normalizeUserFeedbackEvents ────────────────────────────────────────────

test("normalizeUserFeedbackEvents filters invalid events", () => {
  const events = normalizeUserFeedbackEvents("u1", [
    { recipeId: "r1", eventType: "recipe_like" },
    { recipeId: "", eventType: "recipe_like" },       // empty recipeId
    { recipeId: "r2", eventType: "unknown_type" },     // invalid eventType
    { recipeId: "r3" },                                // missing eventType
    { eventType: "recipe_cook" },                      // missing recipeId
  ]);

  assert.equal(events.length, 1);
  assert.equal(events[0]!.recipeId, "r1");
  assert.equal(events[0]!.eventType, "recipe_like");
});

test("normalizeUserFeedbackEvents preserves valid fields", () => {
  const events = normalizeUserFeedbackEvents("u1", [
    { recipeId: "r1", eventType: "recipe_cook", timestamp: "2025-06-15T12:00:00Z", value: 0.5 }
  ]);

  assert.equal(events.length, 1);
  assert.equal(events[0]!.userId, "u1");
  assert.equal(events[0]!.recipeId, "r1");
  assert.equal(events[0]!.eventType, "recipe_cook");
  assert.equal(events[0]!.value, 0.5);
  assert.ok(events[0]!.timestamp.includes("2025"));
});

test("normalizeUserFeedbackEvents handles all valid event types", () => {
  const types = ["recipe_view", "recipe_save", "recipe_cook", "recipe_like", "recipe_dislike", "meal_plan_accept"] as const;

  const events = normalizeUserFeedbackEvents("u1",
    types.map((eventType) => ({ recipeId: "r1", eventType }))
  );

  assert.equal(events.length, types.length);
});

// ── buildTasteProfileFromEvents ────────────────────────────────────────────

test("returns neutral profile for empty events", () => {
  const profile = buildTasteProfileFromEvents("u1", [], []);

  assert.equal(profile.userId, "u1");
  assert.equal(profile.topIngredients.length, 0);
  assert.equal(profile.topCuisines.length, 0);
  assert.equal(profile.preferredMealTypes.length, 0);
  assert.equal(profile.dislikedRecipeIds.length, 0);
  assert.equal(profile.confidence, 0);
  assert.equal(profile.totalEvents, 0);
});

test("builds ingredient preferences from liked recipes", () => {
  const recipes = [
    makeRecipe({ id: "r1", ingredients: ["курица", "рис", "лук"] }),
    makeRecipe({ id: "r2", ingredients: ["курица", "гречка", "морковь"] })
  ];

  const events = [
    event("r1", "recipe_like"),
    event("r2", "recipe_like"),
    event("r1", "recipe_cook")
  ];

  const profile = buildTasteProfileFromEvents("u1", events, recipes);

  // "курица" appears in both liked recipes → highest score
  assert.ok(profile.topIngredients.includes("курица"));
  assert.ok(profile.topIngredients.indexOf("курица") < profile.topIngredients.indexOf("гречка"));
});

test("builds cuisine preferences", () => {
  const recipes = [
    makeRecipe({ id: "r1", cuisine: "Русская", ingredients: ["борщ"] }),
    makeRecipe({ id: "r2", cuisine: "Русская", ingredients: ["пельмени"] }),
    makeRecipe({ id: "r3", cuisine: "Итальянская", ingredients: ["паста"] })
  ];

  const events = [
    event("r1", "recipe_like"),
    event("r2", "recipe_cook"),
    event("r3", "recipe_view")  // weak signal
  ];

  const profile = buildTasteProfileFromEvents("u1", events, recipes);

  // "русская" should rank higher (like + cook vs view)
  assert.ok(profile.topCuisines.length > 0);
  assert.equal(profile.topCuisines[0], "русская");
});

test("builds mealType preferences", () => {
  const recipes = [
    makeRecipe({ id: "r1", mealTypes: ["breakfast"], ingredients: ["яйца"] }),
    makeRecipe({ id: "r2", mealTypes: ["lunch", "dinner"], ingredients: ["курица"] })
  ];

  const events = [
    event("r1", "recipe_cook"),
    event("r1", "recipe_cook"),
    event("r2", "recipe_like")
  ];

  const profile = buildTasteProfileFromEvents("u1", events, recipes);
  assert.ok(profile.preferredMealTypes.includes("breakfast"));
});

test("marks disliked recipes", () => {
  const recipes = [
    makeRecipe({ id: "r1", ingredients: ["кускус"] }),
    makeRecipe({ id: "r2", ingredients: ["курица"] })
  ];

  const events = [
    event("r1", "recipe_dislike"),
    event("r2", "recipe_like")
  ];

  const profile = buildTasteProfileFromEvents("u1", events, recipes);

  assert.ok(profile.dislikedRecipeIds.includes("r1"));
  assert.ok(!profile.dislikedRecipeIds.includes("r2"));
});

test("disliked ingredients get negative score and are excluded from top", () => {
  const recipes = [
    makeRecipe({ id: "r1", ingredients: ["кускус", "томаты"] }),
    makeRecipe({ id: "r2", ingredients: ["курица", "рис"] })
  ];

  const events = [
    event("r1", "recipe_dislike"),
    event("r2", "recipe_like")
  ];

  const profile = buildTasteProfileFromEvents("u1", events, recipes);

  // "кускус" should not appear in top ingredients (negative score from dislike)
  assert.ok(!profile.topIngredients.includes("кускус"));
  assert.ok(profile.topIngredients.includes("курица"));
});

test("confidence scales with number of events up to 1.0", () => {
  const recipes = [makeRecipe({ id: "r1", ingredients: ["курица"] })];

  // 10 events → confidence = 10/40 = 0.25
  const fewEvents = Array.from({ length: 10 }, () => event("r1", "recipe_view"));
  const profileFew = buildTasteProfileFromEvents("u1", fewEvents, recipes);
  assert.equal(profileFew.confidence, 0.25);

  // 40 events → confidence = 1.0
  const manyEvents = Array.from({ length: 40 }, () => event("r1", "recipe_view"));
  const profileMany = buildTasteProfileFromEvents("u1", manyEvents, recipes);
  assert.equal(profileMany.confidence, 1);

  // 100 events → confidence clamped to 1.0
  const lotsOfEvents = Array.from({ length: 100 }, () => event("r1", "recipe_view"));
  const profileLots = buildTasteProfileFromEvents("u1", lotsOfEvents, recipes);
  assert.equal(profileLots.confidence, 1);
});

test("ignores events for unknown recipes", () => {
  const recipes = [makeRecipe({ id: "r1", ingredients: ["курица"] })];

  const events = [
    event("r1", "recipe_like"),
    event("unknown_recipe", "recipe_like")  // not in recipe list
  ];

  const profile = buildTasteProfileFromEvents("u1", events, recipes);

  assert.equal(profile.totalEvents, 2);
  // Only r1's ingredients should appear
  assert.ok(profile.topIngredients.includes("курица"));
  assert.equal(profile.topIngredients.length, 1);
});

test("event weights influence ranking: like > cook > save > view", () => {
  const recipes = [
    makeRecipe({ id: "r_view", ingredients: ["ингредиент_вью"], cuisine: "вью" }),
    makeRecipe({ id: "r_save", ingredients: ["ингредиент_сейв"], cuisine: "сейв" }),
    makeRecipe({ id: "r_cook", ingredients: ["ингредиент_кук"], cuisine: "кук" }),
    makeRecipe({ id: "r_like", ingredients: ["ингредиент_лайк"], cuisine: "лайк" })
  ];

  const events = [
    event("r_view", "recipe_view"),
    event("r_save", "recipe_save"),
    event("r_cook", "recipe_cook"),
    event("r_like", "recipe_like")
  ];

  const profile = buildTasteProfileFromEvents("u1", events, recipes);

  // Top cuisines should be ordered: лайк > кук > сейв > вью (by weight)
  assert.equal(profile.topCuisines[0], "лайк");
  assert.equal(profile.topCuisines[1], "кук");
  assert.equal(profile.topCuisines[2], "сейв");
  assert.equal(profile.topCuisines[3], "вью");
});

test("top ingredients limited to 12 items", () => {
  const ingredients = Array.from({ length: 20 }, (_, i) => `ингредиент_${i}`);
  const recipes = [makeRecipe({ id: "r1", ingredients })];

  const events = [event("r1", "recipe_like")];
  const profile = buildTasteProfileFromEvents("u1", events, recipes);

  assert.ok(profile.topIngredients.length <= 12);
});
