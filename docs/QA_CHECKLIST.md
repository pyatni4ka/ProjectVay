# QA_CHECKLIST

## Core flow

- [ ] Generate week создает 7 дней с корректными meal slots.
- [ ] По умолчанию 3 meals/day.
- [ ] Смена на 2..6 meals/day корректно меняет таргеты и план.

## Replace / Repeat

- [ ] Replace показывает 3–7 вариантов.
- [ ] Сортировки `cheap/fast/protein/expiry` меняют порядок ожидаемо.
- [ ] После Replace обновляются shopping list и budget projection.
- [ ] Repeat на завтра работает.
- [ ] Repeat на N дней обновляет количества покупок и недельную стоимость.

## Deviation flow

- [ ] “Ate out / cheated / different meal” запускает адаптацию remaining плана.
- [ ] Прошедшие дни не меняются.
- [ ] Тон сообщений мягкий, без давления.

## Shopping / Budget

- [ ] Shopping list показывает quantity + unit.
- [ ] `Already have` исключает/уменьшает позицию в покупках.
- [ ] Strict budget не дает превышение.
- [ ] Soft budget допускает до 5%.
- [ ] Кнопка “Make it cheaper” снижает стоимость с минимальными изменениями меню.

## Inventory / Expiry

- [ ] Expiring items реально поднимаются в приоритете рекомендаций.
- [ ] После готовки инвентарь корректно списывается.

## Apple Health

- [ ] Case granted: метрики подтягиваются, last sync отображается.
- [ ] Case denied: предлагается ручной ввод, генерация не блокируется.
- [ ] Case no data: fallback на ручной ввод + предупреждение.
- [ ] Case stale data: показывается статус, пересчет делает best effort.

## Reliability

- [ ] Offline режим не падает.
- [ ] Ошибки API показываются понятным текстом.
- [ ] Одинаковый input + seed дает стабильный output.
