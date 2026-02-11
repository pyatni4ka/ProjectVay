import test from "node:test";
import assert from "node:assert/strict";
import { lookupBarcode, parseEANDBProduct, parseOpenFoodFactsProduct, type FetchLike } from "../src/services/barcodeLookup.js";

test("parseOpenFoodFactsProduct extracts product and nutrition", () => {
  const parsed = parseOpenFoodFactsProduct(
    {
      status: 1,
      product: {
        product_name_ru: "Йогурт питьевой",
        brands: "Пример Бренд",
        categories: "Молочные продукты, Йогурты",
        nutriments: {
          "energy-kcal_100g": 88,
          proteins_100g: 3.2,
          fat_100g: 2.9,
          carbohydrates_100g: 11.4
        }
      }
    },
    "4601234567890"
  );

  assert.equal(parsed?.name, "Йогурт питьевой");
  assert.equal(parsed?.category, "Молочные продукты");
  assert.equal(parsed?.nutrition?.kcal, 88);
  assert.equal(parsed?.nutrition?.protein, 3.2);
});

test("parseEANDBProduct extracts minimal payload", () => {
  const parsed = parseEANDBProduct(
    {
      title: "Сок яблочный",
      brand: "Марка",
      category: "Напитки"
    },
    "4601234567890"
  );

  assert.equal(parsed?.name, "Сок яблочный");
  assert.equal(parsed?.brand, "Марка");
  assert.equal(parsed?.category, "Напитки");
});

test("lookupBarcode falls back to OpenFoodFacts when EAN-DB misses", async () => {
  const fetcher: FetchLike = async (input: string) => {
    if (input.includes("ean-db")) {
      return {
        ok: true,
        status: 200,
        json: async () => ({ title: "" })
      };
    }

    return {
      ok: true,
      status: 200,
      json: async () => ({
        status: 1,
        product: {
          product_name: "Кефир",
          brands: "Тест",
          categories: "Молочные продукты"
        }
      })
    };
  };

  const result = await lookupBarcode("4601234567890", {
    eanDbApiKey: "fake",
    fetcher
  });

  assert.equal(result.found, true);
  assert.equal(result.provider, "open_food_facts");
  assert.equal(result.product?.name, "Кефир");
});
