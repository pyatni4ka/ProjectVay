# Домашний Инвентарь + ИИ-Рецепты + План Питания

Монорепозиторий MVP для iPhone-приложения (SwiftUI) и backend-сервиса рецептов.

## Текущее состояние

Реализован **Этап 1 (Production MVP-инвентарь)**, усиленный **Этап 2 (scanner/lookup hardening)** и базовый **Этап 3 (recipe backend parsing + cache)**:
- локальное хранилище `GRDB + SQLite` с миграциями;
- CRUD для `Product`, `Batch`, `PriceEntry`, `InventoryEvent`, `AppSettings`;
- рабочий онбординг и настройки (quiet hours, шаблон 5/3/1, бюджет, магазины, дизлайки);
- рабочий экран инвентаря, карточка товара, создание/редактирование партий;
- планирование/отмена/перепланирование уведомлений сроков.
- live-сканер через `VisionKit DataScannerViewController` (EAN-13/DataMatrix/internal);
- lookup pipeline: локальная база -> провайдеры (`EAN-DB`, `RF proxy`, `Open Food Facts`) -> ручное создание;
- локальное маппирование внутренних кодов товара (`internal_code_mappings`) для повторных сканов.
- hardening lookup: `negative cache`, `circuit breaker` для провайдеров, retry/timeout/cooldown policy и безопасная валидация endpoint'ов.
- backend `/recipes/fetch`: парсинг schema.org JSON-LD, whitelist доменов источников, кэш и индексация рецептов для `/recipes/search`.

## Структура

- `ios/` — iOS-приложение (SwiftUI + локальная БД + сервисы).
- `backend/` — Node.js/TypeScript API для рецептов (search/recommend/fetch + whitelist + cache).
- `docs/` — архитектура, API-спека, ранжирование, тест-план.

## Локальная проверка iOS-ядра

В `ios/` добавлен `Swift Package` для тестов доменной/инфраструктурной логики.

```bash
cd /Users/antonpyatnica/Downloads/ProjectVay/ios
swift test
```

## Локальная проверка backend

```bash
cd /Users/antonpyatnica/Downloads/ProjectVay/backend
npm install
npm test
npm run build
```

## Ограничения текущего этапа

- `EAN-DB` и RF-провайдер подключены как опциональные (нужны реальные ключи/endpoint);
- whitelist источников рецептов нужно актуализировать под production-домены;
- генерация meal-plan и HealthKit-графики остаются следующими этапами;
- backend не получает полный инвентарь и не блокирует работу локального MVP.
