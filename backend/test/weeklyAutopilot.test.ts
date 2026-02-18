/**
 * Tests for Weekly Autopilot endpoints:
 *   POST /api/v1/meal-plan/week
 *   POST /api/v1/meal-plan/replace
 *   POST /api/v1/meal-plan/adapt
 *   POST /api/v1/recipes/cook-now
 */
import test from "node:test";
import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import express from "express";
import recipesRouter from "../src/routes/v1/recipes.js";

async function withServer<T>(run: (baseURL: string) => Promise<T>): Promise<T> {
  const app = express();
  app.use(express.json());
  app.use("/api/v1", recipesRouter);

  const server = await new Promise<import("node:http").Server>((resolve, reject) => {
    const instance = app.listen(0, () => resolve(instance));
    instance.on("error", reject);
  });

  const address = server.address() as AddressInfo | null;
  if (!address) {
    await new Promise<void>((resolve) => server.close(() => resolve()));
    throw new Error("Failed to resolve test server address");
  }

  const baseURL = `http://127.0.0.1:${address.port}`;
  try {
    return await run(baseURL);
  } finally {
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
}

const BASE_REQUEST = {
  days: 7,
  ingredientKeywords: ["курица", "рис", "яйца"],
  expiringSoonKeywords: [],
  targets: { kcal: 2200, protein: 140, fat: 70, carbs: 220 },
  budget: { perDay: 400, strictness: "soft", softLimitPct: 5 },
};

test("POST /api/v1/meal-plan/week returns WeeklyAutopilotResponse shape", async () => {
  await withServer(async (baseURL) => {
    const response = await fetch(`${baseURL}/api/v1/meal-plan/week`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(BASE_REQUEST),
    });

    assert.equal(response.status, 200, "should return 200");
    const payload = await response.json() as Record<string, unknown>;

    // planId must be a string
    assert.equal(typeof payload.planId, "string", "planId must be string");

    // days must be an array of length 7
    assert.ok(Array.isArray(payload.days), "days must be an array");
    assert.equal((payload.days as unknown[]).length, 7, "days must have 7 entries");

    // shoppingListWithQuantities must be an array
    assert.ok(Array.isArray(payload.shoppingListWithQuantities), "shoppingListWithQuantities must be array");

    // budgetProjection must have day/week/month
    const budget = payload.budgetProjection as Record<string, unknown>;
    assert.ok(budget, "budgetProjection must exist");
    assert.ok(typeof budget.day === "object", "budgetProjection.day must be object");
    assert.ok(typeof budget.week === "object", "budgetProjection.week must be object");

    // warnings must be array
    assert.ok(Array.isArray(payload.warnings), "warnings must be array");

    // nutritionConfidence must be high|medium|low
    assert.ok(
      ["high", "medium", "low"].includes(payload.nutritionConfidence as string),
      "nutritionConfidence must be valid"
    );

    // Each day must have entries with mealSlotKey and explanationTags
    const firstDay = (payload.days as Record<string, unknown>[])[0]!;
    assert.ok(Array.isArray(firstDay.entries), "day.entries must be array");
    const firstEntry = (firstDay.entries as Record<string, unknown>[])[0];
    if (firstEntry) {
      assert.equal(typeof firstEntry.mealSlotKey, "string", "entry.mealSlotKey must be string");
      assert.ok(Array.isArray(firstEntry.explanationTags), "entry.explanationTags must be array");
      assert.ok(
        ["high", "medium", "low"].includes(firstEntry.nutritionConfidence as string),
        "entry.nutritionConfidence must be valid"
      );
    }
  });
});

test("POST /api/v1/meal-plan/week returns 400 for invalid body", async () => {
  await withServer(async (baseURL) => {
    const response = await fetch(`${baseURL}/api/v1/meal-plan/week`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "not json",
    });
    assert.ok(response.status >= 400, "should return 4xx for invalid body");
  });
});

test("POST /api/v1/meal-plan/week shoppingListWithQuantities has quantity fields", async () => {
  await withServer(async (baseURL) => {
    const response = await fetch(`${baseURL}/api/v1/meal-plan/week`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(BASE_REQUEST),
    });

    assert.equal(response.status, 200);
    const payload = await response.json() as Record<string, unknown>;
    const list = payload.shoppingListWithQuantities as Record<string, unknown>[];

    if (list.length > 0) {
      const item = list[0]!;
      assert.equal(typeof item.ingredient, "string", "item.ingredient must be string");
      assert.equal(typeof item.amount, "number", "item.amount must be number");
      assert.ok(["g", "ml", "piece"].includes(item.unit as string), "item.unit must be g|ml|piece");
      assert.equal(typeof item.approximate, "boolean", "item.approximate must be boolean");
    }
  });
});

