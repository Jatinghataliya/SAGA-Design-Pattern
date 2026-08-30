package com.saga.choreography.commons.events;

public class InventoryFailedEvent extends SagaEvent {

    private final Long paymentId;
    private final String reason;

    public InventoryFailedEvent(Long orderId, Long paymentId, String reason) {
        super(orderId, EventType.INVENTORY_FAILED);
        this.paymentId = paymentId;
        this.reason = reason;
    }

    public Long getPaymentId() { return paymentId; }
    public String getReason() { return reason; }
}
