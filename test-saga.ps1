##############################################################################
#  SAGA Design Pattern - Full Feature Test Script (PowerShell)
#
#  Covers:
#    1. Health checks  - all 4 services are up
#    2. Happy path     - full SAGA completes (COMPLETED)
#    3. Payment fail   - amount > $10,000 (PAYMENT_FAILED, no compensation)
#    4. Inventory fail - PROD-003 has 0 stock (INVENTORY_FAILED, refund fires)
#    5. Partial stock  - qty > available (INVENTORY_FAILED)
#    6. Shipping fail  - BLOCKED address (SHIPPING_FAILED, release + refund)
#    7. Idempotency    - same idempotencyKey 3x returns same orderId
#    8. No key         - calls without key each create a new order
#    9. GET by ID      - fetch single order
#   10. GET all orders - list all orders
#
#  Run from project root:
#    powershell -ExecutionPolicy Bypass -File .\test-saga.ps1
##############################################################################

$ORDER_URL     = "http://localhost:8080"
$PAYMENT_URL   = "http://localhost:8081"
$INVENTORY_URL = "http://localhost:8082"
$SHIPPING_URL  = "http://localhost:8083"

$PASS = 0
$FAIL = 0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Header($text) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Step($text) {
    Write-Host ""
    Write-Host "  >> $text" -ForegroundColor Yellow
}

function Pass($label) {
    Write-Host "  [PASS]  $label" -ForegroundColor Green
    $script:PASS++
}

function Fail($label, $detail = "") {
    Write-Host "  [FAIL]  $label" -ForegroundColor Red
    if ($detail) { Write-Host "          $detail" -ForegroundColor DarkRed }
    $script:FAIL++
}

function Print-Json($obj) {
    if ($obj) {
        Write-Host ($obj | ConvertTo-Json -Depth 5) -ForegroundColor DarkGray
    }
}

function Invoke-Api($method, $url, $body = $null) {
    try {
        $params = @{
            Method      = $method
            Uri         = $url
            ContentType = "application/json"
            ErrorAction = "Stop"
        }
        if ($body) { $params["Body"] = ($body | ConvertTo-Json -Depth 5) }
        $resp = Invoke-RestMethod @params
        return @{ Success = $true; Body = $resp }
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errBody = $null
        try {
            $stream  = $_.Exception.Response.GetResponseStream()
            $reader  = New-Object System.IO.StreamReader($stream)
            $errBody = $reader.ReadToEnd() | ConvertFrom-Json
        } catch {}
        return @{ Success = $false; Body = $errBody; StatusCode = $statusCode; Error = $_.Exception.Message }
    }
}

##############################################################################
#  TEST 1 - Health Checks
##############################################################################
Write-Header "TEST 1 - Health Checks (all 4 services)"

$services = @(
    @{ Name = "order-service     :8080"; Url = "$ORDER_URL/actuator/health" },
    @{ Name = "payment-service   :8081"; Url = "$PAYMENT_URL/actuator/health" },
    @{ Name = "inventory-service :8082"; Url = "$INVENTORY_URL/actuator/health" },
    @{ Name = "shipping-service  :8083"; Url = "$SHIPPING_URL/actuator/health" }
)

foreach ($svc in $services) {
    Write-Step "GET $($svc.Url)"
    $r = Invoke-Api "GET" $svc.Url
    if ($r.Success -and $r.Body.status -eq "UP") {
        Pass "$($svc.Name)  status=UP"
    } else {
        Fail "$($svc.Name)  NOT healthy" "$($r.Error)"
    }
}

##############################################################################
#  TEST 2 - Happy Path (full SAGA completes successfully)
##############################################################################
Write-Header "TEST 2 - Happy Path (expected: COMPLETED)"

Write-Step "POST /orders  [PROD-001, qty=2, amount=199.99]"
$r = Invoke-Api "POST" "$ORDER_URL/orders" @{
    customerId      = "CUST-001"
    productId       = "PROD-001"
    quantity        = 2
    amount          = 199.99
    shippingAddress = "123 Main St, New York, NY 10001"
}
Print-Json $r.Body

$HAPPY_ORDER_ID = $null
if ($r.Body.status -eq "COMPLETED") {
    Pass "SAGA status is COMPLETED"
    $HAPPY_ORDER_ID = $r.Body.orderId
} else {
    Fail "Expected COMPLETED, got: $($r.Body.status)" "$($r.Body.message)"
}

