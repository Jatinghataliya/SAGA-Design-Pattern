package com.saga.commons.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ShippingRequest {
    private String orderId;
    private String customerId;
    private String productId;
    private int quantity;
    private String shippingAddress;
}
