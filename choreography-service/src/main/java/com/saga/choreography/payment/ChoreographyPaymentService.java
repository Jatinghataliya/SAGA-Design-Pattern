package com.saga.choreography.payment;

import com.saga.choreography.common.EventBus;
import com.saga.choreography.commons.events.*;
import com.saga.choreography.order.ChoreographyOrderRepository;
import com.saga.choreography.order.ChoreographyOrderStatus;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

@Service
public class ChoreographyPaymentService {

    private static final BigDecimal MAX_ALLOWED_AMOUNT = new BigDecimal("10000");

    private final ChoreographyPaymentRepository paymentRepository;
    private final ChoreographyOrderRepository orderRepository;
    private final EventBus eventBus;

    public ChoreographyPaymentService(ChoreographyPaymentRepository paymentRepository,
                                      ChoreographyOrderRepository orderRepository,
                                      EventBus eventBus) {
        this.paymentRepository = paymentRepository;
        this.orderRepository = orderRepository;
        this.eventBus = eventBus;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onOrderCreated(OrderCreatedEvent event) {
        // Update order status to PAYMENT_PROCESSING
        orderRepository.findById(event.getOrderId()).ifPresent(order -> {
            order.setStatus(ChoreographyOrderStatus.PAYMENT_PROCESSING);
            orderRepository.save(order);
        });

        ChoreographyPayment payment = new ChoreographyPayment();
        payment.setOrderId(event.getOrderId());
        payment.setCustomerId(event.getCustomerId());
        payment.setAmount(event.getAmount());

        if (event.getAmount().compareTo(MAX_ALLOWED_AMOUNT) > 0) {
            payment.setStatus(PaymentStatus.FAILED);
            paymentRepository.save(payment);
            eventBus.publish(new PaymentFailedEvent(
                    event.getOrderId(),
                    "Payment declined: amount exceeds maximum allowed limit of " + MAX_ALLOWED_AMOUNT
            ));
        } else {
            payment.setStatus(PaymentStatus.APPROVED);
            final ChoreographyPayment savedPayment = paymentRepository.save(payment);

            // Update order's paymentId
            orderRepository.findById(event.getOrderId()).ifPresent(order -> {
                order.setPaymentId(savedPayment.getId());
                orderRepository.save(order);
            });

            eventBus.publish(new PaymentApprovedEvent(
                    event.getOrderId(),
                    event.getCustomerId(),
                    savedPayment.getId(),
                    event.getProductId(),
                    event.getQuantity(),
                    event.getShippingAddress(),
                    event.getAmount()
            ));
        }
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onInventoryFailed(InventoryFailedEvent event) {
        refundPayment(event.getOrderId(), event.getPaymentId(), event.getReason());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void onInventoryReleased(InventoryReleasedEvent event) {
        refundPayment(event.getOrderId(), event.getPaymentId(), event.getReason());
    }

    private void refundPayment(Long orderId, Long paymentId, String reason) {
        paymentRepository.findById(paymentId).ifPresent(payment -> {
            payment.setStatus(PaymentStatus.REFUNDED);
            paymentRepository.save(payment);
        });
        eventBus.publish(new PaymentRefundedEvent(orderId, paymentId, reason));
    }
}
