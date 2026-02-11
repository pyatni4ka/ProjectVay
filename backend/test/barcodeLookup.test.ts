import test from "node:test";
import assert from "node:assert/strict";
import { lookupBarcode, parseEANDBProduct, parseOpenFoodFactsProduct } from "../src/services/barcodeLookup.ts";

test("parseOpenFoodFactsProduct extracts product and nutrition", () => {
  const product = parseOpenFoodFactsProduct(
    {
      status: 1,
      product: {
        code: "4601234567890",
        product_name_ru: "Творог 5%",
        brands: "Домик в деревне, Тест",
        categories: "Молочные продукты, Творог",
        nutriments: {
          "energy-kcal_100g": 121,
          proteins_100g: 16,
          fat_100g: 5,
          carbohydrates_100g: 3
        }
      }
    },
    "4601234567890"
  );

  assert.ok(product);
  assert.equal(product?.name, "Творог 5%");
  assert.equal(product?.brand, "Домик в деревне");
  assert.equal(product?.category, "Молочные продукты");
  assert.deepEqual(product?.nutrition, {
    kcal: 121,
    protein: 16,
    fat: 5,
    carbs: 3
  });
});

test("parseEANDBProduct extracts minimal payload", () => {
  const product = parseEANDBProduct(
    {
      title: "Йогурт натуральный",
      brand: "Тест",
      category: "Молочные продукты"
    },
    "4600000000000"
  );

  assert.ok(product);
  assert.equal(product?.barcode, "4600000000000");
  assert.equal(product?.name, "Йогурт натуральный");
  assert.equal(product?.brand, "Тест");
  assert.equal(product?.category, "Молочные продукты");
});

test("lookupBarcode falls back to OpenFoodFacts when EAN-DB misses", async () => {
  const calls: string[] = [];
  const fetchImpl: typeof fetch = async (input: string | URL | Request) => {
    const url = String(input);
    calls.push(url);

    if (url.includes("ean-db.com")) {
      return new Response(JSON.stringify({ status: "error", message: "not_found" }), { status: 200 });
    }

    if (url.includes("openfoodfacts")) {
      return new Response(
        JSON.stringify({
          status: 1,
          product: {
            code: "4601234567890",
            product_name: "Milk 2.5%",
            brands: "Sample",
            categories: "Dairy, Milk"
          }
        }),
        { status: 200 }
      );
    }

    return new Response(null, { status: 404 });
  };

  const result = await lookupBarcode({
    code: "4601234567890",
    eanDBApiKey: "test-key",
    fetchImpl
  });

  assert.equal(result.found, true);
  assert.equal(result.provider, "open_food_facts");
  assert.equal(result.product?.name, "Milk 2.5%");
  assert.equal(result.product?.category, "Dairy");
  assert.equal(calls.length, 2);
});
