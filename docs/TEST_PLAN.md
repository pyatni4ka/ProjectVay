# Тест-план (Этапы 1 + 2 hardening + расширенный 3)

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

### SettingsService
- Сохранение настроек триггерит перепланирование уведомлений только для партий с `expiryDate`.
- Флаг `onboarding_completed` корректно сохраняется и читается.
- Экспорт локальных данных создаёт валидный JSON snapshot (settings/products/batches/prices/events).
- `deleteAllLocalData` очищает инвентарь и сбрасывает onboarding/settings.

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
  - в режиме списания (`allowCreate = false`) не создаёт новые карточки товара.

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
- Быстрое списание партии через swipe-action в `InventoryView`.
- Быстрые действия в карточке товара: `Открыть/Закрыть` и `Списать` по партии.
- Добавление новой цены из `ProductDetailView` и обновление истории цен.
- Быстрое списание через сканер в режиме `Списание` (`Быстро −1`).
- Поиск по имени/бренду/штрихкоду и фильтр по зоне.
- Запуск live-сканера из toolbar и корректная обработка fallback-режима (ручной ввод кода).

### План питания
- Экран `План` запрашивает backend `meal-plan` и показывает 3 приёма пищи/день.
- Переключатель День/Неделя перестраивает payload и результат.
- Отображаются shopping list, предупреждения и оценка стоимости.
- Для режима `День` цель и меню адаптируются к уже съеденному КБЖУ из Apple Health (записи Yazio).
- Для режима `Неделя` используется базовая дневная цель без агрессивной коррекции.
- Отдельно отображаются рекомендации на следующий приём пищи по целевому КБЖУ.

### Настройки
- Изменение quiet hours и шаблона дней.
- Изменение бюджетов, дизлайков и магазинов.
- Изменение расписания приёмов пищи (завтрак/обед/ужин).
- Сохранение и повторная загрузка актуальных значений.
- После сохранения настроек обновляется расписание expiry-уведомлений по текущим партиям.
- Экспорт JSON и удаление локальных данных через UI.

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
- `PersistentRecipeCache` сохраняет/читает recipe и удаляет просроченные записи.
- `mealPlan` генерирует 3 приёма в день и корректно ограничивает диапазон дней (1..7).

### API/Integration
- `POST /recipes/fetch`:
  - отклоняет URL вне whitelist;
  - возвращает нормализованный recipe при валидном источнике;
  - возвращает код ошибки по типу scrape failure.
- `GET /recipes/search` ищет по индексу (включая ранее fetched рецепты).
- `GET /recipes/sources` возвращает активный whitelist и размер кэша.
- `POST /recipes/recommend` ранжирует текущий индекс (seed + fetched).
- `POST /meal-plan/generate` строит день/неделю, возвращает shopping list и estimate стоимости.
