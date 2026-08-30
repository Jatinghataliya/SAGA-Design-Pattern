package com.saga.choreography.commons.events;

public class InventoryReservedEvent extends SagaEvent {

    private final Long customerId;
    private final Long paymentId;
    private final Long reservationId;
    private final String productId;
    private final Integer quantity;
    private final String shippingAddress;
    private final java.math.BigDecimal amount;

    public InventoryReservedEvent(Long orderId, Long customerId, Long paymentId,
                                  Long reservationId, String productId,
                                  Integer quantity, String shippingAddress,
                                  java.math.BigDecimal amount) {
        super(orderId, EventType.INVENTORY_RESERVED);
        this.customerId = customerId;
        this.paymentId = paymentId;
        this.reservationId = reservationId;
        this.productId = productId;
        this.quantity = quantity;
        this.shippingAddress = shippingAddress;
        this.amount = amount;
    }

    public Long getCustomerId() { return customerId; }
    public Long getPaymentId() { return paymentId; }
    public Long getReservationId() { return reservationId; }
    public String getProductId() { return productId; }
    public Integer getQuantity() { return quantity; }
    public String getShippingAddress() { return shippingAddress; }
    public java.math.BigDecimal getAmount() { return amount; }
}
