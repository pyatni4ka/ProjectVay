import { mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname } from "node:path";
import { randomUUID } from "node:crypto";
import { ingestionSourceRegistry } from "./sourceRegistry.js";
import { dedupeProducts, dedupeRecipes } from "./dedupe.js";
import { isLicenseRiskAllowed, normalizeLicenseRisk } from "./licenseGuard.js";
import { passesMinimumQualityScore, scoreProductCompleteness, scoreRecipeCompleteness } from "./qualityScoring.js";
import type { IngestionAdapterResult, IngestionContext, IngestionProduct, IngestionRecipe, LicenseRisk } from "./types.js";

type SQLiteStatementLike = {
  run: (...args: unknown[]) => { changes?: number };
};

type SQLiteDatabaseLike = {
  exec: (sql: string) => void;
  prepare: (sql: string) => SQLiteStatementLike;
};

type SQLiteModuleLike = {
  DatabaseSync: new (path: string) => SQLiteDatabaseLike;
};

type RunSummary = {
  runId: string;
  status: "success" | "partial" | "failed";
  startedAt: string;
  finishedAt: string;
  sources: Array<{
    id: string;
    status: "ok" | "skipped" | "error";
    products: number;
    recipes: number;
    prices: number;
    reason?: string;
  }>;
};

const require = createRequire(import.meta.url);

export async function runIngestion(): Promise<RunSummary> {
  const sqlite = loadSQLiteModule();
  if (!sqlite) {
    throw new Error("node:sqlite is unavailable. Use Node.js version with node:sqlite support.");
  }

  const dbPath = process.env.AI_STORE_DB_PATH ?? "data/ai-store.sqlite";
  if (dbPath !== ":memory:") {
    mkdirSync(dirname(dbPath), { recursive: true });
  }

  const db = new sqlite.DatabaseSync(dbPath);
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA synchronous = NORMAL;");
  db.exec("PRAGMA foreign_keys = ON;");
  ensureSchema(db);

  const runId = randomUUID();
  const startedAt = new Date().toISOString();
  const nowISO = startedAt;
  const maxItemsPerSource = clampInt(Number(process.env.INGESTION_MAX_ITEMS_PER_SOURCE ?? 1_500), 50, 25_000);
  const allowedRisk = normalizeLicenseRisk(process.env.INGESTION_MAX_LICENSE_RISK, "high");
  const context: IngestionContext = { nowISO, runId, maxItemsPerSource };
  const sourceSummaries: RunSummary["sources"] = [];
  let hasErrors = false;

  db.prepare(`
    INSERT INTO ingestion_runs (run_id, started_at, status, summary_json)
    VALUES (?, ?, ?, ?)
  `).run(runId, startedAt, "running", "{}");

  for (const adapter of ingestionSourceRegistry) {
    if (!isLicenseRiskAllowed(adapter.licenseRisk, allowedRisk)) {
      sourceSummaries.push({
        id: adapter.id,
        status: "skipped",
        products: 0,
        recipes: 0,
        prices: 0,
        reason: `license_risk_${adapter.licenseRisk}`
      });
      continue;
    }

    try {
      const raw = await adapter.ingest(context);
      const normalized = normalizeAdapterOutput(raw);
      const products = dedupeProducts(normalized.products)
        .map((item) => ({ item, score: scoreProductCompleteness(item) }))
        .filter((entry) => passesMinimumQualityScore(entry.score));
      const recipes = dedupeRecipes(normalized.recipes)
        .map((item) => ({ item, score: scoreRecipeCompleteness(item) }))
        .filter((entry) => passesMinimumQualityScore(entry.score));
      const priceSignals = normalized.priceSignals
        .filter((item) => Number.isFinite(item.priceRub) && item.priceRub > 0);
      const synonyms = normalized.synonyms
        .filter((item) => item.normalizedKey.trim() && item.synonym.trim());

      for (const entry of products) {
        upsertProduct(db, adapter.id, adapter.licenseRisk, context.nowISO, entry.item, entry.score);
      }
      for (const entry of recipes) {
        upsertRecipe(db, adapter.id, adapter.licenseRisk, context.nowISO, entry.item, entry.score);
      }
      for (const signal of priceSignals) {
        insertPriceSignal(db, adapter.id, signal);
      }
      for (const synonym of synonyms) {
        db.prepare(`
          INSERT INTO ingredient_synonyms_ru (normalized_key, synonym, source_id)
          VALUES (?, ?, ?)
          ON CONFLICT(normalized_key, synonym) DO UPDATE SET source_id = excluded.source_id
        `).run(synonym.normalizedKey, synonym.synonym, adapter.id);
      }

      db.prepare(`
        INSERT INTO source_snapshots (source_id, run_id, counts_json, license_risk, captured_at)
        VALUES (?, ?, ?, ?, ?)
      `).run(
        adapter.id,
        runId,
        JSON.stringify({
          products: products.length,
          recipes: recipes.length,
          prices: priceSignals.length,
          synonyms: synonyms.length
        }),
        adapter.licenseRisk,
        context.nowISO
      );

      sourceSummaries.push({
        id: adapter.id,
        status: "ok",
        products: products.length,
        recipes: recipes.length,
        prices: priceSignals.length
      });
    } catch (error) {
      hasErrors = true;
      sourceSummaries.push({
        id: adapter.id,
        status: "error",
        products: 0,
        recipes: 0,
        prices: 0,
        reason: error instanceof Error ? error.message : "unknown_error"
      });
    }
  }

  const finishedAt = new Date().toISOString();
  const summary: RunSummary = {
    runId,
    status: hasErrors ? "partial" : "success",
    startedAt,
    finishedAt,
    sources: sourceSummaries
  };

  db.prepare(`
    UPDATE ingestion_runs
    SET finished_at = ?, status = ?, summary_json = ?
    WHERE run_id = ?
  `).run(finishedAt, summary.status, JSON.stringify(summary), runId);

  return summary;
}

