import test from "node:test";
import assert from "node:assert/strict";
import { isURLAllowedByWhitelist, parseRecipeURL } from "../src/services/sourcePolicy.js";

test("parseRecipeURL rejects non-http schemes and local hosts", () => {
  assert.equal(parseRecipeURL("ftp://example.com/recipe"), null);
  assert.equal(parseRecipeURL("http://localhost:3000/recipe"), null);
  assert.equal(parseRecipeURL("http://127.0.0.1/recipe"), null);
  const allowed = parseRecipeURL("https://food.ru/recipe");
  assert.ok(allowed instanceof URL);
  assert.equal(allowed?.hostname, "food.ru");
});

test("isURLAllowedByWhitelist supports exact domain and subdomain", () => {
  const whitelist = ["food.ru", "allrecipes.com"];
  const allowed = new URL("https://eda.food.ru/r/123");
  const blocked = new URL("https://malicious.example/r/123");

  assert.equal(isURLAllowedByWhitelist(allowed, whitelist), true);
  assert.equal(isURLAllowedByWhitelist(blocked, whitelist), false);
});
