package com.saga.inventory.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Represents the stock level of a product.
 * Pre-seeded via data.sql on startup.
 */
@Entity
@Table(name = "product_stock")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ProductStock {

    @Id
    private String productId;

    @Column(nullable = false)
    private int availableQuantity;
}
