package com.saga.choreography.inventory;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface ChoreographyInventoryReservationRepository extends JpaRepository<ChoreographyInventoryReservation, Long> {
    Optional<ChoreographyInventoryReservation> findByOrderId(Long orderId);
}
