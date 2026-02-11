# Архитектура проекта (после Этапов 1 + 2 hardening + расширенного 3)

## 1) Структура модулей

```text
ProjectVay/
├── ios/
│   ├── Package.swift
│   ├── App/
│   │   ├── InventoryAIApp.swift
│   │   ├── AppCoordinator.swift
│   │   ├── AppDependencies.swift
│   │   └── RootTabView.swift
│   ├── Models/
│   │   ├── DomainModels.swift
│   │   └── DTOs.swift
│   ├── Persistence/
│   │   ├── Database.swift
│   │   ├── Migrations.swift
│   │   └── Records/
│   ├── Repositories/
│   │   ├── InventoryRepository.swift
│   │   └── SettingsRepository.swift
│   ├── Services/
│   │   ├── InventoryService.swift
│   │   ├── SettingsService.swift
│   │   ├── NotificationScheduler.swift
│   │   ├── BarcodeLookupService.swift
│   │   ├── BarcodeLookupProviders.swift
│   │   ├── HealthKitService.swift
│   │   ├── ScannerService.swift
│   │   └── RecipeServiceClient.swift
│   ├── UseCases/
│   │   └── InventoryUseCases.swift
│   ├── Features/
│   │   ├── Onboarding/OnboardingFlowView.swift
│   │   ├── Inventory/{InventoryView,ProductDetailView,EditBatchView,AddProductView}.swift
│   │   ├── Home/HomeView.swift
│   │   ├── Settings/SettingsView.swift
│   │   ├── MealPlan/MealPlanView.swift
│   │   ├── Progress/ProgressView.swift
│   │   ├── Recipe/RecipeView.swift
│   │   └── Scanner/ScannerView.swift
│   └── Shared/
├── backend/
│   ├── src/
│   │   ├── api/routes.ts
│   │   ├── config/recipeSources.ts
│   │   ├── services/{recipeScraper,recipeIndex,sourcePolicy,cacheStore,persistentRecipeCache,recommendation,mealPlan}.ts
│   │   └── types/contracts.ts
│   └── test/
└── docs/
```

## 2) Локальные данные и приватность

Полный инвентарь хранится только локально (SQLite):
- `products`
- `batches`
- `price_entries`
- `inventory_events`
- `app_settings`
- `internal_code_mappings`

На сервер отправляются только barcode-запросы lookup (без полного инвентаря и партий).

## 3) Схема БД и миграции

`v1_initial` создаёт таблицы:
- `products(id PK, barcode UNIQUE NULL, name, brand NULL, category, image_url NULL, local_image_path NULL, default_unit, nutrition_json, disliked, may_contain_bones, created_at, updated_at)`
- `batches(id PK, product_id FK, location, quantity, unit, expiry_date NULL, is_opened, created_at, updated_at)`
- `price_entries(id PK, product_id FK, store, price_minor, currency, date)`
- `inventory_events(id PK, type, product_id FK, batch_id NULL FK, quantity_delta, timestamp, note NULL)`
- `app_settings(id=1, quiet_start_minute, quiet_end_minute, expiry_alerts_days_json, budget_day_minor, budget_week_minor NULL, stores_json, disliked_list_json, avoid_bones, onboarding_completed)`

`v2_internal_code_mappings` создаёт:
- `internal_code_mappings(code PK, product_id FK, parsed_weight_grams NULL, created_at)`

Индексы:
- `idx_products_barcode`
- `idx_batches_expiry_date`
- `idx_batches_location`
- `idx_price_entries_product_date`
- `idx_events_product_timestamp`
- `idx_internal_code_mappings_product`

Политика: только forward migrations.

## 4) Потоки данных

### Онбординг
1. `OnboardingFlowView` запрашивает уведомления.
2. Пользователь настраивает quiet hours, шаблон дней, бюджет, магазины, дизлайки и расписание приёмов пищи.
3. `SettingsService` сохраняет нормализованные настройки и флаг `onboarding_completed`.
4. После сохранения настроек `SettingsService` автоматически перепланирует expiry-уведомления для всех актуальных партий с датой срока.
5. В `SettingsView` доступны экспорт локального snapshot в JSON и полная очистка локальных данных.

### Инвентарь
1. `AddProductView` создаёт `Product` и первичную `Batch`.
2. `InventoryService` сохраняет данные через `InventoryRepository`.
3. `InventoryService` пишет `InventoryEvent`.
4. `NotificationScheduler` ставит уведомления для партий с `expiryDate`.
5. `InventoryView` поддерживает быстрый swipe-action `Списать` по партии.
6. `ProductDetailView` поддерживает:
   - swipe-actions по партиям (`Открыть/Закрыть`, `Списать`);
   - добавление цены по магазину с немедленным обновлением истории.

### Редактирование партии
1. `EditBatchView` меняет срок/количество/локацию.
2. `InventoryService.updateBatch` сохраняет изменения.
3. Старые уведомления отменяются, новые планируются заново.

### Сканирование и lookup pipeline
1. `ScannerView` читает live-баркоды через `DataScannerViewController`.
2. `ScannerService` классифицирует payload: EAN-13 / DataMatrix / internal.
3. `ScannerView` поддерживает режимы:
   - `Добавление` (lookup + при необходимости создание карточки),
   - `Списание` (только существующий локальный инвентарь, без автосоздания).
