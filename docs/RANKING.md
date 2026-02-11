# Алгоритм ранжирования рецептов

Итоговый скор:

`Score = 0.35*Expiry + 0.30*InStock + 0.15*Nutrition + 0.10*Budget + 0.05*Preference - 0.05*Penalty`

Где:

1. `Expiry` (0..1): доля ингредиентов, которые совпадают с продуктами "скоро испортится".
2. `InStock` (0..1): доля ингредиентов, которые уже есть дома.
3. `Nutrition` (0..1): близость к целевым КБЖУ на приём пищи.
4. `Budget` (0..1): соответствие оценке стоимости на порцию.
5. `Preference` (0..1): бонус за любимые кухни/закреплённые теги.
6. `Penalty` (0..1): штраф за дизлайки (например, кускус) и вероятные блюда "с костями".

## Нормализация

- Любые сырьевые метрики переводятся в диапазон 0..1.
- Для бюджета: если оценка неизвестна, ставится 0.5 и пометка "неполные цены".
- Для nutrition используется экспоненциальный спад от целевого отклонения.

## Псевдокод

```text
for recipe in candidates:
  expiry = overlap(recipe.ingredients, expiringSoonSet)
  inStock = overlap(recipe.ingredients, inStockSet)
  nutrition = macroDistance(recipe.nutrition, targetMacros)
  budget = budgetFit(estimatePrice(recipe), perMealBudget)
  preference = preferenceBoost(recipe.tags, favoriteCuisines)
  penalty = dislikedPenalty(recipe.ingredients, dislikedSet, avoidBones)

  score = 0.35*expiry + 0.30*inStock + 0.15*nutrition + 0.10*budget + 0.05*preference - 0.05*penalty
```

## Тюнинг

- Если у пользователя много продуктов с близким сроком, вес `Expiry` повышается до `0.45`.
- Если задан жёсткий бюджет, вес `Budget` повышается до `0.20`.
- Для "кости допустимы редко" применяется мягкий штраф (не исключение).
