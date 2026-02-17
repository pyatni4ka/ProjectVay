#!/usr/bin/env python3
"""Fetch a local seed recipe catalog from TheMealDB and save as app-ready JSON.

Usage:
  ios/scripts/fetch_recipe_seed.py
  ios/scripts/fetch_recipe_seed.py --output ios/DataSources/External/index/recipe_catalog.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import string
import time
import urllib.request
from pathlib import Path

BASE_URL = "https://www.themealdb.com/api/json/v1/1/search.php?f={}"


def normalize_text(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    text = value.strip()
    return text if text else None


def split_steps(text: str) -> list[str]:
    if not text:
        return []

    normalized = text.replace("\r", "\n")
    lines = [line.strip(" -•\t\n") for line in normalized.split("\n")]
    lines = [line for line in lines if line]

    if len(lines) < 2:
        lines = [piece.strip() for piece in normalized.split(".") if piece.strip()]

    return lines[:16] if lines else [normalized.strip()]


def estimate_nutrition(meal_id: str, ingredients_count: int, category: str) -> dict[str, float]:
    try:
        seed = int(meal_id) % 97
    except Exception:
        seed = ingredients_count * 7

    base_kcal = 220 + ingredients_count * 65 + (seed % 17) * 9
    category_lower = (category or "").lower()

    protein = 12 + ingredients_count * 2.2 + (seed % 9)
    fat = 9 + ingredients_count * 1.3 + ((seed // 2) % 6)

    if any(word in category_lower for word in ["beef", "chicken", "pork", "lamb", "goat", "seafood"]):
        protein += 10
        fat += 5

    if any(word in category_lower for word in ["vegetarian", "vegan", "pasta", "side", "dessert", "breakfast"]):
        fat -= 2

    fat = max(6.0, fat)
    protein = max(10.0, protein)

    carbs = max(12.0, (base_kcal - protein * 4 - fat * 9) / 4)
    kcal = protein * 4 + fat * 9 + carbs * 4

    return {
        "kcal": round(kcal, 1),
        "protein": round(protein, 1),
        "fat": round(fat, 1),
        "carbs": round(carbs, 1),
    }


def build_recipe(meal: dict[str, object]) -> dict[str, object] | None:
    meal_id = normalize_text(meal.get("idMeal"))
    title = normalize_text(meal.get("strMeal"))
    image = normalize_text(meal.get("strMealThumb"))

    if not meal_id or not title or not image:
        return None

    ingredients: list[str] = []
    for idx in range(1, 21):
        ingredient = normalize_text(meal.get(f"strIngredient{idx}"))
        if not ingredient:
            continue
        measure = normalize_text(meal.get(f"strMeasure{idx}"))
        ingredients.append(f"{ingredient} ({measure})" if measure else ingredient)

    if not ingredients:
        return None

    instructions = split_steps(normalize_text(meal.get("strInstructions")) or "")
    if not instructions:
        return None

    area = normalize_text(meal.get("strArea"))
    category = normalize_text(meal.get("strCategory"))
    source_url = normalize_text(meal.get("strSource")) or f"https://www.themealdb.com/meal/{meal_id}"
    video_url = normalize_text(meal.get("strYoutube"))

    tags: list[str] = []
    if category:
        tags.append(category.lower())
    if area:
        tags.append(area.lower())

    tags_payload = normalize_text(meal.get("strTags"))
    if tags_payload:
        for tag in tags_payload.split(","):
            normalized = normalize_text(tag)
            if normalized:
                tags.append(normalized.lower())

    dedup_tags: list[str] = []
    seen: set[str] = set()
    for tag in tags:
        if tag in seen:
            continue
        seen.add(tag)
        dedup_tags.append(tag)

    total_time = max(12, min(90, len(instructions) * 6 + len(ingredients) * 2))

    return {
        "id": f"themealdb:{meal_id}",
        "sourceURL": source_url,
        "sourceName": "TheMealDB",
        "title": title,
        "imageURL": image,
        "videoURL": video_url,
        "ingredients": ingredients,
        "instructions": instructions,
        "totalTimeMinutes": total_time,
        "servings": 2,
        "cuisine": area,
        "tags": dedup_tags,
        "nutrition": estimate_nutrition(meal_id, len(ingredients), category or ""),
    }


def fetch_letter(letter: str) -> dict[str, object]:
    url = BASE_URL.format(letter)
    delay_seconds = 0.6

    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=25) as response:
                raw = response.read().decode("utf-8")
                return json.loads(raw)
        except Exception:
            if attempt == 3:
                return {"meals": []}
            time.sleep(delay_seconds)
            delay_seconds *= 1.8

    return {"meals": []}


def build_catalog() -> dict[str, object]:
    recipes: list[dict[str, object]] = []
    seen_ids: set[str] = set()

    for letter in string.ascii_lowercase:
        payload = fetch_letter(letter)
        meals = payload.get("meals") or []

        if not isinstance(meals, list):
            continue

        for meal in meals:
            if not isinstance(meal, dict):
                continue

            recipe = build_recipe(meal)
            if not recipe:
                continue

            recipe_id = str(recipe["id"])
            if recipe_id in seen_ids:
                continue

            seen_ids.add(recipe_id)
            recipes.append(recipe)

    recipes.sort(key=lambda item: str(item["title"]).lower())

    return {
        "source": "themealdb",
        "fetchedAt": dt.datetime.now(dt.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "count": len(recipes),
        "items": recipes,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch local recipe seed dataset from TheMealDB")
    parser.add_argument(
        "--output",
        default="ios/DataSources/Seed/recipes_seed.json",
        help="Path to output JSON file",
    )
    args = parser.parse_args()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    payload = build_catalog()

    with output_path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)

    print(f"Wrote {payload['count']} recipes to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
