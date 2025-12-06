package fpt.com.testorderservices.event;

import lombok.*;

import java.time.LocalDateTime;

/**
 * Dữ liệu sự kiện gửi đi (payload).
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EventPayload {
    private String eventCode;
    private String description;
    private String operator;
    private LocalDateTime timestamp;
    private Object data;
}
