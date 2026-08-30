package com.saga.choreography.shipping;

import jakarta.persistence.*;

@Entity
@Table(name = "choreography_shipments")
public class ChoreographyShipment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long orderId;
    private String shippingAddress;

    @Enumerated(EnumType.STRING)
    private ShipmentStatus status;

    public ChoreographyShipment() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getOrderId() { return orderId; }
    public void setOrderId(Long orderId) { this.orderId = orderId; }

    public String getShippingAddress() { return shippingAddress; }
    public void setShippingAddress(String shippingAddress) { this.shippingAddress = shippingAddress; }

    public ShipmentStatus getStatus() { return status; }
    public void setStatus(ShipmentStatus status) { this.status = status; }
}
