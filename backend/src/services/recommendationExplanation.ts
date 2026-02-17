import type { Recipe } from "../types/contracts.js";

type ExplanationInput = {
  recipe: Recipe;
  scoreBreakdown: Record<string, number>;
  maxReasons?: number;
};

export function buildRecommendationReasons(input: ExplanationInput): string[] {
  const { recipe, scoreBreakdown } = input;
  const maxReasons = Math.max(1, Math.min(input.maxReasons ?? 3, 5));
  const candidates: Array<{ text: string; weight: number }> = [];

  const nutritionFit = scoreBreakdown.nutritionFit ?? scoreBreakdown.nutrition ?? 0;
  const budgetFit = scoreBreakdown.budgetFit ?? scoreBreakdown.budget ?? 0;
  const availabilityFit = scoreBreakdown.availabilityFit ?? scoreBreakdown.inStock ?? 0;
  const timeFit = scoreBreakdown.prepTimeFit ?? 0;
  const personalFit = scoreBreakdown.personalTasteFit ?? 0;
  const cuisineFit = scoreBreakdown.cuisineFit ?? 0;

  if (nutritionFit > 0.55) {
    candidates.push({
      text: "Хорошо попадает в целевые КБЖУ",
      weight: nutritionFit
    });
  }
  if (budgetFit > 0.45) {
    candidates.push({
      text: "Подходит под бюджет на приём пищи",
      weight: budgetFit
    });
  }
  if (availabilityFit > 0.35) {
    candidates.push({
      text: "Много ингредиентов уже есть дома",
      weight: availabilityFit
    });
  }
  if (timeFit > 0.4) {
    candidates.push({
      text: "Укладывается в желаемое время готовки",
      weight: timeFit
    });
  }
  if (personalFit > 0.5) {
    candidates.push({
      text: "Учитывает ваши прошлые выборы и вкусы",
      weight: personalFit
    });
  }
  if (cuisineFit > 0.55 && recipe.cuisine) {
    candidates.push({
      text: `Соответствует предпочтению по кухне: ${recipe.cuisine}`,
      weight: cuisineFit
    });
  }
  if (recipe.rating != null && recipe.rating > 70) {
    candidates.push({
      text: "Рецепт с высокой пользовательской оценкой",
      weight: 0.4
    });
  }

  if (candidates.length === 0) {
    candidates.push(
      { text: "Сбалансирован по нескольким критериям", weight: 0.5 },
      { text: "Подходит для текущего набора продуктов", weight: 0.45 },
      { text: "Поддерживает разнообразие рациона", weight: 0.4 }
    );
  }

  return candidates
    .sort((left, right) => right.weight - left.weight)
    .slice(0, maxReasons)
    .map((item) => item.text);
}
