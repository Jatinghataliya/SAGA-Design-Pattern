package com.saga.choreography.inventory;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "choreography_inventory_reservations")
public class ChoreographyInventoryReservation {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long orderId;
    private String productId;
    private Integer quantity;

    @Enumerated(EnumType.STRING)
    private ReservationStatus status;

    public ChoreographyInventoryReservation() {}

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getOrderId() { return orderId; }
    public void setOrderId(Long orderId) { this.orderId = orderId; }

    public String getProductId() { return productId; }
    public void setProductId(String productId) { this.productId = productId; }

    public Integer getQuantity() { return quantity; }
    public void setQuantity(Integer quantity) { this.quantity = quantity; }

    public ReservationStatus getStatus() { return status; }
    public void setStatus(ReservationStatus status) { this.status = status; }
}
