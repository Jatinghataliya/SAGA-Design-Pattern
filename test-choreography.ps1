#!/usr/bin/env pwsh
# ============================================================
#  test-choreography.ps1
#  End-to-end test script for the SAGA Choreography Service
# ============================================================

$BASE_URL = "http://localhost:8090"
$PASSED   = 0
$FAILED   = 0

function Write-Header([string]$title) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

function Assert-Equals([string]$label, $actual, $expected) {
    if ($actual -eq $expected) {
        Write-Host "  [PASS] $label : $actual" -ForegroundColor Green
        $script:PASSED++
    } else {
        Write-Host "  [FAIL] $label — expected '$expected', got '$actual'" -ForegroundColor Red
        $script:FAILED++
    }
}

function Assert-NotNull([string]$label, $actual) {
    if ($null -ne $actual -and $actual -ne "") {
        Write-Host "  [PASS] $label : $actual" -ForegroundColor Green
        $script:PASSED++
    } else {
        Write-Host "  [FAIL] $label — expected non-null/non-empty value" -ForegroundColor Red
        $script:FAILED++
    }
}

function Post-Order($body) {
    $json = $body | ConvertTo-Json
    $response = Invoke-RestMethod -Uri "$BASE_URL/choreography/orders" `
                                  -Method POST `
                                  -ContentType "application/json" `
                                  -Body $json
    return $response
}

function Get-Order($id) {
    return Invoke-RestMethod -Uri "$BASE_URL/choreography/orders/$id" -Method GET
}

function Get-AllOrders() {
    return Invoke-RestMethod -Uri "$BASE_URL/choreography/orders" -Method GET
}

# ─── 1. Health Check ─────────────────────────────────────────────────────────
Write-Header "1. Health Check"
try {
    $health = Invoke-RestMethod -Uri "$BASE_URL/actuator/health" -Method GET
    Assert-Equals "Health status" $health.status "UP"
} catch {
    Write-Host "  [FAIL] Health check failed: $_" -ForegroundColor Red
    $script:FAILED++
    Write-Host ""
    Write-Host "  ► Is the choreography-service running on port 8090?" -ForegroundColor Yellow
    exit 1
}

# ─── 2. Happy Path → COMPLETED ───────────────────────────────────────────────
Write-Header "2. Happy Path — COMPLETED"
$happyOrder = Post-Order @{
    customerId      = 1
    productId       = "PROD-001"
    quantity        = 2
    amount          = 500.00
    shippingAddress = "123 Main Street, Springfield"
}
Write-Host "  Order ID: $($happyOrder.id)"
Assert-Equals "Status"     $happyOrder.status "COMPLETED"
Assert-NotNull "paymentId"    $happyOrder.paymentId
Assert-NotNull "reservationId" $happyOrder.reservationId
Assert-NotNull "shipmentId"   $happyOrder.shipmentId

# ─── 3. Payment Failure (amount > 10000) → FAILED ────────────────────────────
Write-Header "3. Payment Failure (amount > 10000) → FAILED"
$payFailOrder = Post-Order @{
    customerId      = 2
    productId       = "PROD-001"
    quantity        = 1
    amount          = 15000.00
    shippingAddress = "456 Oak Avenue, Portland"
}
Write-Host "  Order ID: $($payFailOrder.id)"
Assert-Equals "Status"        $payFailOrder.status "FAILED"
Assert-NotNull "failureReason" $payFailOrder.failureReason
Write-Host "  Failure reason: $($payFailOrder.failureReason)"

# ─── 4. Inventory Failure (out of stock PROD-003) → FAILED + payment refunded ─
Write-Header "4. Inventory Failure (PROD-003 zero stock) → FAILED + Payment Refunded"
$invFailOrder = Post-Order @{
    customerId      = 3
    productId       = "PROD-003"
    quantity        = 1
    amount          = 200.00
    shippingAddress = "789 Elm Street, Denver"
}
Write-Host "  Order ID: $($invFailOrder.id)"
Assert-Equals "Status"        $invFailOrder.status "FAILED"
Assert-NotNull "failureReason" $invFailOrder.failureReason
Write-Host "  Failure reason: $($invFailOrder.failureReason)"

# ─── 5. Shipping Failure (BLOCKED address) → FAILED + inventory released + payment refunded ─
Write-Header "5. Shipping Failure (BLOCKED address) → FAILED + Inventory Released + Payment Refunded"
$shipFailOrder = Post-Order @{
    customerId      = 4
    productId       = "PROD-001"
    quantity        = 1
    amount          = 300.00
    shippingAddress = "BLOCKED ZONE, Area 51"
}
Write-Host "  Order ID: $($shipFailOrder.id)"
Assert-Equals "Status"        $shipFailOrder.status "FAILED"
Assert-NotNull "failureReason" $shipFailOrder.failureReason
Write-Host "  Failure reason: $($shipFailOrder.failureReason)"

# ─── 6. Inventory Failure (insufficient stock PROD-002, request > 5) ──────────
Write-Header "6. Inventory Failure (PROD-002 insufficient quantity) → FAILED"
$invInsuffOrder = Post-Order @{
    customerId      = 5
    productId       = "PROD-002"
    quantity        = 10
    amount          = 100.00
    shippingAddress = "321 Pine Road, Seattle"
}
Write-Host "  Order ID: $($invInsuffOrder.id)"
Assert-Equals "Status"        $invInsuffOrder.status "FAILED"
Assert-NotNull "failureReason" $invInsuffOrder.failureReason
Write-Host "  Failure reason: $($invInsuffOrder.failureReason)"

# ─── 7. GET by ID ─────────────────────────────────────────────────────────────
Write-Header "7. GET Order by ID"
$fetchedOrder = Get-Order $happyOrder.id
Assert-Equals "Fetched order ID"     $fetchedOrder.id     $happyOrder.id
Assert-Equals "Fetched order status" $fetchedOrder.status "COMPLETED"

# ─── 8. GET all orders ────────────────────────────────────────────────────────
Write-Header "8. GET All Orders"
$allOrders = Get-AllOrders
Assert-Equals "Total orders count" $allOrders.Count 5
Write-Host "  All orders:"
foreach ($o in $allOrders) {
    Write-Host "    ID=$($o.id)  Status=$($o.status)  Product=$($o.productId)  Amount=$($o.amount)"
}

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "  RESULTS: $PASSED passed, $FAILED failed" -ForegroundColor $(if ($FAILED -eq 0) { "Green" } else { "Red" })
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

if ($FAILED -gt 0) {
    exit 1
}
