package com.saga.choreography.inventory;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ChoreographyProductStockRepository extends JpaRepository<ChoreographyProductStock, String> {
}
