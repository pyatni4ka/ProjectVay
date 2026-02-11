# Домашний Инвентарь + ИИ-Рецепты + План Питания

Монорепозиторий MVP для iPhone-приложения (SwiftUI) и backend-сервиса рецептов.

## Текущее состояние

Реализован **Этап 1 (Production MVP-инвентарь)**, усиленный **Этап 2 (scanner/lookup hardening)** и расширенный **Этап 3 (recipe backend parsing + cache + meal plan API)**:
- локальное хранилище `GRDB + SQLite` с миграциями;
- CRUD для `Product`, `Batch`, `PriceEntry`, `InventoryEvent`, `AppSettings`;
- рабочий онбординг и настройки (quiet hours, шаблон 5/3/1, бюджет, магазины, дизлайки);
- рабочий экран инвентаря, карточка товара, создание/редактирование партий;
- быстрые действия по партиям: списание из инвентаря, открыть/закрыть/списать в карточке товара;
- добавление цены по магазину прямо в карточке товара (последняя цена + история);
- планирование/отмена/перепланирование уведомлений сроков.
- автоматическое перепланирование уведомлений при изменении quiet hours/шаблона дней в настройках.
- live-сканер через `VisionKit DataScannerViewController` (EAN-13/DataMatrix/internal);
- lookup pipeline: локальная база -> провайдеры (`EAN-DB`, `RF proxy`, `Open Food Facts`) -> ручное создание;
- локальное маппирование внутренних кодов товара (`internal_code_mappings`) для повторных сканов.
- hardening lookup: `negative cache`, `circuit breaker` для провайдеров, retry/timeout/cooldown policy и безопасная валидация endpoint'ов.
- backend `/recipes/fetch`: парсинг schema.org JSON-LD, whitelist доменов источников, кэш и индексация рецептов для `/recipes/search`.
- backend persistent cache рецептов на SQLite (`node:sqlite`) + endpoint `/meal-plan/generate` (день/неделя, 3 приёма, shopping list, cost estimate).
- сканер поддерживает отдельный режим `Списание` (быстрый сценарий `Быстро −1` по штрихкоду);
- адаптивное меню по Apple Health (включая КБЖУ из Yazio): таргет на следующий приём пищи пересчитывается по уже съеденному;
- в `Настройки` добавлены:
  - экспорт локальных данных в JSON;
  - удаление локальных данных (инвентарь/цены/история) со сбросом настроек;
- экран `Прогресс` показывает текущие метрики HealthKit и тренды веса/жира за 30 дней.

## Структура

- `ios/` — iOS-приложение (SwiftUI + локальная БД + сервисы).
- `backend/` — Node.js/TypeScript API для рецептов (search/recommend/fetch/sources/meal-plan + whitelist + memory+SQLite cache).
- `docs/` — архитектура, API-спека, ранжирование, тест-план, заметки по дистрибуции IPA (`docs/IPA_DISTRIBUTION.md`).

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
- iOS `План` подключён к backend `meal-plan` endpoint и учитывает КБЖУ для следующего приёма;
- backend не получает полный инвентарь и не блокирует работу локального MVP.
