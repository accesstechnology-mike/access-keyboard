#!/usr/bin/env python3
"""Create the access: keyboard Pro products in App Store Connect.

DRY RUN BY DEFAULT. Without --apply this only prints what it would create and
makes no requests at all. With --apply it reads prices from App Store Connect
and creates products, so only run it once Mike has said to.

Products (defaults confirmed by Mike on 19 Oct 2026; change them below or with
flags):

  Subscription group "access: keyboard Pro"
    <bundle>.pro.monthly   1 month   GBP 3.99   14-day free trial
    <bundle>.pro.yearly    1 year    GBP 29.99  14-day free trial
  Non-consumable
    <bundle>.pro.lifetime  one time  GBP 79.99  no trial

The UK (GBR) is the base territory. Other territories get Apple's equalised
price for the same price point. Credentials come from AppStoreConnect.env, as
for scripts/app_store_connect.py.

Before --apply: the Paid Apps agreement must be active, and the app record
(6803257519) must exist. New products start as "Missing Metadata" until a
review screenshot is added in App Store Connect; this script does not upload
one and does not submit anything for review.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from decimal import Decimal

BUNDLE_ID = "app.access.keyboard.6M3Z27M69P"
BASE_TERRITORY = "GBR"
GROUP_REFERENCE_NAME = "access: keyboard Pro"
LOCALES = ("en-GB", "en-US")

MONTHLY_PRICE_GBP = Decimal("3.99")
YEARLY_PRICE_GBP = Decimal("29.99")
LIFETIME_PRICE_GBP = Decimal("79.99")
# A free trial on both subscriptions. Set to None for no trial.
TRIAL_DURATION = "TWO_WEEKS"  # SubscriptionOfferDuration in the ASC API
FREE_FIXES_PER_MONTH = 30
PRO_FIXES_PER_DAY = 100

REVIEW_NOTE = (
    "The keyboard and predictions are free. Fix (AI correction of the current "
    f"paragraph) is free for {FREE_FIXES_PER_MONTH} uses a month. Pro removes the "
    f"monthly limit, with a fair-use cap of {PRO_FIXES_PER_DAY} a day. Buy or "
    "redeem in the app: Settings > Pro."
)


@dataclass
class Product:
    product_id: str
    reference_name: str
    kind: str  # "subscription" or "non_consumable"
    price_gbp: Decimal
    display_name: str
    description: str
    period: str | None = None
    group_level: int | None = None
    trial: str | None = None
    family_sharable: bool = False
    localizations: dict[str, tuple[str, str]] = field(default_factory=dict)


def products(
    bundle_id: str = BUNDLE_ID,
    monthly: Decimal = MONTHLY_PRICE_GBP,
    yearly: Decimal = YEARLY_PRICE_GBP,
    lifetime: Decimal = LIFETIME_PRICE_GBP,
    trial: str | None = TRIAL_DURATION,
) -> list[Product]:
    items = [
        Product(
            f"{bundle_id}.pro.yearly", "Pro Yearly", "subscription", yearly,
            "Pro Yearly", f"Up to {PRO_FIXES_PER_DAY} Fixes a day, billed yearly.",
            period="ONE_YEAR", group_level=1, trial=trial,
        ),
        Product(
            f"{bundle_id}.pro.monthly", "Pro Monthly", "subscription", monthly,
            "Pro Monthly", f"Up to {PRO_FIXES_PER_DAY} Fixes a day, billed monthly.",
            period="ONE_MONTH", group_level=2, trial=trial,
        ),
        Product(
            f"{bundle_id}.pro.lifetime", "Pro Lifetime", "non_consumable", lifetime,
            "Pro Lifetime", f"Up to {PRO_FIXES_PER_DAY} Fixes a day. Pay once.",
        ),
    ]
    for item in items:
        # App Store limits: display name 30 characters, description 45.
        assert len(item.display_name) <= 30, item.display_name
        assert len(item.description) <= 45, item.description
        item.localizations = {locale: (item.display_name, item.description) for locale in LOCALES}
    return items


def plan_lines(items: list[Product]) -> list[str]:
    lines = [f"Subscription group: {GROUP_REFERENCE_NAME} (localised name '{GROUP_REFERENCE_NAME}')"]
    for item in items:
        trial = f", free trial {item.trial}" if item.trial else ", no trial"
        period = f", {item.period}" if item.period else ""
        lines.append(
            f"{item.kind}: {item.product_id} '{item.reference_name}'{period}, "
            f"GBP {item.price_gbp} in {BASE_TERRITORY} (equalised elsewhere){trial}; "
            f"locales {', '.join(item.localizations)}"
        )
    return lines


def pick_price_point(points: list[dict], price: Decimal) -> str:
    """The price point whose customerPrice is exactly `price`. No rounding guesses."""
    for point in points:
        raw = (point.get("attributes") or {}).get("customerPrice")
        if raw is not None and Decimal(str(raw)) == price:
            return point["id"]
    near = sorted(
        {Decimal(str(p["attributes"]["customerPrice"])) for p in points if p.get("attributes")},
        key=lambda value: abs(value - price),
    )[:3]
    raise SystemExit(f"No {BASE_TERRITORY} price point at exactly {price}. Nearest: {near}")


def ref(kind: str, ident: str) -> dict:
    return {"data": {"type": kind, "id": ident}}


class Creator:
    """Thin wrapper so tests can inject a fake request function."""

    def __init__(self, request, collect, token: str):
        self.request = request
        self.collect = collect
        self.token = token

    def post(self, path: str, body: dict) -> dict:
        return self.request(self.token, path, method="POST", body=body)["data"]

    def existing_product_ids(self, app_id: str) -> set[str]:
        found: set[str] = set()
        iaps, _ = self.collect(self.token, f"/v1/apps/{app_id}/inAppPurchasesV2", {"limit": "200"})
        found.update(i["attributes"]["productId"] for i in iaps)
        groups, _ = self.collect(self.token, f"/v1/apps/{app_id}/subscriptionGroups", {"limit": "200"})
        for group in groups:
            subs, _ = self.collect(self.token, f"/v1/subscriptionGroups/{group['id']}/subscriptions", {"limit": "200"})
            found.update(s["attributes"]["productId"] for s in subs)
        return found

    def territories(self) -> list[str]:
        items, _ = self.collect(self.token, "/v1/territories", {"limit": "200"})
        return [item["id"] for item in items]

    def create_group(self, app_id: str) -> str:
        group = self.post("/v1/subscriptionGroups", {"data": {
            "type": "subscriptionGroups",
            "attributes": {"referenceName": GROUP_REFERENCE_NAME},
            "relationships": {"app": ref("apps", app_id)},
        }})
        for locale in LOCALES:
            self.post("/v1/subscriptionGroupLocalizations", {"data": {
                "type": "subscriptionGroupLocalizations",
                "attributes": {"name": GROUP_REFERENCE_NAME, "locale": locale},
                "relationships": {"subscriptionGroup": ref("subscriptionGroups", group["id"])},
            }})
        return group["id"]

    def create_subscription(self, group_id: str, item: Product, territories: list[str]) -> str:
        sub = self.post("/v1/subscriptions", {"data": {
            "type": "subscriptions",
            "attributes": {
                "name": item.reference_name, "productId": item.product_id,
                "subscriptionPeriod": item.period, "groupLevel": item.group_level,
                "familySharable": item.family_sharable, "reviewNote": REVIEW_NOTE,
            },
            "relationships": {"group": ref("subscriptionGroups", group_id)},
        }})
        sid = sub["id"]
        for locale, (name, description) in item.localizations.items():
            self.post("/v1/subscriptionLocalizations", {"data": {
                "type": "subscriptionLocalizations",
                "attributes": {"name": name, "locale": locale, "description": description},
                "relationships": {"subscription": ref("subscriptions", sid)},
            }})
        self.post("/v1/subscriptionAvailabilities", {"data": {
            "type": "subscriptionAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "subscription": ref("subscriptions", sid),
                "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]},
            },
        }})
        points, _ = self.collect(self.token, f"/v1/subscriptions/{sid}/pricePoints",
                                 {"filter[territory]": BASE_TERRITORY, "limit": "8000"})
        base_point = pick_price_point(points, item.price_gbp)
        prices = [(BASE_TERRITORY, base_point)]
        equal, _ = self.collect(self.token, f"/v1/subscriptionPricePoints/{base_point}/equalizations",
                                {"limit": "8000", "include": "territory"})
        prices += [((e.get("relationships") or {}).get("territory", {}).get("data", {}).get("id"), e["id"]) for e in equal]
        for territory, point in prices:
            if territory and territory not in territories:
                continue
            self.post("/v1/subscriptionPrices", {"data": {
                "type": "subscriptionPrices",
                "attributes": {"preserveCurrentPrice": False},
                "relationships": {
                    "subscription": ref("subscriptions", sid),
                    "subscriptionPricePoint": ref("subscriptionPricePoints", point),
                    **({"territory": ref("territories", territory)} if territory else {}),
                },
            }})
        if item.trial:
            for territory in territories:
                self.post("/v1/subscriptionIntroductoryOffers", {"data": {
                    "type": "subscriptionIntroductoryOffers",
                    "attributes": {"duration": item.trial, "offerMode": "FREE_TRIAL", "numberOfPeriods": 1},
                    "relationships": {
                        "subscription": ref("subscriptions", sid),
                        "territory": ref("territories", territory),
                    },
                }})
        return sid

    def create_non_consumable(self, app_id: str, item: Product, territories: list[str]) -> str:
        iap = self.post("/v2/inAppPurchases", {"data": {
            "type": "inAppPurchases",
            "attributes": {
                "name": item.reference_name, "productId": item.product_id,
                "inAppPurchaseType": "NON_CONSUMABLE", "reviewNote": REVIEW_NOTE,
                "familySharable": item.family_sharable,
            },
            "relationships": {"app": ref("apps", app_id)},
        }})
        iid = iap["id"]
        for locale, (name, description) in item.localizations.items():
            self.post("/v1/inAppPurchaseLocalizations", {"data": {
                "type": "inAppPurchaseLocalizations",
                "attributes": {"name": name, "locale": locale, "description": description},
                "relationships": {"inAppPurchaseV2": ref("inAppPurchases", iid)},
            }})
        self.post("/v1/inAppPurchaseAvailabilities", {"data": {
            "type": "inAppPurchaseAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "inAppPurchase": ref("inAppPurchases", iid),
                "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]},
            },
        }})
        points, _ = self.collect(self.token, f"/v2/inAppPurchases/{iid}/pricePoints",
                                 {"filter[territory]": BASE_TERRITORY, "limit": "8000"})
        point = pick_price_point(points, item.price_gbp)
        # One manual price in the base territory; Apple equalises the rest.
        self.post("/v1/inAppPurchasePriceSchedules", {
            "data": {
                "type": "inAppPurchasePriceSchedules",
                "relationships": {
                    "inAppPurchase": ref("inAppPurchases", iid),
                    "baseTerritory": ref("territories", BASE_TERRITORY),
                    "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${base}"}]},
                },
            },
            "included": [{
                "type": "inAppPurchasePrices", "id": "${base}",
                "attributes": {"startDate": None},
                "relationships": {
                    "inAppPurchaseV2": ref("inAppPurchases", iid),
                    "inAppPurchasePricePoint": ref("inAppPurchasePricePoints", point),
                },
            }],
        })
        return iid


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--apply", action="store_true", help="Really create the products. Default is a dry run.")
    parser.add_argument("--monthly", type=Decimal, default=MONTHLY_PRICE_GBP)
    parser.add_argument("--yearly", type=Decimal, default=YEARLY_PRICE_GBP)
    parser.add_argument("--lifetime", type=Decimal, default=LIFETIME_PRICE_GBP)
    parser.add_argument("--no-trial", action="store_true", help="Create the subscriptions without a free trial.")
    args = parser.parse_args(argv)

    items = products(monthly=args.monthly, yearly=args.yearly, lifetime=args.lifetime,
                     trial=None if args.no_trial else TRIAL_DURATION)
    print("\n".join(plan_lines(items)))
    if not args.apply:
        print("\nDry run: nothing was sent to App Store Connect. Re-run with --apply to create these.")
        return 0

    import app_store_connect as asc  # credentials and HTTP helpers

    token = asc.fresh_token()
    creator = Creator(asc.asc_request, asc.collect_resources, token)
    app_id = asc.app_id(token, BUNDLE_ID)
    existing = creator.existing_product_ids(app_id)
    clash = [item.product_id for item in items if item.product_id in existing]
    if clash:
        print(f"Already in App Store Connect, not touching anything: {', '.join(clash)}")
        return 1
    territories = creator.territories()
    group_id = creator.create_group(app_id)
    for item in items:
        if item.kind == "subscription":
            creator.create_subscription(group_id, item, territories)
        else:
            creator.create_non_consumable(app_id, item, territories)
        print(f"Created {item.product_id}")
    print("Done. Add a review screenshot to each product in App Store Connect before submitting.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
