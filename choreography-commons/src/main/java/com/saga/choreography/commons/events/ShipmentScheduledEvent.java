package com.saga.choreography.commons.events;

public class ShipmentScheduledEvent extends SagaEvent {

    private final Long shipmentId;

    public ShipmentScheduledEvent(Long orderId, Long shipmentId) {
        super(orderId, EventType.SHIPMENT_SCHEDULED);
        this.shipmentId = shipmentId;
    }

    public Long getShipmentId() { return shipmentId; }
}
