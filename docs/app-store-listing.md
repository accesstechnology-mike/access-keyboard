# App Store listing draft — access: keyboard

Draft for the first public App Store release. This is not a private or unlisted release. The binary is the universal iPhone + iPad keyboard (`TARGETED_DEVICE_FAMILY = "1,2"`, iOS/iPadOS 18). Latest TestFlight upload is build 18. Do not treat this file as already entered in App Store Connect.

Fix ships in v1. `FeatureFlags.fixConsentRequired` is **on**, so the first Fix tap asks Allow / Not now before any text is sent.

Source for the review notes and privacy answers: `TESTFLIGHT.md`.

## TODO — Mike in App Store Connect

The product IDs are decided. There is no free tier. The whole keyboard, including Fix, requires an active subscription or the 14-day free trial. Mike still has to create that subscription in App Store Connect before review. The app does not hardcode prices and does not grant access from config.

- **Paid Apps agreement, banking, and tax.** A subscription cannot be submitted until the Paid Apps agreement is active and banking and tax are complete.
- **Subscription group.** One group, name `access: keyboard`.
- **Products.** Create exactly `app.access.keyboard.6M3Z27M69P.pro.monthly` at £1.99 per month and `app.access.keyboard.6M3Z27M69P.pro.yearly` at £19.99 per year. Those IDs stay as written, including `.pro.`, and are `SubscriptionConfig` in `Packages/AccessKeyboardCore/Sources/AccessKeyboardCore/SubscriptionConfig.swift`. They are two prices for one offering, not a separate Pro tier.
- **Introductory offer.** Set a 14-day free introductory offer on both products. The trial length is chosen here, not in the app. The paywall shows that offer only when StoreKit returns it and the user is eligible.
- **Subscription review screenshot.** Apple asks for a screenshot of the paywall when the subscription is submitted.
- **Privacy page deploy.** The page source is `proxy/public/privacy.html`. App Store Connect should use `https://access-keyboard.vercel.app/privacy.html`, which serves that file. The live URL updates when the Vercel project deploys from `main`. Confirm the deployed page matches this repo before review. `proxy/public/config.json` is the optional paywall headline switch at `https://access-keyboard.vercel.app/config.json`.
- **Support URL.** Proposed below from the company site already referenced in the repo (`scripts/generate-icon.swift`). Confirm it, or replace it, before submission.

## Identity

| Field | Value |
| --- | --- |
| Name | `access: keyboard` |
| Subtitle | `Large keys, iPhone and iPad` |
| Bundle ID | `app.access.keyboard.6M3Z27M69P` |
| SKU | `app.access.keyboard.6M3Z27M69P` |
| Primary category | Utilities |
| Secondary category | Productivity (optional) |
| Primary language | English (UK), unless the App Store Connect record is already English (US). The keyboard’s `PrimaryLanguage` is `en-US`. |
| Copyright | Access Technology North Limited |
| Version | `0.1.0` (marketing version in the Xcode project) |
| Price | Free to download. Using the keyboard requires one auto-renewing subscription: £1.99 a month or £19.99 a year, entered in App Store Connect, or the 14-day free trial on that subscription. The paywall shows StoreKit’s localized price and trial. |

Subtitle is 27 characters (limit 30). Name is 16 characters (limit 30). Promotional text is 157 characters (limit 170). Keywords are 79 characters (limit 100).

## Promotional text

170 characters maximum. This draft is within that limit.

```
An assistive keyboard for iPhone and iPad. Large keys and a literacy font. Subscribe to use it, including Fix. A free trial is available for new subscribers.
```

Fix ships in this version for subscribers and trial users, with the consent step on.

## Description

