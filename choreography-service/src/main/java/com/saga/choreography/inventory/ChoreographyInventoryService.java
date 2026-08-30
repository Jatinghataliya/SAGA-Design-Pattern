package com.saga.choreography.inventory;

import com.saga.choreography.common.EventBus;
import com.saga.choreography.commons.events.*;
import com.saga.choreography.order.ChoreographyOrderRepository;
import com.saga.choreography.order.ChoreographyOrderStatus;
import jakarta.annotation.PostConstruct;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ChoreographyInventoryService {

    private final ChoreographyProductStockRepository stockRepository;
    private final ChoreographyInventoryReservationRepository reservationRepository;
    private final ChoreographyOrderRepository orderRepository;
    private final EventBus eventBus;

    public ChoreographyInventoryService(ChoreographyProductStockRepository stockRepository,
                                        ChoreographyInventoryReservationRepository reservationRepository,
                                        ChoreographyOrderRepository orderRepository,
                                        EventBus eventBus) {
        this.stockRepository = stockRepository;
        this.reservationRepository = reservationRepository;
        this.orderRepository = orderRepository;
        this.eventBus = eventBus;
    }

    @PostConstruct
    @Transactional
    public void seedStock() {
        if (stockRepository.count() == 0) {
            stockRepository.save(new ChoreographyProductStock("PROD-001", 100));
            stockRepository.save(new ChoreographyProductStock("PROD-002", 5));
            stockRepository.save(new ChoreographyProductStock("PROD-003", 0));
        }
    }

    @EventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onPaymentApproved(PaymentApprovedEvent event) {
        // Update order status
        orderRepository.findById(event.getOrderId()).ifPresent(order -> {
            order.setStatus(ChoreographyOrderStatus.INVENTORY_RESERVING);
            orderRepository.save(order);
        });

        ChoreographyProductStock stock = stockRepository.findById(event.getProductId()).orElse(null);

        if (stock == null || stock.getAvailableQuantity() < event.getQuantity()) {
            String reason = stock == null
                    ? "Product not found: " + event.getProductId()
                    : "Insufficient stock for " + event.getProductId()
                      + ". Requested: " + event.getQuantity()
                      + ", Available: " + stock.getAvailableQuantity();

            eventBus.publish(new InventoryFailedEvent(event.getOrderId(), event.getPaymentId(), reason));
        } else {
            stock.setAvailableQuantity(stock.getAvailableQuantity() - event.getQuantity());
            stockRepository.save(stock);

            ChoreographyInventoryReservation reservation = new ChoreographyInventoryReservation();
            reservation.setOrderId(event.getOrderId());
            reservation.setProductId(event.getProductId());
            reservation.setQuantity(event.getQuantity());
            reservation.setStatus(ReservationStatus.RESERVED);
            reservation = reservationRepository.save(reservation);

            // Update order's reservationId
            final Long reservationId = reservation.getId();
            orderRepository.findById(event.getOrderId()).ifPresent(order -> {
                order.setReservationId(reservationId);
                orderRepository.save(order);
            });

            eventBus.publish(new InventoryReservedEvent(
                    event.getOrderId(),
                    event.getCustomerId(),
                    event.getPaymentId(),
                    reservation.getId(),
                    event.getProductId(),
                    event.getQuantity(),
                    event.getShippingAddress(),
                    event.getAmount()
            ));
        }
    }

    @EventListener
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onShipmentFailed(ShipmentFailedEvent event) {
        Long reservationId = event.getReservationId();
        reservationRepository.findById(reservationId).ifPresent(reservation -> {
            // Restore stock
            stockRepository.findById(reservation.getProductId()).ifPresent(stock -> {
                stock.setAvailableQuantity(stock.getAvailableQuantity() + reservation.getQuantity());
                stockRepository.save(stock);
            });
            reservation.setStatus(ReservationStatus.RELEASED);
            reservationRepository.save(reservation);
        });

        eventBus.publish(new InventoryReleasedEvent(
                event.getOrderId(),
                event.getPaymentId(),
                reservationId,
                event.getReason()
        ));
    }
}
