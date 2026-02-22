import type { Recipe } from "../types/contracts.js";

export const mockRecipes: Recipe[] = [
  // ── ЗАВТРАКИ ────────────────────────────────────────────────────────────
  {
    id: "mock:omelet-tomato",
    title: "Омлет с помидорами и зеленью",
    imageURL: "https://images.example/omelet.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/omelet",
    ingredients: ["яйца 3 шт", "молоко 50 мл", "помидор 1 шт", "сливочное масло 15 г", "зелень", "соль, перец"],
    instructions: [
      "Взбить яйца с молоком, посолить и поперчить.",
      "Разогреть масло на сковороде на среднем огне.",
      "Влить яичную смесь, готовить 2 минуты под крышкой.",
      "Добавить нарезанный помидор и зелень, сложить пополам."
    ],
    times: { totalMinutes: 10 },
    servings: 1,
    nutrition: { kcal: 380, protein: 22, fat: 24, carbs: 12 },
    estimatedCost: 80,
    tags: ["завтрак", "яйца", "быстро"],
    mealTypes: ["breakfast"],
    cuisine: "домашняя"
  },
  {
    id: "mock:oatmeal",
    title: "Овсяная каша с яблоком и корицей",
    imageURL: "https://images.example/oatmeal.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/oatmeal",
    ingredients: ["овсяные хлопья 80 г", "молоко 250 мл", "яблоко 1 шт", "мёд 1 ч.л.", "корица 0.5 ч.л."],
    instructions: [
      "Довести молоко до кипения, всыпать хлопья.",
      "Варить 5 минут, помешивая.",
      "Добавить нарезанное яблоко, корицу. Снять с огня.",
      "Заправить мёдом и подавать."
    ],
    times: { totalMinutes: 10 },
    servings: 1,
    nutrition: { kcal: 380, protein: 12, fat: 8, carbs: 64 },
    estimatedCost: 60,
    tags: ["завтрак", "каша", "вегетарианское"],
    mealTypes: ["breakfast"],
    cuisine: "домашняя"
  },
  {
    id: "mock:buckwheat-porridge",
    title: "Гречневая каша с маслом",
    imageURL: "https://images.example/buckwheat.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/buckwheat",
    ingredients: ["гречневая крупа 100 г", "вода 250 мл", "сливочное масло 15 г", "соль"],
    instructions: [
      "Промыть гречку, залить водой, посолить.",
      "Довести до кипения, убавить огонь.",
      "Варить под крышкой 15 минут до поглощения воды.",
      "Добавить масло, накрыть и дать настояться 5 минут."
    ],
    times: { totalMinutes: 20 },
    servings: 2,
    nutrition: { kcal: 320, protein: 10, fat: 9, carbs: 52 },
    estimatedCost: 40,
    tags: ["завтрак", "каша", "вегетарианское"],
    mealTypes: ["breakfast"],
    cuisine: "русская"
  },
  {
    id: "mock:scrambled-eggs-bacon",
    title: "Яичница с беконом",
    imageURL: "https://images.example/eggs-bacon.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/eggs-bacon",
    ingredients: ["яйца 3 шт", "бекон 80 г", "растительное масло", "соль, перец", "зелень лука"],
    instructions: [
      "Обжарить бекон на сухой сковороде до хрустящего состояния, вынуть.",
      "На том же масле разбить яйца, жарить 3 минуты.",
      "Подавать с беконом и зелёным луком."
    ],
    times: { totalMinutes: 10 },
    servings: 1,
    nutrition: { kcal: 480, protein: 30, fat: 38, carbs: 2 },
    estimatedCost: 130,
    tags: ["завтрак", "яйца", "мясной", "быстро"],
    mealTypes: ["breakfast"],
    cuisine: "домашняя"
  },
  {
    id: "mock:blini",
    title: "Блины классические",
    imageURL: "https://images.example/blini.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/blini",
    ingredients: ["мука 200 г", "яйца 2 шт", "молоко 500 мл", "масло растительное 2 ст.л.", "сахар 1 ст.л.", "соль"],
    instructions: [
      "Взбить яйца с сахаром и солью, влить молоко, перемешать.",
      "Всыпать муку, замесить однородное тесто без комков.",
      "Добавить растительное масло.",
      "Жарить на разогретой сковороде по 1–2 минуты с каждой стороны."
    ],
    times: { totalMinutes: 30 },
    servings: 4,
    nutrition: { kcal: 340, protein: 10, fat: 10, carbs: 54 },
    estimatedCost: 70,
    tags: ["завтрак", "выпечка", "классика"],
    mealTypes: ["breakfast"],
    cuisine: "русская"
  },
  {
    id: "mock:yogurt-granola",
    title: "Йогурт с гранолой и ягодами",
    imageURL: "https://images.example/yogurt-granola.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/yogurt-granola",
    ingredients: ["греческий йогурт 150 г", "гранола 40 г", "ягоды свежие 80 г", "мёд 1 ч.л."],
    instructions: [
      "Выложить йогурт в миску.",
      "Добавить гранолу и ягоды.",
      "Полить мёдом и подавать."
    ],
    times: { totalMinutes: 5 },
    servings: 1,
    nutrition: { kcal: 360, protein: 18, fat: 10, carbs: 50 },
    estimatedCost: 120,
    tags: ["завтрак", "быстро", "без готовки"],
    mealTypes: ["breakfast"],
    cuisine: "домашняя"
  },
  {
    id: "mock:avocado-toast",
    title: "Тост с авокадо и яйцом пашот",
    imageURL: "https://images.example/avocado-toast.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/avocado-toast",
    ingredients: ["хлеб тостовый 2 ломтика", "авокадо 1 шт", "яйца 2 шт", "лимонный сок 1 ч.л.", "соль, перец", "красный перец хлопьями"],
    instructions: [
      "Размять авокадо с лимонным соком, солью и перцем.",
      "Поджарить хлеб в тостере.",
      "Приготовить яйцо пашот: варить в воде с уксусом 3–4 минуты.",
      "Выложить авокадо на тост, сверху яйцо пашот, посыпать хлопьями."
    ],
    times: { totalMinutes: 15 },
    servings: 1,
    nutrition: { kcal: 420, protein: 16, fat: 26, carbs: 36 },
    estimatedCost: 150,
    tags: ["завтрак", "авокадо", "трендовое"],
    mealTypes: ["breakfast"],
    cuisine: "домашняя"
  },
  {
    id: "mock:kefir-pancakes",
    title: "Оладьи на кефире",
    imageURL: "https://images.example/oladyi.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/oladyi",
    ingredients: ["кефир 250 мл", "мука 200 г", "яйцо 1 шт", "сахар 2 ст.л.", "сода 0.5 ч.л.", "соль", "масло 3 ст.л."],
    instructions: [
      "Смешать кефир, яйцо, сахар и соль.",
      "Добавить соду и дождаться реакции.",
      "Всыпать муку, перемешать до густой сметаны.",
      "Жарить на масле по 2–3 минуты с каждой стороны."
    ],
    times: { totalMinutes: 25 },
    servings: 3,
    nutrition: { kcal: 390, protein: 11, fat: 12, carbs: 60 },
    estimatedCost: 85,
    tags: ["завтрак", "выпечка", "вегетарианское"],
    mealTypes: ["breakfast"],
    cuisine: "русская"
  },
  // ── ОБЕДЫ ───────────────────────────────────────────────────────────────
  {
    id: "mock:borsch",
    title: "Борщ со свининой",
    imageURL: "https://images.example/borsch.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/borsch",
    ingredients: ["свинина 500 г", "свёкла 2 шт", "капуста 300 г", "картофель 3 шт", "морковь 1 шт", "лук 1 шт", "томатная паста 2 ст.л.", "чеснок 3 зуб.", "сметана"],
    instructions: [
      "Сварить свинину, снять пену. Мясо вынуть, бульон процедить.",
      "Натереть свёклу и морковь, пассеровать с луком и томатной пастой 10 минут.",
      "В бульон добавить картофель, варить 10 минут.",
      "Добавить капусту и зажарку, варить 10 минут. Добавить чеснок, дать настояться."
    ],
    times: { totalMinutes: 90 },
    servings: 6,
    nutrition: { kcal: 280, protein: 18, fat: 14, carbs: 22 },
    estimatedCost: 280,
    tags: ["обед", "суп", "мясной"],
    mealTypes: ["lunch"],
    cuisine: "русская"
  },
  {
    id: "mock:chicken-soup",
    title: "Куриный суп с лапшой",
    imageURL: "https://images.example/chicken-soup.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/chicken-soup",
    ingredients: ["куриные бёдра 600 г", "лапша 100 г", "морковь 1 шт", "лук 1 шт", "картофель 2 шт", "лавровый лист", "петрушка", "соль, перец"],
    instructions: [
      "Варить курицу 30 минут, снять пену. Вынуть и отделить мясо от костей.",
      "Процедить бульон, вернуть мясо.",
      "Добавить картофель и морковь, варить 15 минут.",
      "Добавить лук и лапшу, варить 8 минут. Посыпать петрушкой."
    ],
    times: { totalMinutes: 60 },
    servings: 5,
    nutrition: { kcal: 240, protein: 22, fat: 8, carbs: 20 },
    estimatedCost: 220,
    tags: ["обед", "суп", "курица"],
    mealTypes: ["lunch"],
    cuisine: "домашняя"
  },
  {
    id: "mock:caesar-salad",
    title: "Салат Цезарь с курицей",
    imageURL: "https://images.example/caesar.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/caesar",
    ingredients: ["куриное филе 300 г", "салат романо 1 кочан", "пармезан 50 г", "гренки 80 г", "майонез 3 ст.л.", "лимонный сок 1 ст.л.", "горчица 1 ч.л."],
    instructions: [
      "Обжарить куриное филе, нарезать ломтиками.",
      "Разорвать листья романо, выложить на тарелку.",
      "Смешать майонез, лимонный сок и горчицу — заправка.",
      "Собрать салат: зелень, курица, гренки, пармезан, полить заправкой."
    ],
    times: { totalMinutes: 25 },
    servings: 2,
    nutrition: { kcal: 460, protein: 38, fat: 24, carbs: 22 },
    estimatedCost: 320,
    tags: ["обед", "салат", "курица"],
    mealTypes: ["lunch"],
    cuisine: "домашняя"
  },
  {
    id: "mock:solyanka",
    title: "Солянка сборная мясная",
    imageURL: "https://images.example/solyanka.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/solyanka",
    ingredients: ["говядина 200 г", "колбаса 150 г", "солёные огурцы 3 шт", "томатная паста 2 ст.л.", "лук 1 шт", "маслины 50 г", "лимон 0.5 шт", "сметана"],
    instructions: [
      "Нарезать все мясные продукты соломкой, лук и огурцы — кубиками.",
      "Обжарить лук с томатной пастой 5 минут.",
      "Добавить мясо и огурцы, залить бульоном 1.5 л.",
      "Варить 15 минут, добавить маслины. Подавать с лимоном и сметаной."
    ],
    times: { totalMinutes: 40 },
    servings: 4,
    nutrition: { kcal: 320, protein: 24, fat: 18, carbs: 12 },
    estimatedCost: 380,
    tags: ["обед", "суп", "мясной"],
    mealTypes: ["lunch"],
    cuisine: "русская"
  },
  {
    id: "mock:beef-stroganoff",
    title: "Бефстроганов из говядины",
    imageURL: "https://images.example/beef-stroganoff.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/beef-stroganoff",
    ingredients: ["говядина 500 г", "лук 2 шт", "сметана 200 г", "томатная паста 1 ст.л.", "мука 2 ст.л.", "масло 3 ст.л.", "соль, перец", "петрушка"],
    instructions: [
      "Нарезать говядину тонкими полосками, обвалять в муке.",
      "Обжарить лук до золотистого, добавить мясо, жарить 7 минут.",
      "Смешать сметану с томатной пастой и 50 мл воды, залить.",
      "Тушить 15 минут. Подавать с гречкой или пюре."
    ],
    times: { totalMinutes: 40 },
    servings: 4,
    nutrition: { kcal: 460, protein: 36, fat: 28, carbs: 14 },
    estimatedCost: 450,
    tags: ["обед", "говядина", "классика"],
    mealTypes: ["lunch"],
    cuisine: "русская"
  },
  {
    id: "mock:pasta-bolognese",
    title: "Паста болоньезе",
    imageURL: "https://images.example/bolognese.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/bolognese",
    ingredients: ["спагетти 300 г", "фарш говяжий 400 г", "помидоры в/с 400 г", "лук 1 шт", "морковь 1 шт", "чеснок 3 зуб.", "вино 100 мл", "оливковое масло"],
    instructions: [
      "Пассеровать лук, морковь 8 минут. Добавить чеснок и фарш, обжарить.",
      "Влить вино, дать выпариться. Добавить помидоры.",
      "Тушить соус 30 минут на слабом огне.",
      "Отварить пасту al dente. Подавать с соусом и пармезаном."
    ],
    times: { totalMinutes: 60 },
    servings: 4,
    nutrition: { kcal: 580, protein: 34, fat: 20, carbs: 68 },
    estimatedCost: 380,
    tags: ["обед", "паста", "итальянское"],
    mealTypes: ["lunch"],
    cuisine: "итальянская"
  },
  {
    id: "mock:greek-salad",
    title: "Греческий салат",
    imageURL: "https://images.example/greek-salad.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/greek-salad",
    ingredients: ["огурцы 2 шт", "помидоры 3 шт", "фета 150 г", "маслины 50 г", "лук красный 0.5 шт", "болгарский перец 1 шт", "оливковое масло 3 ст.л.", "орегано"],
    instructions: [
      "Нарезать огурцы, помидоры и перец крупными кусками.",
      "Лук нарезать и замочить в воде на 5 минут.",
      "Смешать овощи с маслинами, выложить фету кусками.",
      "Полить маслом, посыпать орегано."
    ],
    times: { totalMinutes: 15 },
    servings: 3,
    nutrition: { kcal: 280, protein: 10, fat: 22, carbs: 14 },
    estimatedCost: 260,
    tags: ["обед", "салат", "вегетарианское"],
    mealTypes: ["lunch"],
    cuisine: "греческая"
  },
  {
    id: "mock:pilaf",
    title: "Плов с курицей",
    imageURL: "https://images.example/pilaf.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/pilaf",
    ingredients: ["рис длиннозёрный 300 г", "куриные бёдра 600 г", "морковь 2 шт", "лук 2 шт", "чеснок 1 головка", "масло 80 мл", "зира, куркума", "соль"],
    instructions: [
      "Обжарить курицу на сильном огне, вынуть.",
      "Обжарить лук, добавить морковь соломкой, готовить 8 минут.",
      "Вернуть курицу, добавить специи, залить водой. Тушить 20 минут.",
      "Выложить промытый рис, воткнуть чеснок. Варить под крышкой 25 минут."
    ],
    times: { totalMinutes: 75 },
    servings: 6,
    nutrition: { kcal: 520, protein: 28, fat: 18, carbs: 62 },
    estimatedCost: 350,
    tags: ["обед", "рис", "курица"],
    mealTypes: ["lunch"],
    cuisine: "азиатская"
  },
  {
    id: "mock:chicken-cutlets",
    title: "Куриные котлеты",
    imageURL: "https://images.example/chicken-cutlets.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/chicken-cutlets",
    ingredients: ["куриный фарш 600 г", "лук 1 шт", "яйцо 1 шт", "хлеб белый 2 ломтика", "молоко 50 мл", "чеснок 2 зуб.", "сухари", "соль, перец"],
    instructions: [
      "Замочить хлеб в молоке, отжать.",
      "Смешать фарш, лук, чеснок, хлеб, яйцо, соль, перец.",
      "Сформировать котлеты, обвалять в сухарях.",
      "Обжарить по 5–6 минут с каждой стороны."
    ],
    times: { totalMinutes: 40 },
    servings: 5,
    nutrition: { kcal: 380, protein: 32, fat: 18, carbs: 22 },
    estimatedCost: 280,
    tags: ["обед", "курица", "котлеты"],
    mealTypes: ["lunch"],
    cuisine: "домашняя"
  },
  {
    id: "mock:lentil-soup",
    title: "Чечевичный суп со специями",
    imageURL: "https://images.example/lentil-soup.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/lentil-soup",
    ingredients: ["красная чечевица 200 г", "лук 1 шт", "морковь 1 шт", "помидоры 2 шт", "чеснок 3 зуб.", "зира, куркума", "оливковое масло", "соль"],
    instructions: [
      "Обжарить лук и морковь 6 минут. Добавить специи.",
      "Добавить помидоры, тушить 3 минуты.",
      "Добавить чечевицу, залить 1 л воды. Варить 20 минут.",
      "Добавить чеснок, посолить. Подавать с лимоном."
    ],
    times: { totalMinutes: 40 },
    servings: 4,
    nutrition: { kcal: 300, protein: 18, fat: 8, carbs: 44 },
    estimatedCost: 140,
    tags: ["обед", "суп", "вегетарианское", "бюджетный"],
    mealTypes: ["lunch"],
    cuisine: "домашняя"
  },
  // ── УЖИНЫ ───────────────────────────────────────────────────────────────
  {
    id: "mock:salmon-pan",
    title: "Стейк из лосося на сковороде",
    imageURL: "https://images.example/salmon.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/salmon",
    ingredients: ["стейк лосося 2 шт (400 г)", "лимон 1 шт", "сливочное масло 30 г", "тимьян", "чеснок 2 зуб.", "соль, перец", "оливковое масло"],
    instructions: [
      "Посолить и поперчить стейки, дать постоять 10 минут.",
      "Обжарить лосось 3–4 минуты на сильном огне.",
      "Перевернуть, добавить масло, чеснок и тимьян. Поливать рыбу маслом 2–3 минуты.",
      "Подавать с лимоном."
    ],
    times: { totalMinutes: 25 },
    servings: 2,
    nutrition: { kcal: 420, protein: 44, fat: 26, carbs: 2 },
    estimatedCost: 560,
    tags: ["ужин", "рыба", "быстро", "белковый"],
    mealTypes: ["dinner"],
    cuisine: "домашняя"
  },
  {
    id: "mock:baked-chicken-thighs",
    title: "Куриные бёдра в духовке с чесноком",
    imageURL: "https://images.example/chicken-thighs.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/chicken-thighs",
    ingredients: ["куриные бёдра 800 г", "чеснок 5 зуб.", "паприка 1 ч.л.", "оливковое масло 3 ст.л.", "розмарин", "лимонный сок 1 ст.л.", "соль, перец"],
    instructions: [
      "Смешать масло, чеснок, паприку, розмарин, соль, лимонный сок.",
      "Натереть курицу маринадом, оставить на 20 минут.",
      "Запекать при 200°C 40–45 минут до золотистой корочки."
    ],
    times: { totalMinutes: 70 },
    servings: 4,
    nutrition: { kcal: 480, protein: 42, fat: 32, carbs: 4 },
    estimatedCost: 320,
    tags: ["ужин", "курица", "запечённое"],
    mealTypes: ["dinner"],
    cuisine: "домашняя"
  },
  {
    id: "mock:pasta-carbonara",
    title: "Паста карбонара",
    imageURL: "https://images.example/carbonara.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/carbonara",
    ingredients: ["спагетти 300 г", "бекон 150 г", "яйца 3 шт", "желтки 2 шт", "пармезан 80 г", "чеснок 2 зуб.", "чёрный перец"],
    instructions: [
      "Отварить спагетти al dente, сохранить 150 мл воды от варки.",
      "Обжарить бекон с чесноком на сухой сковороде.",
      "Взбить яйца и желтки с половиной пармезана и перцем.",
      "Снять с огня, добавить пасту, влить яичную смесь, разбавляя водой. Подавать с сыром."
    ],
    times: { totalMinutes: 25 },
    servings: 3,
    nutrition: { kcal: 620, protein: 30, fat: 26, carbs: 68 },
    estimatedCost: 340,
    tags: ["ужин", "паста", "итальянское"],
    mealTypes: ["dinner"],
    cuisine: "итальянская"
  },
  {
    id: "mock:beef-stew",
    title: "Говядина тушёная с картофелем",
    imageURL: "https://images.example/beef-stew.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/beef-stew",
    ingredients: ["говядина 600 г", "картофель 5 шт", "лук 2 шт", "морковь 1 шт", "томатная паста 2 ст.л.", "чеснок 3 зуб.", "лавровый лист", "масло"],
    instructions: [
      "Обжарить говядину до корочки, добавить лук и морковь.",
      "Добавить томатную пасту, залить водой 500 мл, тушить 60 минут.",
      "Добавить картофель и чеснок, тушить 25 минут.",
      "Посыпать зеленью."
    ],
    times: { totalMinutes: 100 },
    servings: 5,
    nutrition: { kcal: 420, protein: 30, fat: 16, carbs: 38 },
    estimatedCost: 420,
    tags: ["ужин", "говядина", "тушёное"],
    mealTypes: ["dinner"],
    cuisine: "домашняя"
  },
  {
    id: "mock:stuffed-peppers",
    title: "Фаршированный перец с рисом и мясом",
    imageURL: "https://images.example/stuffed-peppers.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/stuffed-peppers",
    ingredients: ["болгарский перец 6 шт", "фарш говяжий 400 г", "рис варёный 150 г", "лук 1 шт", "томатная паста 3 ст.л.", "сметана 100 г", "соль, перец"],
    instructions: [
      "Срезать верхушки перцев, удалить семена.",
      "Смешать фарш, рис, лук, соль и перец. Начинить перцы.",
      "Смешать томатную пасту, сметану, 300 мл воды. Залить перцы.",
      "Тушить под крышкой 45 минут."
    ],
    times: { totalMinutes: 70 },
    servings: 6,
    nutrition: { kcal: 360, protein: 22, fat: 14, carbs: 38 },
    estimatedCost: 310,
    tags: ["ужин", "говядина", "фарш"],
    mealTypes: ["dinner"],
    cuisine: "домашняя"
  },
  {
    id: "mock:chicken-cream",
    title: "Курица в сливочном соусе",
    imageURL: "https://images.example/chicken-cream.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/chicken-cream",
    ingredients: ["куриное филе 600 г", "сливки 200 мл", "лук 1 шт", "чеснок 3 зуб.", "масло сливочное 30 г", "мука 1 ст.л.", "итальянские травы", "соль"],
    instructions: [
      "Нарезать и обжарить филе, вынуть.",
      "Обжарить лук, добавить чеснок, муку, влить сливки.",
      "Варить соус 5 минут с травами.",
      "Вернуть курицу, прогреть 3 минуты."
    ],
    times: { totalMinutes: 35 },
    servings: 4,
    nutrition: { kcal: 440, protein: 42, fat: 28, carbs: 8 },
    estimatedCost: 360,
    tags: ["ужин", "курица", "сливочный соус"],
    mealTypes: ["dinner"],
    cuisine: "домашняя"
  },
  {
    id: "mock:fish-cutlets",
    title: "Рыбные котлеты из трески",
    imageURL: "https://images.example/fish-cutlets.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/fish-cutlets",
    ingredients: ["филе трески 600 г", "лук 1 шт", "яйцо 1 шт", "хлеб белый 2 ломтика", "молоко 50 мл", "укроп", "сухари", "соль, белый перец"],
    instructions: [
      "Замочить хлеб в молоке, отжать.",
      "Измельчить рыбу, смешать с хлебом, луком, яйцом, укропом.",
      "Сформировать котлеты, обвалять в сухарях.",
      "Обжарить по 4–5 минут с каждой стороны."
    ],
    times: { totalMinutes: 35 },
    servings: 4,
    nutrition: { kcal: 300, protein: 30, fat: 12, carbs: 18 },
    estimatedCost: 290,
    tags: ["ужин", "рыба", "котлеты"],
    mealTypes: ["dinner"],
    cuisine: "домашняя"
  },
  {
    id: "mock:vegetable-stew",
    title: "Овощное рагу",
    imageURL: "https://images.example/veg-stew.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/veg-stew",
    ingredients: ["баклажан 1 шт", "кабачок 1 шт", "болгарский перец 2 шт", "помидоры 3 шт", "лук 1 шт", "морковь 1 шт", "чеснок 3 зуб.", "оливковое масло", "итальянские травы"],
    instructions: [
      "Нарезать все овощи крупными кубиками.",
      "Обжарить лук и морковь 5 минут, добавить баклажан и кабачок на 8 минут.",
      "Добавить перец, помидоры, чеснок и специи.",
      "Тушить под крышкой 20 минут."
    ],
    times: { totalMinutes: 45 },
    servings: 4,
    nutrition: { kcal: 180, protein: 4, fat: 10, carbs: 22 },
    estimatedCost: 180,
    tags: ["ужин", "вегетарианское", "овощи"],
    mealTypes: ["dinner"],
    cuisine: "домашняя"
  },
  {
    id: "mock:pelmeni",
    title: "Пельмени домашние",
    imageURL: "https://images.example/pelmeni.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/pelmeni",
    ingredients: ["мука 400 г", "яйцо 1 шт", "вода 150 мл", "фарш свиной 300 г", "фарш говяжий 200 г", "лук 1 шт", "соль, перец", "сметана"],
    instructions: [
      "Замесить тесто из муки, яйца, воды и соли. Отдохнуть 30 минут.",
      "Смешать фарши с луком, солью и перцем.",
      "Раскатать тесто, вырезать кружки. Слепить пельмени.",
      "Варить 7–8 минут после всплытия. Подавать со сметаной."
    ],
    times: { totalMinutes: 90 },
    servings: 6,
    nutrition: { kcal: 520, protein: 28, fat: 20, carbs: 58 },
    estimatedCost: 280,
    tags: ["ужин", "пельмени", "классика"],
    mealTypes: ["dinner"],
    cuisine: "русская"
  },
  // ── ПЕРЕКУСЫ ────────────────────────────────────────────────────────────
  {
    id: "mock:cottage-cheese-bowl",
    title: "Творог с ягодами и орехами",
    imageURL: "https://images.example/cottage-cheese-bowl.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/cottage-cheese-bowl",
    ingredients: ["творог 5% 200 г", "ягоды 80 г", "грецкие орехи 30 г", "мёд 1 ч.л.", "ваниль"],
    instructions: [
      "Разморозить ягоды.",
      "Выложить творог в миску, добавить ваниль.",
      "Сверху ягоды и орехи. Полить мёдом."
    ],
    times: { totalMinutes: 10 },
    servings: 1,
    nutrition: { kcal: 320, protein: 24, fat: 14, carbs: 26 },
    estimatedCost: 130,
    tags: ["перекус", "творог", "белковый"],
    mealTypes: ["snack"],
    cuisine: "домашняя"
  },
  {
    id: "mock:hummus",
    title: "Хумус с овощными палочками",
    imageURL: "https://images.example/hummus.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/hummus",
    ingredients: ["нут консерв. 240 г", "тахини 2 ст.л.", "лимонный сок 2 ст.л.", "чеснок 2 зуб.", "оливковое масло 2 ст.л.", "морковь 1 шт", "огурец 1 шт"],
    instructions: [
      "Слить жидкость с нута, оставить 3 ст.л.",
      "Взбить в блендере нут, тахини, лимон, чеснок, масло до кремовой текстуры.",
      "Нарезать овощи палочками. Подавать с хумусом."
    ],
    times: { totalMinutes: 15 },
    servings: 4,
    nutrition: { kcal: 220, protein: 8, fat: 12, carbs: 22 },
    estimatedCost: 160,
    tags: ["перекус", "вегетарианское", "веганское"],
    mealTypes: ["snack"],
    cuisine: "домашняя"
  },
  {
    id: "mock:banana-smoothie",
    title: "Банановый протеиновый смузи",
    imageURL: "https://images.example/banana-smoothie.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/banana-smoothie",
    ingredients: ["банан 2 шт", "молоко 200 мл", "творог 100 г", "мёд 1 ч.л.", "корица"],
    instructions: [
      "Нарезать бананы кусочками.",
      "Взбить все ингредиенты в блендере до кремовой консистенции.",
      "Подавать сразу или охладить."
    ],
    times: { totalMinutes: 5 },
    servings: 2,
    nutrition: { kcal: 260, protein: 12, fat: 4, carbs: 48 },
    estimatedCost: 90,
    tags: ["перекус", "смузи", "быстро"],
    mealTypes: ["snack"],
    cuisine: "домашняя"
  },
  {
    id: "mock:nuts-mix",
    title: "Ореховая смесь с сухофруктами",
    imageURL: "https://images.example/nuts-mix.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/nuts-mix",
    ingredients: ["грецкие орехи 40 г", "миндаль 40 г", "кешью 40 г", "курага 30 г", "изюм 30 г", "тыквенные семечки 20 г"],
    instructions: [
      "Отмерить все ингредиенты.",
      "Смешать орехи с сухофруктами и семечками.",
      "Разложить по порциям."
    ],
    times: { totalMinutes: 5 },
    servings: 4,
    nutrition: { kcal: 280, protein: 8, fat: 20, carbs: 22 },
    estimatedCost: 200,
    tags: ["перекус", "без готовки", "веганское"],
    mealTypes: ["snack"],
    cuisine: "домашняя"
  },
  {
    id: "mock:baked-apple",
    title: "Запечённые яблоки с корицей",
    imageURL: "https://images.example/baked-apple.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/baked-apple",
    ingredients: ["яблоки 3 шт", "мёд 2 ст.л.", "корица 1 ч.л.", "грецкие орехи 40 г", "масло сливочное 15 г"],
    instructions: [
      "Удалить сердцевину яблок, не прорезая до конца.",
      "Смешать мёд, корицу и орехи. Наполнить яблоки.",
      "Запекать при 180°C 25 минут."
    ],
    times: { totalMinutes: 35 },
    servings: 3,
    nutrition: { kcal: 200, protein: 3, fat: 9, carbs: 30 },
    estimatedCost: 80,
    tags: ["перекус", "десерт", "вегетарианское"],
    mealTypes: ["snack"],
    cuisine: "домашняя"
  },
  {
    id: "mock:cheese-toast",
    title: "Тост с сыром и помидором",
    imageURL: "https://images.example/cheese-toast.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/cheese-toast",
    ingredients: ["хлеб цельнозерновой 2 ломтика", "сыр твёрдый 40 г", "помидор 1 шт", "базилик", "оливковое масло"],
    instructions: [
      "Поджарить хлеб, сбрызнуть маслом.",
      "Выложить ломтики сыра и помидора.",
      "Запечь в духовке 5 минут при 200°C или в тостере.",
      "Украсить базиликом."
    ],
    times: { totalMinutes: 10 },
    servings: 1,
    nutrition: { kcal: 280, protein: 14, fat: 12, carbs: 32 },
    estimatedCost: 70,
    tags: ["перекус", "быстро", "вегетарианское"],
    mealTypes: ["snack"],
    cuisine: "домашняя"
  },

  // ── ДОПОЛНИТЕЛЬНЫЕ ЗАВТРАКИ ───────────────────────────────────────────
  {
    id: "mock:syrniki",
    title: "Сырники из творога",
    imageURL: "https://images.example/syrniki.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/syrniki",
    ingredients: ["творог 250 г", "яйцо 1 шт", "мука 2 ст.л.", "сахар 1 ст.л.", "растительное масло 2 ст.л.", "сметана 50 г"],
    instructions: [
      "Смешать творог, яйцо, муку и сахар до однородной массы.",
      "Сформовать лепёшки, обвалять в муке.",
      "Обжарить на масле по 3 минуты с каждой стороны.",
      "Подавать со сметаной."
    ],
    times: { totalMinutes: 20 },
    servings: 2,
    nutrition: { kcal: 420, protein: 24, fat: 20, carbs: 34 },
    estimatedCost: 110,
    tags: ["завтрак", "творог"],
    mealTypes: ["breakfast"],
    cuisine: "русская"
  },
  {
    id: "mock:bliny",
    title: "Блины на молоке",
    imageURL: "https://images.example/bliny.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/bliny",
    ingredients: ["мука 200 г", "молоко 500 мл", "яйца 2 шт", "сахар 2 ст.л.", "растительное масло 2 ст.л.", "соль"],
    instructions: [
      "Взбить яйца с сахаром и солью.",
      "Добавить молоко и муку, размешать до однородности.",
      "Влить масло, дать тесту отдохнуть 15 минут.",
      "Жарить на раскалённой сковороде тонким слоем."
    ],
    times: { totalMinutes: 30 },
    servings: 4,
    nutrition: { kcal: 350, protein: 10, fat: 12, carbs: 50 },
    estimatedCost: 75,
    tags: ["завтрак", "выпечка"],
    mealTypes: ["breakfast"],
    cuisine: "русская"
  },

  // ── ДОПОЛНИТЕЛЬНЫЕ ОБЕДЫ ──────────────────────────────────────────────
  {
    id: "mock:shchi",
    title: "Щи из свежей капусты",
    imageURL: "https://images.example/shchi.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/shchi",
    ingredients: ["капуста 300 г", "картофель 2 шт", "морковь 1 шт", "лук 1 шт", "томатная паста 1 ст.л.", "говядина 200 г", "лавровый лист", "соль, перец"],
    instructions: [
      "Сварить бульон из говядины 1 час.",
      "Добавить нарезанный картофель, варить 10 мин.",
      "Нашинковать капусту, добавить в суп.",
      "Обжарить лук и морковь с томатной пастой, добавить в щи. Варить 15 мин."
    ],
    times: { totalMinutes: 80 },
    servings: 4,
    nutrition: { kcal: 280, protein: 20, fat: 12, carbs: 22 },
    estimatedCost: 180,
    tags: ["обед", "суп", "русская кухня"],
    mealTypes: ["lunch"],
    cuisine: "русская"
  },
  {
    id: "mock:plov",
    title: "Плов узбекский",
    imageURL: "https://images.example/plov.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/plov",
    ingredients: ["рис 300 г", "баранина 400 г", "морковь 3 шт", "лук 2 шт", "чеснок 1 головка", "зира 1 ч.л.", "растительное масло 80 мл", "соль"],
    instructions: [
      "Разогреть масло в казане, обжарить мясо до корочки.",
      "Добавить лук полукольцами, затем морковь соломкой.",
      "Залить водой, добавить зиру и соль. Тушить 40 мин.",
      "Промыть рис, выложить ровным слоем. Воткнуть чеснок. Варить на тихом огне 25 мин."
    ],
    times: { totalMinutes: 90 },
    servings: 6,
    nutrition: { kcal: 520, protein: 22, fat: 24, carbs: 52 },
    estimatedCost: 350,
    tags: ["обед", "рис", "мясное"],
    mealTypes: ["lunch", "dinner"],
    cuisine: "узбекская"
  },
  {
    id: "mock:beef-stroganoff-buckwheat",
    title: "Бефстроганов с гречкой",
    imageURL: "https://images.example/beef-stroganoff.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/befstroganov",
    ingredients: ["говядина 300 г", "лук 1 шт", "сметана 150 г", "мука 1 ст.л.", "гречневая крупа 150 г", "растительное масло 2 ст.л.", "соль, перец"],
    instructions: [
      "Нарезать мясо соломкой, обжарить на сильном огне 3 мин.",
      "Добавить лук полукольцами, жарить 5 мин.",
      "Посыпать мукой, перемешать, влить сметану.",
      "Тушить 20 мин на среднем огне. Подавать с отварной гречкой."
    ],
    times: { totalMinutes: 40 },
    servings: 3,
    nutrition: { kcal: 480, protein: 32, fat: 22, carbs: 38 },
    estimatedCost: 280,
    tags: ["обед", "мясное", "гречка"],
    mealTypes: ["lunch", "dinner"],
    cuisine: "русская"
  },
  {
    id: "mock:vinegret",
    title: "Винегрет",
    imageURL: "https://images.example/vinegret.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/vinegret",
    ingredients: ["свёкла 2 шт", "картофель 2 шт", "морковь 1 шт", "огурцы солёные 2 шт", "горошек зелёный 100 г", "лук 0.5 шт", "масло подсолнечное 3 ст.л.", "соль"],
    instructions: [
      "Отварить свёклу, картофель, морковь до готовности. Остудить.",
      "Нарезать всё мелкими кубиками.",
      "Добавить огурцы, горошек и лук.",
      "Заправить маслом, посолить, перемешать."
    ],
    times: { totalMinutes: 50 },
    servings: 4,
    nutrition: { kcal: 180, protein: 4, fat: 8, carbs: 24 },
    estimatedCost: 100,
    tags: ["обед", "салат", "вегетарианское"],
    mealTypes: ["lunch", "dinner"],
    cuisine: "русская"
  },

  // ── ДОПОЛНИТЕЛЬНЫЕ УЖИНЫ ──────────────────────────────────────────────
  {
    id: "mock:kotlety-domashnie",
    title: "Котлеты домашние с пюре",
    imageURL: "https://images.example/kotlety.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/kotlety",
    ingredients: ["фарш свино-говяжий 400 г", "лук 1 шт", "хлеб белый 2 ломтика", "молоко 50 мл", "яйцо 1 шт", "картофель 4 шт", "сливочное масло 30 г", "соль, перец"],
    instructions: [
      "Замочить хлеб в молоке. Прокрутить с луком через мясорубку.",
      "Смешать с фаршем, яйцом, солью и перцем. Вымешать.",
      "Сформовать котлеты, обжарить по 5 мин с каждой стороны.",
      "Отварить картофель, сделать пюре с маслом и молоком."
    ],
    times: { totalMinutes: 45 },
    servings: 4,
    nutrition: { kcal: 520, protein: 28, fat: 26, carbs: 42 },
    estimatedCost: 220,
    tags: ["ужин", "мясное", "классика"],
    mealTypes: ["dinner", "lunch"],
    cuisine: "русская"
  },
  {
    id: "mock:golubtsy",
    title: "Голубцы с мясом и рисом",
    imageURL: "https://images.example/golubtsy.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/golubtsy",
    ingredients: ["капуста 1 кочан", "фарш мясной 400 г", "рис 100 г", "лук 1 шт", "морковь 1 шт", "томатная паста 2 ст.л.", "сметана 100 г", "соль, перец"],
    instructions: [
      "Отварить листья капусты до мягкости.",
      "Смешать фарш с отварным рисом, луком, солью.",
      "Завернуть начинку в капустные листья.",
      "Обжарить морковь с томатной пастой, залить голубцы со сметаной. Тушить 40 мин."
    ],
    times: { totalMinutes: 70 },
    servings: 4,
    nutrition: { kcal: 380, protein: 22, fat: 16, carbs: 36 },
    estimatedCost: 230,
    tags: ["ужин", "мясное", "капуста"],
    mealTypes: ["dinner"],
    cuisine: "русская"
  },
  {
    id: "mock:tefteli-v-souse",
    title: "Тефтели в томатном соусе",
    imageURL: "https://images.example/tefteli.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/tefteli",
    ingredients: ["фарш мясной 500 г", "рис 80 г", "лук 1 шт", "яйцо 1 шт", "томатная паста 3 ст.л.", "морковь 1 шт", "мука 1 ст.л.", "соль, перец"],
    instructions: [
      "Отварить рис до полуготовности. Смешать с фаршем, яйцом, луком.",
      "Сформовать шарики, обвалять в муке.",
      "Обжарить тефтели до корочки.",
      "Приготовить соус из обжаренной моркови, лука и томатной пасты. Тушить тефтели в соусе 30 мин."
    ],
    times: { totalMinutes: 50 },
    servings: 4,
    nutrition: { kcal: 420, protein: 26, fat: 20, carbs: 32 },
    estimatedCost: 200,
    tags: ["ужин", "мясное"],
    mealTypes: ["dinner", "lunch"],
    cuisine: "русская"
  },
  {
    id: "mock:zrazy",
    title: "Зразы картофельные с грибами",
    imageURL: "https://images.example/zrazy.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/zrazy",
    ingredients: ["картофель 600 г", "шампиньоны 200 г", "лук 1 шт", "яйцо 1 шт", "мука 3 ст.л.", "растительное масло 3 ст.л.", "сметана 50 г", "соль, перец"],
    instructions: [
      "Отварить картофель, сделать пюре с яйцом и мукой.",
      "Обжарить грибы с луком для начинки.",
      "Сформовать лепёшки, внутрь начинку, слепить зразы.",
      "Обжарить на масле до золотистой корочки. Подавать со сметаной."
    ],
    times: { totalMinutes: 50 },
    servings: 4,
    nutrition: { kcal: 340, protein: 10, fat: 14, carbs: 44 },
    estimatedCost: 150,
    tags: ["ужин", "грибы", "вегетарианское"],
    mealTypes: ["dinner"],
    cuisine: "русская"
  },
  {
    id: "mock:ryba-zapechennaya",
    title: "Рыба запечённая с овощами",
    imageURL: "https://images.example/ryba.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/ryba-zapech",
    ingredients: ["филе трески 400 г", "картофель 3 шт", "лук 1 шт", "морковь 1 шт", "сыр 80 г", "сметана 100 г", "соль, перец, лимон"],
    instructions: [
      "Нарезать овощи кружками, выложить в форму.",
      "Филе посолить, поперчить, сбрызнуть лимоном. Выложить на овощи.",
      "Смазать сметаной, посыпать тёртым сыром.",
      "Запекать при 190°C 35 минут."
    ],
    times: { totalMinutes: 45 },
    servings: 3,
    nutrition: { kcal: 380, protein: 30, fat: 16, carbs: 28 },
    estimatedCost: 300,
    tags: ["ужин", "рыба", "запечённое"],
    mealTypes: ["dinner"],
    cuisine: "русская"
  },

  // ── ДОПОЛНИТЕЛЬНЫЕ ПЕРЕКУСЫ ───────────────────────────────────────────
  {
    id: "mock:oladyi",
    title: "Оладьи на кефире",
    imageURL: "https://images.example/oladyi.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/oladyi",
    ingredients: ["кефир 250 мл", "мука 200 г", "яйцо 1 шт", "сахар 2 ст.л.", "сода 0.5 ч.л.", "растительное масло 2 ст.л."],
    instructions: [
      "Смешать кефир, яйцо и сахар.",
      "Добавить муку с содой, перемешать до густого теста.",
      "Жарить на масле порциями по 2 мин с каждой стороны.",
      "Подавать со сметаной или вареньем."
    ],
    times: { totalMinutes: 20 },
    servings: 3,
    nutrition: { kcal: 310, protein: 8, fat: 10, carbs: 46 },
    estimatedCost: 55,
    tags: ["перекус", "выпечка"],
    mealTypes: ["snack", "breakfast"],
    cuisine: "русская"
  },
  {
    id: "mock:zapekanka-tvorozhnaya",
    title: "Запеканка творожная",
    imageURL: "https://images.example/zapekanka.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/zapekanka",
    ingredients: ["творог 500 г", "яйца 2 шт", "манная крупа 3 ст.л.", "сахар 3 ст.л.", "сметана 50 г", "ванилин", "изюм 50 г"],
    instructions: [
      "Смешать творог, яйца, манку, сахар и ванилин.",
      "Добавить промытый изюм.",
      "Выложить в смазанную форму, смазать сверху сметаной.",
      "Запекать при 180°C 35 минут до золотистой корочки."
    ],
    times: { totalMinutes: 45 },
    servings: 4,
    nutrition: { kcal: 280, protein: 18, fat: 10, carbs: 30 },
    estimatedCost: 130,
    tags: ["перекус", "творог", "выпечка"],
    mealTypes: ["snack", "breakfast"],
    cuisine: "русская"
  },

  // ── ДОПОЛНИТЕЛЬНЫЕ БЛЮДА ──────────────────────────────────────────────
  {
    id: "mock:okroshka",
    title: "Окрошка на кефире",
    imageURL: "https://images.example/okroshka.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/okroshka",
    ingredients: ["кефир 500 мл", "картофель 2 шт", "яйца 2 шт", "огурцы 2 шт", "редис 5 шт", "колбаса 100 г", "зелень", "соль"],
    instructions: [
      "Отварить картофель и яйца, остудить, нарезать кубиками.",
      "Нарезать огурцы, редис, колбасу и зелень.",
      "Смешать всё, залить кефиром.",
      "Посолить, перемешать, подавать холодной."
    ],
    times: { totalMinutes: 30 },
    servings: 3,
    nutrition: { kcal: 240, protein: 14, fat: 10, carbs: 22 },
    estimatedCost: 130,
    tags: ["обед", "суп", "холодное"],
    mealTypes: ["lunch"],
    cuisine: "русская"
  },
  {
    id: "mock:draniki",
    title: "Драники картофельные",
    imageURL: "https://images.example/draniki.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/draniki",
    ingredients: ["картофель 500 г", "лук 1 шт", "яйцо 1 шт", "мука 2 ст.л.", "растительное масло 3 ст.л.", "сметана 100 г", "соль, перец"],
    instructions: [
      "Натереть картофель и лук на мелкой тёрке, отжать сок.",
      "Добавить яйцо, муку, соль и перец.",
      "Жарить оладьи на масле по 3 мин с каждой стороны.",
      "Подавать со сметаной."
    ],
    times: { totalMinutes: 30 },
    servings: 3,
    nutrition: { kcal: 360, protein: 8, fat: 16, carbs: 46 },
    estimatedCost: 80,
    tags: ["ужин", "картофель"],
    mealTypes: ["dinner", "lunch"],
    cuisine: "белорусская"
  },
  {
    id: "mock:olivye",
    title: "Салат Оливье",
    imageURL: "https://images.example/olivye.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/olivye",
    ingredients: ["картофель 3 шт", "морковь 1 шт", "яйца 3 шт", "колбаса 200 г", "горошек зелёный 150 г", "огурцы солёные 2 шт", "майонез 150 г", "соль"],
    instructions: [
      "Отварить картофель, морковь и яйца. Остудить.",
      "Нарезать всё мелкими кубиками.",
      "Добавить горошек и огурцы.",
      "Заправить майонезом, посолить, перемешать."
    ],
    times: { totalMinutes: 40 },
    servings: 6,
    nutrition: { kcal: 280, protein: 10, fat: 18, carbs: 20 },
    estimatedCost: 180,
    tags: ["обед", "салат", "праздничное"],
    mealTypes: ["lunch", "dinner"],
    cuisine: "русская"
  },
  {
    id: "mock:kurinye-naggetsy",
    title: "Куриные наггетсы домашние",
    imageURL: "https://images.example/naggetsy.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/naggetsy",
    ingredients: ["куриное филе 400 г", "мука 100 г", "яйцо 2 шт", "панировочные сухари 100 г", "растительное масло 200 мл", "соль, перец, паприка"],
    instructions: [
      "Нарезать филе на кусочки, посолить, поперчить.",
      "Обвалять в муке, затем в яйце, затем в сухарях.",
      "Обжарить во фритюре 3-4 минуты до золотистого цвета.",
      "Выложить на бумажное полотенце."
    ],
    times: { totalMinutes: 25 },
    servings: 3,
    nutrition: { kcal: 380, protein: 30, fat: 18, carbs: 24 },
    estimatedCost: 170,
    tags: ["перекус", "курица", "быстро"],
    mealTypes: ["snack", "dinner"],
    cuisine: "домашняя"
  },

  // ── ЕЩЁ ПОПУЛЯРНЫЕ БЛЮДА ──────────────────────────────────────────────
  {
    id: "mock:rassolnik",
    title: "Рассольник ленинградский",
    imageURL: "https://images.example/rassolnik.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/rassolnik",
    ingredients: ["говядина 300 г", "перловая крупа 80 г", "огурцы солёные 3 шт", "картофель 3 шт", "морковь 1 шт", "лук 1 шт", "лавровый лист", "соль, перец"],
    instructions: [
      "Замочить перловку на 1 час, отварить до полуготовности.",
      "Сварить бульон из говядины, мясо вынуть и нарезать.",
      "В бульон добавить картофель и перловку, варить 15 минут.",
      "Обжарить лук и морковь, добавить нарезанные огурцы. Добавить зажарку в суп, варить 10 минут."
    ],
    times: { totalMinutes: 90 },
    servings: 5,
    nutrition: { kcal: 260, protein: 18, fat: 10, carbs: 26 },
    estimatedCost: 200,
    tags: ["обед", "суп", "мясное"],
    mealTypes: ["lunch"],
    cuisine: "русская"
  },
  {
    id: "mock:lazy-vareniki",
    title: "Ленивые вареники из творога",
    imageURL: "https://images.example/lazy-vareniki.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/lazy-vareniki",
    ingredients: ["творог 400 г", "яйцо 1 шт", "мука 100 г", "сахар 2 ст.л.", "соль", "сметана 100 г"],
    instructions: [
      "Смешать творог, яйцо, сахар и соль.",
      "Добавить муку, замесить мягкое тесто.",
      "Раскатать в колбаску, нарезать кусочки.",
      "Варить в подсоленной воде 3–4 минуты после всплытия. Подавать со сметаной."
    ],
    times: { totalMinutes: 20 },
    servings: 3,
    nutrition: { kcal: 340, protein: 20, fat: 12, carbs: 38 },
    estimatedCost: 110,
    tags: ["завтрак", "творог", "быстро"],
    mealTypes: ["breakfast", "snack"],
    cuisine: "русская"
  },
  {
    id: "mock:kurinaya-grudka-grilled",
    title: "Куриная грудка на гриле с овощами",
    imageURL: "https://images.example/chicken-grilled.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/chicken-grilled",
    ingredients: ["куриная грудка 500 г", "кабачок 1 шт", "болгарский перец 1 шт", "оливковое масло 2 ст.л.", "чеснок 2 зуб.", "лимонный сок 1 ст.л.", "прованские травы", "соль, перец"],
    instructions: [
      "Замариновать грудку в масле, лимоне, чесноке и травах на 20 минут.",
      "Нарезать овощи крупными кусками, сбрызнуть маслом.",
      "Обжарить грудку на гриль-сковороде по 6 минут с каждой стороны.",
      "Обжарить овощи на гриле 5–7 минут. Подавать вместе."
    ],
    times: { totalMinutes: 40 },
    servings: 3,
    nutrition: { kcal: 320, protein: 42, fat: 12, carbs: 10 },
    estimatedCost: 280,
    tags: ["ужин", "курица", "белковый", "ЗОЖ"],
    mealTypes: ["dinner", "lunch"],
    cuisine: "домашняя"
  },
  {
    id: "mock:uha",
    title: "Уха из сёмги",
    imageURL: "https://images.example/uha.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/uha",
    ingredients: ["сёмга (стейки/хребты) 500 г", "картофель 3 шт", "лук 1 шт", "морковь 1 шт", "лавровый лист 2 шт", "перец горошком", "укроп", "соль"],
    instructions: [
      "Сварить бульон из рыбы 20 минут, процедить, рыбу вынуть.",
      "В бульон добавить картофель, варить 10 минут.",
      "Добавить морковь и лук, варить 10 минут.",
      "Вернуть рыбу, добавить лавровый лист и укроп. Дать настояться 5 минут."
    ],
    times: { totalMinutes: 50 },
    servings: 4,
    nutrition: { kcal: 280, protein: 26, fat: 12, carbs: 18 },
    estimatedCost: 350,
    tags: ["обед", "суп", "рыба"],
    mealTypes: ["lunch"],
    cuisine: "русская"
  },
  {
    id: "mock:shakshuka",
    title: "Шакшука (яйца в томатном соусе)",
    imageURL: "https://images.example/shakshuka.jpg",
    sourceName: "domashnie-recepty.ru",
    sourceURL: "https://domashnie-recepty.ru/shakshuka",
    ingredients: ["яйца 4 шт", "помидоры 4 шт", "лук 1 шт", "болгарский перец 1 шт", "чеснок 2 зуб.", "паприка 1 ч.л.", "зира 0.5 ч.л.", "оливковое масло 2 ст.л.", "соль, перец", "петрушка"],
    instructions: [
      "Обжарить лук и перец на масле 5 минут.",
      "Добавить чеснок, паприку и зиру, жарить 1 минуту.",
      "Добавить нарезанные помидоры, тушить 10 минут до густоты.",
      "Сделать лунки, разбить яйца. Готовить под крышкой 5–7 минут. Посыпать петрушкой."
    ],
    times: { totalMinutes: 25 },
    servings: 2,
    nutrition: { kcal: 340, protein: 20, fat: 22, carbs: 16 },
    estimatedCost: 140,
    tags: ["завтрак", "яйца", "быстро"],
    mealTypes: ["breakfast", "dinner"],
    cuisine: "домашняя"
  }
];
