import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export function loadLocalEnv() {
  const path = join(dirname(fileURLToPath(import.meta.url)), "..", ".env.local");
  if (!existsSync(path)) {
    return;
  }

  const text = readFileSync(path, "utf8");
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) {
      continue;
    }
    const index = line.indexOf("=");
    const key = line.slice(0, index).trim();
    let value = line.slice(index + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

export function requireConfig() {
  if (!process.env.OPENAI_API_KEY) {
    console.error("OPENAI_API_KEY is missing");
    process.exit(1);
  }
  if (!process.env.OPENAI_MODEL) {
    console.error("OPENAI_MODEL is missing");
    process.exit(1);
  }
  if (!process.env.OPENAI_BASE_URL) {
    console.error("OPENAI_BASE_URL is missing");
    process.exit(1);
  }
}
