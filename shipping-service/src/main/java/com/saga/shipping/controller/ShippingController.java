package com.saga.shipping.controller;

import com.saga.commons.dto.ShippingRequest;
import com.saga.commons.dto.ShippingResponse;
import com.saga.shipping.service.ShippingService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/shipping")
@RequiredArgsConstructor
public class ShippingController {

    private final ShippingService shippingService;

    /**
     * POST /shipping/schedule
     * Called by the orchestrator as the third saga step.
     */
    @PostMapping("/schedule")
    public ResponseEntity<ShippingResponse> scheduleShipment(@RequestBody ShippingRequest request) {
        return ResponseEntity.ok(shippingService.scheduleShipment(request));
    }

    /**
     * POST /shipping/cancel/{shipmentId}
     * COMPENSATING transaction.
     */
    @PostMapping("/cancel/{shipmentId}")
    public ResponseEntity<ShippingResponse> cancelShipment(@PathVariable String shipmentId) {
        return ResponseEntity.ok(shippingService.cancelShipment(shipmentId));
    }
}
