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
- локально для ручного теста в Xcode использовать `RECIPE_SERVICE_BASE_URL=http://127.0.0.1:8080` (симулятор) или `http://<LAN-IP-Mac>:8080` (физический iPhone).

## 3) Минимальные backend env для друзей
- `RECIPE_SOURCE_WHITELIST`
- `RECIPE_CACHE_DB_PATH`
- `EAN_DB_API_KEY` (опционально)
- `BARCODE_ENABLE_OPEN_FOOD_FACTS=true`
- `BARCODE_LOOKUP_RATE_MAX`, `BARCODE_LOOKUP_RATE_WINDOW_MS`

## 4) Подпись и сборка
1. Сгенерировать проект (если ещё не создан):
   - `cd /Users/antonpyatnica/Downloads/ProjectVay/ios`
   - `xcodegen generate`
2. Открыть `/Users/antonpyatnica/Downloads/ProjectVay/ios/InventoryAI.xcodeproj` и выбрать target `InventoryAI`.
3. Настроить `Signing & Capabilities`:
   - `HealthKit` (read),
   - Push/Notifications.
4. `Product -> Archive`.
5. Через Organizer:
   - `Distribute App -> TestFlight` (предпочтительно),
   - или `Distribute App -> Ad Hoc` и экспорт `.ipa`.

### CLI-путь (автоматизация)
1. Скопировать шаблон export options и заполнить `teamID`:
   - `cp /Users/antonpyatnica/Downloads/ProjectVay/ios/scripts/exportOptions.ad-hoc.plist.template /Users/antonpyatnica/Downloads/ProjectVay/ios/scripts/exportOptions.ad-hoc.plist`
2. Запустить сборку:
   - `cd /Users/antonpyatnica/Downloads/ProjectVay/ios`
   - `./scripts/build_ipa.sh`
3. Готовый `.ipa` появится в:
   - `/Users/antonpyatnica/Downloads/ProjectVay/ios/build/export`

## 5) Проверка перед раздачей
- Preflight backend:
  - `GET http://127.0.0.1:8080/health`
  - `GET http://127.0.0.1:8080/api/v1/recipes/search?q=сыр`
- Добавление товара/партии и уведомления 5/3/1 вне quiet hours.
- Списание через сканер в режиме `Списание`.
- Генерация рекомендаций/плана питания при подключенном backend.
- Подтягивание КБЖУ из Apple Health (данные из Yazio).
