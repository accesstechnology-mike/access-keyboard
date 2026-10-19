# Fix proxy

`POST /api/fix` takes `{ "text": "<paragraph>" }`, sends it to the OpenAI
Responses API (`store: false`, capped at `FIX_MAX_OUTPUT_TOKENS`) and returns
`{ "text": "<corrected>" }`.

## Who gets a Fix

Every request still needs `Authorization: Bearer <FIX_PROXY_SECRET>`.

The app (from the subscription build on) also sends Apple-signed StoreKit data,
written by the app into the App Group and read by the keyboard:

| Header | What | Used for |
| --- | --- | --- |
| `X-AK-Transaction` | Signed transaction (JWS) for monthly, yearly or Lifetime | Pro: `originalTransactionId`, up to `PRO_FIXES_PER_DAY` (100) a day |
| `X-AK-App-Transaction` | Signed app transaction (JWS) | Free: `appTransactionId`, `FREE_FIXES_PER_MONTH` (30) per calendar month |

Both are verified with Apple's App Store Server Library against Apple Root CA - G3
(embedded in `lib/apple-root-ca-g3.mjs`), Production first and then Sandbox
(TestFlight) when `FIX_ALLOW_SANDBOX` is true. A subscription must not be expired
or revoked; Lifetime has no expiry. Signed data that does not verify is a 401,
never a silent downgrade.

Requests with only the shared secret (builds already on TestFlight) still work
while `FIX_ALLOW_LEGACY_SECRET` is true. They are rate limited per IP but have no
allowance, because there is nothing to count them against. Set it to `false`
once every live build sends signed data.

Limits reset at 00:00 UTC (the free month on the 1st).

## Responses

| Status | Body `error` | Meaning |
| --- | --- | --- |
| 429 | `free_limit` | 30 free Fixes used this month (`limit`, `resetsAt`) |
| 429 | `daily_limit` | 100 Pro Fixes used today (`limit`, `resetsAt`) |
| 429 | `rate_limited` | Too many requests this minute (`Retry-After`) |
| 401 | `unauthorized` / `invalid_entitlement` / `signed_data_required` | Secret wrong, signed data forged, or legacy access off |

A Fix that fails upstream is refunded. A usage store outage is logged and Fix
carries on, unless `FIX_REQUIRE_USAGE_STORE=true`.

## Environment

See `.env.example`. Required today: `OPENAI_API_KEY`, `OPENAI_MODEL`,
`OPENAI_BASE_URL`, `FIX_PROXY_SECRET`. For limits to be enforced, add an Upstash
Redis (or Vercel KV) database: `UPSTASH_REDIS_REST_URL` and
`UPSTASH_REDIS_REST_TOKEN` (or `KV_REST_API_URL` and `KV_REST_API_TOKEN`).
Everything else has a default.

## Not built yet

App Attest / DeviceCheck. The signed StoreKit data proves a real purchase or
install, but not that the request came from our app on a real device. App Attest
would need an attestation endpoint, key storage per device, and the keyboard
extension to generate assertions. It is a sensible next step once the counters
are live.

## Tests

```
npm ci
npm test
```
