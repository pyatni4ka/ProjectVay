# AUDIT_CURRENT_STATE

## Что уже есть сейчас (подтверждено в коде)

- Есть backend API для базовой и «умной» генерации плана питания:
  - `POST /api/v1/meal-plan/generate`, `POST /api/v1/meal-plan/smart-generate`, `POST /api/v1/meal-plan/smart-v2`, `POST /api/v1/meal-plan/optimize` в `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/routes/v1/recipes.ts`.
- Есть генератор плана на 1..7 дней с расчетом КБЖУ, стоимости и списка покупок:
  - логика в `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/services/mealPlan.ts`.
- Есть ранжирование рецептов и v2-рекомендации:
  - `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/services/recommendation.ts`.
- Есть объяснения «почему рекомендовано»:
  - `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/services/recommendationExplanation.ts`.
- Есть оценка цен ингредиентов и сравнение стоимости:
  - `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/services/priceEstimator.ts` и route `GET /prices/compare` в `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/routes/v1/recipes.ts`.
- Есть нормализация ингредиентов и замены:
  - `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/services/ingredientNormalizer.ts`, `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/services/ingredientSubstitutions.ts`.
- Есть индекс рецептов + внешние источники + кеш:
  - `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/services/recipeIndex.ts`, `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/services/externalRecipes.ts`, `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/services/persistentRecipeCache.ts`.
- Есть контрактные backend-типы с nutrition, diets, meal types и smart request:
  - `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/types/contracts.ts`.

- iOS уже использует SwiftUI + сервисы + локальное хранилище:
  - структура в `/Users/antonpyatnica/Downloads/ProjectVay/ios/App`, `/Users/antonpyatnica/Downloads/ProjectVay/ios/Features`, `/Users/antonpyatnica/Downloads/ProjectVay/ios/Services`, `/Users/antonpyatnica/Downloads/ProjectVay/ios/Persistence`.
- Есть экран плана питания с генерацией на день/неделю и fallback в offline:
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Features/MealPlan/MealPlanView.swift`.
- Есть сетевой клиент к backend для meal plan/recommend/price:
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Services/RecipeServiceClient.swift`.
- Есть Apple Health интеграция (чтение веса, body fat %, nutrition consumption и активности):
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Services/HealthKitService.swift`.
- Есть адаптация дневных таргетов по daily-метрикам и weekly smoothing:
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/UseCases/MacroRecommendationFilterUseCase.swift` (включая `AdaptiveNutritionUseCase`, `DietCoachUseCase`).
- Есть инвентарь, сканирование штрихкода, скан чеков, списание ингредиентов при готовке:
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Services/InventoryService.swift`,
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Features/Inventory/InventoryView.swift`,
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Features/ReceiptScan/ReceiptScanView.swift`,
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Features/Recipe/RecipeView.swift`.
- Есть уведомления про истекающие продукты + quiet hours:
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Services/NotificationScheduler.swift`.
- Есть настройки бюджета и профиля оптимизации:
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Features/Settings/DietSettingsView.swift`,
  - `/Users/antonpyatnica/Downloads/ProjectVay/ios/Persistence/Records/AppSettingsRecord.swift`.

## Что неясно (нужно отдельное углубление)

- Насколько стабильно/масштабно работает ingestion данных рецептов для продакшн-пула (сейчас в сиде мало рецептов):
  - проверить `/Users/antonpyatnica/Downloads/ProjectVay/backend/src/ingestion/runIngestion.ts`,
  - проверить фактический размер и качество данных в sqlite cache.
- Где будет храниться server-side `planId` для replace/adapt (сейчас API в основном stateless).
- Нужна ли запись nutrition обратно в Apple Health (в коде есть акцент на read, write-поток явно не найден):
  - углубить `/Users/antonpyatnica/Downloads/ProjectVay/ios/Services/HealthKitService.swift` и вызовы из use cases.
- Насколько текущие документы соответствуют коду: в `/Users/antonpyatnica/Downloads/ProjectVay/docs/ARCHITECTURE.md` есть ссылки на пути, которые уже отличаются от реальных.

## Gaps vs mission requirements (разрыв по 19 требованиям)

1. Low effort first — **частично есть** (есть генерация, fallback), но нет полного one-tap цикла replace/repeat/adapt.
2. Default 3 meals/day + настраиваемое число приемов — **частично**: сейчас по факту 3 слота фиксированы в `/backend/src/services/mealPlan.ts`.
3. Weekly targets + daily recalculation — **частично есть** на iOS через adaptive use cases, но не end-to-end в backend weekly autopilot.
4. Daily weight + body fat из Apple Health — **частично есть** (чтение метрик есть).
5. Все body metrics и nutrition consumption из Apple Health — **частично** (основа есть, но fallback/UX и contract-level связка не завершены).
6. Пер-meal targets — **частично** (внутренне считаются, но UX/API еще не оформлены как first-class).
7. Eat home / eat out / ate something else — **нет полного flow** (нет endpoint для adapt после deviation).
8. Cheat/break/surplus/deficit и мягкая адаптация — **нет полного flow**.
9. Cooking pattern daily или 3x/week + repeat meal-prep — **нет repeat-flow**.
10. Favorites/likes/dislikes — **частично** (есть user feedback/taste profile backend, но не полный продуктовый flow в iOS).
11. Allergies/diet constraints — **частично** (типы и фильтры есть, end-to-end UX недостаточный).
12. Не только КБЖУ (fiber/sugar/salt) — **частично в типах**, но в основном UX/алгоритм опирается на КБЖУ.
13. Домашний inventory + scan + manual search — **есть**.
14. Приоритет expiring soon + reminders — **частично** (логика expiring в ранжировании есть, reminders по истечению есть; приоритет/UX можно усилить).
15. Shopping list с количествами — **нет** (сейчас чаще список названий без агрегированных qty/unit).
16. Budget first (day/week/month, make cheaper) — **частично** (бюджет и оптимизатор есть; режима «make it cheaper» как one-tap нет).
17. No chat UI, Why? on demand — **частично** (объяснения есть в backend, но в iOS не оформлено как явный expandable “Почему?” для каждого meal).
18. UI: list of days, gentle notifications — **частично** (list of days есть; уведомления мягкие для expiry, shopping reminders еще нет).
19. Quick screen “What can I cook now from what I have?” — **нет выделенного экрана**.

## Риски

- Риск качества данных рецептов: `mockRecipes` маленький seed (`/Users/antonpyatnica/Downloads/ProjectVay/backend/src/data/mockRecipes.ts`), это снижает разнообразие и качество планов.
- Риск несогласованности контрактов iOS/backend при расширении API.
- Риск неточных цен при слабых ценовых подсказках (в коде уже есть fallback confidence, но UX нужно явно показывать).
- Риск «шумных» уведомлений при добавлении shopping reminders без тонкой настройки quiet hours.
- Риск drift между docs и кодом (часть архитектурной документации устарела).
- Риск нестабильных тестовых артефактов (`backend/data/ai-store.sqlite` меняется после тестов).

## Короткое резюме для фаундера

Сильная база уже есть: генерация плана, инвентарь, цены, Apple Health чтение и экран плана. Но сейчас не хватает именно «автопилота закрытого цикла»: быстрых замен в 1 тап, повторов meal-prep, адаптации после «съел не по плану», количеств в покупках и явного режима «сделай дешевле». Это и будет основной фокус MVP.
