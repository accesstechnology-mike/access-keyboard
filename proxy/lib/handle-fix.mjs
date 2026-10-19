import { timingSafeEqual } from "node:crypto";
import { loadConfig } from "./config.mjs";
import { EntitlementError, createAppleVerifier, resolveIdentity } from "./entitlement.mjs";
import { loadLocalEnv } from "./env.mjs";
import { checkRate, clientIp, consumeAllowance, refundAllowance, usageKeys } from "./limits.mjs";
import { TEST_USAGE_HEADER, testAccess } from "./test-hook.mjs";
import { createUsageStore } from "./usage-store.mjs";

const INSTRUCTIONS = [
  "You correct typing errors in a message.",
  "Fix spelling, grammar, missing letters, missing spaces, and duplicated letters or words.",
  "Do not change meaning, names, or tone.",
  "Do not add information or rewrite the message.",
  "Preserve the writer's spelling variant (colour/color, honour/honor).",
  "Reply with the corrected message only. No quotes. No explanation.",
].join(" ");

let cachedVerifier;
let cachedVerifierKey;

function defaultDeps(config) {
  const key = `${config.bundleId}|${config.appAppleId}|${config.allowSandbox}|${config.appleOnlineChecks}`;
  if (!cachedVerifier || cachedVerifierKey !== key) {
    cachedVerifier = createAppleVerifier(config);
    cachedVerifierKey = key;
  }
  return { verifier: cachedVerifier, store: createUsageStore(), fetch, now: () => Date.now() };
}

/**
 * deps (tests): { config, verifier, store, fetch, now }. Anything missing comes
 * from the environment.
 */
export async function handleFixRequest(request, deps = {}) {
  loadLocalEnv();
  const config = deps.config ?? loadConfig();
  const { verifier, store, fetch: fetchImpl, now } = { ...defaultDepsLazy(config, deps), ...deps };

  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const expectedSecret = process.env.FIX_PROXY_SECRET?.trim() ?? "";
  if (!expectedSecret) {
    return json({ error: "misconfigured" }, 500);
  }
  if (!bearerMatches(request, expectedSecret)) {
    return json({ error: "unauthorized" }, 401);
  }

  const test = testAccess(request, deps.env ?? process.env);
  const response = await handleAuthorised(request, config, { verifier, store, fetchImpl, now, test });
  if (!test || !store) return response;
  // Preview diagnostics: report (or clear) the counters this request touched.
  const keys = Object.values(usageKeys({ ip: clientIp(request), identity: test.identity }, now()));
  const headers = new Headers(response.headers);
  if (test.reset) {
    headers.set(TEST_USAGE_HEADER, JSON.stringify({ removed: await store.remove(keys) }));
  } else {
    const usage = {};
    for (const key of keys) usage[key] = await store.peek(key);
    headers.set(TEST_USAGE_HEADER, JSON.stringify(usage));
  }
  return new Response(response.body, { status: response.status, headers });
}

