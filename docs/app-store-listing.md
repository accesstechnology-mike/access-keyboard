# App Store listing draft: access: keyboard

Version 1.0 build 22 went live on the App Store on 6 Nov 2026. The binary is the universal iPhone and iPad keyboard (`TARGETED_DEVICE_FAMILY = "1,2"`, iOS and iPadOS 18). The next binary in this repo is 1.0.1 build 23. Do not treat an edit here as a change already made in App Store Connect.

Fix ships in v1. `FeatureFlags.fixConsentRequired` is **on**, so the first Fix asks Allow / Not now before any text is sent.

Source for the review notes and privacy answers: `TESTFLIGHT.md`.

## Pricing (confirmed by Mike, 19 Oct 2026)

| | |
| --- | --- |
| Keyboard and predictions | Free, for good. Nothing locks without Pro. |
| Fix, free | 30 Fixes per calendar month, counted by the Fix service per App Store install (`appTransactionId`) |
| Pro Monthly | £3.99 a month, 14-day free trial |
| Pro Yearly | £29.99 a year, 14-day free trial |
| Pro Lifetime | £79.99 once, non-consumable, no trial |
| Pro fair use | Up to 100 Fixes a day |

The app never hard-codes prices or trial wording. The paywall uses StoreKit `displayPrice` and the introductory offer StoreKit returns. The limits live in `SubscriptionConfig` (app copy) and in the Fix service env vars (enforcement; see `proxy/README.md`).

## Shipped with 1.0

Left here so the next version does not rediscover them. Nothing in this list is an instruction to change App Store Connect from this branch.

- **Products.** Live: subscription group `access: keyboard Pro`, `app.access.keyboard.6M3Z27M69P.pro.yearly` (£29.99), `app.access.keyboard.6M3Z27M69P.pro.monthly` (£3.99), each with a 14-day free trial, and non-consumable `app.access.keyboard.6M3Z27M69P.pro.lifetime` (£79.99). `scripts/asc_create_products.py` is a dry run unless `--apply`.
- **Review screenshots.** The in-app purchase screenshots used for 1.0 are on `cursor/app-store-listing-d49e` (`docs/app-store/review/`). The **Review screenshots** workflow is not on `main`. All eight runs on 19 Oct 2026 failed or were cancelled. The last failure (`39274007820`, commit `edc4e93`) was `simctl bootstatus` timing out for iPhone 17 Pro Max and iPad Pro 13-inch (M5) on OS 26.5. Do not re-enable that workflow until a Mac run can boot those simulators.
- **Listing copy that shipped** is in `docs/app-store/`. Subtitle `Large keys for easier typing` (App Review 5.2.5, 28 Oct: no Apple product names in the subtitle, description, or promotional text). Those files were on `cursor/app-store-listing-d49e` and were not on `main`.
- **Free access for chosen people.** Offer codes, once the products are approved. The app has a Redeem Code button on the Pro screen and in Settings.
- **Fix service.** The proxy enforces 30 a month and 100 a day when Upstash is configured (`proxy/README.md`). If the counter is down, an identified Fix is refused with `usage_unavailable` instead of being given away uncounted.
- **Privacy page.** Source `proxy/public/privacy.html`. Live URL `https://access-keyboard.vercel.app/privacy.html`, updated when `main` deploys.

## Identity

| Field | Value |
| --- | --- |
| Name | `access: keyboard` |
| Subtitle | `Large keys for easier typing` |
| Bundle ID | `app.access.keyboard.6M3Z27M69P` |
| SKU | `app.access.keyboard.6M3Z27M69P` |
| Primary category | Utilities |
| Secondary category | Productivity (optional) |
| Primary language | English (UK). The keyboard’s `PrimaryLanguage` is `en-GB`. |
| Copyright | Access Technology North Limited |
| Version | `1.0` is the live App Store version (build 22, 6 Nov 2026). This repo is `1.0.1` build 23, not yet submitted. |
| Price | Free. In-app purchases: Pro Monthly £3.99, Pro Yearly £29.99 (both with a 14-day free trial), Pro Lifetime £79.99. |

Subtitle is 27 characters (limit 30). Name is 16 characters (limit 30). The promotional text and keywords below are the ones that shipped; the files in `docs/app-store/` are the same text.

## Promotional text

170 characters maximum.

```
A free assistive keyboard with large keys and a literacy font. Fix corrects your typing: 30 free Fixes a month, or up to 100 a day with Pro.
```

## Description

The description that shipped is `docs/app-store/description.txt`. It does not name iPhone, iPad, or iOS, which is what App Review 5.2.5 required on 28 Oct 2026. It still says the keyboard and predictions are free, Fix is 30 a month, and Pro is £3.99 a month, £29.99 a year, or Lifetime £79.99.

## Keywords

100 characters maximum, comma-separated. The app name already contains “access” and “keyboard”, so those words are left out.

