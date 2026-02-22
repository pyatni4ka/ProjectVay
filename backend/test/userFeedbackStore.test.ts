import test from "node:test";
import assert from "node:assert/strict";
import { UserFeedbackStore } from "../src/services/userFeedbackStore.js";
import type { Recipe } from "../src/types/contracts.js";

// ── helpers ────────────────────────────────────────────────────────────────

function createStore(): UserFeedbackStore {
  return new UserFeedbackStore({ dbPath: ":memory:" });
}

function makeRecipe(id: string, ingredients: string[] = ["курица"]): Recipe {
  return {
    id,
    title: id,
    imageURL: "",
    sourceName: "test",
    sourceURL: "",
    ingredients,
    instructions: ["Приготовить"],
    nutrition: { kcal: 400, protein: 25, fat: 15, carbs: 45 }
  };
}

// ── appendEvents ───────────────────────────────────────────────────────────

test("appendEvents stores valid events and returns count", () => {
  const store = createStore();
  const count = store.appendEvents("u1", [
    { recipeId: "r1", eventType: "recipe_like" },
    { recipeId: "r2", eventType: "recipe_cook" }
  ]);

  assert.equal(count, 2);
});

test("appendEvents returns 0 for empty or invalid events", () => {
  const store = createStore();

  assert.equal(store.appendEvents("u1", []), 0);
  assert.equal(store.appendEvents("u1", [{ recipeId: "", eventType: "recipe_like" }]), 0);
  assert.equal(store.appendEvents("u1", [{ recipeId: "r1", eventType: "invalid" }]), 0);
});

test("appendEvents stores events for multiple users independently", () => {
  const store = createStore();
  store.appendEvents("u1", [{ recipeId: "r1", eventType: "recipe_like" }]);
  store.appendEvents("u2", [{ recipeId: "r2", eventType: "recipe_cook" }]);

  const u1Events = store.listEvents("u1");
  const u2Events = store.listEvents("u2");

  assert.equal(u1Events.length, 1);
  assert.equal(u1Events[0]!.recipeId, "r1");
  assert.equal(u2Events.length, 1);
  assert.equal(u2Events[0]!.recipeId, "r2");
});

// ── listEvents ─────────────────────────────────────────────────────────────

test("listEvents returns events sorted by timestamp descending", () => {
  const store = createStore();
  store.appendEvents("u1", [
    { recipeId: "r1", eventType: "recipe_view", timestamp: "2025-01-01T10:00:00Z" },
    { recipeId: "r2", eventType: "recipe_like", timestamp: "2025-01-02T10:00:00Z" },
    { recipeId: "r3", eventType: "recipe_cook", timestamp: "2025-01-01T15:00:00Z" }
  ]);

  const events = store.listEvents("u1");
  assert.equal(events.length, 3);
  assert.equal(events[0]!.recipeId, "r2"); // latest
  assert.equal(events[2]!.recipeId, "r1"); // earliest
});

test("listEvents returns empty array for unknown user", () => {
  const store = createStore();
  const events = store.listEvents("nonexistent_user");
  assert.equal(events.length, 0);
});

test("listEvents respects limit parameter", () => {
  const store = createStore();
  store.appendEvents("u1", [
    { recipeId: "r1", eventType: "recipe_view" },
    { recipeId: "r2", eventType: "recipe_view" },
    { recipeId: "r3", eventType: "recipe_view" },
    { recipeId: "r4", eventType: "recipe_view" },
    { recipeId: "r5", eventType: "recipe_view" }
  ]);

  const limited = store.listEvents("u1", 3);
  assert.equal(limited.length, 3);
});

test("listEvents clamps limit to safe range", () => {
  const store = createStore();
  store.appendEvents("u1", [{ recipeId: "r1", eventType: "recipe_like" }]);

  // limit <= 0 should be clamped to 1
  const events = store.listEvents("u1", 0);
  assert.equal(events.length, 1);
});

test("listEvents preserves event value field", () => {
  const store = createStore();
  store.appendEvents("u1", [
    { recipeId: "r1", eventType: "recipe_like", value: 4.5 }
  ]);

  const events = store.listEvents("u1");
  assert.equal(events[0]!.value, 4.5);
});

test("listEvents returns undefined value when not provided", () => {
  const store = createStore();
  store.appendEvents("u1", [
    { recipeId: "r1", eventType: "recipe_like" }
  ]);

  const events = store.listEvents("u1");
  assert.equal(events[0]!.value, undefined);
});

// ── buildTasteProfile ──────────────────────────────────────────────────────

test("buildTasteProfile integrates store events with recipe catalog", () => {
  const store = createStore();
  const recipes = [
    makeRecipe("r1", ["курица", "рис", "лук"]),
    makeRecipe("r2", ["курица", "гречка"])
  ];

  store.appendEvents("u1", [
    { recipeId: "r1", eventType: "recipe_like" },
    { recipeId: "r1", eventType: "recipe_cook" },
    { recipeId: "r2", eventType: "recipe_save" }
  ]);

  const profile = store.buildTasteProfile("u1", recipes);

  assert.equal(profile.userId, "u1");
  assert.equal(profile.totalEvents, 3);
  assert.ok(profile.topIngredients.includes("курица"));
  assert.ok(profile.confidence > 0);
});

test("buildTasteProfile marks disliked recipes", () => {
  const store = createStore();
  const recipes = [makeRecipe("r1"), makeRecipe("r2")];

  store.appendEvents("u1", [
    { recipeId: "r1", eventType: "recipe_dislike" },
    { recipeId: "r2", eventType: "recipe_like" }
  ]);

  const profile = store.buildTasteProfile("u1", recipes);
  assert.ok(profile.dislikedRecipeIds.includes("r1"));
  assert.ok(!profile.dislikedRecipeIds.includes("r2"));
});

test("buildTasteProfile returns neutral profile for user with no events", () => {
  const store = createStore();
  const recipes = [makeRecipe("r1")];

  const profile = store.buildTasteProfile("new_user", recipes);
  assert.equal(profile.totalEvents, 0);
  assert.equal(profile.confidence, 0);
  assert.equal(profile.topIngredients.length, 0);
});

// ── storage mode ───────────────────────────────────────────────────────────

test("store initializes with a valid storage mode", () => {
  const store = createStore();
  assert.ok(
    store.storageMode === "sqlite" || store.storageMode === "memory",
    `storageMode should be sqlite or memory, got: ${store.storageMode}`
  );
});

test("multiple appends accumulate events correctly", () => {
  const store = createStore();

  store.appendEvents("u1", [{ recipeId: "r1", eventType: "recipe_view" }]);
  store.appendEvents("u1", [{ recipeId: "r2", eventType: "recipe_like" }]);
  store.appendEvents("u1", [{ recipeId: "r3", eventType: "recipe_cook" }]);

  const events = store.listEvents("u1");
  assert.equal(events.length, 3);
});
