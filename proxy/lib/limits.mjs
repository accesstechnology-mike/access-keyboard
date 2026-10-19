// Rate limits and allowances. Periods are UTC: the free month starts at 00:00
// UTC on the 1st, the Pro day at 00:00 UTC.

function utcMonth(now) {
  const d = new Date(now);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

function utcDay(now) {
  return new Date(now).toISOString().slice(0, 10);
}

function nextMonthStart(now) {
  const d = new Date(now);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1)).toISOString();
}

function nextDayStart(now) {
  const d = new Date(now);
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1)).toISOString();
}

export function clientIp(request) {
  const forwarded = request.headers.get("x-forwarded-for");
  if (forwarded) return forwarded.split(",")[0].trim();
  return request.headers.get("x-real-ip")?.trim() || "unknown";
}

/** Per-minute rate limits. Returns null when allowed, or a 429 body. */
export async function checkRate(store, { ip, identity }, config, now = Date.now()) {
  const minute = Math.floor(now / 60_000);
  const ipCount = await store.increment(`fix:rate:ip:${ip}:${minute}`, 120);
  if (config.perIpPerMinute > 0 && ipCount > config.perIpPerMinute) {
    return { error: "rate_limited", retryAfterSeconds: 60 - Math.floor((now / 1000) % 60) };
  }
  if (identity) {
    const idCount = await store.increment(`fix:rate:${identity.tier}:${identity.id}:${minute}`, 120);
    if (config.perIdentityPerMinute > 0 && idCount > config.perIdentityPerMinute) {
      return { error: "rate_limited", retryAfterSeconds: 60 - Math.floor((now / 1000) % 60) };
    }
  }
  return null;
}

/**
 * Counts one Fix against the allowance. Returns { key } when allowed (pass it
 * to refundAllowance if the Fix then fails), or { error, limit, resetsAt }.
 */
export async function consumeAllowance(store, identity, config, now = Date.now()) {
  if (identity.tier === "pro") {
    const key = `fix:pro:${identity.id}:${utcDay(now)}`;
    const count = await store.increment(key, 2 * 24 * 3600);
    if (count > config.proFixesPerDay) {
      return { error: "daily_limit", limit: config.proFixesPerDay, resetsAt: nextDayStart(now) };
    }
    return { key, used: count, limit: config.proFixesPerDay };
  }
  const key = `fix:free:${identity.id}:${utcMonth(now)}`;
  const count = await store.increment(key, 32 * 24 * 3600);
  if (count > config.freeFixesPerMonth) {
    return { error: "free_limit", limit: config.freeFixesPerMonth, resetsAt: nextMonthStart(now) };
  }
  return { key, used: count, limit: config.freeFixesPerMonth };
}

export async function refundAllowance(store, grant) {
  if (grant?.key) await store.decrement(grant.key);
}
