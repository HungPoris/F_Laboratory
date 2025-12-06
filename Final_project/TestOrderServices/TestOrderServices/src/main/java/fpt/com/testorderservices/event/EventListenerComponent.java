package fpt.com.testorderservices.event;

import lombok.extern.slf4j.Slf4j;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Lắng nghe các sự kiện trong hệ thống.
 * Có thể thay bằng message listener (Kafka consumer) nếu cần tích hợp nhiều service.
 */
@Slf4j
@Component
public class EventListenerComponent {

    @EventListener
    public void handleEvent(EventPayload payload) {
        log.info("📡 Received event: {} | Description: {}",
                payload.getEventCode(), payload.getDescription());
        // TODO: Ghi log vào MonitoringService hoặc EventLog table
    }
}
