package com.saga.choreography.commons.events;

import java.math.BigDecimal;

public class PaymentApprovedEvent extends SagaEvent {

    private final Long customerId;
    private final Long paymentId;
    private final String productId;
    private final Integer quantity;
    private final String shippingAddress;
    private final BigDecimal amount;

    public PaymentApprovedEvent(Long orderId, Long customerId, Long paymentId,
                                String productId, Integer quantity,
                                String shippingAddress, BigDecimal amount) {
        super(orderId, EventType.PAYMENT_APPROVED);
        this.customerId = customerId;
        this.paymentId = paymentId;
        this.productId = productId;
        this.quantity = quantity;
        this.shippingAddress = shippingAddress;
        this.amount = amount;
    }

    public Long getCustomerId() { return customerId; }
    public Long getPaymentId() { return paymentId; }
    public String getProductId() { return productId; }
    public Integer getQuantity() { return quantity; }
    public String getShippingAddress() { return shippingAddress; }
    public BigDecimal getAmount() { return amount; }
}
