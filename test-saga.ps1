##############################################################################
#  SAGA Design Pattern — Full Feature Test Script (PowerShell)
#
#  Covers:
#    1. Health checks  — all 4 services are up
#    2. Happy path     — full SAGA completes (COMPLETED)
#    3. Payment fail   — amount > $10,000 (PAYMENT_FAILED, no compensation)
#    4. Inventory fail — PROD-003 has 0 stock (INVENTORY_FAILED, refund fires)
#    5. Shipping fail  — "BLOCKED" address (SHIPPING_FAILED, release + refund)
#    6. Idempotency    — same idempotencyKey twice → same orderId, no double charge
#    7. Get order      — fetch a single order by ID
#    8. List all orders — GET /orders returns all results
#
#  Prerequisites: all 4 services running locally (or via docker-compose)
#  Run: .\test-saga.ps1
##############################################################################

$ORDER_URL     = "http://localhost:8080"
$PAYMENT_URL   = "http://localhost:8081"
$INVENTORY_URL = "http://localhost:8082"
$SHIPPING_URL  = "http://localhost:8083"

$PASS = 0
$FAIL = 0

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Header($text) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Step($text) {
    Write-Host ""
    Write-Host "  ▶  $text" -ForegroundColor Yellow
}

function Pass($label) {
    Write-Host "  ✅ PASS  $label" -ForegroundColor Green
    $script:PASS++
}

function Fail($label, $detail) {
    Write-Host "  ❌ FAIL  $label" -ForegroundColor Red
    if ($detail) { Write-Host "          $detail" -ForegroundColor DarkRed }
    $script:FAIL++
}

function Print-Response($response) {
    if ($response) {
        $json = $response | ConvertTo-Json -Depth 5
        Write-Host $json -ForegroundColor DarkGray
    }
}

function Invoke-Api($method, $url, $body = $null) {
    try {
        $params = @{ Method = $method; Uri = $url; ContentType = "application/json"; ErrorAction = "Stop" }
        if ($body) { $params["Body"] = ($body | ConvertTo-Json -Depth 5) }
        $response = Invoke-RestMethod @params
        return @{ Success = $true; Body = $response; StatusCode = 200 }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        try {
            $stream  = $_.Exception.Response.GetResponseStream()
            $reader  = New-Object System.IO.StreamReader($stream)
            $errBody = $reader.ReadToEnd() | ConvertFrom-Json
        } catch { $errBody = $null }
        return @{ Success = $false; Body = $errBody; StatusCode = $statusCode; Error = $_.Exception.Message }
    }
}

##############################################################################
#  TEST 1 — Health Checks
##############################################################################
Write-Header "TEST 1 — Health Checks (all 4 services)"

$services = @(
    @{ Name = "order-service    :8080"; Url = "$ORDER_URL/actuator/health" },
    @{ Name = "payment-service  :8081"; Url = "$PAYMENT_URL/actuator/health" },
    @{ Name = "inventory-service:8082"; Url = "$INVENTORY_URL/actuator/health" },
    @{ Name = "shipping-service :8083"; Url = "$SHIPPING_URL/actuator/health" }
)

foreach ($svc in $services) {
    Write-Step "GET $($svc.Url)"
    $r = Invoke-Api "GET" $svc.Url
    if ($r.Success -and $r.Body.status -eq "UP") {
        Pass "$($svc.Name) → status=UP"
    } else {
        Fail "$($svc.Name) → NOT healthy" "$($r.Error)"
    }
}

##############################################################################
#  TEST 2 — Happy Path (full SAGA completes successfully)
##############################################################################
Write-Header "TEST 2 — Happy Path (COMPLETED)"

Write-Step "POST $ORDER_URL/orders  [PROD-001, qty=2, amount=199.99]"
$body = @{
    customerId      = "CUST-001"
    productId       = "PROD-001"
    quantity        = 2
    amount          = 199.99
    shippingAddress = "123 Main St, New York, NY 10001"
}
$r = Invoke-Api "POST" "$ORDER_URL/orders" $body
Print-Response $r.Body

if ($r.Body.status -eq "COMPLETED") {
    Pass "SAGA status is COMPLETED"
    $HAPPY_ORDER_ID = $r.Body.orderId
} else {
    Fail "Expected COMPLETED, got: $($r.Body.status)" "$($r.Body.message)"
    $HAPPY_ORDER_ID = $null
}

