package fpt.com.testorderservices.event;

import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.stereotype.Component;

/**
 * Bộ phát sự kiện nội bộ (Spring Event).
 * Có thể mở rộng để publish ra message broker (Kafka, RabbitMQ...).
 */
@Slf4j
@Component
public class EventPublisher {

    private final ApplicationEventPublisher publisher;

    public EventPublisher(ApplicationEventPublisher publisher) {
        this.publisher = publisher;
    }

    public void publish(EventPayload payload) {
        log.info("[EVENT] {} by {} - {}",
                payload.getEventCode(),
                payload.getOperator(),
                payload.getDescription());
        publisher.publishEvent(payload);
    }
}
