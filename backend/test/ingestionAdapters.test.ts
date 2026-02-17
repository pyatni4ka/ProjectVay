import test from "node:test";
import assert from "node:assert/strict";
import { parseOFFTSVSnapshot } from "../src/ingestion/adapters/off.js";
import { parseCatalogCSV } from "../src/ingestion/adapters/catalog.js";
import { parseUHTTTSV } from "../src/ingestion/adapters/uhtt.js";
import { parseRecipeJSONLDFromHTML } from "../src/ingestion/adapters/recipeHTML.js";

test("parse OFF tsv snapshot", () => {
  const tsv = [
    "code\tproduct_name\tgeneric_name",
    "4601234567890\tЙогурт клубничный\t",
    "4601234500001\t\tЙогурт без сахара"
  ].join("\n");

  const parsed = parseOFFTSVSnapshot(tsv);
  assert.equal(parsed.length, 2);
  assert.equal(parsed[0]?.barcode, "4601234567890");
  assert.equal(parsed[1]?.name, "Йогурт без сахара");
});

test("parse catalog csv snapshot", () => {
  const csv = [
    "Barcode;Name;Vendor;Category",
    "4607004650014;Молоко 3.2%;Вкуснотеево;Молочные продукты"
  ].join("\n");

  const parsed = parseCatalogCSV(csv);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0]?.brand, "Вкуснотеево");
  assert.equal(parsed[0]?.category, "Молочные продукты");
});

test("parse uhtt tsv snapshot", () => {
  const tsv = [
    "id\tbarcode\tname\tname_u\tdescription\tdescription_u\tvendor\tvendor_u",
    "1\t4607004650014\tТворог зерненый\t\tМолочные продукты\t\tПростоквашино\t"
  ].join("\n");

  const parsed = parseUHTTTSV(tsv);
  assert.equal(parsed.length, 1);
  assert.equal(parsed[0]?.name, "Творог зерненый");
  assert.equal(parsed[0]?.brand, "Простоквашино");
});

test("parse recipe json-ld for food.ru", () => {
  const html = `
    <html><head>
      <script type="application/ld+json">
      {"@context":"https://schema.org","@type":"Recipe","name":"Борщ","image":"https://food.ru/borsch.jpg","recipeIngredient":["свекла","картофель"],"recipeInstructions":[{"@type":"HowToStep","text":"Сварить"}],"totalTime":"PT1H20M"}
      </script>
    </head></html>
  `;
  const recipe = parseRecipeJSONLDFromHTML(html, "food.ru", "https://food.ru/recipes/1");
  assert.ok(recipe);
  assert.equal(recipe?.title, "Борщ");
  assert.equal(recipe?.totalTimeMinutes, 80);
});

test("parse recipe json-ld for eda.ru", () => {
  const html = `
    <script type="application/ld+json">
    {"@type":"Recipe","name":"Окрошка","image":["https://eda.ru/okroshka.jpg"],"recipeIngredient":["кефир","огурец","укроп"],"recipeInstructions":"Смешать\\nОхладить"}
    </script>
  `;
  const recipe = parseRecipeJSONLDFromHTML(html, "eda.ru", "https://eda.ru/recepty/2");
  assert.ok(recipe);
  assert.equal(recipe?.ingredients.length, 3);
  assert.equal(recipe?.instructions.length, 2);
});

test("parse recipe json-ld for povar.ru", () => {
  const html = `
    <script type="application/ld+json">
    {"@graph":[{"@type":"Recipe","name":"Пюре","image":{"url":"https://povar.ru/puree.jpg"},"recipeIngredient":["картофель","масло"],"recipeInstructions":[{"text":"Отварить"},{"text":"Размять"}]}]}
    </script>
  `;
  const recipe = parseRecipeJSONLDFromHTML(html, "povar.ru", "https://povar.ru/recepty/3");
  assert.ok(recipe);
  assert.equal(recipe?.sourceName, "povar.ru");
  assert.equal(recipe?.instructions.length, 2);
});
