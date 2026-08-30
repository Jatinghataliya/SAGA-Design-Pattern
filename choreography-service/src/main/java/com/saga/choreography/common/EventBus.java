package com.saga.choreography.common;

import com.saga.choreography.commons.events.SagaEvent;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Service;

@Service
public class EventBus {

    private final ApplicationEventPublisher publisher;

    public EventBus(ApplicationEventPublisher publisher) {
        this.publisher = publisher;
    }

    public void publish(SagaEvent event) {
        publisher.publishEvent(event);
    }
}
