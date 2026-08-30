package com.saga.choreography.commons.events;

public class PaymentRefundedEvent extends SagaEvent {

    private final Long paymentId;
    private final String reason;

    public PaymentRefundedEvent(Long orderId, Long paymentId, String reason) {
        super(orderId, EventType.PAYMENT_REFUNDED);
        this.paymentId = paymentId;
        this.reason = reason;
    }

    public Long getPaymentId() { return paymentId; }
    public String getReason() { return reason; }
}
