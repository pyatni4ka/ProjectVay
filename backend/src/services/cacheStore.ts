export class CacheStore<T> {
  private map = new Map<string, { value: T; expiresAt: number }>();

  constructor(
    private readonly ttlMs: number = 1000 * 60 * 60 * 24,
    private readonly maxEntries: number = 5000
  ) {}

  get(key: string): T | null {
    const hit = this.map.get(key);
    if (!hit) return null;
    if (Date.now() > hit.expiresAt) {
      this.map.delete(key);
      return null;
    }
    return hit.value;
  }

  set(key: string, value: T): void {
    this.pruneExpired();
    if (this.map.size >= this.maxEntries) {
      const oldestKey = this.map.keys().next().value;
      if (oldestKey) {
        this.map.delete(oldestKey);
      }
    }

    this.map.set(key, { value, expiresAt: Date.now() + this.ttlMs });
  }

  size(): number {
    this.pruneExpired();
    return this.map.size;
  }

  private pruneExpired(): void {
    const now = Date.now();
    for (const [key, entry] of this.map.entries()) {
      if (entry.expiresAt <= now) {
        this.map.delete(key);
      }
    }
  }
}
