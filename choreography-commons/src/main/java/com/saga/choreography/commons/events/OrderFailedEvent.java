package com.saga.choreography.commons.events;

public class OrderFailedEvent extends SagaEvent {

    private final String reason;

    public OrderFailedEvent(Long orderId, String reason) {
        super(orderId, EventType.ORDER_FAILED);
        this.reason = reason;
    }

    public String getReason() { return reason; }
}
