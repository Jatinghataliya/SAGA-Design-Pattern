package com.saga.choreography.commons.events;

public class InventoryReleasedEvent extends SagaEvent {

    private final Long paymentId;
    private final Long reservationId;
    private final String reason;

    public InventoryReleasedEvent(Long orderId, Long paymentId, Long reservationId, String reason) {
        super(orderId, EventType.INVENTORY_RELEASED);
        this.paymentId = paymentId;
        this.reservationId = reservationId;
        this.reason = reason;
    }

    public Long getPaymentId() { return paymentId; }
    public Long getReservationId() { return reservationId; }
    public String getReason() { return reason; }
}
