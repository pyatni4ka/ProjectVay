# API_EXAMPLES

## 1) Generate weekly autopilot

### Request

```json
POST /api/v1/meal-plan/week
{
  "startDate": "2026-02-16",
  "days": 7,
  "mealsPerDay": 3,
  "includeSnacks": false,
  "ingredientKeywords": ["курица", "рис", "яйца"],
  "expiringSoonKeywords": ["йогурт"],
  "targets": { "kcal": 2200, "protein": 140, "fat": 70, "carbs": 220 },
  "budget": { "perDay": 900, "strictness": "soft", "softLimitPct": 0.05 },
  "effortLevel": "quick",
  "objective": "cost_macro",
  "optimizerProfile": "balanced",
  "seed": 42
}
```

### Response (пример)

```json
{
  "planId": "week_2026-02-16_42",
  "startDate": "2026-02-16",
  "days": [
    {
      "date": "2026-02-16",
      "mealTargets": {
        "breakfast": { "kcal": 733, "protein": 47, "fat": 23, "carbs": 73 },
        "lunch": { "kcal": 733, "protein": 47, "fat": 23, "carbs": 73 },
        "dinner": { "kcal": 733, "protein": 47, "fat": 23, "carbs": 73 }
      },
      "entries": [],
      "totals": { "kcal": 2140, "protein": 136, "fat": 67, "carbs": 216, "estimatedCost": 860 },
      "dayBudget": { "target": 900, "actual": 860, "delta": -40 }
    }
  ],
  "shoppingListWithQuantities": [
    { "ingredient": "курица", "amount": 1200, "unit": "g", "approximate": false },
    { "ingredient": "рис", "amount": 700, "unit": "g", "approximate": true }
  ],
  "budgetProjection": {
    "day": { "target": 900, "actual": 860 },
    "week": { "target": 6300, "actual": 5980 },
    "month": { "target": 27000, "actual": 25600 },
    "strictness": "soft",
    "softLimitPct": 0.05
  },
  "warnings": ["Для 1 приёма пищи использована приблизительная оценка цены."],
  "nutritionConfidence": "medium"
}
```

## 2) Replace meal (1 tap)

### Request

```json
POST /api/v1/meal-plan/replace
{
  "planId": "week_2026-02-16_42",
  "dayIndex": 1,
  "mealSlot": "lunch",
  "sortMode": "cheap",
  "topN": 5,
  "budget": { "perDay": 900, "strictness": "soft", "softLimitPct": 0.05 },
  "inventorySnapshot": ["курица", "рис", "йогурт"],
  "constraints": {
    "diets": ["gluten_free"],
    "allergies": ["арахис"]
  }
}
```

### Response (пример)

```json
{
  "candidates": [
    {
      "recipeId": "r_123",
      "title": "Курица с рисом",
      "costDelta": -45,
      "macroDelta": { "kcal": -20, "protein": 4, "fat": -2, "carbs": -1 },
      "timeDelta": -10,
      "tags": ["cheap", "uses_inventory", "high_protein"]
    }
  ],
  "updatedPlanPreview": { "estimatedTotalCost": 5820 },
  "why": ["Дешевле текущего варианта", "Использует продукты из инвентаря"]
}
```

## 3) Adapt plan after deviation

### Request

```json
POST /api/v1/meal-plan/adapt
{
  "planId": "week_2026-02-16_42",
  "eventType": "ate_out",
  "impactEstimate": "medium",
  "timestamp": "2026-02-18T14:30:00+03:00",
  "applyScope": "week"
}
```

### Response (пример)

```json
{
  "updatedRemainingPlan": {
    "daysChanged": 4,
    "estimatedTotalCost": 5750
  },
  "disruptionScore": 0.22,
  "newBudgetProjection": {
    "week": { "target": 6300, "actual": 5750 },
    "strictness": "soft",
    "softLimitPct": 0.05
  },
  "gentleMessage": "Ничего страшного. Я мягко подстроил оставшийся план недели.",
  "why": ["Учтен дополнительный прием вне дома", "Сохранено большинство уже выбранных блюд"]
}
```
