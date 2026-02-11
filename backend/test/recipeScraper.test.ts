import test from "node:test";
import assert from "node:assert/strict";
import { RecipeScraperError, parseRecipeFromHTML } from "../src/services/recipeScraper.js";

const SAMPLE_HTML = `
<!doctype html>
<html>
  <head>
    <title>Омлет</title>
    <script type="application/ld+json">
      {
        "@context": "https://schema.org",
        "@type": "Recipe",
        "name": "Омлет с томатами",
        "image": ["https://cdn.example.com/omelet.jpg"],
        "recipeIngredient": ["2 яйца", "1 томат", "20 мл молока"],
        "recipeInstructions": [
          {"@type":"HowToStep","text":"Взбить яйца с молоком"},
          {"@type":"HowToStep","text":"Добавить томаты и жарить 5 минут"}
        ],
        "video": {"@type":"VideoObject","contentUrl":"https://video.example.com/omelet.mp4"},
        "totalTime":"PT15M",
        "recipeYield":"2 порции",
        "nutrition": {
          "@type":"NutritionInformation",
          "calories":"380 kcal",
          "proteinContent":"22 g",
          "fatContent":"24 g",
          "carbohydrateContent":"12 g"
        },
        "keywords":"завтрак,быстро",
        "recipeCuisine":"русская"
      }
    </script>
  </head>
  <body></body>
</html>
`;

test("parseRecipeFromHTML extracts schema.org recipe fields", () => {
  const recipe = parseRecipeFromHTML("https://food.ru/recipes/omelet", SAMPLE_HTML);

  assert.equal(recipe.title, "Омлет с томатами");
  assert.equal(recipe.imageURL, "https://cdn.example.com/omelet.jpg");
  assert.equal(recipe.sourceName, "food.ru");
  assert.equal(recipe.ingredients.length, 3);
  assert.equal(recipe.instructions.length, 2);
  assert.equal(recipe.videoURL, "https://video.example.com/omelet.mp4");
  assert.equal(recipe.times?.totalMinutes, 15);
  assert.equal(recipe.servings, 2);
  assert.equal(recipe.cuisine, "русская");
  assert.equal(recipe.nutrition?.kcal, 380);
  assert.equal(recipe.nutrition?.protein, 22);
  assert.equal(recipe.nutrition?.fat, 24);
  assert.equal(recipe.nutrition?.carbs, 12);
  assert.ok(recipe.tags?.includes("русская"));
});

test("parseRecipeFromHTML throws when image is missing", () => {
  const htmlNoImage = `
  <html><head>
    <script type="application/ld+json">
      {
        "@context":"https://schema.org",
        "@type":"Recipe",
        "name":"Без картинки",
        "recipeIngredient":["вода"],
        "recipeInstructions":["Шаг 1"]
      }
    </script>
  </head></html>
  `;

  assert.throws(
    () => parseRecipeFromHTML("https://food.ru/recipes/no-image", htmlNoImage),
    (error: unknown) => error instanceof RecipeScraperError && error.code === "missing_image"
  );
});
