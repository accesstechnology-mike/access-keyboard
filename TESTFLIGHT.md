# TestFlight, step by step

This is an iPad-only keyboard (`access: keyboard`). Archive the **AccessKeyboard** scheme. That already embeds `AccessKeyboardExtension`. You cannot do the upload from Linux; the last mile is Xcode on a Mac signed into team `A688GUK8XK` (Access Technology North Limited).

Debug and Release builds call the live Fix proxy at `https://access-keyboard.vercel.app/api/fix`. Both send `Authorization: Bearer` with `AK_FIX_PROXY_SECRET`. That value is not in git: copy `Secrets.xcconfig.example` to `Secrets.xcconfig`, and put the same string in Vercel as `FIX_PROXY_SECRET` (Production and Preview). GitHub deploys do not wipe Vercel env vars. Do not enable Vercel Authentication; the keyboard cannot log in.

## 0. Confirm the project is ready

On this repo:

```sh
python3 scripts/check-testflight.py
```

That checks the 1024 icon has no alpha, both targets share one marketing version and one build number, privacy manifests declare UserDefaults (`CA92.1`), and the live Fix endpoint answers.

If you change the app after a TestFlight upload, bump `CURRENT_PROJECT_VERSION` on **both** the app and the extension (Debug and Release). Apple rejects a reuse of the same build number.

## 1. Apple Developer identifiers

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) for team `A688GUK8XK`, create these if they are missing. Automatic signing will often create them the first time you archive, but App Groups do not always appear on their own.

| Kind | Identifier |
| --- | --- |
| App ID | `app.access.keyboard.6M3Z27M69P` |
| App ID | `app.access.keyboard.6M3Z27M69P.extension` |
| App Group | `group.6M3Z27M69P.app.access.keyboard` |

On **both** App IDs, enable App Groups and tick `group.6M3Z27M69P.app.access.keyboard`. The keyboard extension will not see colour settings without that group.

## 2. App Store Connect record