function ensureSchema(db: SQLiteDatabaseLike): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS products_master (
      id TEXT PRIMARY KEY,
      source_id TEXT NOT NULL,
      source_ref TEXT NOT NULL,
      barcode TEXT,
      name TEXT NOT NULL,
      brand TEXT,
      category TEXT,
      nutrition_json TEXT,
      quality_score REAL NOT NULL,
      license_risk TEXT NOT NULL,
      provenance_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_products_master_barcode ON products_master(barcode);
    CREATE INDEX IF NOT EXISTS idx_products_master_name ON products_master(name);

    CREATE TABLE IF NOT EXISTS recipes_corpus (
      id TEXT PRIMARY KEY,
      source_id TEXT NOT NULL,
      source_ref TEXT NOT NULL,
      title TEXT NOT NULL,
      source_url TEXT NOT NULL,
      source_name TEXT NOT NULL,
      image_url TEXT,
      ingredients_json TEXT NOT NULL,
      instructions_json TEXT NOT NULL,
      nutrition_json TEXT,
      total_time_minutes INTEGER,
      quality_score REAL NOT NULL,
      license_risk TEXT NOT NULL,
      provenance_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_recipes_corpus_source ON recipes_corpus(source_id, updated_at DESC);

    CREATE TABLE IF NOT EXISTS recipe_ingredients_norm (
      recipe_id TEXT NOT NULL,
      ingredient TEXT NOT NULL,
      normalized_key TEXT NOT NULL,
      PRIMARY KEY (recipe_id, normalized_key)
    );
    CREATE INDEX IF NOT EXISTS idx_recipe_ingredients_norm_key ON recipe_ingredients_norm(normalized_key);

    CREATE TABLE IF NOT EXISTS ingredient_synonyms_ru (
      normalized_key TEXT NOT NULL,
      synonym TEXT NOT NULL,
      source_id TEXT NOT NULL,
      PRIMARY KEY (normalized_key, synonym)
    );

    CREATE TABLE IF NOT EXISTS price_signals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ingredient TEXT NOT NULL,
      normalized_key TEXT NOT NULL,
      price_rub REAL NOT NULL,
      source_id TEXT NOT NULL,
      source_kind TEXT NOT NULL,
      confidence REAL NOT NULL,
      captured_at TEXT NOT NULL,
      region TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_price_signals_key_time ON price_signals(normalized_key, captured_at DESC);

    CREATE TABLE IF NOT EXISTS user_feedback_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT NOT NULL,
      recipe_id TEXT NOT NULL,
      event_type TEXT NOT NULL,
      value REAL,
      timestamp TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_user_feedback_events_user_time ON user_feedback_events(user_id, timestamp DESC);

    CREATE TABLE IF NOT EXISTS source_snapshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_id TEXT NOT NULL,
      run_id TEXT NOT NULL,
      counts_json TEXT NOT NULL,
      license_risk TEXT NOT NULL,
      captured_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS ingestion_runs (
      run_id TEXT PRIMARY KEY,
      started_at TEXT NOT NULL,
      finished_at TEXT,
      status TEXT NOT NULL,
      summary_json TEXT NOT NULL
    );
  `);
}

function upsertProduct(
  db: SQLiteDatabaseLike,
  sourceId: string,
  licenseRisk: LicenseRisk,
  updatedAt: string,
  product: IngestionProduct,
  qualityScore: number
): void {
  const id = `${sourceId}:${product.sourceRef}`;
  db.prepare(`
    INSERT INTO products_master (
      id, source_id, source_ref, barcode, name, brand, category, nutrition_json,
      quality_score, license_risk, provenance_json, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      barcode = excluded.barcode,
      name = excluded.name,
      brand = excluded.brand,
      category = excluded.category,
      nutrition_json = excluded.nutrition_json,
      quality_score = excluded.quality_score,
      license_risk = excluded.license_risk,
      provenance_json = excluded.provenance_json,
      updated_at = excluded.updated_at
  `).run(
    id,
    sourceId,
    product.sourceRef,
    product.barcode ?? null,
    product.name,
    product.brand ?? null,
    product.category ?? null,
    product.nutrition ? JSON.stringify(product.nutrition) : null,
    qualityScore,
    licenseRisk,
    JSON.stringify(product.provenance ?? {}),
    updatedAt
  );
}

function upsertRecipe(
  db: SQLiteDatabaseLike,
  sourceId: string,
  licenseRisk: LicenseRisk,
  updatedAt: string,
  recipe: IngestionRecipe,
  qualityScore: number
): void {
  const id = `${sourceId}:${recipe.sourceRef}`;
  db.prepare(`
    INSERT INTO recipes_corpus (
      id, source_id, source_ref, title, source_url, source_name, image_url,
      ingredients_json, instructions_json, nutrition_json, total_time_minutes,
      quality_score, license_risk, provenance_json, updated_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      title = excluded.title,
      source_url = excluded.source_url,
      source_name = excluded.source_name,
      image_url = excluded.image_url,
      ingredients_json = excluded.ingredients_json,
      instructions_json = excluded.instructions_json,
      nutrition_json = excluded.nutrition_json,
      total_time_minutes = excluded.total_time_minutes,
      quality_score = excluded.quality_score,
      license_risk = excluded.license_risk,
      provenance_json = excluded.provenance_json,
      updated_at = excluded.updated_at
  `).run(
    id,
    sourceId,
    recipe.sourceRef,
    recipe.title,
    recipe.sourceURL,
    recipe.sourceName,
    recipe.imageURL ?? null,
    JSON.stringify(recipe.ingredients),
    JSON.stringify(recipe.instructions),
    recipe.nutrition ? JSON.stringify(recipe.nutrition) : null,
    recipe.totalTimeMinutes ?? null,
    qualityScore,
    licenseRisk,
    JSON.stringify(recipe.provenance ?? {}),
    updatedAt
  );

  db.prepare("DELETE FROM recipe_ingredients_norm WHERE recipe_id = ?").run(id);
  const statement = db.prepare(`
    INSERT INTO recipe_ingredients_norm (recipe_id, ingredient, normalized_key)
    VALUES (?, ?, ?)
    ON CONFLICT(recipe_id, normalized_key) DO UPDATE SET ingredient = excluded.ingredient
  `);
  for (const ingredient of recipe.ingredients) {
    const normalized = ingredient.trim().toLowerCase();
    if (!normalized) continue;
    statement.run(id, ingredient, normalized);
  }
}

function insertPriceSignal(
  db: SQLiteDatabaseLike,
  sourceId: string,
  signal: {
    ingredient: string;
    normalizedKey: string;
    priceRub: number;
    sourceKind: string;
    confidence: number;
    capturedAtISO: string;
    region: string;
  }
): void {
  db.prepare(`
    INSERT INTO price_signals (
      ingredient, normalized_key, price_rub, source_id, source_kind, confidence, captured_at, region
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    signal.ingredient,
    signal.normalizedKey,
    signal.priceRub,
    sourceId,
    signal.sourceKind,
    Math.min(Math.max(signal.confidence, 0), 1),
    signal.capturedAtISO,
    signal.region
  );
}

function normalizeAdapterOutput(raw: IngestionAdapterResult): IngestionAdapterResult {
  return {
    products: raw.products ?? [],
    recipes: raw.recipes ?? [],
    priceSignals: raw.priceSignals ?? [],
    synonyms: raw.synonyms ?? []
  };
}

function loadSQLiteModule(): SQLiteModuleLike | null {
  try {
    return require("node:sqlite") as SQLiteModuleLike;
  } catch {
    return null;
  }
}

function clampInt(value: number, minValue: number, maxValue: number): number {
  if (!Number.isFinite(value)) {
    return minValue;
  }
  return Math.min(Math.max(Math.floor(value), minValue), maxValue);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runIngestion()
    .then((summary) => {
      console.log(JSON.stringify(summary, null, 2));
    })
    .catch((error) => {
      console.error("[ingestion] failed", error);
      process.exitCode = 1;
    });
}
