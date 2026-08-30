package com.saga.choreography.payment;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface ChoreographyPaymentRepository extends JpaRepository<ChoreographyPayment, Long> {
    Optional<ChoreographyPayment> findByOrderId(Long orderId);
}