async function handleAuthorised(request, config, { verifier, store, fetchImpl, now, test }) {
  if (test?.reset) return json({ reset: true }, 200);

  // Who is asking: Pro, free, or a build that only knows the shared secret.
  let identity;
  try {
    identity = test?.identity ?? (await resolveIdentity(request, verifier, config, now()));
  } catch (error) {
    if (error instanceof EntitlementError) {
      console.error(`fix auth=rejected reason=${error.code}`);
      return json({ error: "invalid_entitlement" }, 401);
    }
    throw error;
  }
  if (!identity && !config.allowLegacySecret) {
    return json({ error: "signed_data_required" }, 401);
  }

  if (!store && config.requireUsageStore) {
    console.error("fix usage_store=missing");
    return json({ error: "misconfigured" }, 503);
  }

  const apiKey = process.env.OPENAI_API_KEY;
  const model = process.env.OPENAI_MODEL;
  const baseURL = process.env.OPENAI_BASE_URL;
  const effort = process.env.OPENAI_REASONING_EFFORT;
  if (!apiKey || !model || !baseURL) {
    return json({ error: "misconfigured" }, 500);
  }

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const text = typeof payload?.text === "string" ? payload.text : "";
  if (!text.trim()) {
    return json({ error: "empty" }, 400);
  }
  if (text.length > config.maxChars) {
    return json({ error: "too_long" }, 413);
  }

  let grant = null;
  if (store) {
    try {
      const limited = await checkRate(store, { ip: clientIp(request), identity }, config, now());
      if (limited) {
        return json(limited, 429, { "retry-after": String(limited.retryAfterSeconds) });
      }
      if (identity) {
        grant = await consumeAllowance(store, identity, config, now());
        if (grant.error) {
          console.error(`fix tier=${identity.tier} limit=${grant.error}`);
          return json(grant, 429);
        }
      }
    } catch (error) {
      // A store outage must not stop people typing; log and carry on.
      console.error(`fix usage_store=error ${error?.message ?? ""}`);
      if (config.requireUsageStore) return json({ error: "misconfigured" }, 503);
      grant = null;
    }
  }
  const tier = identity?.tier ?? "legacy";

  const refund = async () => {
    if (!grant?.key) return;
    try {
      await refundAllowance(store, grant);
    } catch {
      // Best effort.
    }
  };

  const started = Date.now();
  let openaiStatus = 0;
  try {
    const body = {
      model,
      instructions: INSTRUCTIONS,
      input: text,
      store: false,
    };
    if (config.maxOutputTokens > 0) {
      body.max_output_tokens = config.maxOutputTokens;
    }
    if (effort) {
      body.reasoning = { effort };
    }

    const openaiResponse = await fetchImpl(new URL("responses", ensureTrailingSlash(baseURL)), {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(20_000),
    });
    openaiStatus = openaiResponse.status;

    const openaiPayload = await openaiResponse.json().catch(() => null);
    if (!openaiResponse.ok) {
      const upstream = openaiPayload?.error ?? {};
      console.error(
        `fix openai_status=${openaiStatus} duration_ms=${Date.now() - started} type=${upstream.type ?? ""} code=${upstream.code ?? ""}`
      );
      await refund();
      return json({ error: "upstream_failed" }, 502);
    }

    const corrected = outputText(openaiPayload).trim();
    if (!corrected) {
      console.error(`fix openai_status=${openaiStatus} duration_ms=${Date.now() - started} empty_output`);
      await refund();
      return json({ error: "empty_output" }, 502);
    }

    console.error(`fix tier=${tier} openai_status=${openaiStatus} duration_ms=${Date.now() - started}`);
    return json({ text: corrected }, 200);
  } catch (error) {
    const timedOut = error?.name === "TimeoutError" || error?.name === "AbortError";
    console.error(
      `fix openai_status=${openaiStatus} duration_ms=${Date.now() - started} ${timedOut ? "timeout" : "network"}`
    );
    await refund();
    return json({ error: timedOut ? "timeout" : "network" }, 504);
  }
}

function outputText(payload) {
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) {
    return payload.output_text;
  }

  const parts = [];
  for (const item of payload?.output ?? []) {
    if (item?.type !== "message") {
      continue;
    }
    for (const content of item.content ?? []) {
      if (content?.type === "output_text" && content.text) {
        parts.push(content.text);
      }
    }
  }
  return parts.join("");
}

function ensureTrailingSlash(url) {
  return url.endsWith("/") ? url : `${url}/`;
}

function bearerMatches(request, expected) {
  const header = request.headers.get("authorization") ?? "";
  const presented = header.startsWith("Bearer ") ? header.slice("Bearer ".length).trim() : "";
  const left = Buffer.from(presented);
  const right = Buffer.from(expected);
  if (left.length !== right.length) {
    return false;
  }
  return timingSafeEqual(left, right);
}

function defaultDepsLazy(config, deps) {
  if (deps.verifier && "store" in deps && deps.fetch && deps.now) return {};
  return defaultDeps(config);
}

function json(body, status, headers = {}) {
  return Response.json(body, { status, headers });
}
