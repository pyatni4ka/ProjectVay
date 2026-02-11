import type { Recipe } from "../types/contracts.js";

export const mockRecipes: Recipe[] = [
  {
    id: "r_omelet",
    title: "Омлет с помидорами",
    imageURL: "https://images.example/omelet.jpg",
    sourceName: "example.ru",
    sourceURL: "https://example.ru/omelet",
    ingredients: ["яйца", "помидоры", "молоко"],
    instructions: ["Взбить яйца", "Добавить помидоры", "Пожарить"],
    nutrition: { kcal: 380, protein: 22, fat: 24, carbs: 12 },
    estimatedCost: 180,
    tags: ["быстро", "завтрак"]
  },
  {
    id: "r_couscous",
    title: "Кускус с овощами",
    imageURL: "https://images.example/couscous.jpg",
    sourceName: "example.ru",
    sourceURL: "https://example.ru/couscous",
    ingredients: ["кускус", "перец", "лук"],
    instructions: ["Запарить", "Смешать"],
    nutrition: { kcal: 520, protein: 15, fat: 14, carbs: 84 },
    estimatedCost: 140,
    tags: ["вегетарианское"]
  }
];