4. `BarcodeLookupService` применяет pipeline:
   - нормализует GTIN из DataMatrix (`14 -> 13`, если префикс `0`) для совместимости с EAN-13;
   - локальный поиск (`InventoryService.findProduct`)
   - внешние провайдеры (`EAN-DB`, `RF`, `Open Food Facts`)
   - fallback на ручное создание
5. Для internal code после ручного подтверждения сохраняется `internal_code_mappings`, и последующие сканы резолвятся локально, включая fallback веса из сохранённого mapping.
6. В режиме списания доступен быстрый сценарий `Быстро −1`:
   - выбор подходящей партии по товару и единице измерения;
   - уменьшение количества или удаление партии при исчерпании.
7. Hardening:
   - negative cache по barcode для повторных miss;
   - circuit breaker по провайдерам (threshold/cooldown);
   - retry + timeout + межзапросный cooldown;
   - безопасная валидация RF endpoint (по умолчанию только `https`).

### Backend recipes (Stage 3)
1. `POST /api/v1/recipes/fetch`:
   - валидирует URL источника и применяет whitelist доменов;
   - применяет rate limiting;
   - берёт recipe из кэша или скачивает HTML и парсит JSON-LD schema.org;
   - отклоняет рецепт без изображения/ингредиентов/шагов.
2. Кэш:
   - L1: `CacheStore` (in-memory TTL + ограничение размера);
   - L2: `PersistentRecipeCache` (SQLite через `node:sqlite`, TTL и bootstrap индекса после рестарта).
3. Успешно распарсенный рецепт индексируется в `RecipeIndex`.
4. `GET /api/v1/recipes/search` ищет по объединённому индексу (seed + fetched).
5. `POST /api/v1/recipes/recommend` ранжирует текущий индекс.
6. `POST /api/v1/meal-plan/generate` строит план на 1..7 дней:
   - 3 приёма пищи/день (завтрак/обед/ужин),
   - учитывает цели, бюджет, исключения, expiring/in-stock сигналы,
   - возвращает shopping list и ориентировочную стоимость.

### iOS meal plan flow
1. `MealPlanView` собирает данные из локального инвентаря и настроек (`budget/disliked/avoidBones`).
2. Подтягивает КБЖУ из Apple Health (`dietaryEnergyConsumed`, `dietaryProtein`, `dietaryFatTotal`, `dietaryCarbohydrates`), куда данные попадают из Yazio.
3. Вычисляет адаптивные цели:
   - для режима `День` таргет на план считается из остатка КБЖУ после уже съеденного;
   - для режима `Неделя` используется базовый дневной таргет;
   - таргет на следующий приём рассчитывается по `mealSchedule` и числу оставшихся приёмов.
4. Формирует payload для `/api/v1/meal-plan/generate`:
   - список доступных ингредиентов,
   - список expiring-ингредиентов,
   - цель по КБЖУ и бюджет.
5. Дополнительно запрашивает `/api/v1/recipes/recommend` для следующего приёма пищи с таргетом КБЖУ.
6. Отображает план по дням, missing ingredients, shopping list, estimated total cost, warnings и рекомендации на следующий приём.

### Recipe cook flow
1. На экране рецепта кнопка `Готовлю` запускает `BuildRecipeWriteOffPlanUseCase`.
2. Use case сопоставляет ингредиенты с локальными товарами, выбирает партии с приоритетом ближайшего срока и рассчитывает объём списания.
3. После подтверждения `ApplyRecipeWriteOffUseCase` уменьшает количество партий или удаляет исчерпанные партии.
4. Изменения проходят через `InventoryService.updateBatch/removeBatch`, поэтому сохраняются события и корректно перепланируются уведомления.

## 5) Уведомления сроков (quiet hours)

Правила:
- шаблон дней берётся из `AppSettings.expiryAlertsDays`;
- дни нормализуются в диапазон `1...30`, уникальные и отсортированные;
- если рассчитанная дата в quiet hours, перенос на ближайшее разрешённое время;
- поддерживается окно quiet hours через полночь;
- даты в прошлом пропускаются;
- для истечения «сегодня» выбирается ближайшее допустимое время текущего дня.

Идентификатор уведомления: `expiry.<batch_id>.<days_before>`.

## 6) Разделение ответственности

- `Persistence` — инфраструктура SQLite/GRDB и миграции.
- `Repositories` — доступ к данным и SQL-операции.
- `Services` — бизнес-операции, правила, уведомления.
  `NotificationScheduler` реализует `NotificationScheduling` для тестируемой интеграции `InventoryService`.
- `UseCases` — сценарии UI (композиция сервисов).
- `Features` — SwiftUI экраны и пользовательские потоки.

## 7) Что остаётся следующими этапами

- калибровка lookup-провайдеров на реальных ключах/API-квотах;
- автогенерация списка покупок из фактического meal-flow;
- полноценная интеграция HealthKit-графиков прогресса;
- миграция backend-кэша на Postgres при необходимости scale-out.
