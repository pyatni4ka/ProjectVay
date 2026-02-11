# Backend API (MVP + Stage 3 baseline)

Base URL: `/api/v1`

## 1) GET /recipes/search
Поиск по индексу рецептов (seed + fetched из white-list источников).

Query params:
- `q` — строка поиска
- `cuisine` — csv-фильтр по кухне/тегам (опционально)
- `limit` — ограничение размера выдачи (по умолчанию 50, максимум 200)

Response `200`:
```json
{
  "items": [
    {
      "id": "r_123",
      "title": "Курица с рисом",
      "imageURL": "https://...",
      "sourceName": "example.ru",
      "sourceURL": "https://...",
      "videoURL": "https://...",
      "ingredients": ["курица", "рис"],
      "instructions": ["..."],
      "nutrition": {"kcal": 420, "protein": 34, "fat": 12, "carbs": 44}
    }
  ]
}
```

## 2) POST /recipes/recommend
Рекомендации с ранжированием под инвентарь/цели/бюджет.

Request body:
```json
{
  "ingredientKeywords": ["яйца", "творог", "помидоры"],
  "expiringSoonKeywords": ["творог"],
  "targets": {"kcal": 700, "protein": 45, "fat": 25, "carbs": 70},
  "budget": {"perMeal": 250},
  "exclude": ["кускус"],
  "avoidBones": true,
  "cuisine": ["русская", "средиземноморская"],
  "limit": 30
}
```

Response `200`:
```json
{
  "items": [
    {
      "recipe": {"id": "r_123", "title": "...", "imageURL": "..."},
      "score": 0.88,
      "scoreBreakdown": {
        "expiry": 0.32,
        "inStock": 0.28,
        "nutrition": 0.14,
        "budget": 0.08,
        "penalties": -0.04
      }
    }
  ]
}
```

## 3) POST /recipes/fetch
Парсинг recipe URL + кэширование schema.org JSON-LD.

Request:
```json
{"url": "https://example.ru/recipe/123"}
```

Response `200`:
```json
{
  "id": "r_123",
  "title": "Омлет",
  "imageURL": "https://...jpg",
  "sourceName": "example.ru",
  "sourceURL": "https://example.ru/recipe/123",
  "videoURL": null,
  "ingredients": ["яйца", "молоко"],
  "instructions": ["Шаг 1", "Шаг 2"],
  "servings": 2,
  "cuisine": "русская",
  "times": {"totalMinutes": 15}
}
```

Ошибки:
- `400 invalid_url`
- `403 source_not_allowed`
- `429 rate_limited`
- `422 recipe_schema_not_found | recipe_image_required | recipe_ingredients_required | recipe_instructions_required`
- `502 upstream_fetch_failed`
- `504 upstream_timeout`

## 4) GET /recipes/sources
Текущие разрешённые источники и размер кэша.

Response `200`:
```json
{
  "sources": ["food.ru", "eda.ru", "allrecipes.com"],
  "cacheSize": 42,
  "persistentCacheSize": 128,
  "persistentCacheEnabled": true
}
```

## 5) POST /meal-plan/generate
Генерация плана питания на день/неделю (3 приёма пищи).

Request:
```json
{
  "days": 7,
  "ingredientKeywords": ["яйца", "молоко", "курица"],
  "expiringSoonKeywords": ["молоко"],
  "targets": {"kcal": 2200, "protein": 150, "fat": 70, "carbs": 220},
  "beveragesKcal": 120,
  "budget": {"perDay": 900},
  "exclude": ["кускус"],
  "avoidBones": true,
  "cuisine": ["русская"]
}
```

Response `200`:
```json
{
  "days": [
    {
      "date": "2026-02-12",
      "entries": [
        {"mealType": "breakfast", "score": 0.91, "kcal": 380, "estimatedCost": 180, "recipe": {"id": "r_omelet", "title": "Омлет с помидорами"}}
      ],
      "totals": {"kcal": 1260, "estimatedCost": 540},
      "targets": {"kcal": 2080, "perMealKcal": 693.33},
      "missingIngredients": ["помидоры"]
    }
  ],
  "shoppingList": ["помидоры"],
  "estimatedTotalCost": 3780,
  "warnings": ["Учтён калораж напитков: 120 ккал/день."]
}
```

Ошибки:
- `400 invalid_meal_plan_payload`

## 6) GET /barcode/lookup (optional)
Прокси-lookup для barcode провайдеров.

Query:
- `code` — ean/datamatrix/internal

Response:
```json
{
  "found": true,
  "product": {
    "barcode": "4601234567890",
    "name": "Молоко 2.5%",
    "brand": "Простоквашино",
    "category": "Молочные продукты"
  },
  "provider": "openfoodfacts"
}
```

## Политики безопасности
- `recipes/fetch` принимает только `http/https` URL.
- Блокируются `localhost`, loopback и private network диапазоны.
- Источник должен входить в whitelist доменов (`RECIPE_SOURCE_WHITELIST`).
- На endpoint действует in-memory rate limit (окно и лимит настраиваются env-переменными).
- Для recipe-кэша используется persistent SQLite (`RECIPE_CACHE_DB_PATH`) + TTL (`RECIPE_CACHE_TTL_SECONDS`).
