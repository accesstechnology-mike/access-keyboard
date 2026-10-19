import io
import unittest
from contextlib import redirect_stdout
from decimal import Decimal

import asc_create_products as acp


class ProductPlanTests(unittest.TestCase):
    def test_defaults_match_confirmed_pricing(self):
        items = {i.product_id.rsplit(".", 1)[-1]: i for i in acp.products()}
        self.assertEqual(items["monthly"].price_gbp, Decimal("3.99"))
        self.assertEqual(items["yearly"].price_gbp, Decimal("29.99"))
        self.assertEqual(items["lifetime"].price_gbp, Decimal("79.99"))
        self.assertEqual(items["monthly"].trial, "TWO_WEEKS")
        self.assertEqual(items["yearly"].trial, "TWO_WEEKS")
        self.assertIsNone(items["lifetime"].trial)
        self.assertEqual(items["lifetime"].kind, "non_consumable")
        self.assertEqual(items["monthly"].product_id, "app.access.keyboard.6M3Z27M69P.pro.monthly")

    def test_dry_run_makes_no_requests(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(acp.main([]), 0)
        self.assertIn("Dry run", out.getvalue())
        self.assertIn("GBP 79.99", out.getvalue())

    def test_no_trial_flag(self):
        self.assertTrue(all(i.trial is None for i in acp.products(trial=None)))

    def test_price_point_must_match_exactly(self):
        points = [{"id": "a", "attributes": {"customerPrice": "3.99"}},
                  {"id": "b", "attributes": {"customerPrice": "4.49"}}]
        self.assertEqual(acp.pick_price_point(points, Decimal("3.99")), "a")
        with self.assertRaises(SystemExit):
            acp.pick_price_point(points, Decimal("3.89"))

    def test_lifetime_flow_posts_one_base_territory_price(self):
        posts = []

        def request(token, path, params=None, method="GET", body=None):
            posts.append((path, body))
            return {"data": {"id": f"id{len(posts)}"}}

        def collect(token, path, params=None):
            return [{"id": "pp7999", "attributes": {"customerPrice": "79.99"}}], []

        creator = acp.Creator(request, collect, "t")
        lifetime = [i for i in acp.products() if i.kind == "non_consumable"][0]
        creator.create_non_consumable("app", lifetime, ["GBR", "USA"])
        paths = [p for p, _ in posts]
        self.assertEqual(paths[0], "/v2/inAppPurchases")
        self.assertEqual(posts[0][1]["data"]["attributes"]["inAppPurchaseType"], "NON_CONSUMABLE")
        schedule = posts[-1][1]
        self.assertEqual(posts[-1][0], "/v1/inAppPurchasePriceSchedules")
        self.assertEqual(schedule["included"][0]["relationships"]["inAppPurchasePricePoint"]["data"]["id"], "pp7999")

    def test_subscription_flow_adds_trial_per_territory(self):
        posts = []

        def request(token, path, params=None, method="GET", body=None):
            posts.append((path, body))
            return {"data": {"id": f"id{len(posts)}"}}

        def collect(token, path, params=None):
            if path.endswith("/equalizations"):
                return [{"id": "usa399", "relationships": {"territory": {"data": {"id": "USA"}}}}], []
            return [{"id": "gbr399", "attributes": {"customerPrice": "3.99"}}], []

        creator = acp.Creator(request, collect, "t")
        monthly = [i for i in acp.products() if i.product_id.endswith("monthly")][0]
        creator.create_subscription("g", monthly, ["GBR", "USA"])
        prices = [b for p, b in posts if p == "/v1/subscriptionPrices"]
        self.assertEqual([b["data"]["relationships"]["subscriptionPricePoint"]["data"]["id"] for b in prices], ["gbr399", "usa399"])
        offers = [b for p, b in posts if p == "/v1/subscriptionIntroductoryOffers"]
        self.assertEqual(len(offers), 2)
        self.assertEqual(offers[0]["data"]["attributes"]["offerMode"], "FREE_TRIAL")


if __name__ == "__main__":
    unittest.main()
