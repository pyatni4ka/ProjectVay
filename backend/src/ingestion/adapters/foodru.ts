import type { IngestionAdapter, IngestionContext, IngestionRecipe } from "../types.js";
import { parseRecipeJSONLDFromHTML } from "./recipeHTML.js";

const DEFAULT_FOOD_RU_SEEDS = (process.env.FOOD_RU_SEED_URLS ?? "")
  .split(",")
  .map((item) => item.trim())
  .filter(Boolean);

export const foodRuAdapter: IngestionAdapter = {
  id: "food_ru",
  kind: "recipes",
  licenseRisk: "high",
  ingest: (context) => ingestFoodRu(context)
};

export async function ingestFoodRu(context: IngestionContext): Promise<{
  products: [];
  recipes: IngestionRecipe[];
  priceSignals: [];
  synonyms: [];
}> {
  const recipes: IngestionRecipe[] = [];
  for (const url of DEFAULT_FOOD_RU_SEEDS) {
    if (recipes.length >= context.maxItemsPerSource) {
      break;
    }

    try {
      const response = await fetch(url, {
        headers: {
          "User-Agent": "ProjectVayIngestionBot/1.0 (+https://projectvay.local)",
          Accept: "text/html,application/xhtml+xml"
        }
      });
      if (!response.ok) {
        continue;
      }
      const html = await response.text();
      const recipe = parseRecipeJSONLDFromHTML(html, "food.ru", url);
      if (recipe) {
        recipes.push(recipe);
      }
    } catch {
      continue;
    }
  }

  return { products: [], recipes, priceSignals: [], synonyms: [] };
}
