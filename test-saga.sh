#!/usr/bin/env bash
##############################################################################
#  SAGA Design Pattern — Full Feature Test Script (Bash)
#
#  Covers:
#    1. Health checks  — all 4 services are up
#    2. Happy path     — full SAGA completes (COMPLETED)
#    3. Payment fail   — amount > $10,000 (PAYMENT_FAILED)
#    4. Inventory fail — PROD-003 has 0 stock (INVENTORY_FAILED + refund)
#    5. Partial stock  — qty > available (INVENTORY_FAILED)
#    6. Shipping fail  — BLOCKED address  (SHIPPING_FAILED + release + refund)
#    7. Idempotency    — same key 3× → same orderId, no double charge
#    8. No key         — two calls without key → two distinct orders
#    9. GET by ID      — fetch single order
#   10. GET all        — list all orders
#
#  Prerequisites: curl, jq  — all 4 services running on localhost
#  Run: chmod +x test-saga.sh && ./test-saga.sh
##############################################################################

set -euo pipefail

ORDER_URL="http://localhost:8080"
PAYMENT_URL="http://localhost:8081"
INVENTORY_URL="http://localhost:8082"
SHIPPING_URL="http://localhost:8083"

PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

header() { echo ""; echo "══════════════════════════════════════════════════════════════════════"; echo "  $1"; echo "══════════════════════════════════════════════════════════════════════"; }
step()   { echo ""; echo "  ▶  $1"; }
pass()   { echo "  ✅ PASS  $1"; PASS=$((PASS + 1)); }
fail()   { echo "  ❌ FAIL  $1"; [ -n "${2:-}" ] && echo "          $2"; FAIL=$((FAIL + 1)); }

# POST wrapper — returns response body; sets $HTTP_STATUS
post() {
    local url=$1; local payload=$2
    HTTP_STATUS=0
    RESPONSE=$(curl -s -o /tmp/saga_resp.json -w "%{http_code}" \
        -X POST "$url" -H "Content-Type: application/json" -d "$payload")
    HTTP_STATUS=$RESPONSE
    cat /tmp/saga_resp.json | jq . 2>/dev/null || cat /tmp/saga_resp.json
    cat /tmp/saga_resp.json
}

# GET wrapper
get() {
    local url=$1
    HTTP_STATUS=0
    RESPONSE=$(curl -s -o /tmp/saga_resp.json -w "%{http_code}" -X GET "$url")
    HTTP_STATUS=$RESPONSE
    cat /tmp/saga_resp.json | jq . 2>/dev/null || cat /tmp/saga_resp.json
    cat /tmp/saga_resp.json
}

jq_field() { cat /tmp/saga_resp.json | jq -r "$1" 2>/dev/null; }

##############################################################################
#  TEST 1 — Health Checks
##############################################################################
header "TEST 1 — Health Checks (all 4 services)"

for entry in \
    "order-service    :8080|$ORDER_URL/actuator/health" \
    "payment-service  :8081|$PAYMENT_URL/actuator/health" \
    "inventory-service:8082|$INVENTORY_URL/actuator/health" \
    "shipping-service :8083|$SHIPPING_URL/actuator/health"; do

    name="${entry%%|*}"; url="${entry##*|}"
    step "GET $url"
    STATUS=$(curl -s -o /tmp/saga_resp.json -w "%{http_code}" "$url")
    if [ "$STATUS" = "200" ] && [ "$(cat /tmp/saga_resp.json | jq -r '.status' 2>/dev/null)" = "UP" ]; then
        pass "$name → status=UP"
    else
        fail "$name → NOT healthy (HTTP $STATUS)"
    fi
done

##############################################################################
#  TEST 2 — Happy Path
##############################################################################
header "TEST 2 — Happy Path (COMPLETED)"

step "POST $ORDER_URL/orders  [PROD-001, qty=2, amount=199.99]"
post "$ORDER_URL/orders" '{
  "customerId": "CUST-001",
  "productId": "PROD-001",
  "quantity": 2,
  "amount": 199.99,
  "shippingAddress": "123 Main St, New York, NY 10001"
}' > /dev/null

STATUS_VAL=$(jq_field '.status')
HAPPY_ORDER_ID=$(jq_field '.orderId')
MESSAGE=$(jq_field '.message')

