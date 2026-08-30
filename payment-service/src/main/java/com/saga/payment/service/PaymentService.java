package com.saga.payment.service;

import com.saga.commons.dto.PaymentRequest;
import com.saga.commons.dto.PaymentResponse;
import com.saga.commons.enums.PaymentStatus;
import com.saga.payment.entity.Payment;
import com.saga.payment.repository.PaymentRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;

@Slf4j
@Service
@RequiredArgsConstructor
public class PaymentService {

    private final PaymentRepository paymentRepository;

    // Simulate a credit limit — orders above this amount will be declined
    private static final BigDecimal CREDIT_LIMIT = new BigDecimal("10000.00");

    /**
     * Forward transaction: debit the customer's account.
     *
     * Business rule: decline if amount exceeds credit limit.
     * In a real system this would integrate with a payment gateway.
     */
    public PaymentResponse processPayment(PaymentRequest request) {
        log.info("Processing payment for orderId={} amount={}", request.getOrderId(), request.getAmount());

        if (request.getAmount().compareTo(CREDIT_LIMIT) > 0) {
            log.warn("Payment DECLINED — amount {} exceeds credit limit {}", request.getAmount(), CREDIT_LIMIT);
            Payment payment = Payment.builder()
                    .orderId(request.getOrderId())
                    .customerId(request.getCustomerId())
                    .amount(request.getAmount())
                    .status(PaymentStatus.DECLINED)
                    .build();
            paymentRepository.save(payment);
            return PaymentResponse.builder()
                    .paymentId(payment.getId())
                    .orderId(request.getOrderId())
                    .amount(request.getAmount())
                    .status(PaymentStatus.DECLINED)
                    .message("Payment declined: amount exceeds credit limit of " + CREDIT_LIMIT)
                    .build();
        }

        Payment payment = Payment.builder()
                .orderId(request.getOrderId())
                .customerId(request.getCustomerId())
                .amount(request.getAmount())
                .status(PaymentStatus.APPROVED)
                .build();
        paymentRepository.save(payment);
        log.info("Payment APPROVED. paymentId={}", payment.getId());

        return PaymentResponse.builder()
                .paymentId(payment.getId())
                .orderId(request.getOrderId())
                .amount(request.getAmount())
                .status(PaymentStatus.APPROVED)
                .message("Payment approved successfully")
                .build();
    }

    /**
     * Compensating transaction: refund a previously approved payment.
     * Called by the orchestrator when a downstream step fails.
     */
    public PaymentResponse refundPayment(String paymentId) {
        log.info("[COMPENSATE] Refunding paymentId={}", paymentId);
        Payment payment = paymentRepository.findById(paymentId)
                .orElseThrow(() -> new RuntimeException("Payment not found: " + paymentId));

        payment.setStatus(PaymentStatus.REFUNDED);
        paymentRepository.save(payment);

        log.info("[COMPENSATE] Payment REFUNDED. paymentId={}", paymentId);
        return PaymentResponse.builder()
                .paymentId(paymentId)
                .orderId(payment.getOrderId())
                .amount(payment.getAmount())
                .status(PaymentStatus.REFUNDED)
                .message("Payment refunded as part of SAGA compensation")
                .build();
    }
}
