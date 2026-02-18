# ROADMAP_6_WEEKS

## Week 1–2: MVP weekly plan + replace + shopping quantities

### Engineering tasks

- Backend: добавить/расширить weekly endpoint (`/meal-plan/week`) с `mealTargets`, `dayTargets`, `shoppingListWithQuantities`, `cost projections`.
- Backend: добавить `POST /meal-plan/replace`.
- Backend: добавить `POST /meal-plan/adapt` (минимальная версия для remaining plan).
- Backend: стабилизировать детерминизм (seed + стабильные сортировки).
- Backend: обновить контракты и тесты.
- Docs: `API_EXAMPLES.md`.

### Verification

- `npm test` в backend проходит.
- 10 запусков с одинаковым seed дают одинаковый результат.
- Ручная проверка: replace меняет meal и обновляет shopping/cost.

## Week 3–4: cheat/eat-out adapt + budget strictness + quick cook-now

### Engineering tasks

- iOS: действия Replace / Repeat / Why? в day detail.
- iOS: действие “Я съел другое” (ate out/cheat/different meal).
- iOS: shopping screen с qty и `already have`.
- Backend: усилить adapt (day/week scope, disruption score).
- Backend + iOS: strict/soft budget (soft default 5%).
- iOS: быстрый экран “Cook now”.

### Verification

- `swift test` проходит.
- Smoke flow: generate → replace → repeat → deviation → budget delta.
- На экране budget видны day/week/month и strictness.

## Week 5–6: notifications + deeper constraints + better explanations

### Engineering tasks

- Уведомления: shopping reminders + expiring (gentle, quiet hours, category toggles).
- Доработать ограничения: аллергии, диеты, dislikes/favorites end-to-end.
- Улучшить блок “Почему?” для каждого meal/action.
- Укрепить data quality: единицы, нормализация RU/EN, confidence.
- Подготовить QA и release docs.

### Verification

- Чеклист регрессии закрыт.
- Критичные сценарии без крашей в offline и при denied Health permissions.
- Release notes готовы для фаундера.