if ($r.Body.message -match "Shipment ID") {
    Pass "Response contains Shipment ID"
} else {
    Fail "Response message missing Shipment ID" "$($r.Body.message)"
}

##############################################################################
#  TEST 3 — Payment Failure (amount > $10,000 → declined)
##############################################################################
Write-Header "TEST 3 — Payment Failure (amount exceeds credit limit)"

Write-Step "POST $ORDER_URL/orders  [amount=99999.00 → should be declined]"
$body = @{
    customerId      = "CUST-002"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 99999.00
    shippingAddress = "456 Oak Ave, Chicago, IL"
}
$r = Invoke-Api "POST" "$ORDER_URL/orders" $body
Print-Response $r.Body

if ($r.Body.status -eq "PAYMENT_FAILED") {
    Pass "SAGA status is PAYMENT_FAILED"
} else {
    Fail "Expected PAYMENT_FAILED, got: $($r.Body.status)"
}

if ($r.Body.message -match "declined" -or $r.Body.message -match "credit") {
    Pass "Failure message mentions credit limit"
} else {
    Fail "Failure message unclear" "$($r.Body.message)"
}

##############################################################################
#  TEST 4 — Inventory Failure (PROD-003 has 0 stock → compensation fires)
##############################################################################
Write-Header "TEST 4 — Inventory Failure + Payment Compensation (refund)"

Write-Step "POST $ORDER_URL/orders  [PROD-003 has 0 stock → INVENTORY_FAILED, payment refunded]"
$body = @{
    customerId      = "CUST-003"
    productId       = "PROD-003"
    quantity        = 1
    amount          = 49.99
    shippingAddress = "789 Pine Rd, Seattle, WA"
}
$r = Invoke-Api "POST" "$ORDER_URL/orders" $body
Print-Response $r.Body

if ($r.Body.status -eq "INVENTORY_FAILED") {
    Pass "SAGA status is INVENTORY_FAILED"
} else {
    Fail "Expected INVENTORY_FAILED, got: $($r.Body.status)"
}

if ($r.Body.message -match "stock" -or $r.Body.message -match "Insufficient") {
    Pass "Failure message mentions insufficient stock"
} else {
    Fail "Failure message unclear" "$($r.Body.message)"
}

##############################################################################
#  TEST 5 — Inventory Partial Stock Failure (PROD-002 has 5, request 10)
##############################################################################
Write-Header "TEST 5 — Partial Stock Failure (request qty > available)"

Write-Step "POST $ORDER_URL/orders  [PROD-002 has 5 stock, requesting qty=10]"
$body = @{
    customerId      = "CUST-004"
    productId       = "PROD-002"
    quantity        = 10
    amount          = 99.00
    shippingAddress = "321 Elm St, Austin, TX"
}
$r = Invoke-Api "POST" "$ORDER_URL/orders" $body
Print-Response $r.Body

if ($r.Body.status -eq "INVENTORY_FAILED") {
    Pass "SAGA status is INVENTORY_FAILED (qty 10 > available 5)"
} else {
    Fail "Expected INVENTORY_FAILED, got: $($r.Body.status)"
}

##############################################################################
#  TEST 6 — Shipping Failure (BLOCKED address → compensation: release + refund)
##############################################################################
Write-Header "TEST 6 — Shipping Failure + Full Compensation (release inventory + refund payment)"

Write-Step "POST $ORDER_URL/orders  [shippingAddress contains 'BLOCKED']"
$body = @{
    customerId      = "CUST-005"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 75.00
    shippingAddress = "BLOCKED ZONE - No Delivery"
}
$r = Invoke-Api "POST" "$ORDER_URL/orders" $body
Print-Response $r.Body

if ($r.Body.status -eq "SHIPPING_FAILED") {
    Pass "SAGA status is SHIPPING_FAILED"
} else {
    Fail "Expected SHIPPING_FAILED, got: $($r.Body.status)"
}

if ($r.Body.message -match "restricted" -or $r.Body.message -match "Shipping") {
    Pass "Failure message mentions shipping restriction"
} else {
    Fail "Failure message unclear" "$($r.Body.message)"
}

##############################################################################
#  TEST 7 — Idempotency (same idempotencyKey → same order, no double charge)
##############################################################################
Write-Header "TEST 7 — Idempotency (duplicate request returns same order)"

