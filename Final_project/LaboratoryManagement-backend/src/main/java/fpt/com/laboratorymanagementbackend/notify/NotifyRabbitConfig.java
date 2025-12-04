package fpt.com.laboratorymanagementbackend.notify;

import org.springframework.context.annotation.Configuration;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.TopicExchange;

@Configuration
public class NotifyRabbitConfig {

    private final Queue notifyQueue;
    private final TopicExchange notifyExchange;

    public NotifyRabbitConfig(
            @Qualifier("notifyQueue") Queue notifyQueue,
            @Qualifier("notifyExchange") TopicExchange notifyExchange
    ) {
        this.notifyQueue = notifyQueue;
        this.notifyExchange = notifyExchange;
    }
}
