import { mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname } from "node:path";
import type { Recipe } from "../types/contracts.js";

type PersistentRecipeCacheOptions = {
  dbPath: string;
  ttlSeconds?: number;
};

type SQLiteStatementLike = {
  get: (...args: unknown[]) => unknown;
  run: (...args: unknown[]) => { changes?: number };
  all: (...args: unknown[]) => unknown[];
};

type SQLiteDatabaseLike = {
  exec: (sql: string) => void;
  prepare: (sql: string) => SQLiteStatementLike;
};

type SQLiteModuleLike = {
  DatabaseSync: new (path: string) => SQLiteDatabaseLike;
};

type StoredRecipeRow = {
  source_url: string;
  recipe_json: string;
  expires_at: number;
  updated_at: number;
};

const require = createRequire(import.meta.url);
let didWarnMissingSQLite = false;

export class PersistentRecipeCache {
  readonly dbPath: string;
  readonly storageMode: "sqlite" | "memory";

  private readonly db: SQLiteDatabaseLike | null;
  private readonly memoryStore = new Map<string, StoredRecipeRow>();
  private readonly ttlMs: number;

  constructor(options: PersistentRecipeCacheOptions) {
    this.dbPath = options.dbPath;
    this.ttlMs = Math.max(1, Math.floor((options.ttlSeconds ?? 60 * 60 * 24 * 7) * 1000));

    const sqliteModule = loadSQLiteModule();
    if (sqliteModule) {
      if (this.dbPath !== ":memory:") {
        mkdirSync(dirname(this.dbPath), { recursive: true });
      }

      const db = new sqliteModule.DatabaseSync(this.dbPath);
      db.exec("PRAGMA journal_mode = WAL;");
      db.exec("PRAGMA synchronous = NORMAL;");
      db.exec("PRAGMA foreign_keys = ON;");
      db.exec(`
        CREATE TABLE IF NOT EXISTS recipe_cache (
          source_url TEXT PRIMARY KEY,
          recipe_json TEXT NOT NULL,
          expires_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_recipe_cache_expires ON recipe_cache(expires_at);
        CREATE INDEX IF NOT EXISTS idx_recipe_cache_updated ON recipe_cache(updated_at);
      `);

      this.db = db;
      this.storageMode = "sqlite";
    } else {
      this.db = null;
      this.storageMode = "memory";
    }
  }

  get isPersistent(): boolean {
    return this.storageMode === "sqlite";
  }

  get(sourceURL: string): Recipe | null {
    this.cleanupExpired();

    const row = this.fetchRow(sourceURL);
    if (!row) {
      return null;
    }

    return decodeRecipe(row.recipe_json);
  }

  set(sourceURL: string, recipe: Recipe): void {
    const now = Date.now();
    const expiresAt = now + this.ttlMs;
    const row: StoredRecipeRow = {
      source_url: sourceURL,
      recipe_json: JSON.stringify(recipe),
      expires_at: expiresAt,
      updated_at: now
    };

    if (!this.db) {
      this.memoryStore.set(sourceURL, row);
      return;
    }

    const stmt = this.db.prepare(`
        INSERT INTO recipe_cache (source_url, recipe_json, expires_at, updated_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(source_url) DO UPDATE SET
          recipe_json = excluded.recipe_json,
          expires_at = excluded.expires_at,
          updated_at = excluded.updated_at
      `);
    stmt.run(sourceURL, row.recipe_json, row.expires_at, row.updated_at);
  }

  listActive(limit: number = 5000): Recipe[] {
    this.cleanupExpired();
    const safeLimit = Math.max(1, Math.min(limit, 50_000));

    const rows: StoredRecipeRow[] = this.db
      ? (this.db.prepare(`
          SELECT source_url, recipe_json, expires_at, updated_at
          FROM recipe_cache
          ORDER BY updated_at DESC
          LIMIT ?
        `).all(safeLimit) as StoredRecipeRow[])
      : Array.from(this.memoryStore.values())
          .sort((left, right) => right.updated_at - left.updated_at)
          .slice(0, safeLimit);

    return rows
      .map((row) => decodeRecipe(row.recipe_json))
      .filter((recipe): recipe is Recipe => recipe !== null);
  }

  size(): number {
    this.cleanupExpired();

    if (!this.db) {
      return this.memoryStore.size;
    }

    const row = this.db.prepare("SELECT COUNT(*) AS count FROM recipe_cache").get() as { count?: number } | undefined;
    return row?.count ?? 0;
  }

  cleanupExpired(): number {
    const now = Date.now();
    if (!this.db) {
      let removed = 0;
      for (const [sourceURL, row] of this.memoryStore.entries()) {
        if (row.expires_at <= now) {
          this.memoryStore.delete(sourceURL);
          removed += 1;
        }
      }
      return removed;
    }

    const result = this.db.prepare("DELETE FROM recipe_cache WHERE expires_at <= ?").run(now) as { changes?: number };
    return result.changes ?? 0;
  }

  private fetchRow(sourceURL: string): StoredRecipeRow | null {
    if (!this.db) {
      return this.memoryStore.get(sourceURL) ?? null;
    }

    const stmt = this.db.prepare(`
        SELECT source_url, recipe_json, expires_at, updated_at
        FROM recipe_cache
        WHERE source_url = ?
    `);
    const row = stmt.get(sourceURL) as StoredRecipeRow | undefined;
    return row ?? null;
  }
}

function loadSQLiteModule(): SQLiteModuleLike | null {
  try {
    return require("node:sqlite") as SQLiteModuleLike;
  } catch {
    if (!didWarnMissingSQLite) {
      didWarnMissingSQLite = true;
      console.warn("[recipe-cache] node:sqlite is unavailable, fallback to in-memory cache mode");
    }
    return null;
  }
}

function decodeRecipe(recipeJSON: string): Recipe | null {
  try {
    return JSON.parse(recipeJSON) as Recipe;
  } catch {
    return null;
  }
}
