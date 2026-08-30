package com.saga.order.saga;

import com.saga.commons.dto.*;
import com.saga.commons.enums.InventoryStatus;
import com.saga.commons.enums.PaymentStatus;
import com.saga.commons.enums.SagaStatus;
import com.saga.commons.enums.ShippingStatus;
import com.saga.order.entity.Order;
import com.saga.order.repository.OrderRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

/**
 * ============================================================
 *  SAGA ORCHESTRATOR
 * ============================================================
 *
 *  The orchestrator owns the entire transaction lifecycle.
 *  It calls each downstream service in sequence, persists the
 *  saga state after every step, and — if any step fails —
 *  triggers compensating transactions in reverse order.
 *
 *  Flow:
 *    1. processPayment()
 *    2. reserveInventory()
 *    3. scheduleShipping()
 *
 *  Compensation (rollback) — invoked when a step fails:
 *    - Shipping failed  → releaseInventory + refundPayment
 *    - Inventory failed → refundPayment
 *    - Payment failed   → (nothing to undo)
 * ============================================================
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class OrderSagaOrchestrator {

    private final OrderRepository orderRepository;
    private final RestTemplate restTemplate;

    @Value("${services.payment.url}")
    private String paymentServiceUrl;

    @Value("${services.inventory.url}")
    private String inventoryServiceUrl;

    @Value("${services.shipping.url}")
    private String shippingServiceUrl;

    // ----------------------------------------------------------------
    //  ENTRY POINT — called once an Order row is saved as PENDING
    // ----------------------------------------------------------------
    public Order executeSaga(Order order) {
        log.info("=== SAGA START === orderId={}", order.getId());

        // ── Step 1: Payment ──────────────────────────────────────────
        order.setSagaStatus(SagaStatus.PAYMENT_PROCESSING);
        orderRepository.save(order);

        PaymentResponse paymentResponse = processPayment(order);

        if (paymentResponse == null || paymentResponse.getStatus() != PaymentStatus.APPROVED) {
            String reason = paymentResponse != null ? paymentResponse.getMessage() : "Payment service unavailable";
            log.warn("SAGA FAILED at PAYMENT step. Reason: {}", reason);
            return failOrder(order, SagaStatus.PAYMENT_FAILED, reason);
        }

        order.setPaymentId(paymentResponse.getPaymentId());
        order.setSagaStatus(SagaStatus.INVENTORY_RESERVING);
        orderRepository.save(order);
        log.info("Payment APPROVED. paymentId={}", paymentResponse.getPaymentId());

        // ── Step 2: Inventory ────────────────────────────────────────
        InventoryResponse inventoryResponse = reserveInventory(order);

        if (inventoryResponse == null || inventoryResponse.getStatus() != InventoryStatus.RESERVED) {
            String reason = inventoryResponse != null ? inventoryResponse.getMessage() : "Inventory service unavailable";
            log.warn("SAGA FAILED at INVENTORY step. Reason: {}. Starting compensation...", reason);
            compensatePayment(order);
            return failOrder(order, SagaStatus.INVENTORY_FAILED, reason);
        }

        order.setInventoryReservationId(inventoryResponse.getReservationId());
        order.setSagaStatus(SagaStatus.SHIPPING_SCHEDULING);
        orderRepository.save(order);
        log.info("Inventory RESERVED. reservationId={}", inventoryResponse.getReservationId());

        // ── Step 3: Shipping ─────────────────────────────────────────
        ShippingResponse shippingResponse = scheduleShipping(order);

        if (shippingResponse == null || shippingResponse.getStatus() != ShippingStatus.SCHEDULED) {
            String reason = shippingResponse != null ? shippingResponse.getMessage() : "Shipping service unavailable";
            log.warn("SAGA FAILED at SHIPPING step. Reason: {}. Starting compensation...", reason);
            compensateInventory(order);
            compensatePayment(order);
            return failOrder(order, SagaStatus.SHIPPING_FAILED, reason);
        }

        order.setShipmentId(shippingResponse.getShipmentId());
        order.setSagaStatus(SagaStatus.COMPLETED);
        orderRepository.save(order);
        log.info("=== SAGA COMPLETED === orderId={} shipmentId={}", order.getId(), shippingResponse.getShipmentId());

        return order;
    }

    // ================================================================
    //  FORWARD STEPS
    // ================================================================

    private PaymentResponse processPayment(Order order) {
        try {
            PaymentRequest request = PaymentRequest.builder()
                    .orderId(order.getId())
                    .customerId(order.getCustomerId())
                    .amount(order.getAmount())
                    .build();

            log.info("Calling Payment Service: {}/payments/process", paymentServiceUrl);
            ResponseEntity<PaymentResponse> response = restTemplate.postForEntity(
                    paymentServiceUrl + "/payments/process", request, PaymentResponse.class);
            return response.getBody();
        } catch (Exception e) {
            log.error("Payment Service call failed: {}", e.getMessage());
            return null;
        }
    }

    private InventoryResponse reserveInventory(Order order) {
        try {
            InventoryRequest request = InventoryRequest.builder()
                    .orderId(order.getId())
                    .productId(order.getProductId())
                    .quantity(order.getQuantity())
                    .build();

            log.info("Calling Inventory Service: {}/inventory/reserve", inventoryServiceUrl);
            ResponseEntity<InventoryResponse> response = restTemplate.postForEntity(
                    inventoryServiceUrl + "/inventory/reserve", request, InventoryResponse.class);
            return response.getBody();
        } catch (Exception e) {
            log.error("Inventory Service call failed: {}", e.getMessage());
            return null;
        }
    }

    private ShippingResponse scheduleShipping(Order order) {
        try {
            ShippingRequest request = ShippingRequest.builder()
                    .orderId(order.getId())
                    .customerId(order.getCustomerId())
                    .productId(order.getProductId())
                    .quantity(order.getQuantity())
                    .shippingAddress(order.getShippingAddress())
                    .build();

            log.info("Calling Shipping Service: {}/shipping/schedule", shippingServiceUrl);
            ResponseEntity<ShippingResponse> response = restTemplate.postForEntity(
                    shippingServiceUrl + "/shipping/schedule", request, ShippingResponse.class);
            return response.getBody();
        } catch (Exception e) {
            log.error("Shipping Service call failed: {}", e.getMessage());
            return null;
        }
    }

    // ================================================================
    //  COMPENSATING TRANSACTIONS (Rollback)
    // ================================================================

    /**
     * Compensation: Refund the payment.
     * Called when inventory or shipping step fails after payment succeeded.
     */
    private void compensatePayment(Order order) {
        if (order.getPaymentId() == null) return;
        try {
            log.info("[COMPENSATE] Refunding payment. paymentId={}", order.getPaymentId());
            restTemplate.postForEntity(
                    paymentServiceUrl + "/payments/refund/" + order.getPaymentId(),
                    null, PaymentResponse.class);
            log.info("[COMPENSATE] Payment refunded successfully.");
        } catch (Exception e) {
            log.error("[COMPENSATE] Failed to refund payment: {}", e.getMessage());
        }
    }

    /**
     * Compensation: Release the inventory reservation.
     * Called when shipping step fails after inventory was reserved.
     */
    private void compensateInventory(Order order) {
        if (order.getInventoryReservationId() == null) return;
        try {
            log.info("[COMPENSATE] Releasing inventory. reservationId={}", order.getInventoryReservationId());
            restTemplate.postForEntity(
                    inventoryServiceUrl + "/inventory/release/" + order.getInventoryReservationId(),
                    null, InventoryResponse.class);
            log.info("[COMPENSATE] Inventory released successfully.");
        } catch (Exception e) {
            log.error("[COMPENSATE] Failed to release inventory: {}", e.getMessage());
        }
    }

    // ================================================================
    //  HELPERS
    // ================================================================

    private Order failOrder(Order order, SagaStatus status, String reason) {
        order.setSagaStatus(status);
        order.setFailureReason(reason);
        return orderRepository.save(order);
    }
}