```
access: keyboard is an assistive keyboard for iPhone and iPad. It starts from the layout you already know and keeps the keys large.

It runs on iPhone and iPad on iOS and iPadOS 18. The same app lays out a compact board on iPhone and the larger iPad and iPad Pro boards. QWERTY is the starting layout. ABC order and a frequency grid are optional. Coloured vowels, Beth colours, and high-contrast themes are optional. A literacy font is used on the keys.

Two fingers anywhere on the keyboard move the cursor, as on the system keyboard. Hold delete to remove letters, then words. Double-space inserts a full stop. Long-press a letter for accents. VoiceOver speaks each key.

The suggestion bar can learn words you type. That learning stays on the device (PredictionMemory in the app’s shared App Group when Full Access is on). It is not uploaded.

Using the keyboard requires a subscription. Monthly and yearly are two prices for the same keyboard, including Fix, purchased in this app through Apple. A free trial is the introductory offer Apple shows when your account is eligible. Tapping Fix can correct the text in the current field. Nothing is sent until you tap Fix, and this version asks you to Allow it once before the first send. You can turn that off in Settings. Only that field is sent, to OpenAI through access: keyboard’s server, so it can be corrected. The server does not keep the text. Ordinary keystrokes are not sent. Password fields are skipped. With no network, Fix does not send anything.

Without an active subscription the keyboard in other apps shows a short locked message, a button that opens this app, and a globe key that switches to another keyboard. It does not show a purchase screen. Allow Full Access has to be on so that keyboard can read the subscription. The app includes a Type screen once you are subscribed.

To use it in other apps: Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard.
```

## Keywords

100 characters maximum, comma-separated. The app name already contains “access” and “keyboard”, so those words are left out.

```
assistive,accessibility,AAC,eye gaze,literacy,large keys,switch,contrast,typing
```

## URLs

| Field | Value |
| --- | --- |
| Support URL | `https://www.accesstechnology.co.uk` |
| Marketing URL | Leave blank unless Mike wants the company site here too |
| Privacy Policy URL | `https://access-keyboard.vercel.app/privacy.html` |
| Contact | `mike@accesstechnology.co.uk` |

The privacy page describes an iPhone and iPad keyboard, on-device PredictionMemory, what Fix sends to OpenAI and when, and that contact address. There was no separate support address elsewhere in the repo.

## Age rating

Answer **None** or **No** to every content and capability question. Expected result: **4+**.

| Question | Answer |
| --- | --- |
| Cartoon or fantasy violence | None |
| Realistic violence | None |
| Guns or other weapons | None |
| Sexual content or nudity | None |
| Profanity or crude humor | None |
| Alcohol, tobacco, or drug use | None |
| Mature or suggestive themes | None |
| Horror or fear | None |
| Medical or treatment information | None |
| Gambling or contests | None |
| Unrestricted web access | No |
| User-generated content shared with other users | No |
| Messaging or chat | No |
| Advertising | No |

The keyboard does not browse the web, host a social feed, or show ads. Fix sends the current field to OpenAI only after the user taps Fix and Allow; that is app functionality, not unrestricted web access and not content shared with other users. Confirm the labels against the live App Store Connect form if Apple has renamed a row.

## Privacy nutrition label

Tracking: **No**.

Fix ships in v1, with the consent step on:

| Question | Answer |
| --- | --- |
| Data collected | Other User Content (the current text field) |
| Linked to the user’s identity | No |
| Used for tracking | No |
| Purpose | App Functionality |
| When | Only if the user taps Fix, and only after they tap Allow while consent is required |
| Third party | Yes. `https://access-keyboard.vercel.app/api/fix` forwards that field to OpenAI with `store` disabled. The proxy does not keep the text. Ordinary keystrokes stay on the device. Password fields are skipped. |
| Colour settings and learned predictions | On-device only (App Group `group.6M3Z27M69P.app.access.keyboard` and UserDefaults). Not collected. |
| Purchases | Handled by Apple. Payment details are not collected by the app. Subscription status (active, product, expiry) stays on the device in that App Group. |

The privacy manifests already declare UserDefaults (`CA92.1`) and Other User Content for app functionality, not linked, not tracking.

## App Review notes

Paste this into App Review. The app requires a subscription. Full Access is required for the system keyboard to read that subscription. The locked state keeps a working globe key.

