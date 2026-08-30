# SAGA Design Pattern — Orchestrator Implementation

A complete, runnable implementation of the **SAGA Orchestrator** pattern using **Java 17 + Spring Boot 3**.

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                   Client (Postman / curl)                  │
└──────────────────────────┬────────────────────────────────┘
                           │ POST /orders
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│              ORDER SERVICE  (port 8080) — ORCHESTRATOR           │
│                                                                  │
│  OrderController → OrderService → OrderSagaOrchestrator          │
│                                                                  │
│  SAGA Steps:                                                     │
│   1. processPayment()   → PaymentService  :8081                  │
│   2. reserveInventory() → InventoryService:8082                  │
│   3. scheduleShipping() → ShippingService :8083                  │
│                                                                  │
│  Compensations (on failure):                                     │
│   Shipping failed  → releaseInventory + refundPayment            │
│   Inventory failed → refundPayment                               │
│   Payment failed   → (nothing to undo)                           │
└──────────────────────────────────────────────────────────────────┘
         │                   │                   │
         ▼                   ▼                   ▼
┌──────────────┐  ┌──────────────────┐  ┌─────────────────┐
│PAYMENT SERVICE│  │INVENTORY SERVICE │  │SHIPPING SERVICE │
│  port 8081   │  │   port 8082      │  │   port 8083     │
│              │  │                  │  │                 │
│ /process     │  │ /reserve         │  │ /schedule       │
│ /refund/{id} │  │ /release/{id}    │  │ /cancel/{id}    │
│  H2 DB       │  │  H2 DB + seed    │  │  H2 DB          │
└──────────────┘  └──────────────────┘  └─────────────────┘
```

## Modules

| Module | Port | Role |
|--------|------|------|
| `saga-commons` | — | Shared DTOs and enums |
| `order-service` | 8080 | **SAGA Orchestrator** |
| `payment-service` | 8081 | Downstream service |
| `inventory-service` | 8082 | Downstream service + stock seed data |
| `shipping-service` | 8083 | Downstream service |

## How to Run

Start **4 terminals**, one per service:

```bash
# Terminal 1 — Payment Service
cd payment-service
mvn spring-boot:run

# Terminal 2 — Inventory Service
cd inventory-service
mvn spring-boot:run

# Terminal 3 — Shipping Service
cd shipping-service
mvn spring-boot:run

# Terminal 4 — Order Service (Orchestrator)
cd order-service
mvn spring-boot:run
```

## Test Scenarios

### ✅ Scenario 1 — Happy Path (All steps succeed)

```bash
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "CUST-001",
    "productId": "PROD-001",
    "quantity": 2,
    "amount": 199.99,
    "shippingAddress": "123 Main St, New York"
  }'
```

Expected: `status: "COMPLETED"` with a shipment tracking number.

---

### ❌ Scenario 2 — Payment Failure (amount > $10,000)
Triggers: Payment declined → **no compensation needed**

```bash
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "CUST-001",
    "productId": "PROD-001",
    "quantity": 1,
    "amount": 99999.00,
    "shippingAddress": "123 Main St"
  }'
```

Expected: `status: "PAYMENT_FAILED"`

---

### ❌ Scenario 3 — Inventory Failure (out-of-stock product)
Triggers: Payment approved, then inventory insufficient → **refund payment (compensation)**

```bash
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "CUST-001",
    "productId": "PROD-003",
    "quantity": 1,
    "amount": 50.00,
    "shippingAddress": "123 Main St"
  }'
```

Expected: `status: "INVENTORY_FAILED"` — and you'll see the payment was **refunded** in the logs.

---

### ❌ Scenario 4 — Shipping Failure (blocked address)
Triggers: Payment + inventory both succeed, then shipping fails → **release inventory + refund payment (compensation)**

```bash
curl -X POST http://localhost:8080/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "CUST-001",
    "productId": "PROD-001",
    "quantity": 1,
    "amount": 50.00,
    "shippingAddress": "BLOCKED ZONE"
  }'
```

Expected: `status: "SHIPPING_FAILED"` — logs show inventory released AND payment refunded.

---

### 🔍 View all orders

```bash
curl http://localhost:8080/orders
```

### 🗄️ H2 Console (inspect DBs directly)

| Service | URL |
|---------|-----|
| Order | http://localhost:8080/h2-console |
| Payment | http://localhost:8081/h2-console |
| Inventory | http://localhost:8082/h2-console |
| Shipping | http://localhost:8083/h2-console |

JDBC URL follows the pattern: `jdbc:h2:mem:<servicename>db`

## SAGA State Machine

```
PENDING
  └─► PAYMENT_PROCESSING
        ├─► PAYMENT_FAILED              (terminal — no compensation)
        └─► INVENTORY_RESERVING
              ├─► INVENTORY_FAILED      (compensate: refund payment)
              └─► SHIPPING_SCHEDULING
                    ├─► SHIPPING_FAILED (compensate: release inventory + refund)
                    └─► COMPLETED       ✅
```

## Key Design Decisions

| Decision | Explanation |
|----------|-------------|
| **Orchestrator over Choreography** | Single place to read the entire business flow; easier to debug |
| **Saga state persisted on every step** | Order's `sagaStatus` column tracks exactly where we are — survives restarts |
| **Compensation IDs stored on Order** | `paymentId`, `inventoryReservationId` on the Order entity means the orchestrator always knows what to undo |
| **RestTemplate for sync HTTP** | Keeps the demo simple; in production use WebClient or a circuit breaker (Resilience4j) |
| **H2 per service** | Each service owns its own schema — true microservice data isolation |

## Project Structure

```
saga-design-pattern/
├── pom.xml                          ← parent POM
├── saga-commons/                    ← shared DTOs & enums
│   └── src/main/java/com/saga/commons/
│       ├── dto/                     ← OrderRequest/Response, Payment*, Inventory*, Shipping*
│       └── enums/                   ← SagaStatus, PaymentStatus, InventoryStatus, ShippingStatus
├── order-service/                   ← ORCHESTRATOR (port 8080)
│   └── src/main/java/com/saga/order/
│       ├── saga/OrderSagaOrchestrator.java  ← ⭐ core pattern
│       ├── service/OrderService.java
│       ├── controller/OrderController.java
│       └── entity/Order.java        ← saga state machine
├── payment-service/                 ← port 8081
├── inventory-service/               ← port 8082 (seeded stock)
└── shipping-service/                ← port 8083
```
