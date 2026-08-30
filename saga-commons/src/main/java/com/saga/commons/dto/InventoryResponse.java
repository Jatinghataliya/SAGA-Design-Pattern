package com.saga.commons.dto;

import com.saga.commons.enums.InventoryStatus;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InventoryResponse {
    private String reservationId;
    private String orderId;
    private String productId;
    private int quantity;
    private InventoryStatus status;
    private String message;
}