$IDEM_KEY = "test-idem-key-$(Get-Random -Maximum 99999)"
Write-Step "First call with idempotencyKey=$IDEM_KEY"
$body = @{
    idempotencyKey  = $IDEM_KEY
    customerId      = "CUST-006"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 29.99
    shippingAddress = "100 Maple Dr, Denver, CO"
}
$r1 = Invoke-Api "POST" "$ORDER_URL/orders" $body
Print-Response $r1.Body
$firstOrderId = $r1.Body.orderId

Write-Step "Second call with SAME idempotencyKey=$IDEM_KEY (should return identical response)"
$r2 = Invoke-Api "POST" "$ORDER_URL/orders" $body
Print-Response $r2.Body
$secondOrderId = $r2.Body.orderId

if ($firstOrderId -and $firstOrderId -eq $secondOrderId) {
    Pass "Both calls return the same orderId=$firstOrderId"
} else {
    Fail "Different orderIds returned! first=$firstOrderId second=$secondOrderId"
}

if ($r1.Body.status -eq "COMPLETED" -and $r2.Body.status -eq "COMPLETED") {
    Pass "Both responses show COMPLETED status"
} else {
    Fail "Status mismatch: first=$($r1.Body.status) second=$($r2.Body.status)"
}

Write-Step "Third call with SAME key (triple duplicate protection check)"
$r3 = Invoke-Api "POST" "$ORDER_URL/orders" $body
if ($r3.Body.orderId -eq $firstOrderId) {
    Pass "Third call also returns same orderId (idempotency holds)"
} else {
    Fail "Third call returned different orderId=$($r3.Body.orderId)"
}

##############################################################################
#  TEST 8 — No idempotencyKey → each call creates a new order
##############################################################################
Write-Header "TEST 8 — Without idempotencyKey each call is independent"

Write-Step "Two calls WITHOUT idempotencyKey → should produce 2 different orderIds"
$body = @{
    customerId      = "CUST-007"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 15.00
    shippingAddress = "200 River Rd, Miami, FL"
}
$ra = Invoke-Api "POST" "$ORDER_URL/orders" $body
$rb = Invoke-Api "POST" "$ORDER_URL/orders" $body

if ($ra.Body.orderId -ne $rb.Body.orderId) {
    Pass "Two calls without key → two distinct orderIds (expected)"
} else {
    Fail "Same orderId returned without a key — unexpected" "$($ra.Body.orderId)"
}

##############################################################################
#  TEST 9 — GET single order
##############################################################################
Write-Header "TEST 9 — GET /orders/{id} (fetch order by ID)"

if ($HAPPY_ORDER_ID) {
    Write-Step "GET $ORDER_URL/orders/$HAPPY_ORDER_ID"
    $r = Invoke-Api "GET" "$ORDER_URL/orders/$HAPPY_ORDER_ID"
    Print-Response $r.Body

    if ($r.Body.orderId -eq $HAPPY_ORDER_ID) {
        Pass "Correct orderId returned"
    } else {
        Fail "orderId mismatch" "expected=$HAPPY_ORDER_ID got=$($r.Body.orderId)"
    }

    if ($r.Body.status -eq "COMPLETED") {
        Pass "Order status is COMPLETED"
    } else {
        Fail "Unexpected status=$($r.Body.status)"
    }
} else {
    Fail "Skipped — no happy-path orderId available (TEST 2 failed)"
}

##############################################################################
#  TEST 10 — GET all orders
##############################################################################
Write-Header "TEST 10 — GET /orders (list all orders)"

Write-Step "GET $ORDER_URL/orders"
$r = Invoke-Api "GET" "$ORDER_URL/orders"

if ($r.Success -and $r.Body.Count -gt 0) {
    Pass "Returned $($r.Body.Count) order(s)"
} else {
    Fail "Empty or failed response" "$($r.Error)"
}

$statuses = $r.Body | ForEach-Object { $_.status } | Sort-Object -Unique
Write-Host "  → Distinct saga statuses found: $($statuses -join ', ')" -ForegroundColor DarkGray

##############################################################################
#  SUMMARY
##############################################################################
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total tests run : $($PASS + $FAIL)"
Write-Host "  ✅ Passed       : $PASS" -ForegroundColor Green
if ($FAIL -gt 0) {
    Write-Host "  ❌ Failed       : $FAIL" -ForegroundColor Red
} else {
    Write-Host "  ❌ Failed       : $FAIL" -ForegroundColor DarkGray
}
Write-Host ""
if ($FAIL -eq 0) {
    Write-Host "  🎉 All tests passed!" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  Some tests failed. Check output above." -ForegroundColor Yellow
}
Write-Host ""
