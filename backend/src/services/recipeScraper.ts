import { createHash } from "node:crypto";
import type { Recipe, RecipeParseResponse } from "../types/contracts.js";
import { normalizeIngredients } from "./ingredientNormalizer.js";
import { buildRecipeQualityReport } from "./recipeQuality.js";

export class RecipeScraperError extends Error {
  constructor(
    message: string,
    readonly code:
      | "network_error"
      | "timeout"
      | "invalid_html"
      | "recipe_not_found"
      | "missing_image"
      | "missing_ingredients"
      | "missing_instructions"
  ) {
    super(message);
    this.name = "RecipeScraperError";
  }
}

type FetchLike = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

type RecipeNode = Record<string, unknown>;

type FetchRecipeOptions = {
  timeoutMs?: number;
  fetchImpl?: FetchLike;
  userAgent?: string;
};

const DEFAULT_TIMEOUT_MS = 8_000;
const DEFAULT_USER_AGENT = "InventoryAIRecipeBot/1.0 (+https://projectvay.local)";

export async function fetchAndParseRecipe(url: string, options: FetchRecipeOptions = {}): Promise<Recipe> {
  const detailed = await fetchAndParseRecipeDetailed(url, options);
  return detailed.recipe;
}

export async function fetchAndParseRecipeDetailed(url: string, options: FetchRecipeOptions = {}): Promise<RecipeParseResponse> {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const fetchImpl = options.fetchImpl ?? fetch;
  const userAgent = options.userAgent ?? DEFAULT_USER_AGENT;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  let html: string;
  try {
    const response = await fetchImpl(url, {
      method: "GET",
      headers: {
        "User-Agent": userAgent,
        Accept: "text/html,application/xhtml+xml"
      },
      signal: controller.signal
    });

    if (!response.ok) {
      throw new RecipeScraperError(`Fetch failed with status ${response.status}`, "network_error");
    }

    html = await response.text();
  } catch (error) {
    if (error instanceof RecipeScraperError) {
      throw error;
    }

    if (isAbortError(error)) {
      throw new RecipeScraperError("Recipe source timeout", "timeout");
    }

    throw new RecipeScraperError("Failed to fetch recipe source", "network_error");
  } finally {
    clearTimeout(timeout);
  }

  return parseRecipeFromHTMLDetailed(url, html);
}

export function parseRecipeFromHTML(url: string, html: string): Recipe {
  return parseRecipeFromHTMLDetailed(url, html).recipe;
}

export function parseRecipeFromHTMLDetailed(url: string, html: string): RecipeParseResponse {
  if (!html || !html.trim()) {
    throw new RecipeScraperError("Empty HTML payload", "invalid_html");
  }

  const recipeNode = extractRecipeNode(html);
  if (!recipeNode) {
    throw new RecipeScraperError("Recipe schema not found", "recipe_not_found");
  }

  const title = nonEmptyString(recipeNode.name) ?? extractTitleFromHTML(html) ?? "Рецепт";
  const imageURL = extractImageURL(recipeNode.image);
  if (!imageURL) {
    throw new RecipeScraperError("Recipe has no image", "missing_image");
  }

  const ingredients = normalizeIngredients(recipeNode.recipeIngredient);
  if (ingredients.length === 0) {
    throw new RecipeScraperError("Recipe has no ingredients", "missing_ingredients");
  }

  const instructions = normalizeInstructions(recipeNode.recipeInstructions);
  if (instructions.length === 0) {
    throw new RecipeScraperError("Recipe has no instructions", "missing_instructions");
  }

  const parsedURL = new URL(url);
  const cuisine = firstTagFromUnknown(recipeNode.recipeCuisine);

  const recipe: Recipe = {
    id: hashID(url),
    title,
    imageURL,
    sourceName: parsedURL.hostname,
    sourceURL: parsedURL.toString(),
    videoURL: extractVideoURL(recipeNode.video),
    ingredients,
    instructions,
    nutrition: normalizeNutrition(recipeNode.nutrition),
    times: { totalMinutes: parseDurationToMinutes(recipeNode.totalTime) },
    servings: parseNumberFromUnknown(recipeNode.recipeYield),
    cuisine,
    tags: normalizeTags(recipeNode.keywords, recipeNode.recipeCuisine, recipeNode.recipeCategory)
  };

  const normalized = normalizeIngredients(recipe.ingredients);
  const quality = buildRecipeQualityReport(recipe);
  const diagnostics: string[] = [];
  if (quality.missingFields.length > 0) {
    diagnostics.push(`Missing fields: ${quality.missingFields.join(", ")}`);
  }

  return {
    recipe,
    normalizedIngredients: normalized,
    quality,
    diagnostics
  };
}

function extractRecipeNode(html: string): RecipeNode | null {
  const matches = html.match(/<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi) ?? [];
  for (const match of matches) {
    const payloadMatch = match.match(/>([\s\S]*?)<\/script>/i);
    const payload = payloadMatch?.[1]?.trim();
    if (!payload) {
      continue;
    }

    const parsed = safeParseJSONLD(payload);
    if (!parsed) {
      continue;
    }

    const recipe = findRecipeNode(parsed);
    if (recipe) {
      return recipe;
    }
  }

  return null;
}

function safeParseJSONLD(raw: string): unknown | null {
  const normalized = raw
    .replace(/^\uFEFF/, "")
    .replace(/<!--/g, "")
    .replace(/-->/g, "")
    .trim();

  try {
    return JSON.parse(normalized);
  } catch {
    return null;
  }
}

