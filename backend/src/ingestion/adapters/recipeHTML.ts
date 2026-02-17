import type { IngestionRecipe } from "../types.js";

export function parseRecipeJSONLDFromHTML(
  html: string,
  sourceId: string,
  sourceURL: string
): IngestionRecipe | null {
  const scripts = html.match(/<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi) ?? [];
  for (const script of scripts) {
    const payload = script.match(/>([\s\S]*?)<\/script>/i)?.[1]?.trim();
    if (!payload) {
      continue;
    }

    const parsed = safeParseJSON(payload);
    const recipeNode = findRecipeNode(parsed);
    if (!recipeNode) {
      continue;
    }

    const title = readString(recipeNode.name);
    const imageURL = extractImageURL(recipeNode.image);
    const ingredients = parseStringArray(recipeNode.recipeIngredient);
    const instructions = parseInstructions(recipeNode.recipeInstructions);
    if (!title || ingredients.length === 0 || instructions.length === 0) {
      continue;
    }

    return {
      sourceRef: sourceURL,
      title,
      sourceName: sourceId,
      sourceURL,
      imageURL: imageURL ?? undefined,
      ingredients,
      instructions,
      nutrition: normalizeNutrition(recipeNode.nutrition),
      totalTimeMinutes: parseDurationMinutes(readString(recipeNode.totalTime)),
      cuisine: readString(recipeNode.recipeCuisine) ?? undefined,
      tags: parseStringArray(recipeNode.keywords),
      provenance: {
        parser: "json-ld",
        sourceId
      }
    };
  }

  return null;
}

type UnknownRecord = Record<string, unknown>;

function safeParseJSON(raw: string): unknown {
  const normalized = raw.replace(/^\uFEFF/, "").replace(/<!--/g, "").replace(/-->/g, "");
  try {
    return JSON.parse(normalized);
  } catch {
    return null;
  }
}

function findRecipeNode(value: unknown): UnknownRecord | null {
  if (Array.isArray(value)) {
    for (const item of value) {
      const found = findRecipeNode(item);
      if (found) return found;
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

  if (value["@graph"]) {
    return findRecipeNode(value["@graph"]);
  }

  if (value.mainEntity) {
    return findRecipeNode(value.mainEntity);
  }

  return null;
}

function isRecipeType(value: unknown): boolean {
  if (typeof value === "string") {
    return value.toLowerCase() === "recipe";
  }
  if (Array.isArray(value)) {
    return value.some((entry) => typeof entry === "string" && entry.toLowerCase() === "recipe");
  }
  return false;
}

function parseStringArray(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value
      .map((item) => readString(item))
      .filter((item): item is string => Boolean(item))
      .map((item) => item.trim())
      .filter(Boolean);
  }
  const single = readString(value);
  if (!single) {
    return [];
  }
  return single
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseInstructions(value: unknown): string[] {
  if (Array.isArray(value)) {
    const out: string[] = [];
    for (const item of value) {
      if (typeof item === "string" && item.trim()) {
        out.push(item.trim());
        continue;
      }
      if (isRecord(item)) {
        const text = readString(item.text);
        if (text) {
          out.push(text);
        }
      }
    }
    return out;
  }
  const text = readString(value);
  if (!text) {
    return [];
  }
  return text
    .split(/\r?\n/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function normalizeNutrition(value: unknown): Record<string, number | undefined> | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const calories = parseNumber((readString(value.calories)?.replace(/[^\d.,]/g, "").replace(",", ".")) ?? null);
  const protein = parseNumber((readString(value.proteinContent)?.replace(/[^\d.,]/g, "").replace(",", ".")) ?? null);
  const fat = parseNumber((readString(value.fatContent)?.replace(/[^\d.,]/g, "").replace(",", ".")) ?? null);
  const carbs = parseNumber((readString(value.carbohydrateContent)?.replace(/[^\d.,]/g, "").replace(",", ".")) ?? null);

  const out: Record<string, number | undefined> = {
    kcal: calories,
    protein,
    fat,
    carbs
  };

  if (!calories && !protein && !fat && !carbs) {
    return undefined;
  }
  return out;
}

function extractImageURL(value: unknown): string | null {
  if (typeof value === "string") {
    return value;
  }
  if (Array.isArray(value)) {
    for (const entry of value) {
      const found = extractImageURL(entry);
      if (found) return found;
    }
    return null;
  }
  if (isRecord(value)) {
    const valueURL = readString(value.url);
    if (valueURL) return valueURL;
  }
  return null;
}

function readString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const normalized = value.trim();
  return normalized ? normalized : null;
}

function parseDurationMinutes(value: string | null): number | undefined {
  if (!value) return undefined;
  const match = value.match(/PT(?:(\d+)H)?(?:(\d+)M)?/i);
  if (!match) return undefined;
  const hours = Number(match[1] ?? 0);
  const minutes = Number(match[2] ?? 0);
  const total = hours * 60 + minutes;
  return Number.isFinite(total) && total > 0 ? total : undefined;
}

function parseNumber(value: string | null): number | undefined {
  if (!value) return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === "object" && value !== null;
}