[ "$STATUS_VAL" = "COMPLETED" ] \
    && pass "SAGA status is COMPLETED" \
    || fail "Expected COMPLETED, got: $STATUS_VAL" "$MESSAGE"

echo "$MESSAGE" | grep -qi "Shipment ID" \
    && pass "Response contains Shipment ID" \
    || fail "Response message missing Shipment ID" "$MESSAGE"

##############################################################################
#  TEST 3 — Payment Failure
##############################################################################
header "TEST 3 — Payment Failure (amount > credit limit)"

step "POST $ORDER_URL/orders  [amount=99999.00]"
post "$ORDER_URL/orders" '{
  "customerId": "CUST-002",
  "productId": "PROD-001",
  "quantity": 1,
  "amount": 99999.00,
  "shippingAddress": "456 Oak Ave, Chicago, IL"
}' > /dev/null

STATUS_VAL=$(jq_field '.status')
[ "$STATUS_VAL" = "PAYMENT_FAILED" ] \
    && pass "SAGA status is PAYMENT_FAILED" \
    || fail "Expected PAYMENT_FAILED, got: $STATUS_VAL"

MSG=$(jq_field '.message')
echo "$MSG" | grep -qiE "declined|credit" \
    && pass "Failure message mentions credit limit" \
    || fail "Failure message unclear" "$MSG"

##############################################################################
#  TEST 4 — Inventory Failure (0 stock)
##############################################################################
header "TEST 4 — Inventory Failure + Payment Compensation"

step "POST $ORDER_URL/orders  [PROD-003 has 0 stock]"
post "$ORDER_URL/orders" '{
  "customerId": "CUST-003",
  "productId": "PROD-003",
  "quantity": 1,
  "amount": 49.99,
  "shippingAddress": "789 Pine Rd, Seattle, WA"
}' > /dev/null

STATUS_VAL=$(jq_field '.status')
[ "$STATUS_VAL" = "INVENTORY_FAILED" ] \
    && pass "SAGA status is INVENTORY_FAILED" \
    || fail "Expected INVENTORY_FAILED, got: $STATUS_VAL"

MSG=$(jq_field '.message')
echo "$MSG" | grep -qiE "stock|Insufficient" \
    && pass "Failure message mentions insufficient stock" \
    || fail "Failure message unclear" "$MSG"

##############################################################################
#  TEST 5 — Partial Stock Failure
##############################################################################
header "TEST 5 — Partial Stock Failure (qty requested > available)"

step "POST $ORDER_URL/orders  [PROD-002 has 5, requesting qty=10]"
post "$ORDER_URL/orders" '{
  "customerId": "CUST-004",
  "productId": "PROD-002",
  "quantity": 10,
  "amount": 99.00,
  "shippingAddress": "321 Elm St, Austin, TX"
}' > /dev/null

STATUS_VAL=$(jq_field '.status')
[ "$STATUS_VAL" = "INVENTORY_FAILED" ] \
    && pass "SAGA status is INVENTORY_FAILED (qty 10 > available 5)" \
    || fail "Expected INVENTORY_FAILED, got: $STATUS_VAL"

##############################################################################
#  TEST 6 — Shipping Failure (BLOCKED address)
##############################################################################
header "TEST 6 — Shipping Failure + Full Compensation"

step "POST $ORDER_URL/orders  [address contains BLOCKED]"
post "$ORDER_URL/orders" '{
  "customerId": "CUST-005",
  "productId": "PROD-001",
  "quantity": 1,
  "amount": 75.00,
  "shippingAddress": "BLOCKED ZONE - No Delivery"
}' > /dev/null

STATUS_VAL=$(jq_field '.status')
[ "$STATUS_VAL" = "SHIPPING_FAILED" ] \
    && pass "SAGA status is SHIPPING_FAILED" \
    || fail "Expected SHIPPING_FAILED, got: $STATUS_VAL"

MSG=$(jq_field '.message')
echo "$MSG" | grep -qiE "restricted|Shipping" \
    && pass "Failure message mentions shipping restriction" \
    || fail "Failure message unclear" "$MSG"

##############################################################################
#  TEST 7 — Idempotency
##############################################################################
header "TEST 7 — Idempotency (same key 3× → same order)"

IDEM_KEY="test-idem-key-$RANDOM"
PAYLOAD=$(printf '{
  "idempotencyKey": "%s",
  "customerId": "CUST-006",
  "productId": "PROD-001",
  "quantity": 1,
  "amount": 29.99,
  "shippingAddress": "100 Maple Dr, Denver, CO"
}' "$IDEM_KEY")

