import type { Recipe } from "../types/contracts.js";

export async function fetchAndParseRecipe(url: string): Promise<Recipe> {
  // MVP mock: в production подключить JSON-LD parser (например recipe-scraper).
  return {
    id: `url_${Buffer.from(url).toString("base64url").slice(0, 10)}`,
    title: "Рецепт из источника",
    imageURL: "https://images.example/placeholder.jpg",
    sourceName: new URL(url).hostname,
    sourceURL: url,
    ingredients: ["ингредиент 1", "ингредиент 2"],
    instructions: ["Шаг 1", "Шаг 2"]
  };
}
