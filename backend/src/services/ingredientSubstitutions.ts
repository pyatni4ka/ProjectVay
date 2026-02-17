import type { IngredientSubstitution } from "../types/contracts.js";

const SUBSTITUTION_HINTS: Array<{
  match: RegExp;
  substitute: string;
  reason: IngredientSubstitution["reason"];
  savingsRub: number;
}> = [
  { match: /авокад/i, substitute: "кабачок", reason: "price", savingsRub: 110 },
  { match: /руккол/i, substitute: "пекинская капуста", reason: "price", savingsRub: 80 },
  { match: /пармезан/i, substitute: "полутвердый сыр", reason: "price", savingsRub: 140 },
  { match: /лосос|семг/i, substitute: "горбуша", reason: "price", savingsRub: 190 },
  { match: /греческий йогурт/i, substitute: "кефир 3.2%", reason: "availability", savingsRub: 45 },
  { match: /кедров/i, substitute: "подсолнечные семечки", reason: "price", savingsRub: 120 }
];

export function suggestIngredientSubstitutions(ingredients: string[], limit: number = 8): IngredientSubstitution[] {
  const substitutions: IngredientSubstitution[] = [];

  for (const ingredient of ingredients) {
    const hint = SUBSTITUTION_HINTS.find((entry) => entry.match.test(ingredient));
    if (!hint) {
      continue;
    }
    substitutions.push({
      ingredient,
      substitute: hint.substitute,
      reason: hint.reason,
      estimatedSavingsRub: hint.savingsRub
    });
    if (substitutions.length >= limit) {
      break;
    }
  }

  return substitutions;
}