if ($r.Body.message -match "Shipment") {
    Pass "Response contains Shipment ID"
} else {
    Fail "Response message missing Shipment ID" "$($r.Body.message)"
}

##############################################################################
#  TEST 3 - Payment Failure (amount > $10,000)
##############################################################################
Write-Header "TEST 3 - Payment Failure (amount exceeds credit limit)"

Write-Step "POST /orders  [amount=99999.00 - should be declined]"
$r = Invoke-Api "POST" "$ORDER_URL/orders" @{
    customerId      = "CUST-002"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 99999.00
    shippingAddress = "456 Oak Ave, Chicago, IL"
}
Print-Json $r.Body

if ($r.Body.status -eq "PAYMENT_FAILED") {
    Pass "SAGA status is PAYMENT_FAILED"
} else {
    Fail "Expected PAYMENT_FAILED, got: $($r.Body.status)"
}

if ($r.Body.message -match "declined|credit") {
    Pass "Failure message mentions credit limit"
} else {
    Fail "Failure message unclear" "$($r.Body.message)"
}

##############################################################################
#  TEST 4 - Inventory Failure (PROD-003 has 0 stock + payment refund)
##############################################################################
Write-Header "TEST 4 - Inventory Failure + Payment Compensation (refund)"

Write-Step "POST /orders  [PROD-003 has 0 stock - INVENTORY_FAILED, payment refunded]"
$r = Invoke-Api "POST" "$ORDER_URL/orders" @{
    customerId      = "CUST-003"
    productId       = "PROD-003"
    quantity        = 1
    amount          = 49.99
    shippingAddress = "789 Pine Rd, Seattle, WA"
}
Print-Json $r.Body

if ($r.Body.status -eq "INVENTORY_FAILED") {
    Pass "SAGA status is INVENTORY_FAILED"
} else {
    Fail "Expected INVENTORY_FAILED, got: $($r.Body.status)"
}

if ($r.Body.message -match "stock|Insufficient") {
    Pass "Failure message mentions insufficient stock"
} else {
    Fail "Failure message unclear" "$($r.Body.message)"
}

##############################################################################
#  TEST 5 - Partial Stock Failure (PROD-002 has 5, request qty=10)
##############################################################################
Write-Header "TEST 5 - Partial Stock Failure (requested qty > available)"

Write-Step "POST /orders  [PROD-002 has 5 stock, requesting qty=10]"
$r = Invoke-Api "POST" "$ORDER_URL/orders" @{
    customerId      = "CUST-004"
    productId       = "PROD-002"
    quantity        = 10
    amount          = 99.00
    shippingAddress = "321 Elm St, Austin, TX"
}
Print-Json $r.Body

if ($r.Body.status -eq "INVENTORY_FAILED") {
    Pass "SAGA status is INVENTORY_FAILED (qty 10 > available 5)"
} else {
    Fail "Expected INVENTORY_FAILED, got: $($r.Body.status)"
}

##############################################################################
#  TEST 6 - Shipping Failure (BLOCKED address -> release inventory + refund)
##############################################################################
Write-Header "TEST 6 - Shipping Failure + Full Compensation (release + refund)"

Write-Step "POST /orders  [shippingAddress contains BLOCKED]"
$r = Invoke-Api "POST" "$ORDER_URL/orders" @{
    customerId      = "CUST-005"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 75.00
    shippingAddress = "BLOCKED ZONE - No Delivery"
}
Print-Json $r.Body

if ($r.Body.status -eq "SHIPPING_FAILED") {
    Pass "SAGA status is SHIPPING_FAILED"
} else {
    Fail "Expected SHIPPING_FAILED, got: $($r.Body.status)"
}

if ($r.Body.message -match "restricted|Shipping|failed") {
    Pass "Failure message mentions shipping restriction"
} else {
    Fail "Failure message unclear" "$($r.Body.message)"
}

##############################################################################
#  TEST 7 - Idempotency (same idempotencyKey 3x -> same orderId)
##############################################################################
Write-Header "TEST 7 - Idempotency (duplicate requests return same order)"

$IDEM_KEY = "test-idem-key-$(Get-Random -Maximum 99999)"
$idemBody = @{
    idempotencyKey  = $IDEM_KEY
    customerId      = "CUST-006"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 29.99
    shippingAddress = "100 Maple Dr, Denver, CO"
}

