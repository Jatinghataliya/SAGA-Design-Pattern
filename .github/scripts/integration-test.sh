#!/usr/bin/env bash
# ============================================================
#  SAGA Orchestrator — Integration Tests
#  Hits real HTTP endpoints on order-service:8080
#  Exits non-zero on any assertion failure.
# ============================================================
set -euo pipefail

BASE="http://localhost:8080"
PASS=0
FAIL=0

# ── helper: assert HTTP response body contains a string ─────
assert_contains() {
  local label="$1" body="$2" expected="$3"
  if echo "$body" | grep -q "$expected"; then
    echo "[PASS] $label"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $label"
    echo "       Expected to contain: $expected"
    echo "       Actual body: $body"
    FAIL=$((FAIL + 1))
  fi
}

# ── helper: assert HTTP status code ─────────────────────────
assert_status() {
  local label="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    echo "[PASS] $label (HTTP $actual)"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $label — expected HTTP $expected, got HTTP $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "====================================================="
echo " SAGA Orchestrator Integration Tests"
echo "====================================================="

# ── Test 1: Happy path — payment approved, inventory reserved, shipped ──────
echo ""
echo "--- Test 1: Happy path (PROD-001, amount=99.99) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "idempotencyKey": "integ-test-happy-001",
    "customerId": "CUST-1",
    "productId": "PROD-001",
    "quantity": 1,
    "amount": 99.99,
    "shippingAddress": "123 Test Street"
  }')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "Happy path HTTP status" "$STATUS" "201"
assert_contains "Happy path status=COMPLETED" "$BODY" "COMPLETED"

# ── Test 2: Payment declined — amount exceeds credit limit ──────────────────
echo ""
echo "--- Test 2: Payment declined (amount=99999) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "idempotencyKey": "integ-test-payment-declined-001",
    "customerId": "CUST-2",
    "productId": "PROD-001",
    "quantity": 1,
    "amount": 99999,
    "shippingAddress": "456 Test Avenue"
  }')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "Payment declined HTTP status" "$STATUS" "400"
assert_contains "Payment declined status=FAILED" "$BODY" "FAILED"

# ── Test 3: Out-of-stock — PROD-003 has 0 quantity ──────────────────────────
echo ""
echo "--- Test 3: Out of stock (PROD-003, qty=0) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "idempotencyKey": "integ-test-oos-001",
    "customerId": "CUST-3",
    "productId": "PROD-003",
    "quantity": 1,
    "amount": 50.00,
    "shippingAddress": "789 Test Road"
  }')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "Out-of-stock HTTP status" "$STATUS" "400"
assert_contains "Out-of-stock status=FAILED" "$BODY" "FAILED"

# ── Test 4: Idempotency — duplicate key returns same order ──────────────────
echo ""
echo "--- Test 4: Idempotency (duplicate key) ---"
RESPONSE1=$(curl -s -X POST "$BASE/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "idempotencyKey": "integ-test-idem-001",
    "customerId": "CUST-4",
    "productId": "PROD-001",
    "quantity": 1,
    "amount": 10.00,
    "shippingAddress": "Idempotency Lane"
  }')
ORDER_ID=$(echo "$RESPONSE1" | grep -o '"orderId":"[^"]*"' | cut -d'"' -f4)

RESPONSE2=$(curl -s -X POST "$BASE/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "idempotencyKey": "integ-test-idem-001",
    "customerId": "CUST-4",
    "productId": "PROD-001",
    "quantity": 1,
    "amount": 10.00,
    "shippingAddress": "Idempotency Lane"
  }')
ORDER_ID2=$(echo "$RESPONSE2" | grep -o '"orderId":"[^"]*"' | cut -d'"' -f4)
if [ "$ORDER_ID" = "$ORDER_ID2" ] && [ -n "$ORDER_ID" ]; then
  echo "[PASS] Idempotency — same orderId returned: $ORDER_ID"
  PASS=$((PASS + 1))
else
  echo "[FAIL] Idempotency — orderId1=$ORDER_ID orderId2=$ORDER_ID2"
  FAIL=$((FAIL + 1))
fi

# ── Test 5: GET /orders returns list ────────────────────────────────────────
echo ""
echo "--- Test 5: GET /orders ---"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE/orders")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "GET /orders HTTP status" "$STATUS" "200"
assert_contains "GET /orders returns array" "$BODY" "\["

# ── Test 6: GET /orders/{id} returns single order ───────────────────────────
echo ""
echo "--- Test 6: GET /orders/{id} ---"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE/orders/$ORDER_ID")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "GET /orders/{id} HTTP status" "$STATUS" "200"
assert_contains "GET /orders/{id} returns orderId" "$BODY" "$ORDER_ID"

# ── Test 7: Health endpoint ──────────────────────────────────────────────────
echo ""
echo "--- Test 7: Actuator health ---"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE/actuator/health")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "Actuator health HTTP status" "$STATUS" "200"
assert_contains "Actuator health UP" "$BODY" "UP"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "====================================================="
echo " Results: $PASS passed, $FAIL failed"
echo "====================================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
