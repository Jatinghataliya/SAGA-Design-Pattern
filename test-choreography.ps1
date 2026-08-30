##############################################################################
#  SAGA Choreography Design Pattern - Full Feature Test Script (PowerShell)
#
#  Covers:
#    1. Health Check           - choreography-service :8090 is UP
#    2. Happy Path             - full event chain completes (COMPLETED)
#    3. Payment Failure        - amount > 10000 (FAILED, no compensation)
#    4. Inventory Failure      - PROD-003 zero stock (FAILED + payment refunded)
#    5. Shipping Failure       - BLOCKED address (FAILED + inventory released + refund)
#    6. Partial Stock Failure  - PROD-002 qty > available (FAILED + payment refunded)
#    7. GET Order by ID        - fetch single order
#    8. GET All Orders         - list all orders
#
#  Run from project root:
#    powershell -ExecutionPolicy Bypass -File .\test-choreography.ps1
##############################################################################

$BASE_URL = "http://localhost:8090"
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

function Pass($label, $value = "") {
    if ($value) {
        Write-Host "  [PASS]  $label : $value" -ForegroundColor Green
    } else {
        Write-Host "  [PASS]  $label" -ForegroundColor Green
    }
    $script:PASS++
}

function Fail($label, $detail = "") {
    Write-Host "  [FAIL]  $label" -ForegroundColor Red
    if ($detail) { Write-Host "          $detail" -ForegroundColor DarkRed }
    $script:FAIL++
}

function Print-Order($order) {
    if ($order) {
        Write-Host ($order | ConvertTo-Json -Depth 4) -ForegroundColor DarkGray
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
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $errBody = $reader.ReadToEnd() | ConvertFrom-Json
        } catch {}
        return @{ Success = $false; Body = $errBody; StatusCode = $statusCode; Error = $_.Exception.Message }
    }
}

function Post-Order($body) {
    return Invoke-Api "POST" "$BASE_URL/choreography/orders" $body
}

##############################################################################
#  TEST 1 - Health Check
##############################################################################
Write-Header "TEST 1 - Health Check (choreography-service :8090)"

Write-Step "GET $BASE_URL/actuator/health"
$r = Invoke-Api "GET" "$BASE_URL/actuator/health"
if ($r.Success -and $r.Body.status -eq "UP") {
    Pass "choreography-service :8090  status=UP"
} else {
    Fail "choreography-service NOT healthy" "$($r.Error)"
    Write-Host ""
    Write-Host "  Is the choreography-service running?" -ForegroundColor Yellow
    Write-Host "  Start it with: mvn -pl choreography-service spring-boot:run" -ForegroundColor Yellow
    exit 1
}

##############################################################################
#  TEST 2 - Happy Path (full event chain -> COMPLETED)
##############################################################################
Write-Header "TEST 2 - Happy Path (expected: COMPLETED)"

Write-Step "POST /choreography/orders  [PROD-001, qty=2, amount=500.00]"
$r = Post-Order @{
    customerId      = "CUST-001"
    productId       = "PROD-001"
    quantity        = 2
    amount          = 500.00
    shippingAddress = "123 Main Street, New York, NY"
}
Print-Order $r.Body

$HAPPY_ORDER_ID = $null
if ($r.Body.status -eq "COMPLETED") {
    Pass "Choreography status is COMPLETED"
    $HAPPY_ORDER_ID = $r.Body.id
} else {
    Fail "Expected COMPLETED, got: $($r.Body.status)" "$($r.Body.failureReason)"
}

if ($r.Body.paymentId) {
    Pass "paymentId is set" "$($r.Body.paymentId)"
} else {
    Fail "paymentId is null (payment event not processed)"
}

if ($r.Body.reservationId) {
    Pass "reservationId is set" "$($r.Body.reservationId)"
} else {
    Fail "reservationId is null (inventory event not processed)"
}

if ($r.Body.shipmentId) {
    Pass "shipmentId is set" "$($r.Body.shipmentId)"
} else {
    Fail "shipmentId is null (shipping event not processed)"
}

##############################################################################
#  TEST 3 - Payment Failure (amount > 10000 -> FAILED)
##############################################################################
Write-Header "TEST 3 - Payment Failure (amount > credit limit)"

Write-Step "POST /choreography/orders  [amount=15000.00 - should be declined]"
$r = Post-Order @{
    customerId      = "CUST-002"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 15000.00
    shippingAddress = "456 Oak Avenue, Portland, OR"
}
Print-Order $r.Body

if ($r.Body.status -eq "FAILED") {
    Pass "Status is FAILED"
} else {
    Fail "Expected FAILED, got: $($r.Body.status)"
}

if ($r.Body.failureReason) {
    Pass "failureReason is set" "$($r.Body.failureReason)"
} else {
    Fail "failureReason is null"
}

