"""Fee math and webhook signature checks. No network."""

import hashlib
import hmac
import os
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))

from server import price_card_charge, verify_stripe_signature  # noqa: E402


def test_ten_dollars():
    priced = price_card_charge(1000)
    assert priced["platform_fee_usd_cents"] == 115, priced
    assert priced["total_usd_cents"] == 1180, priced
    assert priced["stripe_fee_usd_cents"] == 65, priced
    assert (
        priced["order_usd_cents"]
        + priced["platform_fee_usd_cents"]
        + priced["stripe_fee_usd_cents"]
        == priced["total_usd_cents"]
    )


def test_signature():
    secret = "whsec_test"
    payload = b'{"id":"evt_1"}'
    stamp = str(int(time.time()))
    signed = stamp.encode() + b"." + payload
    digest = hmac.new(secret.encode(), signed, hashlib.sha256).hexdigest()
    header = f"t={stamp},v1={digest}"
    assert verify_stripe_signature(payload, header, secret)
    assert not verify_stripe_signature(payload, header, "whsec_other")
    assert not verify_stripe_signature(payload, f"t={int(stamp) - 9999},v1={digest}", secret)


if __name__ == "__main__":
    test_ten_dollars()
    test_signature()
    print("ok")
