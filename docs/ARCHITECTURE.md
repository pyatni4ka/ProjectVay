# Архитектура проекта

## 1) Структура модулей

```text
ProjectVay/
├── ios/
│   ├── App/
│   │   ├── InventoryAIApp.swift
│   │   ├── AppCoordinator.swift
│   │   └── RootTabView.swift
│   ├── Models/
│   │   ├── DomainModels.swift
│   │   └── DTOs.swift
│   ├── Services/
│   │   ├── HealthKitService.swift
│   │   ├── ScannerService.swift
│   │   ├── InventoryService.swift
│   │   ├── RecipeServiceClient.swift
│   │   └── NotificationScheduler.swift
│   ├── Features/
│   │   ├── Onboarding/
│   │   ├── Home/
│   │   ├── Recipe/
│   │   ├── Inventory/
│   │   ├── MealPlan/
│   │   ├── Progress/
│   │   ├── Settings/
│   │   └── Scanner/
│   └── Shared/
│       └── Theme.swift
├── backend/
│   ├── src/
│   │   ├── api/routes.ts
│   │   ├── services/recipeScraper.ts
│   │   ├── services/recommendation.ts
│   │   ├── services/cacheStore.ts
│   │   ├── utils/normalize.ts
│   │   ├── types/contracts.ts
│   │   └── server.ts
│   └── test/recommendation.test.ts
└── docs/
    ├── ARCHITECTURE.md
    ├── API_SPEC.md
    ├── RANKING.md
    └── TEST_PLAN.md
```

## 2) Локальные данные (privacy by default)

На устройстве хранится полный инвентарь:
- `Product`
- `Batch`
- `PriceEntry`
- `InventoryEvent`
- `Settings`
- `MealPlanDay`
- `MealEntry`
- Локальный кэш barcode lookup

На сервер отправляется только минимум:
- ключевые слова ингредиентов
- агрегированные ограничения (ккал/макросы/бюджет)
- исключения (дизлайки, флаг костей)

## 3) Потоки данных

### Сканирование
1. `ScannerService` распознаёт EAN-13/DataMatrix/internal code.
2. `InventoryService.lookupProduct(code)` проверяет локальный кэш.
3. При miss — `RecipeServiceClient`/barcode proxy (если включено).
4. Пользователь подтверждает карточку и сохраняет партию.
5. `NotificationScheduler` планирует 5/3/1 уведомления.

### Рецепты
1. Главный экран отправляет агрегированный запрос в `/recipes/recommend`.
2. Backend ранжирует кандидатов и возвращает карточки.
3. Экран рецепта показывает источник + видео + шаги.
4. Недостающие ингредиенты добавляются в shopping list.

### Питание и прогресс
1. `HealthKitService` читает вес/состав/activeEnergy.
2. `InventoryService` + `RecipeServiceClient` генерируют план на день/неделю.
3. Дневной `calorie target` корректируется мягко (ограничение шага корректировки).

## 4) UX-принципы

- Русский интерфейс по умолчанию.
- Минимум кликов при добавлении товара.
- Деструктивные действия требуют подтверждения.
- Тихие часы учитываются во всех автоматических уведомлениях.
- На карточке рецепта всегда виден источник и ссылка.