function findRecipeNode(value: unknown): RecipeNode | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findRecipeNode(item);
      if (found) {
        return found;
      }
    }
    return null;
  }

  if (!isRecord(value)) {
    return null;
  }

  const typeValue = value["@type"];
  if (isRecipeType(typeValue)) {
    return value;
  }

  const graph = value["@graph"];
  if (graph) {
    const graphRecipe = findRecipeNode(graph);
    if (graphRecipe) {
      return graphRecipe;
    }
  }

  if (value.mainEntity) {
    const main = findRecipeNode(value.mainEntity);
    if (main) {
      return main;
    }
  }

  return null;
}

function isRecipeType(value: unknown): boolean {
  if (typeof value === "string") {
    return value.toLowerCase() === "recipe";
  }

  if (Array.isArray(value)) {
    return value.some((item) => typeof item === "string" && item.toLowerCase() === "recipe");
  }

  return false;
}

function extractImageURL(value: unknown): string | null {
  if (typeof value === "string") {
    return value;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const candidate = extractImageURL(item);
      if (candidate) {
        return candidate;
      }
    }
  }

  if (isRecord(value)) {
    const fromURL = nonEmptyString(value.url);
    if (fromURL) {
      return fromURL;
    }
  }

  return null;
}

function normalizeIngredients(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value
      .map((item) => (typeof item === "string" ? item.trim() : ""))
      .filter((item) => item.length > 0);
  }

  if (typeof value === "string") {
    return value
      .split(/\r?\n|,|;/g)
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
  }

  return [];
}

function normalizeInstructions(value: unknown): string[] {
  if (typeof value === "string") {
    return value
      .split(/\r?\n/g)
      .map((item) => item.trim())
      .filter((item) => item.length > 0);
  }

  if (Array.isArray(value)) {
    const result: string[] = [];

    for (const item of value) {
      if (typeof item === "string") {
        const normalized = item.trim();
        if (normalized) {
          result.push(normalized);
        }
        continue;
      }

      if (isRecord(item)) {
        const text = nonEmptyString(item.text) ?? nonEmptyString(item.name);
        if (text) {
          result.push(text);
        }
      }
    }

    return result;
  }

  if (isRecord(value)) {
    const text = nonEmptyString(value.text) ?? nonEmptyString(value.name);
    return text ? [text] : [];
  }

  return [];
}

function extractVideoURL(value: unknown): string | null {
  if (typeof value === "string") {
    return value;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const candidate = extractVideoURL(item);
      if (candidate) {
        return candidate;
      }
    }
  }

  if (isRecord(value)) {
    return nonEmptyString(value.contentUrl) ?? nonEmptyString(value.embedUrl) ?? nonEmptyString(value.url) ?? null;
  }

  return null;
}

function normalizeNutrition(value: unknown): Recipe["nutrition"] | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const nutrition = {
    kcal: parseNumberFromUnknown(value.calories),
    protein: parseNumberFromUnknown(value.proteinContent),
    fat: parseNumberFromUnknown(value.fatContent),
    carbs: parseNumberFromUnknown(value.carbohydrateContent),
    fiber: parseNumberFromUnknown(value.fiberContent),
    sugar: parseNumberFromUnknown(value.sugarContent),
    sodium: parseNumberFromUnknown(value.sodiumContent)
  };

  if (
    !nutrition.kcal &&
    !nutrition.protein &&
    !nutrition.fat &&
    !nutrition.carbs &&
    !nutrition.fiber &&
    !nutrition.sugar &&
    !nutrition.sodium
  ) {
    return undefined;
  }

  return nutrition;
}

function normalizeTags(...values: unknown[]): string[] | undefined {
  const tags = values
    .flatMap(toStringArray)
    .map((item) => item.trim())
    .filter((item) => item.length > 0);

  if (tags.length === 0) {
    return undefined;
  }

  return Array.from(new Set(tags));
}

function toStringArray(value: unknown): string[] {
  if (typeof value === "string") {
    return value.split(",").map((item) => item.trim());
  }

  if (Array.isArray(value)) {
    return value.filter((item): item is string => typeof item === "string");
  }

  return [];
}

function parseNumberFromUnknown(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }

  if (typeof value !== "string") {
    return undefined;
  }

  const match = value.match(/-?\d+([.,]\d+)?/);
  if (!match) {
    return undefined;
  }

  const normalized = match[0].replace(",", ".");
  const parsed = Number(normalized);
  if (!Number.isFinite(parsed)) {
    return undefined;
  }

  return parsed;
}

function parseDurationToMinutes(value: unknown): number | undefined {
  if (typeof value !== "string" || value.length === 0) {
    return undefined;
  }

  const normalized = value.toUpperCase();
  const match = normalized.match(/^P(?:\d+Y)?(?:\d+M)?(?:\d+D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!match) {
    return undefined;
  }

  const hours = Number(match[1] ?? "0");
  const minutes = Number(match[2] ?? "0");
  const seconds = Number(match[3] ?? "0");

  const totalMinutes = hours * 60 + minutes + (seconds > 0 ? 1 : 0);
  return totalMinutes > 0 ? totalMinutes : undefined;
}

function firstTagFromUnknown(value: unknown): string | undefined {
  const tags = toStringArray(value)
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
  return tags[0];
}

function extractTitleFromHTML(html: string): string | null {
  const match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  const title = match?.[1]?.trim();
  return title && title.length > 0 ? title : null;
}

function hashID(url: string): string {
  return `url_${createHash("sha1").update(url).digest("hex").slice(0, 16)}`;
}

function nonEmptyString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function isAbortError(error: unknown): boolean {
  return (
    isRecord(error) &&
    typeof error.name === "string" &&
    error.name.toLowerCase() === "aborterror"
  );
}
