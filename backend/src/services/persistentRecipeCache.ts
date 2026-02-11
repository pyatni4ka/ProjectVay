import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { Recipe } from "../types/contracts.js";

type PersistentRecipeCacheOptions = {
  dbPath: string;
  ttlSeconds?: number;
};

type StoredRecipeRow = {
  source_url: string;
  recipe_json: string;
  expires_at: number;
  updated_at: number;
};

export class PersistentRecipeCache {
  readonly dbPath: string;

  private readonly db: DatabaseSync;
  private readonly ttlMs: number;

  constructor(options: PersistentRecipeCacheOptions) {
    this.dbPath = options.dbPath;
    this.ttlMs = Math.max(1, Math.floor((options.ttlSeconds ?? 60 * 60 * 24 * 7) * 1000));

    if (this.dbPath !== ":memory:") {
      mkdirSync(dirname(this.dbPath), { recursive: true });
    }

    this.db = new DatabaseSync(this.dbPath);
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec("PRAGMA synchronous = NORMAL;");
    this.db.exec("PRAGMA foreign_keys = ON;");
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS recipe_cache (
        source_url TEXT PRIMARY KEY,
        recipe_json TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_recipe_cache_expires ON recipe_cache(expires_at);
      CREATE INDEX IF NOT EXISTS idx_recipe_cache_updated ON recipe_cache(updated_at);
    `);
  }

  get(sourceURL: string): Recipe | null {
    this.cleanupExpired();

    const stmt = this.db.prepare("SELECT source_url, recipe_json, expires_at, updated_at FROM recipe_cache WHERE source_url = ?");
    const row = stmt.get(sourceURL) as StoredRecipeRow | undefined;
    if (!row) {
      return null;
    }

    return decodeRecipe(row.recipe_json);
  }

  set(sourceURL: string, recipe: Recipe): void {
    const now = Date.now();
    const expiresAt = now + this.ttlMs;
    const stmt = this.db.prepare(`
      INSERT INTO recipe_cache (source_url, recipe_json, expires_at, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(source_url) DO UPDATE SET
        recipe_json = excluded.recipe_json,
        expires_at = excluded.expires_at,
        updated_at = excluded.updated_at
    `);
    stmt.run(sourceURL, JSON.stringify(recipe), expiresAt, now);
  }

  listActive(limit: number = 5000): Recipe[] {
    this.cleanupExpired();
    const safeLimit = Math.max(1, Math.min(limit, 50_000));
    const stmt = this.db.prepare(`
      SELECT source_url, recipe_json, expires_at, updated_at
      FROM recipe_cache
      ORDER BY updated_at DESC
      LIMIT ?
    `);
    const rows = stmt.all(safeLimit) as StoredRecipeRow[];
    return rows.map((row) => decodeRecipe(row.recipe_json)).filter((recipe): recipe is Recipe => recipe !== null);
  }

  size(): number {
    this.cleanupExpired();
    const row = this.db.prepare("SELECT COUNT(*) AS count FROM recipe_cache").get() as { count?: number } | undefined;
    return row?.count ?? 0;
  }

  cleanupExpired(): number {
    const now = Date.now();
    const result = this.db.prepare("DELETE FROM recipe_cache WHERE expires_at <= ?").run(now) as { changes?: number };
    return result.changes ?? 0;
  }
}

function decodeRecipe(recipeJSON: string): Recipe | null {
  try {
    return JSON.parse(recipeJSON) as Recipe;
  } catch {
    return null;
  }
}
