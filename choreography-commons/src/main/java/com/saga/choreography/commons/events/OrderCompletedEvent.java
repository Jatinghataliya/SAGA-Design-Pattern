package com.saga.choreography.commons.events;

public class OrderCompletedEvent extends SagaEvent {

    private final Long shipmentId;

    public OrderCompletedEvent(Long orderId, Long shipmentId) {
        super(orderId, EventType.ORDER_COMPLETED);
        this.shipmentId = shipmentId;
    }

    public Long getShipmentId() { return shipmentId; }
}
