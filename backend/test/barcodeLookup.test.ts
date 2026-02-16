import test from "node:test";
import assert from "node:assert/strict";
import { lookupBarcode, parseEANDBProduct, parseOpenFoodFactsProduct, parseBarcodeListRuHTML } from "../src/services/barcodeLookup.ts";

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

test("parseBarcodeListRuHTML extracts product from og:title", () => {
  const html = `
    <html><head>
      <meta property="og:title" content="Штрихкод 4607001660095 - Молоко Весёлый Молочник 2.5%">
      <meta name="brand" content="Весёлый Молочник">
      <title>Штрихкод 4607001660095 - Молоко Весёлый Молочник 2.5%</title>
    </head><body>
      <div class="breadcrumb"><a href="#">Молочные продукты</a></div>
    </body></html>
  `;

  const product = parseBarcodeListRuHTML(html, "4607001660095");

  assert.ok(product);
  assert.equal(product?.barcode, "4607001660095");
  assert.equal(product?.name, "Молоко Весёлый Молочник 2.5%");
  assert.equal(product?.brand, "Весёлый Молочник");
  assert.equal(product?.category, "Молочные продукты");
  assert.equal(product?.nutrition, undefined);
});

test("parseBarcodeListRuHTML returns null for search page", () => {
  const html = `
    <html><head>
      <meta property="og:title" content="Штрихкод - Поиск">
      <title>Штрихкод - Поиск</title>
    </head><body></body></html>
  `;

  const product = parseBarcodeListRuHTML(html, "0000000000000");
  assert.equal(product, null);
});

test("parseBarcodeListRuHTML falls back to title tag", () => {
  const html = `
    <html><head>
      <title>Штрихкод 4600000000001 - Сок яблочный</title>
    </head><body></body></html>
  `;

  const product = parseBarcodeListRuHTML(html, "4600000000001");

  assert.ok(product);
  assert.equal(product?.name, "Сок яблочный");
  assert.equal(product?.category, "Продукты");
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
    enableBarcodeListRu: false,
    fetchImpl
  });

  assert.equal(result.found, true);
  assert.equal(result.provider, "open_food_facts");
  assert.equal(result.product?.name, "Milk 2.5%");
  assert.equal(result.product?.category, "Dairy");
  assert.equal(calls.length, 2);
});

test("lookupBarcode falls back to barcode-list.ru when EAN-DB and OpenFoodFacts miss", async () => {
  const calls: string[] = [];
  const fetchImpl: typeof fetch = async (input: string | URL | Request) => {
    const url = String(input);
    calls.push(url);

    if (url.includes("ean-db.com")) {
      return new Response(JSON.stringify({ status: "error" }), { status: 200 });
    }

    if (url.includes("openfoodfacts")) {
      return new Response(JSON.stringify({ status: 0 }), { status: 200 });
    }

    if (url.includes("barcode-list.ru")) {
      const html = `
        <html><head>
          <meta property="og:title" content="Штрихкод 4607001660095 - Творог Домик в деревне 5%">
          <meta name="brand" content="Домик в деревне">
          <title>Штрихкод 4607001660095 - Творог Домик в деревне 5%</title>
        </head><body></body></html>
      `;
      return new Response(html, { status: 200, headers: { "Content-Type": "text/html" } });
    }

    return new Response(null, { status: 404 });
  };

  const result = await lookupBarcode({
    code: "4607001660095",
    eanDBApiKey: "test-key",
    enableBarcodeListRu: true,
    fetchImpl
  });

  assert.equal(result.found, true);
  assert.equal(result.provider, "barcode_list_ru");
  assert.equal(result.product?.name, "Творог Домик в деревне 5%");
  assert.equal(result.product?.brand, "Домик в деревне");
  assert.equal(calls.length, 3);
});
