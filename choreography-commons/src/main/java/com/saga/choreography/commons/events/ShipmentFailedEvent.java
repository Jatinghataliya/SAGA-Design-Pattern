package com.saga.choreography.commons.events;

public class ShipmentFailedEvent extends SagaEvent {

    private final Long paymentId;
    private final Long reservationId;
    private final String reason;

    public ShipmentFailedEvent(Long orderId, Long paymentId, Long reservationId, String reason) {
        super(orderId, EventType.SHIPMENT_FAILED);
        this.paymentId = paymentId;
        this.reservationId = reservationId;
        this.reason = reason;
    }

    public Long getPaymentId() { return paymentId; }
    public Long getReservationId() { return reservationId; }
    public String getReason() { return reason; }
}
