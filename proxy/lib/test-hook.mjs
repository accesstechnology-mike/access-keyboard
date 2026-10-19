// Preview-only test access, so the counters can be checked against the real
// store without Apple-signed data. Off unless FIX_TEST_TOKEN (32+ characters)
// is set, and always off when VERCEL_ENV is "production".
//
//   X-AK-Test: <FIX_TEST_TOKEN>              diagnostics only (legacy path)
//   X-AK-Test: <FIX_TEST_TOKEN>:<install>    acts as free install "test-<install>"
//   X-AK-Test-Reset: 1                       deletes that request's counter keys
//
// Responses then carry X-AK-Test-Usage: {"key": [count, secondsToLive], ...}.

import { timingSafeEqual } from "node:crypto";

export const TEST_HEADER = "x-ak-test";
export const TEST_RESET_HEADER = "x-ak-test-reset";
export const TEST_USAGE_HEADER = "x-ak-test-usage";

export function testAccess(request, env = process.env) {
  const header = request.headers.get(TEST_HEADER)?.trim() ?? "";
  if (!header) return null;
  if (env.VERCEL_ENV === "production") {
    console.error("fix test_access=off production");
    return null;
  }
  const token = env.FIX_TEST_TOKEN?.trim() ?? "";
  if (token.length < 32) {
    console.error(`fix test_access=off token_length=${token.length}`);
    return null;
  }
  const split = header.indexOf(":");
  const presented = split === -1 ? header : header.slice(0, split);
  const install = split === -1 ? "" : header.slice(split + 1).replace(/[^A-Za-z0-9_-]/g, "").slice(0, 40);
  const left = Buffer.from(presented);
  const right = Buffer.from(token);
  if (left.length !== right.length || !timingSafeEqual(left, right)) {
    console.error("fix test_access=rejected");
    return null;
  }
  return {
    identity: install ? { tier: "free", id: `test-${install}` } : null,
    reset: request.headers.get(TEST_RESET_HEADER) === "1",
  };
}