if ($null -eq $r.Body.reservationId -and $null -eq $r.Body.shipmentId) {
    Pass "No inventory/shipping side-effects (correct - no compensation needed)"
} else {
    Fail "Unexpected reservationId or shipmentId on payment-failed order"
}

##############################################################################
#  TEST 4 - Inventory Failure (PROD-003 zero stock -> FAILED + payment refunded)
##############################################################################
Write-Header "TEST 4 - Inventory Failure + Payment Compensation"

Write-Step "POST /choreography/orders  [PROD-003 has 0 stock]"
$r = Post-Order @{
    customerId      = "CUST-003"
    productId       = "PROD-003"
    quantity        = 1
    amount          = 200.00
    shippingAddress = "789 Elm Street, Denver, CO"
}
Print-Order $r.Body

if ($r.Body.status -eq "FAILED") {
    Pass "Status is FAILED"
} else {
    Fail "Expected FAILED, got: $($r.Body.status)"
}

if ($r.Body.failureReason -match "stock|Insufficient|inventory") {
    Pass "failureReason mentions stock/inventory" "$($r.Body.failureReason)"
} else {
    Fail "failureReason unclear" "$($r.Body.failureReason)"
}

##############################################################################
#  TEST 5 - Shipping Failure (BLOCKED address -> FAILED + release + refund)
##############################################################################
Write-Header "TEST 5 - Shipping Failure + Full Compensation"

Write-Step "POST /choreography/orders  [shippingAddress contains BLOCKED]"
$r = Post-Order @{
    customerId      = "CUST-004"
    productId       = "PROD-001"
    quantity        = 1
    amount          = 300.00
    shippingAddress = "BLOCKED ZONE - No Delivery"
}
Print-Order $r.Body

if ($r.Body.status -eq "FAILED") {
    Pass "Status is FAILED"
} else {
    Fail "Expected FAILED, got: $($r.Body.status)"
}

if ($r.Body.failureReason -match "restricted|blocked|address|Shipping") {
    Pass "failureReason mentions shipping restriction" "$($r.Body.failureReason)"
} else {
    Fail "failureReason unclear" "$($r.Body.failureReason)"
}

##############################################################################
#  TEST 6 - Partial Stock Failure (PROD-002 has 5, request qty=10)
##############################################################################
Write-Header "TEST 6 - Partial Stock Failure (qty requested > available)"

Write-Step "POST /choreography/orders  [PROD-002 has 5 stock, requesting qty=10]"
$r = Post-Order @{
    customerId      = "CUST-005"
    productId       = "PROD-002"
    quantity        = 10
    amount          = 100.00
    shippingAddress = "321 Pine Road, Seattle, WA"
}
Print-Order $r.Body

if ($r.Body.status -eq "FAILED") {
    Pass "Status is FAILED (qty 10 > available 5)"
} else {
    Fail "Expected FAILED, got: $($r.Body.status)"
}

##############################################################################
#  TEST 7 - GET Order by ID
##############################################################################
Write-Header "TEST 7 - GET /choreography/orders/{id}"

if ($HAPPY_ORDER_ID) {
    Write-Step "GET $BASE_URL/choreography/orders/$HAPPY_ORDER_ID"
    $r = Invoke-Api "GET" "$BASE_URL/choreography/orders/$HAPPY_ORDER_ID"
    Print-Order $r.Body

    if ($r.Body.id -eq $HAPPY_ORDER_ID) {
        Pass "Correct order ID returned"
    } else {
        Fail "ID mismatch" "expected=$HAPPY_ORDER_ID  got=$($r.Body.id)"
    }

    if ($r.Body.status -eq "COMPLETED") {
        Pass "Order status is COMPLETED"
    } else {
        Fail "Unexpected status=$($r.Body.status)"
    }
} else {
    Fail "Skipped - no happy-path order ID available (TEST 2 failed)"
}

##############################################################################
#  TEST 8 - GET All Orders
##############################################################################
Write-Header "TEST 8 - GET /choreography/orders (list all)"

Write-Step "GET $BASE_URL/choreography/orders"
$r = Invoke-Api "GET" "$BASE_URL/choreography/orders"

if ($r.Success -and $r.Body.Count -gt 0) {
    Pass "Returned $($r.Body.Count) order(s)"
} else {
    Fail "Empty or failed response" "$($r.Error)"
}

$statuses = $r.Body | ForEach-Object { $_.status } | Sort-Object -Unique
Write-Host "  Distinct choreography statuses found: $($statuses -join ', ')" -ForegroundColor DarkGray

##############################################################################
#  SUMMARY
##############################################################################
Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  TEST SUMMARY  -  SAGA Choreography" -ForegroundColor Cyan
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
