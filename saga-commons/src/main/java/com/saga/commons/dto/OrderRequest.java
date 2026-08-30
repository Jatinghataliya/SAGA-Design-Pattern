package com.saga.commons.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OrderRequest {

    /**
     * Client-supplied idempotency key (e.g. UUID generated on the client side).
     * If the same key is submitted more than once, the original order is returned
     * without re-running the SAGA or charging the customer again.
     * If omitted, every call creates a new order (backwards-compatible).
     */
    private String idempotencyKey;

    private String customerId;
    private String productId;
    private int quantity;
    private BigDecimal amount;
    private String shippingAddress;
}
