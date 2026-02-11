const DEFAULT_RECIPE_SOURCES = [
  "eda.ru",
  "food.ru",
  "povar.ru",
  "iamcook.ru",
  "say7.info",
  "allrecipes.com",
  "bbcgoodfood.com",
  "seriouseats.com"
];

export function recipeSourceWhitelistFromEnv(
  envValue: string | undefined,
  fallback: readonly string[] = DEFAULT_RECIPE_SOURCES
): string[] {
  const parsed = (envValue ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter((item) => item.length > 0);

  if (parsed.length === 0) {
    return [...fallback];
  }

  return Array.from(new Set(parsed));
}

export const defaultRecipeSourceWhitelist = [...DEFAULT_RECIPE_SOURCES];
