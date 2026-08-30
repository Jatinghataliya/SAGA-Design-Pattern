package com.saga.choreography.commons.events;

import java.math.BigDecimal;

public class OrderCreatedEvent extends SagaEvent {

    private final Long customerId;
    private final String productId;
    private final Integer quantity;
    private final BigDecimal amount;
    private final String shippingAddress;

    public OrderCreatedEvent(Long orderId, Long customerId, String productId,
                             Integer quantity, BigDecimal amount, String shippingAddress) {
        super(orderId, EventType.ORDER_CREATED);
        this.customerId = customerId;
        this.productId = productId;
        this.quantity = quantity;
        this.amount = amount;
        this.shippingAddress = shippingAddress;
    }

    public Long getCustomerId() { return customerId; }
    public String getProductId() { return productId; }
    public Integer getQuantity() { return quantity; }
    public BigDecimal getAmount() { return amount; }
    public String getShippingAddress() { return shippingAddress; }
}
