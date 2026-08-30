package com.saga.order.service;

import com.saga.commons.dto.OrderRequest;
import com.saga.commons.dto.OrderResponse;
import com.saga.commons.enums.SagaStatus;
import com.saga.order.entity.Order;
import com.saga.order.repository.OrderRepository;
import com.saga.order.saga.OrderSagaOrchestrator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("OrderService Unit Tests")
class OrderServiceTest {

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private OrderSagaOrchestrator sagaOrchestrator;

    @InjectMocks
    private OrderService orderService;

    private OrderRequest request;

    @BeforeEach
    void setUp() {
        request = OrderRequest.builder()
                .customerId("CUST-001")
                .productId("PROD-001")
                .quantity(2)
                .amount(new BigDecimal("199.99"))
                .shippingAddress("123 Main St")
                .build();
    }

    // ────────────────────────────────────────────────────────────────────────
    //  createOrder — happy path
    // ────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("createOrder: valid request without idempotency key runs SAGA and returns COMPLETED")
    void createOrder_validRequest_returnsSagaResult() {
        Order savedOrder = buildOrder("ord-001", SagaStatus.PENDING);
        Order completedOrder = buildOrder("ord-001", SagaStatus.COMPLETED);
        completedOrder.setShipmentId("ship-001");

        when(orderRepository.save(any(Order.class))).thenReturn(savedOrder);
        when(sagaOrchestrator.executeSaga(any(Order.class))).thenReturn(completedOrder);

        OrderResponse response = orderService.createOrder(request);

        assertThat(response.getOrderId()).isEqualTo("ord-001");
        assertThat(response.getStatus()).isEqualTo(SagaStatus.COMPLETED);
        assertThat(response.getMessage()).contains("Shipment ID");
        verify(sagaOrchestrator, times(1)).executeSaga(any(Order.class));
    }

    @Test
    @DisplayName("createOrder: SAGA failure returns PAYMENT_FAILED status")
    void createOrder_sagaPaymentFailed_returnsFailedStatus() {
        Order savedOrder = buildOrder("ord-002", SagaStatus.PENDING);
        Order failedOrder = buildOrder("ord-002", SagaStatus.PAYMENT_FAILED);
        failedOrder.setFailureReason("Payment declined: amount exceeds credit limit");

        when(orderRepository.save(any(Order.class))).thenReturn(savedOrder);
        when(sagaOrchestrator.executeSaga(any(Order.class))).thenReturn(failedOrder);

        OrderResponse response = orderService.createOrder(request);

        assertThat(response.getStatus()).isEqualTo(SagaStatus.PAYMENT_FAILED);
        assertThat(response.getMessage()).contains("failed");
    }

    // ────────────────────────────────────────────────────────────────────────
    //  createOrder — idempotency
    // ────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("createOrder: duplicate idempotencyKey returns existing order without re-running SAGA")
    void createOrder_duplicateIdempotencyKey_returnsExistingOrder() {
        request.setIdempotencyKey("idem-key-123");

        Order existingOrder = buildOrder("ord-existing", SagaStatus.COMPLETED);
        existingOrder.setShipmentId("ship-existing");
        existingOrder.setIdempotencyKey("idem-key-123");

        when(orderRepository.findByIdempotencyKey("idem-key-123"))
                .thenReturn(Optional.of(existingOrder));

        OrderResponse response = orderService.createOrder(request);

        assertThat(response.getOrderId()).isEqualTo("ord-existing");
        assertThat(response.getStatus()).isEqualTo(SagaStatus.COMPLETED);
        // SAGA must NOT be triggered again — no save, no executeSaga
        verify(orderRepository, never()).save(any());
        verify(sagaOrchestrator, never()).executeSaga(any());
    }

    @Test
    @DisplayName("createOrder: null idempotencyKey always runs SAGA (no short-circuit)")
    void createOrder_nullIdempotencyKey_alwaysRunsSaga() {
        request.setIdempotencyKey(null);

        Order saved = buildOrder("ord-003", SagaStatus.PENDING);
        Order completed = buildOrder("ord-003", SagaStatus.COMPLETED);
        completed.setShipmentId("ship-003");

        when(orderRepository.save(any(Order.class))).thenReturn(saved);
        when(sagaOrchestrator.executeSaga(any(Order.class))).thenReturn(completed);

        orderService.createOrder(request);

        verify(orderRepository, never()).findByIdempotencyKey(any());
        verify(sagaOrchestrator, times(1)).executeSaga(any(Order.class));
    }