```
This is an assistive keyboard for iPhone and iPad. There is no account or login. There is no free tier.

The app requires one auto-renewing subscription to use the keyboard, including Fix. Monthly and yearly are two prices for that same product. A 14-day free trial is the introductory offer configured in App Store Connect. The app shows trial wording only when StoreKit reports an offer and the Sandbox account is eligible. Config cannot grant access and cannot change the trial length.

On first launch, with no subscription, the app opens on the paywall. It is titled access: keyboard. It lists both plans with the price, period, and renewal terms from StoreKit, plus auto-renew wording, Manage Subscriptions, Restore Purchases, the Privacy Policy (https://access-keyboard.vercel.app/privacy.html), and Terms of Use (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).

Subscription group: access: keyboard.
Products: app.access.keyboard.6M3Z27M69P.pro.monthly (£1.99 per month) and app.access.keyboard.6M3Z27M69P.pro.yearly (£19.99 per year). Both auto-renew until cancelled. The product IDs contain “.pro.”; the offering is not a separate Pro tier.

Sandbox path: Settings → Developer → Sandbox Apple Account, or sign in when the paywall asks. Start the free trial or buy either plan. Restore Purchases is on the same screen. After the subscription is active, the Type screen, Settings, and About are available. Tap Fix on the Type screen and choose Allow. Consent (Allow / Not now) is asked only after the entitlement check, and only for an active subscription or trial.

The keyboard will not appear in other apps until the reviewer adds it:
Settings → General → Keyboard → Keyboards → Add New Keyboard… → access: keyboard.
Then open that keyboard and turn on Allow Full Access.

Without a subscription, or with Allow Full Access off, the system keyboard does not show a blank view and does not show a purchase screen. It shows: “Start your free trial in the access: keyboard app to use this keyboard.”, a button that opens this app (accesskeyboard://subscribe), and a globe (Next Keyboard) key that switches to another keyboard. That globe key stays available so the reviewer is not trapped. With Full Access off, the same panel also asks the reviewer to turn on Allow Full Access so the keyboard can see the subscription.

Full Access is used for three things:
1. Let the keyboard extension read the subscription record in App Group group.6M3Z27M69P.app.access.keyboard.
2. Share colour and layout settings, and on-device learned predictions (PredictionMemory), through that App Group.
3. Let the extension call the Fix proxy at https://access-keyboard.vercel.app/api/fix.

The containing app verifies Transaction.currentEntitlements, listens to Transaction.updates, finishes transactions, and writes active, product, and expiry into that App Group. It refreshes that record on launch and when the app returns to the foreground. The keyboard only reads the record. A missing or expired record means not subscribed.

Keystrokes are not sent off the device. Tapping Fix sends the current field’s text only after the reviewer taps Allow. That choice can be turned off in the app’s Settings (Allow Fix to send text). The proxy forwards that field to OpenAI with store disabled and does not keep the text. Password fields are skipped. If there is no network, Fix shows a short hint and does not change the field. With no network, an already subscribed keyboard still types.

Demo: open the app, start the sandbox trial or subscribe, type on the Type screen, then try Fix and choose Allow. Add the keyboard in Settings, turn on Allow Full Access, and switch to it with the globe key. To see the locked state, use a Sandbox account with no subscription, or turn Allow Full Access off.
```

## App Review information

| Field | Value |
| --- | --- |
| Sign-in required | No |
| Contact | `mike@accesstechnology.co.uk` |
| Notes | The block above |
| Devices | iPhone and iPad. If the App Store Connect record was created as iPad-only, an admin must turn on iPhone availability. The binary is already universal. |

## Export compliance

`ITSAppUsesNonExemptEncryption = NO`. If App Store Connect asks: **No**, the app does not use non-exempt encryption. Fix uses the system HTTPS stack.

## Feature flags the reviewer will hit

| Flag | Default | Where |
| --- | --- | --- |
| `FeatureFlags.fixConsentRequired` | on | `Packages/AccessKeyboardCore/Sources/AccessKeyboardCore/FeatureFlags.swift` |
| `SubscriptionConfig.monetization` | `.allSubscribed` | `Packages/AccessKeyboardCore/Sources/AccessKeyboardCore/SubscriptionConfig.swift` |
| `SubscriptionConfig.showTrialHeadlineDefault` | on | same file; remote `config.json` can hide the headline only |

Beth mode is listed in Settings under the name Beth. `BethColorMap` supplies the colours.
