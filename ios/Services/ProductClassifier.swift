import Foundation

/// Classifies a product into a category and suggested storage location
/// based on keywords from the category field returned by barcode providers.
enum ProductClassifier {
    private static let rules: [(keywords: [String], category: String, location: InventoryLocation)] = [
        // Молочное
        (["молок", "milk", "dairy", "кефир", "ryazhenka", "ряженка", "творог", "cottage", "сметан", "сметана",
          "сливки", "cream", "йогурт", "yogurt", "простокваш"],
         "Молочное", .fridge),
        // Сыр
        (["сыр", "cheese"],
         "Молочное", .fridge),
        // Мясо
        (["мясо", "meat", "beef", "говядина", "свинина", "pork", "телятина", "баранина", "lamb", "фарш", "колбас", "сосиск", "сардельк"],
         "Мясо и колбасы", .fridge),
        // Птица
        (["курица", "chicken", "индейка", "turkey", "утка", "duck", "птица", "poultry", "филе"],
         "Птица", .fridge),
        // Рыба
        (["рыба", "fish", "лосось", "salmon", "семга", "тунец", "tuna", "треска", "cod", "морепродукт", "seafood", "krevetk", "креветк", "икра", "краб", "кальмар"],
         "Рыба и морепродукты", .fridge),
        // Заморозка
        (["замороз", "frozen", "мороженое", "ice cream", "пельмени", "вареники", "блинчики"],
         "Замороженное", .freezer),
        // Хлеб
        (["хлеб", "bread", "батон", "baton", "булка", "булочка", "bun", "выпечка", "bakery", "baguette", "багет", "лаваш"],
         "Хлеб и выпечка", .pantry),
        // Злаки и крупы
        (["каша", "крупа", "cereal", "гречк", "греча", "buckwheat", "рис", "rice", "овсян", "oat", "перлов", "пшен", "булгур", "кускус", "хлопья", "мюсли"],
         "Крупы и злаки", .pantry),
        // Макароны
        (["макарон", "pasta", "спагетти", "spaghetti", "лапша", "noodle"],
         "Макаронные изделия", .pantry),
        // Яйца
        (["яйц", "egg"],
         "Яйца", .fridge),
        // Овощи
        (["овощ", "vegetable", "морковь", "carrot", "картофель", "картошка", "potato", "огурец", "cucumber",
          "помидор", "tomato", "капуста", "cabbage", "свекл", "beet", "лук", "onion", "чеснок", "garlic", "перец", "зелень", "салат", "гриб", "mushroom"],
         "Овощи и зелень", .fridge),
        // Фрукты
        (["фрукт", "fruit", "яблок", "apple", "груш", "pear", "апельсин", "orange", "банан", "banana",
          "виноград", "grape", "ягод", "berry", "лимон", "lemon", "мандарин", "персик", "абрикос", "слива", "арбуз", "дыня"],
         "Фрукты и ягоды", .pantry),
        // Напитки
        (["напиток", "drink", "сок", "juice", "вода", "water", "чай", "tea", "кофе", "coffee", "какао", "cocoa", "квас", "лимонад", "компот", "морс", "сироп", "энергетик"],
         "Напитки", .pantry),
        // Алкоголь
        (["пиво", "beer", "вино", "wine", "водка", "vodka", "коньяк", "виски", "шампанское", "сидр", "алкоголь"],
         "Алкоголь", .pantry),
        // Консервы
        (["консерв", "canned", "тушёнк", "тушенк", "паштет", "шпрот", "горошек", "кукуруза", "оливки", "маслины"],
         "Консервы", .pantry),
        // Бакалея
        (["сахар", "sugar", "соль", "salt", "мука", "flour"],
         "Бакалея", .pantry),
        // Соусы
        (["соус", "sauce", "кетчуп", "ketchup", "майонез", "mayonnaise", "горчица", "mustard", "хрен", "уксус", "приправ", "специ"],
         "Соусы и приправы", .pantry),
        // Сладкое
        (["конфет", "candy", "шоколад", "chocolate", "печень", "cookie", "вафл", "wafer", "торт", "cake",
          "пирог", "pie", "сладост", "sweet", "десерт", "мармелад", "зефир", "пастила", "сгущен", "мед", "мёд", "джем", "варенье", "сироп"],
         "Сладости", .pantry),
        // Снеки
        (["чипсы", "chips", "сухарик", "орех", "nut", "семечки", "попкорн", "снек", "snack"],
         "Снеки", .pantry),
        // Масло
        (["масло", "oil", "butter", "маргарин", "margarine"],
         "Масла и жиры", .fridge),
        // Хозтовары
        (["мыло", "soap", "шампунь", "shampoo", "гель", "gel", "зубная паста", "toothpaste", "щетка", "brush", "туалетная бумага", "paper", "салфетк", "tissue", "порошок", "powder", "кондиционер", "чистящ", "моюд"],
         "Хозтовары", .pantry),
        // Товары для животных
        (["корм", "pet food", "cat food", "dog food", "собач", "кошач", "животн"],
         "Зоотовары", .pantry),
    ]

    /// Returns a category (either matched or original) and a suggested storage location if a keyword matched.
    static func classify(rawCategory: String, productName: String? = nil) -> (category: String, location: InventoryLocation?) {
        let lowerCategory = rawCategory.lowercased()
        let lowerName = productName?.lowercased() ?? ""
        let combinedText = "\(lowerCategory) \(lowerName)"
        
        for rule in rules {
            if rule.keywords.contains(where: { combinedText.contains($0) }) {
                return (category: rule.category, location: rule.location)
            }
        }
        return (category: rawCategory, location: nil)
    }
}
