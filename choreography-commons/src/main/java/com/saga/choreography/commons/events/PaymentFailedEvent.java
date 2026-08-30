package com.saga.choreography.commons.events;

public class PaymentFailedEvent extends SagaEvent {

    private final String reason;

    public PaymentFailedEvent(Long orderId, String reason) {
        super(orderId, EventType.PAYMENT_FAILED);
        this.reason = reason;
    }

    public String getReason() { return reason; }
}
