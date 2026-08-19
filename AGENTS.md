# AGENTS.md

## Cursor Cloud specific instructions

### Repository overview
This repo is the `access:` on-screen keyboard for iPad, split into:
- `AccessKeyboard/` — the iOS/iPadOS host app (SwiftUI), Xcode project `AccessKeyboard.xcodeproj`.
- `AccessKeyboardExtension/` — the custom keyboard extension.
- `Packages/AccessKeyboardCore/` — a Swift package (iOS 18 target, UIKit) holding the keyboard engine, layouts, predictions, and the `FixClient`. Has XCTest targets under `Tests/`.
- `proxy/` — a small zero-dependency Node.js HTTP service that holds the OpenAI key and powers the one-tap "Fix" feature (spelling/grammar correction).

### Platform limitation (important)
The Cloud Agent VM is **Linux**, with **no Swift toolchain and no Xcode**. The iOS app, the keyboard extension, and the `AccessKeyboardCore` package all depend on UIKit/SwiftUI and target iOS 18, so they **cannot be built, run, tested, or linted here**. Building/testing/running those requires macOS + Xcode (`xcodebuild`, `swift test`). Do not attempt to install a Swift toolchain to work around this — the code needs the iOS SDK (UIKit), which is not available on Linux.

The **only** component that runs on the Cloud Agent VM is `proxy/`.

### Running the Fix proxy (`proxy/`)
- Runtime: Node.js (`>=20`; VM has v22). The proxy uses only Node built-ins — there are **no npm dependencies** and no build/lint/test scripts.
- Config: it reads `proxy/.env.local` (gitignored). Copy `proxy/.env.example` to `proxy/.env.local`. On startup `requireConfig()` **exits the process** if `OPENAI_API_KEY`, `OPENAI_MODEL`, or `OPENAI_BASE_URL` is missing.
- Run (from `proxy/`): `node server.mjs` (or `npm run dev` / `npm start`). It binds `127.0.0.1:8787` (`PORT` overridable).
- Endpoints: `GET /health` → `{"ok":true}`; `POST /api/fix` with `{"text":"..."}` → `{"text":"<corrected>"}`. It forwards `text` to the OpenAI Responses API (`<OPENAI_BASE_URL>/responses`) and returns `output_text`.
- Real corrections need a valid `OPENAI_API_KEY` (set it as a secret). Without one, you can still exercise the full proxy pipeline by pointing `OPENAI_BASE_URL` at a local stand-in server that returns the Responses API shape (`{"output_text": "..."}`).
- Deployment note: `proxy/api/fix.js` + `proxy/vercel.json` expose the same handler as a Vercel function; `server.mjs` is the local dev server.
