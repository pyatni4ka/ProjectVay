export class CacheStore<T> {
  private map = new Map<string, { value: T; expiresAt: number }>();

  constructor(private readonly ttlMs: number = 1000 * 60 * 60 * 24) {}

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
    this.map.set(key, { value, expiresAt: Date.now() + this.ttlMs });
  }
}
