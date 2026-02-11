# Архитектура проекта (после Этапа 1)

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
└── docs/
```

## 2) Локальные данные и приватность

Полный инвентарь хранится только локально (SQLite):
- `products`
- `batches`
- `price_entries`
- `inventory_events`
- `app_settings`

На сервер в Этапе 1 инвентарь не отправляется.

## 3) Схема БД и миграции

`v1_initial` создаёт таблицы:
- `products(id PK, barcode UNIQUE NULL, name, brand NULL, category, image_url NULL, local_image_path NULL, default_unit, nutrition_json, disliked, may_contain_bones, created_at, updated_at)`
- `batches(id PK, product_id FK, location, quantity, unit, expiry_date NULL, is_opened, created_at, updated_at)`
- `price_entries(id PK, product_id FK, store, price_minor, currency, date)`
- `inventory_events(id PK, type, product_id FK, batch_id NULL FK, quantity_delta, timestamp, note NULL)`
- `app_settings(id=1, quiet_start_minute, quiet_end_minute, expiry_alerts_days_json, budget_day_minor, budget_week_minor NULL, stores_json, disliked_list_json, avoid_bones, onboarding_completed)`

Индексы:
- `idx_products_barcode`
- `idx_batches_expiry_date`
- `idx_batches_location`
- `idx_price_entries_product_date`
- `idx_events_product_timestamp`

Политика: только forward migrations.

## 4) Потоки данных

### Онбординг
1. `OnboardingFlowView` запрашивает уведомления.
2. Пользователь настраивает quiet hours, шаблон дней, бюджет, магазины, дизлайки.
3. `SettingsService` сохраняет нормализованные настройки и флаг `onboarding_completed`.

### Инвентарь
1. `AddProductView` создаёт `Product` и первичную `Batch`.
2. `InventoryService` сохраняет данные через `InventoryRepository`.
3. `InventoryService` пишет `InventoryEvent`.
4. `NotificationScheduler` ставит уведомления для партий с `expiryDate`.

### Редактирование партии
1. `EditBatchView` меняет срок/количество/локацию.
2. `InventoryService.updateBatch` сохраняет изменения.
3. Старые уведомления отменяются, новые планируются заново.

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
- `UseCases` — сценарии UI (композиция сервисов).
- `Features` — SwiftUI экраны и пользовательские потоки.

## 7) Что остаётся следующими этапами

- production scanner pipeline (EAN/DataMatrix/internal);
- расширенный recipe ranking + план питания;
- полноценная интеграция HealthKit-графиков прогресса;
- backend интеграции рецептов на production-уровне.
