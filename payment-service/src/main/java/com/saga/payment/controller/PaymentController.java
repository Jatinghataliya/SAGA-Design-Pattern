package com.saga.payment.controller;

import com.saga.commons.dto.PaymentRequest;
import com.saga.commons.dto.PaymentResponse;
import com.saga.payment.service.PaymentService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/payments")
@RequiredArgsConstructor
public class PaymentController {

    private final PaymentService paymentService;

    /**
     * POST /payments/process
     * Called by the orchestrator as the first saga step.
     */
    @PostMapping("/process")
    public ResponseEntity<PaymentResponse> processPayment(@RequestBody PaymentRequest request) {
        return ResponseEntity.ok(paymentService.processPayment(request));
    }

    /**
     * POST /payments/refund/{paymentId}
     * COMPENSATING transaction — called by the orchestrator on saga failure.
     */
    @PostMapping("/refund/{paymentId}")
    public ResponseEntity<PaymentResponse> refundPayment(@PathVariable String paymentId) {
        return ResponseEntity.ok(paymentService.refundPayment(paymentId));
    }
}