```
assistive,accessibility,literacy,dyslexia,large keys,high contrast,spelling,grammar,motor,typing
```

## URLs

| Field | Value |
| --- | --- |
| Support URL | `https://www.accesstechnology.co.uk` |
| Marketing URL | Leave blank unless Mike wants the company site here too |
| Privacy Policy URL | `https://access-keyboard.vercel.app/privacy.html` |
| Contact | `mike@accesstechnology.co.uk` |

The privacy page describes the free keyboard, on-device predictions, what Fix sends to OpenAI and when, the signed Apple records used to count Fixes, and the contact address. There was no separate support address elsewhere in the repo.

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

The keyboard does not browse the web, host a social feed, or show ads. Fix sends the current paragraph to OpenAI only after the user taps Fix and Allow; that is app functionality, not unrestricted web access and not content shared with other users. Confirm the labels against the live App Store Connect form if Apple has renamed a row.

## Privacy nutrition label

Tracking: **No**.

| Question | Answer |
| --- | --- |
| Other User Content | Collected, for App Functionality, not linked, not tracking. The paragraph being corrected, only when the user taps Fix, after Allow. |
| Purchases (Purchase History) | Collected, for App Functionality, **linked**, not tracking. Each Fix sends Apple-signed StoreKit data so the service can count use. The service keeps a count keyed by `appTransactionId` or `originalTransactionId` for up to 32 days. Both `PrivacyInfo.xcprivacy` files declare `NSPrivacyCollectedDataTypePurchaseHistory` with linked true. Linked is true because the retained count is stored against that stable Apple identifier. The paragraph text stays Other User Content, not linked. If the live nutrition label says Purchase History is not linked, change the label to match, or say so and the manifest bool can be flipped. This repo does not edit App Store Connect. |
| Third party | Yes. `https://access-keyboard.vercel.app/api/fix` forwards the paragraph to OpenAI with `store` disabled. The service does not keep the text. Ordinary keystrokes stay on the device. Password fields are skipped. |
| Colour settings and learned predictions | On-device only (App Group `group.6M3Z27M69P.app.access.keyboard` and UserDefaults). Not collected. |
| Payment | Handled by Apple. Not collected by the app. |

## App Review notes

The notes that shipped with 1.0 are `docs/app-store/review-notes.txt`. The block below matches them in substance. For 1.0.1, add that predictions default to UK spellings (`en-GB`) and that Fix says when the correction service or its counter is unavailable.

```
access: keyboard is an assistive keyboard for iPhone and iPad. There is no account or login.

The keyboard and predictions are free and never lock. The only paid part is Fix, which sends the paragraph being typed to an AI service (OpenAI) through our server to correct it. Fix is free for 30 uses a month. Pro allows up to 100 a day.

In-app purchases (Pro screen in the app, and Settings > Pro):
- app.access.keyboard.6M3Z27M69P.pro.monthly: auto-renewing, 1 month, 14-day free trial
- app.access.keyboard.6M3Z27M69P.pro.yearly: auto-renewing, 1 year, 14-day free trial
- app.access.keyboard.6M3Z27M69P.pro.lifetime: non-consumable, one payment
Prices and trial wording come from StoreKit. The Pro screen has Restore Purchases, Redeem Code, Manage Subscriptions, the Privacy Policy (https://access-keyboard.vercel.app/privacy.html) and Terms of Use (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/).

To try it: open the app and use the Type screen. Tap Fix and choose Allow. To buy, open Pro and use a Sandbox account.

To use the keyboard in other apps:
Settings > General > Keyboard > Keyboards > Add New Keyboard > access: keyboard. Then turn on Allow Full Access if you want Fix and shared settings. The keyboard types with Full Access off.

Full Access is used to:
1. Share colour and layout settings, and on-device learned predictions, between the app and the keyboard through App Group group.6M3Z27M69P.app.access.keyboard.
2. Let the keyboard read the Apple-signed purchase records the app saves there, and call the Fix service at https://access-keyboard.vercel.app/api/fix.

Keystrokes are not sent off the device. Fix sends only the current paragraph, only after the user taps Fix and Allow. Permission can be taken back in Settings (Allow Fix to send text). Fix also sends Apple-signed StoreKit records so our server can count Fixes; it checks Apple's signature and keeps only a count. If the free Fixes for the month are used up, the keyboard shows a short message and carries on typing. With no network, Fix shows a short hint and does not change the text.
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
| `SubscriptionConfig.monetization` | `.keyboardFreeFixAllowance` (keyboard free, Fix limited by the service) | `Packages/AccessKeyboardCore/Sources/AccessKeyboardCore/SubscriptionConfig.swift` |
| `SubscriptionConfig.showTrialHeadlineDefault` | on | same file; remote `config.json` can hide the headline only |

Beth mode is listed in Settings under the name Beth. `BethColorMap` supplies the colours.