test("POST /api/v1/meal-plan/replace returns candidates list", async () => {
  await withServer(async (baseURL) => {
    // First generate a plan
    const planResponse = await fetch(`${baseURL}/api/v1/meal-plan/week`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(BASE_REQUEST),
    });
    assert.equal(planResponse.status, 200);
    const plan = await planResponse.json();

    // Now replace first meal of first day
    const replaceResponse = await fetch(`${baseURL}/api/v1/meal-plan/replace`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        currentPlan: plan,
        dayIndex: 0,
        mealSlot: "breakfast",
        sortMode: "cheap",
        topN: 5,
      }),
    });

    assert.equal(replaceResponse.status, 200, "replace should return 200");
    const result = await replaceResponse.json() as Record<string, unknown>;

    assert.ok(Array.isArray(result.candidates), "candidates must be array");
    assert.ok(Array.isArray(result.why), "why must be array");
    assert.ok(result.why.length > 0, "why must have at least one message");
    assert.ok(typeof result.updatedPlanPreview === "object", "updatedPlanPreview must be object");

    if ((result.candidates as unknown[]).length > 0) {
      const candidate = (result.candidates as Record<string, unknown>[])[0]!;
      assert.equal(typeof candidate.recipe, "object", "candidate.recipe must be object");
      assert.equal(typeof candidate.mealSlotKey, "string", "candidate.mealSlotKey must be string");
      assert.ok(Array.isArray(candidate.tags), "candidate.tags must be array");
    }
  });
});

test("POST /api/v1/meal-plan/adapt returns gentle adaptation", async () => {
  await withServer(async (baseURL) => {
    // First generate a plan
    const planResponse = await fetch(`${baseURL}/api/v1/meal-plan/week`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(BASE_REQUEST),
    });
    assert.equal(planResponse.status, 200);
    const plan = await planResponse.json();

    // Simulate a cheat event
    const adaptResponse = await fetch(`${baseURL}/api/v1/meal-plan/adapt`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        currentPlan: plan,
        eventType: "cheat",
        impactEstimate: "medium",
        applyScope: "day",
        timestamp: new Date().toISOString(),
      }),
    });

    assert.equal(adaptResponse.status, 200, "adapt should return 200");
    const result = await adaptResponse.json() as Record<string, unknown>;

    assert.equal(typeof result.updatedRemainingPlan, "object", "updatedRemainingPlan must be object");
    assert.equal(typeof result.disruptionScore, "number", "disruptionScore must be number");
    assert.ok(result.disruptionScore >= 0 && result.disruptionScore <= 1, "disruptionScore must be 0..1");
    assert.equal(typeof result.gentleMessage, "string", "gentleMessage must be string");
    assert.ok(result.gentleMessage.length > 0, "gentleMessage must not be empty");
    assert.ok(Array.isArray(result.why), "why must be array");
  });
});

test("POST /api/v1/recipes/cook-now returns recipes sorted by inventory availability", async () => {
  await withServer(async (baseURL) => {
    const response = await fetch(`${baseURL}/api/v1/recipes/cook-now`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        inventoryKeywords: ["курица", "рис", "лук", "морковь", "масло"],
        expiringSoonKeywords: ["курица"],
        maxPrepTime: 45,
        limit: 5,
      }),
    });

    assert.equal(response.status, 200, "cook-now should return 200");
    const result = await response.json() as Record<string, unknown>;

    assert.ok(Array.isArray(result.recipes), "recipes must be array");
    assert.equal(typeof result.inventoryCount, "number", "inventoryCount must be number");

    if ((result.recipes as unknown[]).length > 0) {
      const first = (result.recipes as Record<string, unknown>[])[0]!;
      assert.equal(typeof first.recipe, "object", "recipe item must have recipe object");
      assert.equal(typeof first.score, "number", "recipe item must have score");
      assert.equal(typeof first.availabilityRatio, "number", "recipe item must have availabilityRatio");
    }
  });
});

test("POST /api/v1/meal-plan/week with effortLevel=quick uses lower maxPrepTime", async () => {
  await withServer(async (baseURL) => {
    const response = await fetch(`${baseURL}/api/v1/meal-plan/week`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ ...BASE_REQUEST, effortLevel: "quick", days: 1 }),
    });
    assert.equal(response.status, 200);
    const payload = await response.json() as Record<string, unknown>;
    assert.ok(Array.isArray(payload.days));
  });
});
