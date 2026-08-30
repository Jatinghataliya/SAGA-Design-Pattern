package com.saga.choreography.order;

public enum ChoreographyOrderStatus {
    PENDING,
    PAYMENT_PROCESSING,
    INVENTORY_RESERVING,
    SHIPPING_SCHEDULING,
    COMPLETED,
    FAILED
}
