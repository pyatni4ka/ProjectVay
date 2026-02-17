import type { NormalizedIngredient } from "../types/contracts.js";

const UNIT_PATTERNS: Array<{ unit: string; re: RegExp }> = [
  { unit: "kg", re: /\b(кг|kg)\b/i },
  { unit: "g", re: /\b(г|гр|g)\b/i },
  { unit: "l", re: /\b(л|l)\b/i },
  { unit: "ml", re: /\b(мл|ml)\b/i },
  { unit: "tbsp", re: /\b(ст\.?\s?л\.?|tbsp)\b/i },
  { unit: "tsp", re: /\b(ч\.?\s?л\.?|tsp)\b/i },
  { unit: "pcs", re: /\b(шт|штук|pcs?)\b/i }
];

const BRACKET_RE = /\(([^)]*)\)/g;
const EXTRA_WORDS_RE = /\b(по вкусу|для подачи|свежий|свежая|свежие|очищенный|очищенная|мелко|крупно|нарезанный|нарезанная)\b/gi;

export function normalizeIngredient(raw: string): NormalizedIngredient {
  const prepared = String(raw ?? "").trim();
  const withoutBrackets = prepared.replace(BRACKET_RE, " ");
  const quantity = parseQuantity(withoutBrackets);
  const unit = parseUnit(withoutBrackets);

  let name = withoutBrackets
    .replace(/[\d.,/]+/g, " ")
    .replace(EXTRA_WORDS_RE, " ")
    .replace(/[–—-]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();

  if (!name) {
    name = prepared.toLowerCase();
  }

  const normalizedKey = normalizeKey(name);
  return {
    raw: prepared,
    normalizedKey,
    name,
    quantity,
    unit
  };
}

export function normalizeIngredients(ingredients: string[]): NormalizedIngredient[] {
  return ingredients
    .map((item) => normalizeIngredient(item))
    .filter((item) => item.normalizedKey.length > 0);
}

function parseQuantity(input: string): number | undefined {
  const match = input.match(/(\d+(?:[.,]\d+)?(?:\s*\/\s*\d+(?:[.,]\d+)?)?)/);
  if (!match?.[1]) {
    return undefined;
  }

  const raw = match[1].replace(",", ".").replace(/\s+/g, "");
  if (raw.includes("/")) {
    const [left, right] = raw.split("/");
    const l = Number(left);
    const r = Number(right);
    if (Number.isFinite(l) && Number.isFinite(r) && r > 0) {
      return round3(l / r);
    }
  }

  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) {
    return undefined;
  }
  return round3(parsed);
}

function parseUnit(input: string): string | undefined {
  for (const pattern of UNIT_PATTERNS) {
    if (pattern.re.test(input)) {
      return pattern.unit;
    }
  }
  return undefined;
}

function normalizeKey(value: string): string {
  return value
    .replace(/ё/g, "е")
    .replace(/[^a-zа-я0-9\s]/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function round3(value: number): number {
  return Math.round(value * 1000) / 1000;
}
