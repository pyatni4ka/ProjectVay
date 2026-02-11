# Backend API (MVP)

Base URL: `/api/v1`

## 1) GET /recipes/search
Поиск по индексу рецептов (из white-list источников).

Query params:
- `q` — строка поиска
- `timeMax` — максимум минут
- `budgetPerServing` — максимум ₽/порция
- `onlyInStock` — bool
- `exclude` — csv исключений

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
  "times": {"totalMinutes": 15}
}
```

## 4) GET /barcode/lookup (optional)
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
