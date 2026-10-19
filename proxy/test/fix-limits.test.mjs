import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import { APPLE_ROOT_CA_G3_BASE64 } from "../lib/apple-root-ca-g3.mjs";
import { loadConfig } from "../lib/config.mjs";
import { EntitlementError, createAppleVerifier, proFromTransaction } from "../lib/entitlement.mjs";
import { handleFixRequest } from "../lib/handle-fix.mjs";
import { MemoryStore, UpstashStore, createUsageStore } from "../lib/usage-store.mjs";

const SECRET = "test-shared-secret";
process.env.FIX_PROXY_SECRET = SECRET;
process.env.OPENAI_API_KEY = "test-key";
process.env.OPENAI_MODEL = "test-model";
process.env.OPENAI_BASE_URL = "https://upstream.invalid/v1";

const BUNDLE = "app.access.keyboard.6M3Z27M69P";
const MONTHLY = `${BUNDLE}.pro.monthly`;
const YEARLY = `${BUNDLE}.pro.yearly`;
const LIFETIME = `${BUNDLE}.pro.lifetime`;
const OCT_19 = Date.parse("2026-10-19T12:00:00Z");
const DAY = 24 * 3600 * 1000;

// Signed data in tests is "signed:<json>"; anything else fails verification.
const fakeVerifier = {
  async transaction(jws) {
    if (!jws.startsWith("signed:")) throw new EntitlementError("invalid_signature");
    return JSON.parse(jws.slice(7));
  },
  async appTransaction(jws) {
    if (!jws.startsWith("signed:")) throw new EntitlementError("invalid_signature");
    return JSON.parse(jws.slice(7));
  },
};
const signed = (value) => `signed:${JSON.stringify(value)}`;

function harness(overrides = {}) {
  const clock = { now: OCT_19 };
  const calls = [];
  const deps = {
    config: { ...loadConfig(), perIdentityPerMinute: 0, perIpPerMinute: 0, ...overrides.config },
    verifier: fakeVerifier,
    store: "store" in overrides ? overrides.store : new MemoryStore(() => clock.now),
    now: () => clock.now,
    fetch: async (url, init) => {
      calls.push(JSON.parse(init.body));
      if (overrides.upstreamFails) return Response.json({ error: { type: "server_error" } }, { status: 500 });
      return Response.json({ output_text: "the" });
    },
  };
  return { deps, clock, calls };
}

function fixRequest(headers = {}, { secret = SECRET, ip = "203.0.113.7" } = {}) {
  return new Request("https://proxy.invalid/api/fix", {
    method: "POST",
    headers: {
      authorization: `Bearer ${secret}`,
      "content-type": "application/json",
      "x-forwarded-for": ip,
      ...headers,
    },
    body: JSON.stringify({ text: "teh" }),
  });
}

const freeHeaders = (id = "app-tx-1") => ({ "x-ak-app-transaction": signed({ appTransactionId: id }) });
const proHeaders = (transaction, appId = "app-tx-1") => ({
  "x-ak-transaction": signed(transaction),
  ...freeHeaders(appId),
});

test("defaults match the confirmed pricing", () => {
  const config = loadConfig();
  assert.equal(config.freeFixesPerMonth, 30);
  assert.equal(config.proFixesPerDay, 100);
  assert.equal(config.appAppleId, 6803257519);
  assert.equal(config.bundleId, BUNDLE);
  assert.deepEqual([...config.subscriptionProductIds], [MONTHLY, YEARLY]);
  assert.deepEqual([...config.lifetimeProductIds], [LIFETIME]);
  assert.equal(config.allowLegacySecret, true);
  assert.ok(config.maxOutputTokens > 0);
});

test("legacy builds with only the shared secret still get a Fix, with an output cap", async () => {
  const { deps, calls } = harness();
  const response = await handleFixRequest(fixRequest(), deps);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { text: "the" });
  assert.equal(calls[0].max_output_tokens, deps.config.maxOutputTokens);
  assert.equal(calls[0].store, false);
});

test("a wrong shared secret is rejected before anything else", async () => {
  const { deps, calls } = harness();
  const response = await handleFixRequest(fixRequest({}, { secret: "nope" }), deps);
  assert.equal(response.status, 401);
  assert.equal(calls.length, 0);
});

