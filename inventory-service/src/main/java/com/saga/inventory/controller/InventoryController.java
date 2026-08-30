package com.saga.inventory.controller;

import com.saga.commons.dto.InventoryRequest;
import com.saga.commons.dto.InventoryResponse;
import com.saga.inventory.service.InventoryService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/inventory")
@RequiredArgsConstructor
public class InventoryController {

    private final InventoryService inventoryService;

    /**
     * POST /inventory/reserve
     * Called by the orchestrator as the second saga step.
     */
    @PostMapping("/reserve")
    public ResponseEntity<InventoryResponse> reserveInventory(@RequestBody InventoryRequest request) {
        return ResponseEntity.ok(inventoryService.reserveInventory(request));
    }

    /**
     * POST /inventory/release/{reservationId}
     * COMPENSATING transaction — called by the orchestrator on saga failure.
     */
    @PostMapping("/release/{reservationId}")
    public ResponseEntity<InventoryResponse> releaseInventory(@PathVariable String reservationId) {
        return ResponseEntity.ok(inventoryService.releaseInventory(reservationId));
    }
}
