package com.saga.choreography.commons.events;

import java.time.Instant;
import java.util.UUID;

public abstract class SagaEvent {

    private final String eventId;
    private final Long orderId;
    private final EventType eventType;
    private final Instant timestamp;

    protected SagaEvent(Long orderId, EventType eventType) {
        this.eventId = UUID.randomUUID().toString();
        this.orderId = orderId;
        this.eventType = eventType;
        this.timestamp = Instant.now();
    }

    public String getEventId() { return eventId; }
    public Long getOrderId() { return orderId; }
    public EventType getEventType() { return eventType; }
    public Instant getTimestamp() { return timestamp; }
}