test("legacy access can be switched off", async () => {
  const { deps } = harness({ config: { allowLegacySecret: false } });
  const response = await handleFixRequest(fixRequest(), deps);
  assert.equal(response.status, 401);
  assert.equal((await response.json()).error, "signed_data_required");
  assert.equal((await handleFixRequest(fixRequest(freeHeaders()), deps)).status, 200);
});

test("free tier: 30 Fixes per calendar month per app transaction", async () => {
  const { deps, clock, calls } = harness();
  for (let i = 0; i < 30; i += 1) {
    assert.equal((await handleFixRequest(fixRequest(freeHeaders()), deps)).status, 200, `fix ${i + 1}`);
  }
  const blocked = await handleFixRequest(fixRequest(freeHeaders()), deps);
  assert.equal(blocked.status, 429);
  const body = await blocked.json();
  assert.equal(body.error, "free_limit");
  assert.equal(body.limit, 30);
  assert.equal(body.resetsAt, "2026-11-01T00:00:00.000Z");
  assert.equal(calls.length, 30, "a blocked Fix never reaches the AI service");

  // Someone else still has their own allowance.
  assert.equal((await handleFixRequest(fixRequest(freeHeaders("app-tx-2")), deps)).status, 200);
  // A new month resets it.
  clock.now = Date.parse("2026-11-01T00:00:01Z");
  assert.equal((await handleFixRequest(fixRequest(freeHeaders()), deps)).status, 200);
});

test("Pro monthly: past the free 30, capped at 100 a day, resets the next day", async () => {
  const { deps, clock } = harness();
  const headers = proHeaders({ productId: MONTHLY, originalTransactionId: "1000", expiresDate: OCT_19 + 10 * DAY });
  for (let i = 0; i < 100; i += 1) {
    assert.equal((await handleFixRequest(fixRequest(headers), deps)).status, 200, `fix ${i + 1}`);
  }
  const blocked = await handleFixRequest(fixRequest(headers), deps);
  assert.equal(blocked.status, 429);
  assert.equal((await blocked.json()).error, "daily_limit");
  clock.now += DAY;
  assert.equal((await handleFixRequest(fixRequest(headers), deps)).status, 200);
});

test("Lifetime counts as Pro with no expiry", () => {
  const config = loadConfig();
  const pro = proFromTransaction({ productId: LIFETIME, originalTransactionId: "42" }, config, OCT_19 + 3650 * DAY);
  assert.deepEqual(pro, { tier: "pro", id: "42", productId: LIFETIME });
});

test("expired, revoked or unknown products fall back to the free tier", async () => {
  const config = loadConfig();
  assert.equal(proFromTransaction({ productId: YEARLY, originalTransactionId: "1", expiresDate: OCT_19 - 1 }, config, OCT_19), null);
  assert.equal(proFromTransaction({ productId: LIFETIME, originalTransactionId: "1", revocationDate: OCT_19 }, config, OCT_19), null);
  assert.equal(proFromTransaction({ productId: "com.other.app.pro", originalTransactionId: "1" }, config, OCT_19), null);

  const { deps } = harness({ config: { freeFixesPerMonth: 1 } });
  const expired = proHeaders({ productId: YEARLY, originalTransactionId: "1", expiresDate: OCT_19 - 1 });
  assert.equal((await handleFixRequest(fixRequest(expired), deps)).status, 200);
  const second = await handleFixRequest(fixRequest(expired), deps);
  assert.equal(second.status, 429);
  assert.equal((await second.json()).error, "free_limit");
});

test("expired Pro without an app transaction is rejected", async () => {
  const { deps } = harness();
  const headers = { "x-ak-transaction": signed({ productId: MONTHLY, originalTransactionId: "1", expiresDate: OCT_19 - 1 }) };
  const response = await handleFixRequest(fixRequest(headers), deps);
  assert.equal(response.status, 401);
  assert.equal((await response.json()).error, "invalid_entitlement");
});

test("signed data that does not verify is rejected, not treated as legacy", async () => {
  const { deps, calls } = harness();
  const response = await handleFixRequest(fixRequest({ "x-ak-app-transaction": "forged" }), deps);
  assert.equal(response.status, 401);
  assert.equal((await response.json()).error, "invalid_entitlement");
  assert.equal(calls.length, 0);
});

