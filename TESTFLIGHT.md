# TestFlight, step by step

This is an iPad-only keyboard (`access: keyboard`). Archive the **AccessKeyboard** scheme. That already embeds `AccessKeyboardExtension`. You cannot do the upload from Linux; the last mile is Xcode on a Mac signed into team `6M3Z27M69P`.

Release builds call the live Fix proxy at `https://access-keyboard.vercel.app/api/fix`. Debug builds still call `http://127.0.0.1:8787/api/fix`. Both send `Authorization: Bearer` with `AK_FIX_PROXY_SECRET`. That value is not in git: copy `Secrets.xcconfig.example` to `Secrets.xcconfig`, and put the same string in Vercel as `FIX_PROXY_SECRET` (Production and Preview). GitHub deploys do not wipe Vercel env vars. Do not enable Vercel Authentication; the keyboard cannot log in.

## 0. Confirm the project is ready

On this repo:

```sh
python3 scripts/check-testflight.py
```

That checks the 1024 icon has no alpha, both targets share version `0.1.0` / build `1`, privacy manifests declare UserDefaults (`CA92.1`), and the live Fix endpoint answers.

If you change the app after a TestFlight upload, bump `CURRENT_PROJECT_VERSION` on **both** the app and the extension (Debug and Release). Apple rejects a reuse of the same build number.

## 1. Apple Developer identifiers

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) for team `6M3Z27M69P`, create these if they are missing. Automatic signing will often create them the first time you archive, but App Groups do not always appear on their own.

| Kind | Identifier |
| --- | --- |
| App ID | `app.access.keyboard.6M3Z27M69P` |
| App ID | `app.access.keyboard.6M3Z27M69P.extension` |
| App Group | `group.6M3Z27M69P.app.access.keyboard` |

On **both** App IDs, enable App Groups and tick `group.6M3Z27M69P.app.access.keyboard`. The keyboard extension will not see Beth mode without that group.

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
| Beth mode / predictions | On-device only (App Group + UserDefaults) |

Internal TestFlight does not need a public privacy-policy URL. External testers / App Review will. After you deploy `proxy/public/privacy.html`, the URL is `https://access-keyboard.vercel.app/privacy.html`.

## 4. Archive and upload from Xcode

1. Open `AccessKeyboard.xcodeproj` on a Mac.
2. Sign in to Xcode with the Apple ID for team `6M3Z27M69P`.
3. Select the **AccessKeyboard** scheme, **Any iOS Device (arm64)** — not a simulator.
4. Confirm both targets use **Automatically manage signing** and team `6M3Z27M69P`.
5. Product → **Archive**. That uses Release, so Fix will hit the Vercel URL.
6. Organizer → **Distribute App** → **App Store Connect** → **Upload**.
7. Leave “Upload your app’s symbols” on. Do not choose Development or Ad Hoc; those never reach TestFlight.
8. Wait until App Store Connect → TestFlight shows the build as **Ready to Test**. Processing often takes 10–30 minutes. A yellow “Missing Compliance” banner is answered in step 2.

If signing fails on the extension, the App Group is missing from one of the App IDs. Fix that in the Developer portal, then archive again.

## 5. Internal testers (do this first)

Internal testers skip Beta App Review. They must be Users in App Store Connect (Admin / App Manager / Developer / Marketing / Sales).

1. TestFlight → **Internal Testing** → create a group, e.g. `Access Technology`.
2. Add testers.
3. Add build **0.1.0 (1)**.
4. Paste the “What to Test” block below.

Each person installs **TestFlight** from the App Store on an **iPad running iPadOS 18**, accepts the invite, and installs `access: keyboard`. An iPhone will not be offered the build.

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

1. Open access: keyboard. Type on the Type screen. Confirm the layout matches a normal iPad keyboard, including the globe key.
2. Settings → turn on Beth mode. Letters should take Beth Moulam’s colours. Type a few misspellings and tap Fix on the suggestion bar. Undo should restore the original. Password fields must not send text.
3. Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard. Open that keyboard and enable Allow Full Access.
4. In Notes or Safari, switch to access: keyboard with the globe key. Beth mode and Fix should now work there too.
5. VoiceOver: every key should have a spoken label (Shift, Delete, Next Keyboard, and so on).

Full Access is required for Beth mode and Fix outside this app. Keystrokes stay on the iPad. Fix sends only the current field to https://access-keyboard.vercel.app/api/fix.
```

## Beta review notes

Paste this into the Beta App Review notes:

```
This is an assistive iPad keyboard. There is no account or login.

The keyboard will not appear in other apps until the reviewer adds it:
Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard.
Then open that keyboard and enable Allow Full Access.

Full Access is required for two things only:
1. Share the Beth-mode colour toggle with the keyboard extension through App Group group.6M3Z27M69P.app.access.keyboard.
2. Let the extension call the Fix proxy at https://access-keyboard.vercel.app/api/fix.

Keystrokes are not sent off the device. Tapping Fix sends the current field’s text to that proxy, which forwards it to OpenAI with store disabled and does not keep the text. Password fields are skipped.

The in-app Type screen uses the same keyboard without Full Access, so you can test layout, Beth mode, and Fix before enabling the system keyboard.
```

## After the first build

- Each new upload needs a new `CURRENT_PROJECT_VERSION` on the app **and** the extension.
- Keep `MARKETING_VERSION` at `0.1.0` until you intend a user-visible version change.
- If Fix starts failing for testers, check the Vercel deployment, `OPENAI_API_KEY`, and `FIX_PROXY_SECRET` on that project. A 401 means the app secret and the Vercel env var do not match. Do not point Release back at `127.0.0.1`.
