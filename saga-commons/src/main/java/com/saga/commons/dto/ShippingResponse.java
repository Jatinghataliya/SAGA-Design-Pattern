package com.saga.commons.dto;

import com.saga.commons.enums.ShippingStatus;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ShippingResponse {
    private String shipmentId;
    private String orderId;
    private String trackingNumber;
    private ShippingStatus status;
    private String message;
}