test("a failed Fix does not use up the allowance", async () => {
  const failing = harness({ upstreamFails: true, config: { freeFixesPerMonth: 1 } });
  assert.equal((await handleFixRequest(fixRequest(freeHeaders()), failing.deps)).status, 502);
  assert.equal((await handleFixRequest(fixRequest(freeHeaders()), failing.deps)).status, 502);
  const store = failing.deps.store;
  const working = harness({ store, config: { freeFixesPerMonth: 1 } });
  assert.equal((await handleFixRequest(fixRequest(freeHeaders()), working.deps)).status, 200);
});

test("per-minute rate limits per person and per IP", async () => {
  const { deps, clock } = harness({ config: { perIdentityPerMinute: 2, perIpPerMinute: 3 } });
  assert.equal((await handleFixRequest(fixRequest(freeHeaders("a")), deps)).status, 200);
  assert.equal((await handleFixRequest(fixRequest(freeHeaders("a")), deps)).status, 200);
  const person = await handleFixRequest(fixRequest(freeHeaders("a")), deps);
  assert.equal(person.status, 429);
  assert.equal((await person.json()).error, "rate_limited");
  assert.ok(Number(person.headers.get("retry-after")) > 0);

  const ip = await handleFixRequest(fixRequest(freeHeaders("b")), deps);
  assert.equal(ip.status, 429, "the fourth request from one IP in a minute is limited");
  assert.equal((await handleFixRequest(fixRequest(freeHeaders("b"), { ip: "198.51.100.1" }), deps)).status, 200);

  clock.now += 60_000;
  assert.equal((await handleFixRequest(fixRequest(freeHeaders("a")), deps)).status, 200);
});

test("with no usage store, Fix still works unless the store is required", async () => {
  const open = harness({ store: null });
  assert.equal((await handleFixRequest(fixRequest(freeHeaders()), open.deps)).status, 200);
  const strict = harness({ store: null, config: { requireUsageStore: true } });
  assert.equal((await handleFixRequest(fixRequest(freeHeaders()), strict.deps)).status, 503);
});

test("a usage store outage does not stop Fix", async () => {
  const broken = { kind: "broken", increment: async () => { throw new Error("down"); }, decrement: async () => 0 };
  const { deps } = harness({ store: broken });
  assert.equal((await handleFixRequest(fixRequest(freeHeaders()), deps)).status, 200);
});

test("Upstash store sends INCR with a first-write expiry", async () => {
  const sent = [];
  const store = new UpstashStore("https://redis.invalid/", "token", async (url, init) => {
    sent.push({ url, auth: init.headers.authorization, body: JSON.parse(init.body) });
    return Response.json([{ result: 3 }, { result: 1 }]);
  });
  assert.equal(await store.increment("k", 60), 3);
  assert.equal(sent[0].url, "https://redis.invalid/pipeline");
  assert.equal(sent[0].auth, "Bearer token");
  assert.deepEqual(sent[0].body, [["INCR", "k"], ["EXPIRE", "k", "60", "NX"]]);
  assert.equal(createUsageStore({}), null);
  assert.ok(createUsageStore({ KV_REST_API_URL: "https://x.invalid", KV_REST_API_TOKEN: "t" }));
});

test("the embedded Apple root certificate is Apple Root CA - G3", () => {
  const embedded = Buffer.from(APPLE_ROOT_CA_G3_BASE64, "base64");
  assert.deepEqual(embedded, readFileSync(new URL("../certs/AppleRootCA-G3.cer", import.meta.url)));
  assert.equal(
    createHash("sha256").update(embedded).digest("hex"),
    "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179"
  );
});

test("Apple's library rejects data that Apple did not sign", async () => {
  const verifier = createAppleVerifier({ ...loadConfig(), appleOnlineChecks: false });
  const header = Buffer.from(JSON.stringify({ alg: "ES256", x5c: ["AAAA", "BBBB", "CCCC"] })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ productId: LIFETIME, bundleId: BUNDLE })).toString("base64url");
  for (const jws of ["garbage", `${header}.${payload}.c2ln`]) {
    await assert.rejects(verifier.transaction(jws), EntitlementError);
    await assert.rejects(verifier.appTransaction(jws), EntitlementError);
  }
});