1. Open [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **+**.
2. Platform: **iOS**.
3. Name: `access: keyboard`.
4. Primary language: English (UK) if that is the team default, otherwise English (US). The keyboard’s primary language is `en-US`.
5. Bundle ID: `app.access.keyboard.6M3Z27M69P`.
6. SKU: use the bundle ID (`app.access.keyboard.6M3Z27M69P`) unless you already have a SKU scheme.
7. User Access: Full Access.

This app is **iPad only** (`TARGETED_DEVICE_FAMILY = 2`) and needs **iPadOS 18.0**. Do not add iPhone in App Store Connect.

Export compliance is already answered in the project (`ITSAppUsesNonExemptEncryption = NO`). If App Store Connect still asks, choose **No**.

## 3. Privacy answers

Use these only; they match the privacy manifests and the Fix proxy.

| Question | Answer |
| --- | --- |
| Tracking? | No |
| Data collected? | Yes — Other User Content |
| Linked to identity? | No |
| Used for tracking? | No |
| Purpose | App Functionality |
| When | Only if the tester taps **Fix** |
| Third party? | Yes. The Release proxy at `https://access-keyboard.vercel.app/api/fix` forwards that field to OpenAI with `store` disabled. The proxy does not keep the text. Ordinary keystrokes stay on the iPad. |
| Colour settings / predictions | On-device only (App Group + UserDefaults) |

Internal TestFlight does not need a public privacy-policy URL. External testers / App Review will. After you deploy `proxy/public/privacy.html`, the URL is `https://access-keyboard.vercel.app/privacy.html`.

## 4. Archive and upload from Xcode

1. Open `AccessKeyboard.xcodeproj` on a Mac.
2. Sign in to Xcode with the Apple ID for team `A688GUK8XK`.
3. Select the **AccessKeyboard** scheme, **Any iOS Device (arm64)** — not a simulator.
4. Confirm both targets use **Automatically manage signing** and team `A688GUK8XK`.
5. Product → **Archive**. That uses Release, so Fix will hit the Vercel URL.
6. Organizer → **Distribute App** → **App Store Connect** → **Upload**.
7. Leave “Upload your app’s symbols” on. Do not choose Development or Ad Hoc; those never reach TestFlight.
8. Wait until App Store Connect → TestFlight shows the build as **Ready to Test**. Processing often takes 10–30 minutes. A yellow “Missing Compliance” banner is answered in step 2.

If signing fails on the extension, the App Group is missing from one of the App IDs. Fix that in the Developer portal, then archive again.

## 5. Internal testers (do this first)

Internal testers skip Beta App Review. They must be Users in App Store Connect (Admin / App Manager / Developer / Marketing / Sales).

1. TestFlight → **Internal Testing** → create a group, e.g. `Access Technology` / **Alpha**.
2. Add **every** App Store Connect user who should test, including the developer/test Apple ID. Being an Admin does not put that Apple ID in the group. A first-build email invite is a per-build invite; it will not follow later uploads.
3. Turn on **Automatically Distribute Builds**. Do not add a specific old build. Uploads wait until the new build is installable, put every existing tester in the internal groups and on that build, then expire older builds.

Each person installs **TestFlight** from the App Store on an **iPad running iPadOS 18**, accepts the invite, and installs `access: keyboard`. An iPhone will not be offered the build.

Every upload assigns the latest build to every group and expires the rest. There is no opt-in. **Actions → TestFlight → Run workflow** does the same for the build already in App Store Connect, without cutting a new archive. Testers who still have an old install must open TestFlight and tap Update; Apple cannot replace an already-installed binary by itself.

## 6. External testers (needs Beta Review)

Do this only after an internal install works, including Full Access and Fix.

1. TestFlight → **External Testing** → new group.
2. Add the build. Fill **What to Test**, contact email, and the review notes below.
3. Submit for Beta App Review. There is no login; say so.
4. When approved, add testers by email or a public link.

## What to Test

Paste this into the TestFlight group:

```
iPad + iPadOS 18 only. iPhone will not install this build.

1. Open access: keyboard. Type on the Type screen. Confirm the layout matches a normal iPad keyboard, including the globe key. Keys should be larger than a stock iPad board, and letters should use the literacy font. Double-space should insert a full stop. Hold delete to remove letters, then words. Two fingers on the space bar should move the cursor.
2. Settings → Colours → Beth. Letters should take Beth Moulam’s colours. Shift and Caps Lock should show capitals. Type a few misspellings and tap Fix on the suggestion bar. Undo should restore the original. Password fields must not send text.
3. Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard. Open that keyboard and enable Allow Full Access.
4. In Notes or Safari, switch to access: keyboard with the globe key. Colour settings and Fix should now work there too.
5. VoiceOver: every key should have a spoken label (Shift, Delete, Next Keyboard, and so on).

Full Access is required for colour settings and Fix outside this app. Keystrokes stay on the iPad. Fix sends only the current field to https://access-keyboard.vercel.app/api/fix.
```

## Beta review notes

Paste this into the Beta App Review notes:

```
This is an assistive iPad keyboard. There is no account or login.

The keyboard will not appear in other apps until the reviewer adds it:
Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard.
Then open that keyboard and enable Allow Full Access.

Full Access is required for two things only:
1. Share colour settings with the keyboard extension through App Group group.6M3Z27M69P.app.access.keyboard.
2. Let the extension call the Fix proxy at https://access-keyboard.vercel.app/api/fix.

Keystrokes are not sent off the device. Tapping Fix sends the current field’s text to that proxy, which forwards it to OpenAI with store disabled and does not keep the text. Password fields are skipped.

The in-app Type screen uses the same keyboard without Full Access, so you can test layout, colours, and Fix before enabling the system keyboard.
```

## 4b. Upload from this repo

The App Store Connect `.p8` is not in git. Locally it lives in `secrets/` (see `AppStoreConnect.env.example`). GitHub Actions uses repository secrets.

```sh
sh scripts/upload-testflight.sh
```

That archives Release, bumps `CURRENT_PROJECT_VERSION` past the latest TestFlight build, uploads, waits until Apple marks the build VALID, assigns it to every TestFlight group, and expires every older build. App Store Connect currently requires the iOS 26 SDK, so CI runs on `macos-26`.

Agents start a new archive by pushing a `testflight-*` tag (see `AGENTS.md`). Do not claim GitHub Actions cannot be started from this environment.

**Actions → TestFlight → Run workflow** always gives every tester the latest existing build. It does not ask. Push a tag when you want a new archive:

```sh
git tag testflight-<short-reason>
git push origin testflight-<short-reason>
```

## After the first build

- Each new upload needs a new `CURRENT_PROJECT_VERSION` on the app **and** the extension.
- Keep `MARKETING_VERSION` at `0.1.0` until you intend a user-visible version change.
- Testers only ever get the latest build. Uploads and **Run workflow** expire every older one.
- If Fix starts failing for testers, check the Vercel deployment, `OPENAI_API_KEY`, and `FIX_PROXY_SECRET` on that project. A 401 means the app secret and the Vercel env var do not match.
