# Дистрибуция IPA (друзьям)

## 1) Рекомендуемый путь
1. Использовать `TestFlight` (самый стабильный сценарий для iPhone и обновлений).
2. Альтернатива: `Ad Hoc` через `.ipa` + UDID устройств (более трудоёмко).

## 2) Конфигурация приложения перед сборкой
Параметры задаются через `Info.plist`/environment (`ios/App/AppConfig.swift`):
- `RecipeServiceBaseURL` / `RECIPE_SERVICE_BASE_URL`
- `BarcodeProxyBaseURL` / `RF_LOOKUP_BASE_URL`
- `EnableEANDBLookup`, `EnableRFLookup`, `EnableOpenFoodFactsLookup`
- `EANDBApiKey` / `EAN_DB_API_KEY`

Рекомендации:
- для production указывать только `https` URL backend;
- ключи внешних API держать на backend, не в клиенте.

## 3) Минимальные backend env для друзей
- `RECIPE_SOURCE_WHITELIST`
- `RECIPE_CACHE_DB_PATH`
- `EAN_DB_API_KEY` (опционально)
- `BARCODE_ENABLE_OPEN_FOOD_FACTS=true`
- `BARCODE_LOOKUP_RATE_MAX`, `BARCODE_LOOKUP_RATE_WINDOW_MS`

## 4) Подпись и сборка
1. В Xcode выбрать target `InventoryAI`.
2. Настроить `Signing & Capabilities`:
   - `HealthKit` (read),
   - Push/Notifications.
3. `Product -> Archive`.
4. Через Organizer:
   - `Distribute App -> TestFlight` (предпочтительно),
   - или `Distribute App -> Ad Hoc` и экспорт `.ipa`.

## 5) Проверка перед раздачей
- Добавление товара/партии и уведомления 5/3/1 вне quiet hours.
- Списание через сканер в режиме `Списание`.
- Генерация рекомендаций/плана питания при подключенном backend.
- Подтягивание КБЖУ из Apple Health (данные из Yazio).
