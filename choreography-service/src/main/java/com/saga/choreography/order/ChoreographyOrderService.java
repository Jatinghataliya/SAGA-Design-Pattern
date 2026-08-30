package com.saga.choreography.order;

import com.saga.choreography.common.EventBus;
import com.saga.choreography.commons.events.*;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class ChoreographyOrderService {

    private final ChoreographyOrderRepository orderRepository;
    private final EventBus eventBus;

    public ChoreographyOrderService(ChoreographyOrderRepository orderRepository, EventBus eventBus) {
        this.orderRepository = orderRepository;
        this.eventBus = eventBus;
    }

    @Transactional
    public ChoreographyOrder createOrder(CreateOrderRequest request) {
        ChoreographyOrder order = new ChoreographyOrder();
        order.setCustomerId(request.getCustomerId());
        order.setProductId(request.getProductId());
        order.setQuantity(request.getQuantity());
        order.setAmount(request.getAmount());
        order.setShippingAddress(request.getShippingAddress());
        order.setStatus(ChoreographyOrderStatus.PENDING);
        order = orderRepository.save(order);

        eventBus.publish(new OrderCreatedEvent(
                order.getId(),
                order.getCustomerId(),
                order.getProductId(),
                order.getQuantity(),
                order.getAmount(),
                order.getShippingAddress()
        ));

        return orderRepository.findById(order.getId()).orElse(order);
    }

    public ChoreographyOrder getOrder(Long id) {
        return orderRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Order not found: " + id));
    }

    public List<ChoreographyOrder> getAllOrders() {
        return orderRepository.findAll();
    }

    @EventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onOrderCompleted(OrderCompletedEvent event) {
        orderRepository.findById(event.getOrderId()).ifPresent(order -> {
            order.setStatus(ChoreographyOrderStatus.COMPLETED);
            order.setShipmentId(event.getShipmentId());
            orderRepository.save(order);
        });
    }

    @EventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onPaymentFailed(PaymentFailedEvent event) {
        // Payment declined → order failed immediately
        eventBus.publish(new OrderFailedEvent(event.getOrderId(), event.getReason()));
    }

    @EventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onPaymentRefunded(PaymentRefundedEvent event) {
        // Payment was refunded after inventory/shipping failure → order failed
        eventBus.publish(new OrderFailedEvent(event.getOrderId(), event.getReason()));
    }

    @EventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onOrderFailed(OrderFailedEvent event) {
        orderRepository.findById(event.getOrderId()).ifPresent(order -> {
            order.setStatus(ChoreographyOrderStatus.FAILED);
            order.setFailureReason(event.getReason());
            orderRepository.save(order);
        });
    }
}