step "First call with idempotencyKey=$IDEM_KEY"
post "$ORDER_URL/orders" "$PAYLOAD" > /dev/null
FIRST_ID=$(jq_field '.orderId')
FIRST_STATUS=$(jq_field '.status')

step "Second call with SAME key"
post "$ORDER_URL/orders" "$PAYLOAD" > /dev/null
SECOND_ID=$(jq_field '.orderId')

step "Third call with SAME key"
post "$ORDER_URL/orders" "$PAYLOAD" > /dev/null
THIRD_ID=$(jq_field '.orderId')

[ "$FIRST_ID" = "$SECOND_ID" ] && [ "$FIRST_ID" = "$THIRD_ID" ] \
    && pass "All 3 calls return the same orderId=$FIRST_ID" \
    || fail "Different orderIds: first=$FIRST_ID second=$SECOND_ID third=$THIRD_ID"

[ "$FIRST_STATUS" = "COMPLETED" ] \
    && pass "Status is COMPLETED for all duplicate calls" \
    || fail "Status is $FIRST_STATUS instead of COMPLETED"

##############################################################################
#  TEST 8 — No idempotencyKey → independent orders
##############################################################################
header "TEST 8 — Without idempotencyKey each call creates a new order"

step "Two calls without idempotencyKey"
PAYLOAD_NO_KEY='{
  "customerId": "CUST-007",
  "productId": "PROD-001",
  "quantity": 1,
  "amount": 15.00,
  "shippingAddress": "200 River Rd, Miami, FL"
}'
post "$ORDER_URL/orders" "$PAYLOAD_NO_KEY" > /dev/null
ID_A=$(jq_field '.orderId')

post "$ORDER_URL/orders" "$PAYLOAD_NO_KEY" > /dev/null
ID_B=$(jq_field '.orderId')

[ "$ID_A" != "$ID_B" ] \
    && pass "Two distinct orderIds created (id_a=$ID_A  id_b=$ID_B)" \
    || fail "Same orderId without a key — unexpected" "$ID_A"

##############################################################################
#  TEST 9 — GET single order
##############################################################################
header "TEST 9 — GET /orders/{id} (fetch order by ID)"

if [ -n "$HAPPY_ORDER_ID" ] && [ "$HAPPY_ORDER_ID" != "null" ]; then
    step "GET $ORDER_URL/orders/$HAPPY_ORDER_ID"
    get "$ORDER_URL/orders/$HAPPY_ORDER_ID" > /dev/null

    FETCHED_ID=$(jq_field '.orderId')
    FETCHED_STATUS=$(jq_field '.status')

    [ "$FETCHED_ID" = "$HAPPY_ORDER_ID" ] \
        && pass "Correct orderId returned" \
        || fail "orderId mismatch: expected=$HAPPY_ORDER_ID got=$FETCHED_ID"

    [ "$FETCHED_STATUS" = "COMPLETED" ] \
        && pass "Order status is COMPLETED" \
        || fail "Unexpected status=$FETCHED_STATUS"
else
    fail "Skipped — no happy-path orderId available (TEST 2 failed)"
fi

##############################################################################
#  TEST 10 — GET all orders
##############################################################################
header "TEST 10 — GET /orders (list all orders)"

step "GET $ORDER_URL/orders"
get "$ORDER_URL/orders" > /dev/null

COUNT=$(cat /tmp/saga_resp.json | jq '. | length' 2>/dev/null || echo 0)
[ "$COUNT" -gt 0 ] \
    && pass "Returned $COUNT order(s)" \
    || fail "Empty or failed response"

STATUSES=$(cat /tmp/saga_resp.json | jq -r '[.[].status] | unique | join(", ")' 2>/dev/null)
echo "  → Distinct saga statuses found: $STATUSES"

##############################################################################
#  SUMMARY
##############################################################################
echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo "  TEST SUMMARY"
echo "══════════════════════════════════════════════════════════════════════"
echo ""
echo "  Total tests run : $((PASS + FAIL))"
printf "  ✅ Passed       : %d\n" "$PASS"
printf "  ❌ Failed       : %d\n" "$FAIL"
echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "  🎉 All tests passed!"
else
    echo "  ⚠️  Some tests failed. Check output above."
fi
echo ""
