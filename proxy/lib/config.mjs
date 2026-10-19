// Fix proxy settings. Every limit and price-related number is an env var with
// the default Mike confirmed on 19 Oct 2026, so it can change without a deploy
// of new code.

function int(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === "") return fallback;
  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function bool(name, fallback) {
  const raw = process.env[name]?.trim().toLowerCase();
  if (!raw) return fallback;
  return ["1", "true", "yes", "on"].includes(raw);
}

export function loadConfig() {
  const bundleId = process.env.APPLE_BUNDLE_ID?.trim() || "app.access.keyboard.6M3Z27M69P";
  const lifetime = process.env.PRO_LIFETIME_PRODUCT_IDS?.trim() || `${bundleId}.pro.lifetime`;
  const subscriptions =
    process.env.PRO_SUBSCRIPTION_PRODUCT_IDS?.trim() || `${bundleId}.pro.monthly,${bundleId}.pro.yearly`;
  return {
    bundleId,
    // App Store Connect app id (Apple ID) of access: keyboard. Needed to verify
    // Production signed data.
    appAppleId: int("APPLE_APP_APPLE_ID", 6803257519),
    // TestFlight and Xcode sandbox purchases are signed for Sandbox.
    allowSandbox: bool("FIX_ALLOW_SANDBOX", true),
    appleOnlineChecks: bool("FIX_APPLE_ONLINE_CHECKS", true),
    lifetimeProductIds: new Set(lifetime.split(",").map((s) => s.trim()).filter(Boolean)),
    subscriptionProductIds: new Set(subscriptions.split(",").map((s) => s.trim()).filter(Boolean)),
    freeFixesPerMonth: int("FREE_FIXES_PER_MONTH", 30),
    proFixesPerDay: int("PRO_FIXES_PER_DAY", 100),
    perIdentityPerMinute: int("FIX_RATE_PER_MINUTE", 10),
    perIpPerMinute: int("FIX_IP_RATE_PER_MINUTE", 30),
    maxChars: int("FIX_MAX_CHARS", 8000),
    maxOutputTokens: int("FIX_MAX_OUTPUT_TOKENS", 2048),
    // Rollout: builds already on TestFlight only send the shared secret. Turn
    // this off once every live build sends signed StoreKit data.
    allowLegacySecret: bool("FIX_ALLOW_LEGACY_SECRET", true),
    // When true, a missing usage store is a 503 instead of "limits not enforced".
    requireUsageStore: bool("FIX_REQUIRE_USAGE_STORE", false),
  };
}
