package com.saga.choreography.order;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/choreography/orders")
public class ChoreographyOrderController {

    private final ChoreographyOrderService orderService;

    public ChoreographyOrderController(ChoreographyOrderService orderService) {
        this.orderService = orderService;
    }

    @PostMapping
    public ResponseEntity<ChoreographyOrder> createOrder(@RequestBody CreateOrderRequest request) {
        ChoreographyOrder order = orderService.createOrder(request);
        return ResponseEntity.ok(order);
    }

    @GetMapping("/{id}")
    public ResponseEntity<ChoreographyOrder> getOrder(@PathVariable Long id) {
        return ResponseEntity.ok(orderService.getOrder(id));
    }

    @GetMapping
    public ResponseEntity<List<ChoreographyOrder>> getAllOrders() {
        return ResponseEntity.ok(orderService.getAllOrders());
    }
}
