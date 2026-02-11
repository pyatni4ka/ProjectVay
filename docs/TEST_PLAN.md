# Тест-план (Этапы 1 + 2 hardening + базовый 3)

## 1) Unit (реализовано в `ios/Tests/InventoryCoreTests`)

### Database / Migrations
- Проверка создания таблиц: `products`, `batches`, `price_entries`, `inventory_events`, `app_settings`, `internal_code_mappings`.
- Проверка индексов: `idx_products_barcode`, `idx_batches_expiry_date`, `idx_batches_location`, `idx_price_entries_product_date`, `idx_events_product_timestamp`, `idx_internal_code_mappings_product`.
- Проверка seed default настроек.

### Repository
- CRUD товара и партии.
- Поиск по инвентарю (name/brand/barcode) + фильтр по локации.
- Сохранение цены и сортировка истории цен по убыванию даты.

### NotificationScheduler
- Перенос напоминаний при quiet hours (обычное окно).
- Перенос при quiet hours через полночь.
- Пропуск напоминаний, попавших в прошлое.

### Scanner / Lookup
- Парсинг EAN-13.
- Парсинг DataMatrix (извлечение GTIN и AI(17) при наличии).
- Парсинг internal code (best effort веса).
- `BarcodeLookupService`:
  - сначала берёт локальный товар;
  - при miss создаёт карточку из внешнего провайдера;
  - резолвит internal code через локальный mapping;
  - применяет negative cache на повторные not found;
  - применяет circuit breaker для нестабильного провайдера.

## 2) Integration (обязательные сценарии)

Автоматизировано unit+integration тестами в:
- `ios/Tests/InventoryCoreTests/InventoryServiceIntegrationTests.swift`
- `ios/Tests/InventoryCoreTests/BarcodeLookupServiceTests.swift`

- Добавление продукта с первичной партией создаёт:
  - `product` + `batch` в БД,
  - `inventory_event` типа `add`,
  - запланированные expiry-уведомления.
- Изменение `expiryDate` партии:
  - отменяет старые notification IDs,
  - создаёт новый набор актуальных уведомлений.
- Удаление партии:
  - удаляет запись,
  - удаляет pending/delivered уведомления.
- Завершение онбординга:
  - сохраняет настройки,
  - сохраняет `onboarding_completed = true`,
  - не показывает онбординг на следующем запуске.
- Скан EAN/DataMatrix:
  - найденный товар ведёт к быстрому добавлению партии;
  - DataMatrix пробрасывает suggested expiry в форму партии;
  - при отсутствии товара ручное создание сохраняет локальную карточку.
- Internal code:
  - после ручного создания товара выполняется bind internal code -> product;
  - следующий скан internal code открывает уже существующий товар.

## 3) UI сценарии (ручные)

### Онбординг
- Запрос уведомлений и корректный статус разрешения.
- Настройка quiet hours, шаблона 5/3/1, бюджета, магазинов, дизлайков.
- Переход в основное приложение после сохранения.

### Инвентарь
- Создание нового товара через `AddProductView`.
- Отображение партий отдельно в карточке товара.
- Редактирование и удаление партии через `EditBatchView`.
- Поиск по имени/бренду/штрихкоду и фильтр по зоне.
- Запуск live-сканера из toolbar и корректная обработка fallback-режима (ручной ввод кода).

### Настройки
- Изменение quiet hours и шаблона дней.
- Изменение бюджетов, дизлайков и магазинов.
- Сохранение и повторная загрузка актуальных значений.

## 4) Acceptance checklist (из ТЗ, покрытие Этапов 1/2)

- Ручное добавление товара и партии выполняется в пределах 3-4 действий.
- Скан EAN-13 добавляет товар с минимальными кликами (если карточка найдена).
- Если товар не найден, ручное создание делает его узнаваемым при повторном скане.
- Для DataMatrix используется GTIN, а срок (AI17) подставляется как suggested expiry.
- Уведомления 5/3/1 не приходят в quiet hours.
- Изменение/удаление партии корректно перепланирует уведомления.
- Инвентарь, история и настройки полностью локальные (privacy by default).

## 5) Команды проверки

```bash
cd /Users/antonpyatnica/Downloads/ProjectVay/ios
swift test
```

```bash
cd /Users/antonpyatnica/Downloads/ProjectVay/backend
npm test
npm run build
```

## 6) Backend Stage 3

### Unit
- `recipeScraper` корректно парсит schema.org JSON-LD (title/image/ingredients/instructions/video/nutrition/time/servings).
- `recipeScraper` возвращает ошибку для рецепта без image.
- `sourcePolicy` отклоняет небезопасные URL/хосты и проверяет whitelist.

### API/Integration
- `POST /recipes/fetch`:
  - отклоняет URL вне whitelist;
  - возвращает нормализованный recipe при валидном источнике;
  - возвращает код ошибки по типу scrape failure.
- `GET /recipes/search` ищет по индексу (включая ранее fetched рецепты).
- `GET /recipes/sources` возвращает активный whitelist и размер кэша.
- `POST /recipes/recommend` ранжирует текущий индекс (seed + fetched).
