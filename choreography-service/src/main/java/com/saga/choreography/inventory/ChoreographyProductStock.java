package com.saga.choreography.inventory;

import jakarta.persistence.*;

@Entity
@Table(name = "choreography_product_stock")
public class ChoreographyProductStock {

    @Id
    private String productId;

    private Integer availableQuantity;

    public ChoreographyProductStock() {}

    public ChoreographyProductStock(String productId, Integer availableQuantity) {
        this.productId = productId;
        this.availableQuantity = availableQuantity;
    }

    public String getProductId() { return productId; }
    public void setProductId(String productId) { this.productId = productId; }

    public Integer getAvailableQuantity() { return availableQuantity; }
    public void setAvailableQuantity(Integer availableQuantity) { this.availableQuantity = availableQuantity; }
}