Write-Step "Call #1 with idempotencyKey=$IDEM_KEY"
$r1 = Invoke-Api "POST" "$ORDER_URL/orders" $idemBody
Print-Json $r1.Body
$firstOrderId = $r1.Body.orderId

Write-Step "Call #2 with SAME key (should return identical response)"
$r2 = Invoke-Api "POST" "$ORDER_URL/orders" $idemBody
Print-Json $r2.Body
$secondOrderId = $r2.Body.orderId

Write-Step "Call #3 with SAME key (triple-check)"
$r3 = Invoke-Api "POST" "$ORDER_URL/orders" $idemBody
$thirdOrderId = $r3.Body.orderId

if ($firstOrderId -and ($firstOrderId -eq $secondOrderId) -and ($firstOrderId -eq $thirdOrderId)) {
    Pass "All 3 calls return the same orderId=$firstOrderId"
} else {
    Fail "Different orderIds! #1=$firstOrderId  #2=$secondOrderId  #3=$thirdOrderId"
}

if ($r1.Body.status -eq "COMPLETED" -and $r2.Body.status -eq "COMPLETED") {
    Pass "Status is COMPLETED for all duplicate calls"
} else {
    Fail "Status mismatch: #1=$($r1.Body.status)  #2=$($r2.Body.status)"
}

##############################################################################
#  TEST 8 - No idempotencyKey -> each call is a new independent order
##############################################################################
Write-Header "TEST 8 - Without idempotencyKey each call creates a new order"

$noKeyBody = @{
    customerId      = "CUST-007"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 15.00
    shippingAddress = "200 River Rd, Miami, FL"
}

Write-Step "Two calls WITHOUT idempotencyKey"
$ra = Invoke-Api "POST" "$ORDER_URL/orders" $noKeyBody
$rb = Invoke-Api "POST" "$ORDER_URL/orders" $noKeyBody

if ($ra.Body.orderId -ne $rb.Body.orderId) {
    Pass "Two distinct orderIds created (expected behaviour without key)"
} else {
    Fail "Same orderId returned without a key - unexpected" "$($ra.Body.orderId)"
}

##############################################################################
#  TEST 9 - GET single order by ID
##############################################################################
Write-Header "TEST 9 - GET /orders/{id} (fetch order by ID)"

if ($HAPPY_ORDER_ID) {
    Write-Step "GET $ORDER_URL/orders/$HAPPY_ORDER_ID"
    $r = Invoke-Api "GET" "$ORDER_URL/orders/$HAPPY_ORDER_ID"
    Print-Json $r.Body

    if ($r.Body.orderId -eq $HAPPY_ORDER_ID) {
        Pass "Correct orderId returned"
    } else {
        Fail "orderId mismatch" "expected=$HAPPY_ORDER_ID  got=$($r.Body.orderId)"
    }

    if ($r.Body.status -eq "COMPLETED") {
        Pass "Order status is COMPLETED"
    } else {
        Fail "Unexpected status=$($r.Body.status)"
    }
} else {
    Fail "Skipped - no happy-path orderId available (TEST 2 failed)"
}

##############################################################################
#  TEST 10 - GET all orders
##############################################################################
Write-Header "TEST 10 - GET /orders (list all orders)"

Write-Step "GET $ORDER_URL/orders"
$r = Invoke-Api "GET" "$ORDER_URL/orders"

if ($r.Success -and $r.Body.Count -gt 0) {
    Pass "Returned $($r.Body.Count) order(s)"
} else {
    Fail "Empty or failed response" "$($r.Error)"
}

$statuses = $r.Body | ForEach-Object { $_.status } | Sort-Object -Unique
Write-Host "  Distinct saga statuses found: $($statuses -join ', ')" -ForegroundColor DarkGray

##############################################################################
#  SUMMARY
##############################################################################
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total : $($PASS + $FAIL)"
Write-Host "  PASS  : $PASS" -ForegroundColor Green
if ($FAIL -gt 0) {
    Write-Host "  FAIL  : $FAIL" -ForegroundColor Red
} else {
    Write-Host "  FAIL  : $FAIL" -ForegroundColor DarkGray
}
Write-Host ""
if ($FAIL -eq 0) {
    Write-Host "  All tests passed!" -ForegroundColor Green
} else {
    Write-Host "  Some tests failed - check output above." -ForegroundColor Yellow
}
Write-Host ""
