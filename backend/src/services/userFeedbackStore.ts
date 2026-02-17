import { mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname } from "node:path";
import type { Recipe, UserFeedbackEvent, UserTasteProfile } from "../types/contracts.js";
import {
  buildTasteProfileFromEvents,
  normalizeUserFeedbackEvents,
  type StoredUserFeedbackEvent
} from "./personalizationModel.js";

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

type UserFeedbackStoreOptions = {
  dbPath: string;
};

const require = createRequire(import.meta.url);

export class UserFeedbackStore {
  readonly storageMode: "sqlite" | "memory";

  private readonly db: SQLiteDatabaseLike | null;
  private readonly memoryStore = new Map<string, StoredUserFeedbackEvent[]>();

  constructor(options: UserFeedbackStoreOptions) {
    const sqliteModule = loadSQLiteModule();
    if (!sqliteModule) {
      this.db = null;
      this.storageMode = "memory";
      return;
    }

    if (options.dbPath !== ":memory:") {
      mkdirSync(dirname(options.dbPath), { recursive: true });
    }

    const db = new sqliteModule.DatabaseSync(options.dbPath);
    db.exec("PRAGMA journal_mode = WAL;");
    db.exec("PRAGMA synchronous = NORMAL;");
    db.exec(`
      CREATE TABLE IF NOT EXISTS user_feedback_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        recipe_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        value REAL,
        timestamp TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_user_feedback_events_user_time ON user_feedback_events(user_id, timestamp DESC);
      CREATE INDEX IF NOT EXISTS idx_user_feedback_events_recipe ON user_feedback_events(recipe_id);
    `);

    this.db = db;
    this.storageMode = "sqlite";
  }

  appendEvents(userId: string, events: Array<Partial<UserFeedbackEvent>>): number {
    const normalized = normalizeUserFeedbackEvents(userId, events);
    if (normalized.length === 0) {
      return 0;
    }

    if (!this.db) {
      const existing = this.memoryStore.get(userId) ?? [];
      existing.push(...normalized);
      this.memoryStore.set(userId, existing);
      return normalized.length;
    }

    const statement = this.db.prepare(`
      INSERT INTO user_feedback_events (user_id, recipe_id, event_type, value, timestamp)
      VALUES (?, ?, ?, ?, ?)
    `);
    for (const event of normalized) {
      statement.run(
        event.userId,
        event.recipeId,
        event.eventType,
        event.value ?? null,
        event.timestamp
      );
    }

    return normalized.length;
  }

  listEvents(userId: string, limit: number = 500): StoredUserFeedbackEvent[] {
    const safeLimit = Math.max(1, Math.min(limit, 10_000));
    if (!this.db) {
      const events = this.memoryStore.get(userId) ?? [];
      return events
        .slice()
        .sort((left, right) => right.timestamp.localeCompare(left.timestamp))
        .slice(0, safeLimit);
    }

    const rows = this.db.prepare(`
      SELECT user_id, recipe_id, event_type, value, timestamp
      FROM user_feedback_events
      WHERE user_id = ?
      ORDER BY timestamp DESC
      LIMIT ?
    `).all(userId, safeLimit) as Array<{
      user_id: string;
      recipe_id: string;
      event_type: StoredUserFeedbackEvent["eventType"];
      value: number | null;
      timestamp: string;
    }>;

    return rows.map((row) => ({
      userId: row.user_id,
      recipeId: row.recipe_id,
      eventType: row.event_type,
      value: row.value ?? undefined,
      timestamp: row.timestamp
    }));
  }

  buildTasteProfile(userId: string, recipes: Recipe[]): UserTasteProfile {
    const events = this.listEvents(userId, 2_000);
    return buildTasteProfileFromEvents(userId, events, recipes);
  }
}

function loadSQLiteModule(): SQLiteModuleLike | null {
  try {
    return require("node:sqlite") as SQLiteModuleLike;
  } catch {
    return null;
  }
}
