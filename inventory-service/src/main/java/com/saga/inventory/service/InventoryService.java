package com.saga.inventory.service;

import com.saga.commons.dto.InventoryRequest;
import com.saga.commons.dto.InventoryResponse;
import com.saga.commons.enums.InventoryStatus;
import com.saga.inventory.entity.InventoryReservation;
import com.saga.inventory.entity.ProductStock;
import com.saga.inventory.repository.InventoryReservationRepository;
import com.saga.inventory.repository.ProductStockRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class InventoryService {

    private final InventoryReservationRepository reservationRepository;
    private final ProductStockRepository stockRepository;

    /**
     * Forward transaction: reserve stock for an order.
     * Uses an optimistic lock via @Transactional to prevent race conditions.
     */
    @Transactional
    public InventoryResponse reserveInventory(InventoryRequest request) {
        log.info("Reserving inventory for orderId={} productId={} qty={}",
                request.getOrderId(), request.getProductId(), request.getQuantity());

        ProductStock stock = stockRepository.findById(request.getProductId()).orElse(null);

        if (stock == null || stock.getAvailableQuantity() < request.getQuantity()) {
            int available = stock != null ? stock.getAvailableQuantity() : 0;
            log.warn("Insufficient stock for productId={}. Available={}, Requested={}",
                    request.getProductId(), available, request.getQuantity());

            InventoryReservation reservation = InventoryReservation.builder()
                    .orderId(request.getOrderId())
                    .productId(request.getProductId())
                    .quantity(request.getQuantity())
                    .status(InventoryStatus.INSUFFICIENT_STOCK)
                    .build();
            reservationRepository.save(reservation);

            return InventoryResponse.builder()
                    .reservationId(reservation.getId())
                    .orderId(request.getOrderId())
                    .productId(request.getProductId())
                    .quantity(request.getQuantity())
                    .status(InventoryStatus.INSUFFICIENT_STOCK)
                    .message("Insufficient stock. Available: " + available + ", Requested: " + request.getQuantity())
                    .build();
        }

        // Deduct stock
        stock.setAvailableQuantity(stock.getAvailableQuantity() - request.getQuantity());
        stockRepository.save(stock);

        InventoryReservation reservation = InventoryReservation.builder()
                .orderId(request.getOrderId())
                .productId(request.getProductId())
                .quantity(request.getQuantity())
                .status(InventoryStatus.RESERVED)
                .build();
        reservationRepository.save(reservation);

        log.info("Inventory RESERVED. reservationId={}", reservation.getId());
        return InventoryResponse.builder()
                .reservationId(reservation.getId())
                .orderId(request.getOrderId())
                .productId(request.getProductId())
                .quantity(request.getQuantity())
                .status(InventoryStatus.RESERVED)
                .message("Inventory reserved successfully")
                .build();
    }

    /**
     * Compensating transaction: release a previously reserved inventory slot.
     * Called by the orchestrator when the shipping step fails.
     */
    @Transactional
    public InventoryResponse releaseInventory(String reservationId) {
        log.info("[COMPENSATE] Releasing inventory reservationId={}", reservationId);
        InventoryReservation reservation = reservationRepository.findById(reservationId)
                .orElseThrow(() -> new RuntimeException("Reservation not found: " + reservationId));

        // Return stock
        ProductStock stock = stockRepository.findById(reservation.getProductId()).orElse(null);
        if (stock != null) {
            stock.setAvailableQuantity(stock.getAvailableQuantity() + reservation.getQuantity());
            stockRepository.save(stock);
        }

        reservation.setStatus(InventoryStatus.RELEASED);
        reservationRepository.save(reservation);

        log.info("[COMPENSATE] Inventory RELEASED for reservationId={}", reservationId);
        return InventoryResponse.builder()
                .reservationId(reservationId)
                .orderId(reservation.getOrderId())
                .productId(reservation.getProductId())
                .quantity(reservation.getQuantity())
                .status(InventoryStatus.RELEASED)
                .message("Inventory released as part of SAGA compensation")
                .build();
    }
}
