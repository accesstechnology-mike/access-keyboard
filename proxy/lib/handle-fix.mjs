import { loadLocalEnv } from "./env.mjs";

const INSTRUCTIONS = [
  "You correct typing errors in a message.",
  "Fix spelling, grammar, missing letters, missing spaces, and duplicated letters or words.",
  "Do not change meaning, names, or tone.",
  "Do not add information or rewrite the message.",
  "Preserve the writer's spelling variant (colour/color, honour/honor).",
  "Reply with the corrected message only. No quotes. No explanation.",
].join(" ");

const MAX_CHARS = 8000;

export async function handleFixRequest(request) {
  loadLocalEnv();

  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
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
  if (text.length > MAX_CHARS) {
    return json({ error: "too_long" }, 413);
  }

  const started = Date.now();
  let openaiStatus = 0;
  try {
    const body = {
      model,
      instructions: INSTRUCTIONS,
      input: text,
      store: false,
    };
    if (effort) {
      body.reasoning = { effort };
    }

    const openaiResponse = await fetch(new URL("responses", ensureTrailingSlash(baseURL)), {
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
      return json({ error: "upstream_failed" }, 502);
    }

    const corrected = outputText(openaiPayload).trim();
    if (!corrected) {
      console.error(`fix openai_status=${openaiStatus} duration_ms=${Date.now() - started} empty_output`);
      return json({ error: "empty_output" }, 502);
    }

    console.error(`fix openai_status=${openaiStatus} duration_ms=${Date.now() - started}`);
    return json({ text: corrected }, 200);
  } catch (error) {
    const timedOut = error?.name === "TimeoutError" || error?.name === "AbortError";
    console.error(
      `fix openai_status=${openaiStatus} duration_ms=${Date.now() - started} ${timedOut ? "timeout" : "network"}`
    );
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

function json(body, status) {
  return Response.json(body, { status });
}
