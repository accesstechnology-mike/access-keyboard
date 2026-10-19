// Counters for Fix limits. Upstash Redis over REST (also what Vercel KV uses),
// so there is no SDK dependency. An in-memory store is used by tests.

export function createUsageStore(env = process.env, fetchImpl = fetch) {
  const url = env.UPSTASH_REDIS_REST_URL || env.KV_REST_API_URL;
  const token = env.UPSTASH_REDIS_REST_TOKEN || env.KV_REST_API_TOKEN;
  if (!url || !token) return null;
  return new UpstashStore(url, token, fetchImpl);
}

export class UpstashStore {
  constructor(url, token, fetchImpl = fetch) {
    this.url = url.replace(/\/+$/, "");
    this.token = token;
    this.fetch = fetchImpl;
    this.kind = "upstash";
  }

  async pipeline(commands) {
    const response = await this.fetch(`${this.url}/pipeline`, {
      method: "POST",
      headers: { authorization: `Bearer ${this.token}`, "content-type": "application/json" },
      body: JSON.stringify(commands),
      signal: AbortSignal.timeout(3_000),
    });
    if (!response.ok) throw new Error(`usage store status ${response.status}`);
    const results = await response.json();
    for (const item of results) {
      if (item?.error) throw new Error(`usage store error ${item.error}`);
    }
    return results.map((item) => item?.result);
  }

  /** Adds one and returns the new count. The key expires `ttlSeconds` after it is first created. */
  async increment(key, ttlSeconds) {
    const [count] = await this.pipeline([
      ["INCR", key],
      ["EXPIRE", key, String(ttlSeconds), "NX"],
    ]);
    return Number(count);
  }

  async decrement(key) {
    const [count] = await this.pipeline([["DECR", key]]);
    return Number(count);
  }

  /** [count, secondsToLive] for diagnostics. TTL is -2 when the key is missing. */
  async peek(key) {
    const [count, ttl] = await this.pipeline([["GET", key], ["TTL", key]]);
    return [count === null ? null : Number(count), Number(ttl)];
  }

  async remove(keys) {
    if (!keys.length) return 0;
    const [removed] = await this.pipeline([["DEL", ...keys]]);
    return Number(removed);
  }
}

export class MemoryStore {
  constructor(now = () => Date.now()) {
    this.values = new Map();
    this.now = now;
    this.kind = "memory";
  }

  live(key) {
    const entry = this.values.get(key);
    if (entry && entry.expiresAt <= this.now()) {
      this.values.delete(key);
      return undefined;
    }
    return entry;
  }

  async increment(key, ttlSeconds) {
    const entry = this.live(key) ?? { count: 0, expiresAt: this.now() + ttlSeconds * 1000 };
    entry.count += 1;
    this.values.set(key, entry);
    return entry.count;
  }

  async decrement(key) {
    const entry = this.live(key);
    if (!entry) return 0;
    entry.count -= 1;
    return entry.count;
  }

  async peek(key) {
    const entry = this.live(key);
    if (!entry) return [null, -2];
    return [entry.count, Math.ceil((entry.expiresAt - this.now()) / 1000)];
  }

  async remove(keys) {
    let removed = 0;
    for (const key of keys) removed += this.values.delete(key) ? 1 : 0;
    return removed;
  }
}
