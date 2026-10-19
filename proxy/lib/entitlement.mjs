// Who is asking for a Fix, from Apple-signed StoreKit data the app sends.
//
//   X-AK-Transaction      signed transaction (JWS) for Pro: monthly, yearly or Lifetime
//   X-AK-App-Transaction  signed app transaction (JWS); appTransactionId keys the free tier
//
// Signatures are checked against Apple's root certificate with Apple's
// App Store Server Library, so a client cannot invent Pro.

import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import { APPLE_ROOT_CA_G3_BASE64 } from "./apple-root-ca-g3.mjs";

export const TRANSACTION_HEADER = "x-ak-transaction";
export const APP_TRANSACTION_HEADER = "x-ak-app-transaction";

export class EntitlementError extends Error {
  constructor(code, message) {
    super(message ?? code);
    this.code = code;
  }
}

export function appleRootCertificates() {
  return [Buffer.from(APPLE_ROOT_CA_G3_BASE64, "base64")];
}

/** Production first, then Sandbox (TestFlight) when allowed. */
export function createAppleVerifier(config, roots = appleRootCertificates()) {
  const verifiers = [
    new SignedDataVerifier(roots, config.appleOnlineChecks, Environment.PRODUCTION, config.bundleId, config.appAppleId),
  ];
  if (config.allowSandbox) {
    verifiers.push(new SignedDataVerifier(roots, config.appleOnlineChecks, Environment.SANDBOX, config.bundleId));
  }
  async function firstValid(fn) {
    let lastError;
    for (const verifier of verifiers) {
      try {
        return await fn(verifier);
      } catch (error) {
        lastError = error;
      }
    }
    throw new EntitlementError("invalid_signature", lastError?.message);
  }
  return {
    transaction: (jws) => firstValid((v) => v.verifyAndDecodeTransaction(jws)),
    appTransaction: (jws) => firstValid((v) => v.verifyAndDecodeAppTransaction(jws)),
  };
}

/**
 * Returns { tier: "pro" | "free", id, productId? } for a request with signed
 * StoreKit data, null when the request has none (legacy builds), or throws
 * EntitlementError when what was sent does not verify.
 */
export async function resolveIdentity(request, verifier, config, now = Date.now()) {
  const signedTransaction = request.headers.get(TRANSACTION_HEADER)?.trim();
  const signedAppTransaction = request.headers.get(APP_TRANSACTION_HEADER)?.trim();
  if (!signedTransaction && !signedAppTransaction) return null;

  if (signedTransaction) {
    const transaction = await verifier.transaction(signedTransaction);
    const pro = proFromTransaction(transaction, config, now);
    if (pro) return pro;
    // An expired or revoked plan falls back to the free tier below.
  }
  if (!signedAppTransaction) {
    throw new EntitlementError("not_pro", "The transaction is not active Pro and no app transaction was sent.");
  }
  const appTransaction = await verifier.appTransaction(signedAppTransaction);
  const id = appTransaction?.appTransactionId;
  if (!id) throw new EntitlementError("no_app_transaction_id");
  return { tier: "free", id: String(id) };
}

export function proFromTransaction(transaction, config, now = Date.now()) {
  const productId = transaction?.productId;
  if (!productId || transaction.revocationDate) return null;
  const id = String(transaction.originalTransactionId ?? transaction.transactionId ?? "");
  if (!id) return null;
  if (config.lifetimeProductIds.has(productId)) {
    return { tier: "pro", id, productId };
  }
  if (config.subscriptionProductIds.has(productId)) {
    const expires = Number(transaction.expiresDate ?? 0);
    if (expires > now) return { tier: "pro", id, productId };
  }
  return null;
}
