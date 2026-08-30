#!/usr/bin/env bash
# ============================================================
#  SAGA Choreography — Integration Tests
#  Hits real HTTP endpoints on choreography-service:8090
#  Exits non-zero on any assertion failure.
# ============================================================
set -euo pipefail

BASE="http://localhost:8090"
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
echo " SAGA Choreography Integration Tests"
echo "====================================================="

# ── Test 1: Happy path — event chain completes ──────────────────────────────
echo ""
echo "--- Test 1: Happy path (PROD-001, amount=50.00) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/choreography/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": 1,
    "productId": "PROD-001",
    "quantity": 1,
    "amount": 50.00,
    "shippingAddress": "123 Choreography Street"
  }')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "Happy path HTTP status" "$STATUS" "200"
ORDER_ID=$(echo "$BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
assert_contains "Happy path has order id" "$BODY" '"id"'

# Give async event chain time to fully complete
sleep 5

# ── Test 2: Poll order until COMPLETED (max 30s) ────────────────────────────
echo ""
echo "--- Test 2: Poll until COMPLETED (orderId=$ORDER_ID) ---"
FINAL_STATUS=""
for i in $(seq 1 30); do
  POLL=$(curl -s "$BASE/choreography/orders/$ORDER_ID")
  FINAL_STATUS=$(echo "$POLL" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  echo "  poll $i: status=$FINAL_STATUS"
  if [ "$FINAL_STATUS" = "COMPLETED" ]; then
    break
  fi
  sleep 1
done
if [ "$FINAL_STATUS" = "COMPLETED" ]; then
  echo "[PASS] Order eventually reached COMPLETED status"
  PASS=$((PASS + 1))
else
  echo "[FAIL] Order status after 30s: $FINAL_STATUS (expected COMPLETED)"
  FAIL=$((FAIL + 1))
fi

# ── Test 3: Payment declined — amount too high ──────────────────────────────
echo ""
echo "--- Test 3: Payment declined (amount=99999) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/choreography/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": 2,
    "productId": "PROD-001",
    "quantity": 1,
    "amount": 99999.00,
    "shippingAddress": "456 Decline Avenue"
  }')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "Payment declined HTTP status" "$STATUS" "200"
DECLINED_ID=$(echo "$BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

sleep 2
for i in $(seq 1 10); do
  POLL=$(curl -s "$BASE/choreography/orders/$DECLINED_ID")
  FINAL_STATUS=$(echo "$POLL" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  if [ "$FINAL_STATUS" = "FAILED" ] || [ "$FINAL_STATUS" = "CANCELLED" ]; then
    break
  fi
  sleep 1
done
if [ "$FINAL_STATUS" = "FAILED" ] || [ "$FINAL_STATUS" = "CANCELLED" ]; then
  echo "[PASS] Declined order reached terminal failed status: $FINAL_STATUS"
  PASS=$((PASS + 1))
else
  echo "[FAIL] Declined order status after 10s: $FINAL_STATUS (expected FAILED/CANCELLED)"
  FAIL=$((FAIL + 1))
fi

# ── Test 4: Out of stock — PROD-003 has 0 quantity ──────────────────────────
echo ""
echo "--- Test 4: Out of stock (PROD-003) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE/choreography/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": 3,
    "productId": "PROD-003",
    "quantity": 1,
    "amount": 20.00,
    "shippingAddress": "789 Out-of-Stock Road"
  }')
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "Out-of-stock HTTP status" "$STATUS" "200"
OOS_ID=$(echo "$BODY" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

sleep 2
for i in $(seq 1 10); do
  POLL=$(curl -s "$BASE/choreography/orders/$OOS_ID")
  FINAL_STATUS=$(echo "$POLL" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  if [ "$FINAL_STATUS" = "FAILED" ] || [ "$FINAL_STATUS" = "CANCELLED" ]; then
    break
  fi
  sleep 1
done
if [ "$FINAL_STATUS" = "FAILED" ] || [ "$FINAL_STATUS" = "CANCELLED" ]; then
  echo "[PASS] Out-of-stock order reached terminal failed status: $FINAL_STATUS"
  PASS=$((PASS + 1))
else
  echo "[FAIL] Out-of-stock order status after 10s: $FINAL_STATUS (expected FAILED/CANCELLED)"
  FAIL=$((FAIL + 1))
fi

# ── Test 5: GET /choreography/orders returns list ───────────────────────────
echo ""
echo "--- Test 5: GET /choreography/orders ---"
RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE/choreography/orders")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
assert_status "GET /choreography/orders HTTP status" "$STATUS" "200"
assert_contains "GET /choreography/orders returns array" "$BODY" "\["

# ── Test 6: Health endpoint ──────────────────────────────────────────────────
echo ""
echo "--- Test 6: Actuator health ---"
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
