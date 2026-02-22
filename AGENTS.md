# AGENTS.md — ProjectVay

> Единый источник правил для агентов (Claude, Copilot, человек).

---

## 1. Команды сборки, линтера и тестов

### iOS (Swift/SwiftUI)

```bash
# Сборка приложения
xcodebuild -project ios/InventoryAI.xcodeproj -scheme InventoryAI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Все тесты (схема InventoryAI)
xcodebuild -project ios/InventoryAI.xcodeproj -scheme InventoryAI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Тесты фреймворка InventoryCore
xcodebuild -project ios/InventoryAI.xcodeproj -scheme InventoryCore \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Одиночный тест (через xcodebuild -only-testing)
xcodebuild -project ios/InventoryAI.xcodeproj -scheme InventoryCore \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:InventoryCoreTests/NutritionCalculatorTests/testBMR_Male_80kg_180cm_30yo test
```

### Backend (TypeScript/Node.js)

```bash
# Разработка
cd backend && npm run dev

# Сборка
cd backend && npm run build

# Все тесты
cd backend && npm test

# Одиночный тест
cd backend && node --test --import tsx test/mealPlan.test.ts

# Тесты с отслеживанием изменений
cd backend && npm run test:watch

# Линтер
cd backend && npm run lint
```

---

## 2. Стиль кода iOS

### Архитектура
- **MVVM-light**: View + Service (без отдельных ViewModel-файлов)
- **Состояние**: `@State`, `@EnvironmentObject` через `AppSettingsStore`
- **База данных**: GRDB (`ios/Persistence/`)
- **Навигация**: `NavigationStack` + `sheet`

### Дизайн-система (КРИТИЧНО)
**ВСЕ стили ТОЛЬКО через `ios/Shared/DesignSystem.swift`:**

```swift
// ПРАВИЛЬНО:
.foregroundStyle(Color.vayPrimary)
.padding(VaySpacing.md)
.background(Color.vayCardBackground)
.font(VayFont.body())

// ЗАПРЕЩЕНО:
.foregroundStyle(Color.red)           // ❌
.padding(16)                          // ❌
.background(Color.white)              // ❌
```

**Токены:**
- Цвета: `Color.vayPrimary`, `.vayAccent`, `.vayWarning`, `.vayDanger`
- Макро: `.vayCalories`, `.vayProtein`, `.vayFat`, `.vayCarbs`
- Отступы: `VaySpacing.xs/sm/md/lg/xl`
- Радиусы: `VayRadius.sm/md/lg/xl`
- Шрифты: `VayFont.hero()`, `.title()`, `.body()`, `.caption()`

### Импорты
```swift
import SwiftUI
import GRDB
// Сторонние библиотеки после Foundation
```

### Именование
- Переменные/функции: `camelCase`
- Типы/struct/enum: `PascalCase`
- Секции: `// MARK: - Section Name`

---

## 3. Стиль кода Backend

### Структура
`routes → services → data`

### Импорты
```typescript
// Типы primero с ключевым словом type
import type { Recipe, Nutrition } from "../types/contracts.js";
// Затем обычные импорты
import { rankRecipes } from "./recommendation.js";
```

### Конвенции
- **Модули**: ESM с расширением `.js` в путях импорта
- **Валидация**: Zod (`zod`)
- **Логирование**: Pino (`pino`)
- **Тесты**: Native Node test runner (`node:test` + `node:assert/strict`)

---

## 4. Обработка ошибок

### iOS
- `nil` / `Optional` для восстанавливаемых ошибок
- `Result<T, Error>` для операций, которые могут fail
- Валидация входных данных с guards

### Backend
- `throw Error` для невосстанавливаемых сбоев
- `null` / `undefined` для отсутствующих данных
- Error middleware в Express

---

## 5. Именование

| Элемент | iOS | Backend |
|---------|-----|---------|
| Переменные | `camelCase` | `camelCase` |
| Типы | `PascalCase` | `PascalCase` |
| Файлы | `PascalCase.swift` | `camelCase.ts` |
| Константы | `lowerCamelCase` | `SCREAMING_SNAKE` |

---

## 6. Структура файлов

### iOS
```
ios/
├── App/           # Точка входа, DI, координация
├── Features/      # Экраны по фичам (Home, Inventory, MealPlan...)
├── Services/      # Бизнес-логика
├── Models/        # Доменные модели, DTOs
├── Persistence/   # GRDB, миграции, рекорды
├── Repositories/  # Слой доступа к данным
└── Shared/        # DesignSystem, компоненты
```

### Backend
```
backend/src/
├── routes/        # Express маршруты
├── services/      # Бизнес-логика
├── middleware/    # CORS, helmet, rate limit, error
├── config/        # env, источники рецептов
├── types/         # TypeScript контракты
├── utils/         # Утилиты (logger, normalize)
└── ingestion/     # Адаптеры внешних источников
```

---

## 7. Definition of Done

Перед завершением задачи:
- [ ] Сборка проходит (`xcodebuild build` или `npm run build`)
- [ ] Тесты проходят (`xcodebuild test` или `npm test`)
- [ ] Нет хардкода цветов/размеров в iOS (только DesignSystem)
- [ ] Нет крашей в ключевых флоу (Inventory, MealPlan, BodyMetrics)
- [ ] Тёмная тема проверена
- [ ] Accessibility: Dynamic Type, VoiceOver labels

---

## 8. Запрещённые паттерны

- **БЕЗ комментариев** в коде (если явно не запрошено)
- **БЕЗ хардкода** цветов и размеров в iOS
- **БЕЗ эмодзи** в коде и коммитах
- **БЕЗ секретов/credentials** в коде или коммитах
- **БЕЗ force push** в main/master
- **БЕЗ git commit --amend** если коммит уже отправлен в remote
