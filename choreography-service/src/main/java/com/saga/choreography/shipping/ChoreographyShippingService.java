package com.saga.choreography.shipping;

import com.saga.choreography.common.EventBus;
import com.saga.choreography.commons.events.*;
import com.saga.choreography.order.ChoreographyOrderRepository;
import com.saga.choreography.order.ChoreographyOrderStatus;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ChoreographyShippingService {

    private final ChoreographyShipmentRepository shipmentRepository;
    private final ChoreographyOrderRepository orderRepository;
    private final EventBus eventBus;

    public ChoreographyShippingService(ChoreographyShipmentRepository shipmentRepository,
                                       ChoreographyOrderRepository orderRepository,
                                       EventBus eventBus) {
        this.shipmentRepository = shipmentRepository;
        this.orderRepository = orderRepository;
        this.eventBus = eventBus;
    }

    @EventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onInventoryReserved(InventoryReservedEvent event) {
        // Update order status
        orderRepository.findById(event.getOrderId()).ifPresent(order -> {
            order.setStatus(ChoreographyOrderStatus.SHIPPING_SCHEDULING);
            orderRepository.save(order);
        });

        String address = event.getShippingAddress();
        if (address != null && address.toUpperCase().contains("BLOCKED")) {
            ChoreographyShipment shipment = new ChoreographyShipment();
            shipment.setOrderId(event.getOrderId());
            shipment.setShippingAddress(address);
            shipment.setStatus(ShipmentStatus.FAILED);
            shipmentRepository.save(shipment);

            eventBus.publish(new ShipmentFailedEvent(
                    event.getOrderId(),
                    event.getPaymentId(),
                    event.getReservationId(),
                    "Shipment rejected: address is blocked - " + address
            ));
        } else {
            ChoreographyShipment shipment = new ChoreographyShipment();
            shipment.setOrderId(event.getOrderId());
            shipment.setShippingAddress(address);
            shipment.setStatus(ShipmentStatus.SCHEDULED);
            shipment = shipmentRepository.save(shipment);

            // Update order's shipmentId
            final Long shipmentId = shipment.getId();
            orderRepository.findById(event.getOrderId()).ifPresent(order -> {
                order.setShipmentId(shipmentId);
                orderRepository.save(order);
            });

            eventBus.publish(new ShipmentScheduledEvent(event.getOrderId(), shipment.getId()));
            eventBus.publish(new OrderCompletedEvent(event.getOrderId(), shipment.getId()));
        }
    }
}