    @Test
    @DisplayName("createOrder: blank idempotencyKey always runs SAGA (no short-circuit)")
    void createOrder_blankIdempotencyKey_alwaysRunsSaga() {
        request.setIdempotencyKey("   ");

        Order saved = buildOrder("ord-004", SagaStatus.PENDING);
        Order completed = buildOrder("ord-004", SagaStatus.COMPLETED);

        when(orderRepository.save(any(Order.class))).thenReturn(saved);
        when(sagaOrchestrator.executeSaga(any(Order.class))).thenReturn(completed);

        orderService.createOrder(request);

        verify(sagaOrchestrator, times(1)).executeSaga(any(Order.class));
    }

    // ────────────────────────────────────────────────────────────────────────
    //  getOrder
    // ────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("getOrder: existing orderId returns correct OrderResponse")
    void getOrder_existingId_returnsOrder() {
        Order order = buildOrder("ord-001", SagaStatus.COMPLETED);
        order.setShipmentId("ship-001");

        when(orderRepository.findById("ord-001")).thenReturn(Optional.of(order));

        OrderResponse response = orderService.getOrder("ord-001");

        assertThat(response.getOrderId()).isEqualTo("ord-001");
        assertThat(response.getStatus()).isEqualTo(SagaStatus.COMPLETED);
    }

    @Test
    @DisplayName("getOrder: non-existent orderId throws RuntimeException")
    void getOrder_notFound_throwsException() {
        when(orderRepository.findById("unknown")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> orderService.getOrder("unknown"))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("unknown");
    }

    // ────────────────────────────────────────────────────────────────────────
    //  getAllOrders
    // ────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("getAllOrders: returns all orders mapped to responses")
    void getAllOrders_returnsAllOrders() {
        List<Order> orders = List.of(
                buildOrder("ord-001", SagaStatus.COMPLETED),
                buildOrder("ord-002", SagaStatus.PAYMENT_FAILED),
                buildOrder("ord-003", SagaStatus.INVENTORY_FAILED)
        );
        when(orderRepository.findAll()).thenReturn(orders);

        List<OrderResponse> responses = orderService.getAllOrders();

        assertThat(responses).hasSize(3);
        assertThat(responses).extracting(OrderResponse::getStatus)
                .containsExactlyInAnyOrder(
                        SagaStatus.COMPLETED,
                        SagaStatus.PAYMENT_FAILED,
                        SagaStatus.INVENTORY_FAILED
                );
    }

    @Test
    @DisplayName("getAllOrders: empty repository returns empty list")
    void getAllOrders_emptyRepo_returnsEmptyList() {
        when(orderRepository.findAll()).thenReturn(List.of());

        List<OrderResponse> responses = orderService.getAllOrders();

        assertThat(responses).isEmpty();
    }

    // ────────────────────────────────────────────────────────────────────────
    //  buildMessage coverage — failure reason vs status name
    // ────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("getOrder: FAILED order with failureReason shows it in message")
    void getOrder_failedOrder_messageContainsFailureReason() {
        Order failedOrder = buildOrder("ord-fail", SagaStatus.SHIPPING_FAILED);
        failedOrder.setFailureReason("address is restricted");

        when(orderRepository.findById("ord-fail")).thenReturn(Optional.of(failedOrder));

        OrderResponse response = orderService.getOrder("ord-fail");

        assertThat(response.getMessage()).contains("address is restricted");
    }

    @Test
    @DisplayName("getOrder: FAILED order without failureReason shows status name in message")
    void getOrder_failedOrderNoReason_messageContainsStatusName() {
        Order failedOrder = buildOrder("ord-nofail", SagaStatus.INVENTORY_FAILED);

        when(orderRepository.findById("ord-nofail")).thenReturn(Optional.of(failedOrder));

        OrderResponse response = orderService.getOrder("ord-nofail");

        assertThat(response.getMessage()).contains("INVENTORY_FAILED");
    }

    // ────────────────────────────────────────────────────────────────────────
    //  Helper
    // ────────────────────────────────────────────────────────────────────────

    private Order buildOrder(String id, SagaStatus status) {
        return Order.builder()
                .id(id)
                .customerId("CUST-001")
                .productId("PROD-001")
                .quantity(2)
                .amount(new BigDecimal("199.99"))
                .shippingAddress("123 Main St")
                .sagaStatus(status)
                .build();
    }
}
