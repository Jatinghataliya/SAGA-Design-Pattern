package com.saga.shipping.service;

import com.saga.commons.dto.ShippingRequest;
import com.saga.commons.dto.ShippingResponse;
import com.saga.commons.enums.ShippingStatus;
import com.saga.shipping.entity.Shipment;
import com.saga.shipping.repository.ShipmentRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class ShippingService {

    private final ShipmentRepository shipmentRepository;

    // Simulate a blacklisted shipping address to trigger failure scenario
    private static final String BLOCKED_ADDRESS = "BLOCKED";

    /**
     * Forward transaction: schedule a shipment.
     *
     * Business rule: reject orders to "BLOCKED" addresses.
     * In a real system this would call a carrier API (FedEx, UPS, etc).
     */
    public ShippingResponse scheduleShipment(ShippingRequest request) {
        log.info("Scheduling shipment for orderId={} address={}",
                request.getOrderId(), request.getShippingAddress());

        // ── Idempotency guard ────────────────────────────────────────────────
        // orderId has a UNIQUE constraint — if a shipment already exists for
        // this order, return it directly without scheduling again.
        var existing = shipmentRepository.findByOrderId(request.getOrderId());
        if (existing.isPresent()) {
            Shipment s = existing.get();
            log.info("[IDEMPOTENT] Shipment already exists for orderId={}. Returning shipmentId={} status={}",
                    request.getOrderId(), s.getId(), s.getStatus());
            return ShippingResponse.builder()
                    .shipmentId(s.getId())
                    .orderId(s.getOrderId())
                    .trackingNumber(s.getTrackingNumber())
                    .status(s.getStatus())
                    .message("[IDEMPOTENT] Returning existing shipment result")
                    .build();
        }
        // ────────────────────────────────────────────────────────────────────

        if (request.getShippingAddress() != null &&
                request.getShippingAddress().toUpperCase().contains(BLOCKED_ADDRESS)) {
            log.warn("Shipping FAILED — address is blocked: {}", request.getShippingAddress());
            Shipment shipment = Shipment.builder()
                    .orderId(request.getOrderId())
                    .customerId(request.getCustomerId())
                    .productId(request.getProductId())
                    .quantity(request.getQuantity())
                    .shippingAddress(request.getShippingAddress())
                    .status(ShippingStatus.FAILED)
                    .build();
            shipmentRepository.save(shipment);

            return ShippingResponse.builder()
                    .shipmentId(shipment.getId())
                    .orderId(request.getOrderId())
                    .status(ShippingStatus.FAILED)
                    .message("Shipping failed: address is restricted")
                    .build();
        }

        String trackingNumber = "TRK-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase();

        Shipment shipment = Shipment.builder()
                .orderId(request.getOrderId())
                .customerId(request.getCustomerId())
                .productId(request.getProductId())
                .quantity(request.getQuantity())
                .shippingAddress(request.getShippingAddress())
                .trackingNumber(trackingNumber)
                .status(ShippingStatus.SCHEDULED)
                .build();
        shipmentRepository.save(shipment);

        log.info("Shipment SCHEDULED. shipmentId={} tracking={}", shipment.getId(), trackingNumber);
        return ShippingResponse.builder()
                .shipmentId(shipment.getId())
                .orderId(request.getOrderId())
                .trackingNumber(trackingNumber)
                .status(ShippingStatus.SCHEDULED)
                .message("Shipment scheduled successfully. Tracking: " + trackingNumber)
                .build();
    }

    /**
     * Compensating transaction: cancel a shipment.
     * Called by the orchestrator (if needed in extended scenarios).
     */
    public ShippingResponse cancelShipment(String shipmentId) {
        log.info("[COMPENSATE] Cancelling shipmentId={}", shipmentId);
        Shipment shipment = shipmentRepository.findById(shipmentId)
                .orElseThrow(() -> new RuntimeException("Shipment not found: " + shipmentId));

        shipment.setStatus(ShippingStatus.CANCELLED);
        shipmentRepository.save(shipment);

        return ShippingResponse.builder()
                .shipmentId(shipmentId)
                .orderId(shipment.getOrderId())
                .status(ShippingStatus.CANCELLED)
                .message("Shipment cancelled as part of SAGA compensation")
                .build();
    }
}
