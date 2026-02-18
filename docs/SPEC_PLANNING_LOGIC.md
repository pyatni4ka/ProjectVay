# SPEC_PLANNING_LOGIC

## Непростое простыми словами (RU)

Система не просто «подбирает рандомные блюда». Она сначала формирует пул кандидатов, затем фильтрует их по ограничениям (аллергии, диета, бюджет, доступные продукты), и только потом ранжирует.

Каждому кандидату ставится итоговая оценка. Чем дешевле, проще и ближе к цели по КБЖУ, тем выше приоритет. Если бюджет напряжен, система сильнее штрафует дорогие варианты. Если включен акцент на точность КБЖУ, система сильнее штрафует отклонение по макросам.

Инвентарь и сроки годности влияют напрямую: блюда, которые используют продукты «закончатся скоро», получают бонус. Это уменьшает списания еды и лишние траты.

Если пользователь меняет блюдо или съедает «не по плану», система не пересобирает все с нуля без причины. Она старается сохранить максимум уже выбранного и аккуратно перестроить только остаток дня/недели.

Если точные данные недоступны (цена, единицы, нутриенты), система не блокирует пользователя. Она показывает приблизительную оценку и коротко объясняет это в “Почему?”.

## Technical appendix (EN)

### 1) Candidate generation

- Build candidate pool from:
  - local recipe index,
  - persistent cache,
  - optional external providers.
- Apply hard filters first:
  - allergy/diet constraints,
  - explicit exclusions/dislikes,
  - max prep time / difficulty,
  - meal slot compatibility.

### 2) Scoring model

Each candidate gets a composite score from weighted terms:

- macro deviation to meal slot target,
- normalized cost signal vs budget,
- inventory availability fit,
- expiring-items usage bonus,
- convenience penalty (time/difficulty),
- repetition penalty (same recipe/cuisine),
- confidence penalty (low price/nutrition confidence).

Weights are selected by optimizer profile:
- `economy_aggressive`
- `balanced`
- `macro_precision`

### 3) Constraint satisfaction strategy

- Hard constraints are strict filters.
- Soft constraints are weighted penalties/bonuses.
- If hard constraints make the pool empty, fallback relaxes in controlled order:
  1. increase macro tolerance,
  2. relax repetition,
  3. allow approximate price confidence,
  4. emit warnings.

### 4) Replace flow

- Compute slot target and evaluate top-N alternatives.
- Sort by chosen mode (`cheap|fast|protein|expiry`) with deterministic tie-breakers.
- Return deltas (`macroDelta`, `costDelta`, `timeDelta`) and an updated plan preview.

### 5) Deviation adapt flow

- Parse event type and impact estimate.
- Convert event to target adjustment for remaining meals.
- Re-plan remaining scope (`day` or `week`) with minimal disruption objective.
- Preserve past days and unaffected meals when possible.

### 6) Determinism

- Stable sort keys + optional `seed` input.
- Same input should produce same or near-same output.
- Any stochastic fallback must be seed-driven.
