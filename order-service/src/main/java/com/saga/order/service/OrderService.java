package com.saga.order.service;

import com.saga.commons.dto.OrderRequest;
import com.saga.commons.dto.OrderResponse;
import com.saga.commons.enums.SagaStatus;
import com.saga.order.entity.Order;
import com.saga.order.repository.OrderRepository;
import com.saga.order.saga.OrderSagaOrchestrator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;
    private final OrderSagaOrchestrator sagaOrchestrator;

    /**
     * Creates an order and hands it off to the SAGA orchestrator.
     *
     * IDEMPOTENCY: if the caller supplies an idempotencyKey and we already have
     * an Order row for that key, we return the existing order immediately without
     * starting a new SAGA or charging the customer a second time.
     */
    @Transactional
    public OrderResponse createOrder(OrderRequest request) {

        // ── Idempotency check ────────────────────────────────────────────────
        if (request.getIdempotencyKey() != null && !request.getIdempotencyKey().isBlank()) {
            Optional<Order> existing = orderRepository.findByIdempotencyKey(request.getIdempotencyKey());
            if (existing.isPresent()) {
                log.info("[IDEMPOTENT] Duplicate request for idempotencyKey={}. Returning existing orderId={}",
                        request.getIdempotencyKey(), existing.get().getId());
                return toResponse(existing.get());
            }
        }
        // ────────────────────────────────────────────────────────────────────

        // Persist the order in PENDING state before starting the saga
        Order order = Order.builder()
                .idempotencyKey(request.getIdempotencyKey())
                .customerId(request.getCustomerId())
                .productId(request.getProductId())
                .quantity(request.getQuantity())
                .amount(request.getAmount())
                .shippingAddress(request.getShippingAddress())
                .sagaStatus(SagaStatus.PENDING)
                .build();

        order = orderRepository.save(order);
        log.info("Order created with id={}, starting SAGA...", order.getId());

        // Execute the SAGA — this will update the order status through all steps
        Order completedOrder = sagaOrchestrator.executeSaga(order);

        return toResponse(completedOrder);
    }

    public OrderResponse getOrder(String orderId) {
        Order order = orderRepository.findById(orderId)
                .orElseThrow(() -> new RuntimeException("Order not found: " + orderId));
        return toResponse(order);
    }

    public List<OrderResponse> getAllOrders() {
        return orderRepository.findAll().stream()
                .map(this::toResponse)
                .collect(Collectors.toList());
    }

    private OrderResponse toResponse(Order order) {
        return OrderResponse.builder()
                .orderId(order.getId())
                .customerId(order.getCustomerId())
                .productId(order.getProductId())
                .quantity(order.getQuantity())
                .amount(order.getAmount())
                .status(order.getSagaStatus())
                .message(buildMessage(order))
                .build();
    }

    private String buildMessage(Order order) {
        if (order.getSagaStatus() == SagaStatus.COMPLETED) {
            return "Order completed successfully! Shipment ID: " + order.getShipmentId();
        }
        return order.getFailureReason() != null
                ? "Order failed: " + order.getFailureReason()
                : order.getSagaStatus().name();
    }
}
