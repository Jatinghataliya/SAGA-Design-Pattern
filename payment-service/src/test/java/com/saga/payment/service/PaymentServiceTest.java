package com.saga.payment.service;

import com.saga.commons.dto.PaymentRequest;
import com.saga.commons.dto.PaymentResponse;
import com.saga.commons.enums.PaymentStatus;
import com.saga.payment.entity.Payment;
import com.saga.payment.repository.PaymentRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@DisplayName("PaymentService Unit Tests")
class PaymentServiceTest {

    @Mock
    private PaymentRepository paymentRepository;

    @InjectMocks
    private PaymentService paymentService;

    private PaymentRequest validRequest;

    @BeforeEach
    void setUp() {
        validRequest = PaymentRequest.builder()
                .orderId("order-001")
                .customerId("cust-001")
                .amount(new BigDecimal("199.99"))
                .build();
    }

    // ────────────────────────────────────────────────────────────────────────
    //  processPayment — happy path
    // ────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("processPayment: amount within limit should return APPROVED")
    void processPayment_withinCreditLimit_returnsApproved() {
        when(paymentRepository.findByOrderId("order-001")).thenReturn(Optional.empty());
        when(paymentRepository.save(any(Payment.class))).thenAnswer(inv -> {
            Payment p = inv.getArgument(0);
            // Simulate DB assigning an ID
            return Payment.builder()
                    .id("pay-001")
                    .orderId(p.getOrderId())
                    .customerId(p.getCustomerId())
                    .amount(p.getAmount())
                    .status(p.getStatus())
                    .processedAt(LocalDateTime.now())
                    .build();
        });

        PaymentResponse response = paymentService.processPayment(validRequest);

        assertThat(response.getStatus()).isEqualTo(PaymentStatus.APPROVED);
        assertThat(response.getOrderId()).isEqualTo("order-001");
        assertThat(response.getMessage()).contains("approved");
        verify(paymentRepository, times(1)).save(any(Payment.class));
    }

    // ────────────────────────────────────────────────────────────────────────
    //  processPayment — credit limit exceeded
    // ────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("processPayment: amount exceeding $10,000 credit limit should return DECLINED")
    void processPayment_exceedsCreditLimit_returnsDeclined() {
        PaymentRequest bigRequest = PaymentRequest.builder()
                .orderId("order-002")
                .customerId("cust-001")
                .amount(new BigDecimal("99999.00"))
                .build();

        when(paymentRepository.findByOrderId("order-002")).thenReturn(Optional.empty());
        when(paymentRepository.save(any(Payment.class))).thenAnswer(inv -> {
            Payment p = inv.getArgument(0);
            return Payment.builder()
                    .id("pay-002")
                    .orderId(p.getOrderId())
                    .customerId(p.getCustomerId())
                    .amount(p.getAmount())
                    .status(p.getStatus())
                    .processedAt(LocalDateTime.now())
                    .build();
        });

        PaymentResponse response = paymentService.processPayment(bigRequest);

        assertThat(response.getStatus()).isEqualTo(PaymentStatus.DECLINED);
        assertThat(response.getMessage()).contains("credit limit");
        verify(paymentRepository, times(1)).save(any(Payment.class));
    }

    @Test
    @DisplayName("processPayment: amount exactly at credit limit ($10,000) should be APPROVED")
    void processPayment_exactlyAtCreditLimit_returnsApproved() {
        PaymentRequest limitRequest = PaymentRequest.builder()
                .orderId("order-003")
                .customerId("cust-001")
                .amount(new BigDecimal("10000.00"))
                .build();

        when(paymentRepository.findByOrderId("order-003")).thenReturn(Optional.empty());
        when(paymentRepository.save(any(Payment.class))).thenAnswer(inv -> {
            Payment p = inv.getArgument(0);
            return Payment.builder().id("pay-003")
                    .orderId(p.getOrderId()).customerId(p.getCustomerId())
                    .amount(p.getAmount()).status(p.getStatus())
                    .processedAt(LocalDateTime.now()).build();
        });

        PaymentResponse response = paymentService.processPayment(limitRequest);

        assertThat(response.getStatus()).isEqualTo(PaymentStatus.APPROVED);
    }

    // ────────────────────────────────────────────────────────────────────────
    //  processPayment — idempotency
    // ────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("processPayment: duplicate orderId should return existing payment (idempotency)")
    void processPayment_duplicateOrderId_returnsExistingPayment() {
        Payment existing = Payment.builder()
                .id("pay-existing")
                .orderId("order-001")
                .customerId("cust-001")
                .amount(new BigDecimal("199.99"))
                .status(PaymentStatus.APPROVED)
                .processedAt(LocalDateTime.now())
                .build();

        when(paymentRepository.findByOrderId("order-001")).thenReturn(Optional.of(existing));

        PaymentResponse response = paymentService.processPayment(validRequest);

        assertThat(response.getPaymentId()).isEqualTo("pay-existing");
        assertThat(response.getStatus()).isEqualTo(PaymentStatus.APPROVED);
        assertThat(response.getMessage()).contains("IDEMPOTENT");
        // Must NOT call save — no second charge
        verify(paymentRepository, never()).save(any());
    }

    // ────────────────────────────────────────────────────────────────────────
    //  refundPayment — happy path
    // ────────────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("refundPayment: existing approved payment should be REFUNDED")
    void refundPayment_existingPayment_returnsRefunded() {
        Payment approved = Payment.builder()
                .id("pay-001")
                .orderId("order-001")
                .customerId("cust-001")
                .amount(new BigDecimal("199.99"))
                .status(PaymentStatus.APPROVED)
                .processedAt(LocalDateTime.now())
                .build();

        when(paymentRepository.findById("pay-001")).thenReturn(Optional.of(approved));
        when(paymentRepository.save(any(Payment.class))).thenAnswer(inv -> inv.getArgument(0));

        PaymentResponse response = paymentService.refundPayment("pay-001");

        assertThat(response.getStatus()).isEqualTo(PaymentStatus.REFUNDED);
        assertThat(response.getPaymentId()).isEqualTo("pay-001");
        assertThat(response.getMessage()).contains("compensation");
        verify(paymentRepository, times(1)).save(any(Payment.class));
    }

    @Test
    @DisplayName("refundPayment: non-existent paymentId should throw RuntimeException")
    void refundPayment_notFound_throwsException() {
        when(paymentRepository.findById("pay-unknown")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> paymentService.refundPayment("pay-unknown"))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("pay-unknown");
    }
}
