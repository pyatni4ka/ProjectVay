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

test("POST /api/v1/user/events persists feedback events", async () => {
  await withServer(async (baseURL) => {
    const response = await fetch(`${baseURL}/api/v1/user/events`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        userId: "test-user-1",
        events: [
          {
            recipeId: "r1",
            eventType: "recipe_like",
            value: 1
          },
          {
            recipeId: "r2",
            eventType: "recipe_dislike",
            value: -1
          }
        ]
      })
    });

    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.ok, true);
    assert.equal(typeof payload.saved, "number");
    assert.ok(payload.saved >= 1);
  });
});

test("POST /api/v1/recipes/recommend/v2 returns v2 ranked payload", async () => {
  await withServer(async (baseURL) => {
    const response = await fetch(`${baseURL}/api/v1/recipes/recommend/v2`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        userId: "test-user-2",
        includeReasons: true,
        ingredientKeywords: ["курица"],
        expiringSoonKeywords: [],
        targets: { kcal: 650, protein: 40, fat: 20, carbs: 60 },
        limit: 5
      })
    });

    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.ok(Array.isArray(payload.items));
    assert.ok(payload.items.length > 0);

    const first = payload.items[0];
    assert.equal(typeof first.score, "number");
    assert.ok(first.recipe?.id);
    assert.ok(Array.isArray(first.reasons));
    assert.equal(typeof first.scoreBreakdown, "object");
    assert.equal(typeof payload.personalizationApplied, "boolean");
    assert.equal(typeof payload.profileConfidence, "number");
  });
});

test("POST /api/v1/meal-plan/smart-v2 returns optimization and explanations", async () => {
  await withServer(async (baseURL) => {
    const response = await fetch(`${baseURL}/api/v1/meal-plan/smart-v2`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        days: 2,
        ingredientKeywords: ["курица", "рис"],
        expiringSoonKeywords: ["йогурт"],
        targets: { kcal: 2100, protein: 120, fat: 70, carbs: 220 },
        budget: { perDay: 900 },
        objective: "cost_macro",
        optimizerProfile: "balanced"
      })
    });

    assert.equal(response.status, 200);
    const payload = await response.json();

    assert.ok(Array.isArray(payload.days));
    assert.ok(payload.days.length > 0);
    assert.equal(typeof payload.estimatedTotalCost, "number");
    assert.equal(typeof payload.costConfidence, "number");
    assert.ok(Array.isArray(payload.priceExplanation));
    assert.ok(Array.isArray(payload.recommendationReasons));
    assert.ok(Array.isArray(payload.ingredientSubstitutions));
  });
});

test("GET /api/v1/prices/compare returns compare payload", async () => {
  await withServer(async (baseURL) => {
    const response = await fetch(
      `${baseURL}/api/v1/prices/compare?ingredients=${encodeURIComponent("курица,рис,лук")}`
    );

    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.ok(Array.isArray(payload.items));
    assert.equal(typeof payload.totalEstimatedRub, "number");
    assert.equal(typeof payload.estimatedBestCaseRub, "number");
    assert.equal(typeof payload.potentialSavingsRub, "number");
    assert.ok(Array.isArray(payload.substitutions));
    assert.equal(typeof payload.confidence, "number");
    assert.ok(Array.isArray(payload.missingIngredients));
  });
});
