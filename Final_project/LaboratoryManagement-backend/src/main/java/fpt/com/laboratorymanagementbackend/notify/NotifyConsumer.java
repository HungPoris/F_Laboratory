package fpt.com.laboratorymanagementbackend.notify;

import org.springframework.stereotype.Component;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import com.fasterxml.jackson.databind.ObjectMapper;
import fpt.com.laboratorymanagementbackend.common.service.EmailService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.util.Map;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import org.springframework.beans.factory.annotation.Value;
import java.util.HashMap;
import java.util.Optional;

@Component
public class NotifyConsumer {
    private final ObjectMapper mapper;
    private final EmailService emailService;
    private final Logger log = LoggerFactory.getLogger(NotifyConsumer.class);

    @Value("${app.name:Laboratory Management}")
    private String appName;

    public NotifyConsumer(ObjectMapper mapper, EmailService emailService) {
        this.mapper = mapper;
        this.emailService = emailService;
    }

    @SuppressWarnings("unchecked")
    @RabbitListener(queues = "lab.notify.queue", containerFactory = "rabbitListenerContainerFactory")
    public void handle(Map<String, Object> payload) {
        try {
            if (payload == null) {
                log.warn("Received null payload");
                return;
            }

            String template = Optional.ofNullable(payload.get("template")).map(Object::toString).orElse("");
            Map<String, Object> toMap = payload.get("to") instanceof Map ? (Map<String, Object>) payload.get("to") : null;
            String email = toMap != null ? Optional.ofNullable(toMap.get("email")).map(Object::toString).orElse(null) : null;

            if (email == null || email.isBlank()) {
                log.warn("Notify payload missing email -> skip (template={})", template);
                return;
            }

            Map<String, Object> variables = payload.get("variables") instanceof Map ? (Map<String, Object>) payload.get("variables") : null;

            if ("welcome".equals(template)) {
                Map<String, Object> modelForTemplate = extractModelForTemplate(variables);
                if (modelForTemplate == null) modelForTemplate = new HashMap<>();
                emailService.sendHtml(email, (String) payload.getOrDefault("subject", "Welcome"), "welcome", modelForTemplate);
                log.info("Sent welcome email (template=welcome) to {}", email);
                return;
            }

            if (variables == null) {
                String templateGeneric = template;
                emailService.sendHtml(email, (String) payload.getOrDefault("subject", "Thông báo"), templateGeneric, Map.of());
                log.info("Sent generic email (no variables) to {} using template {}", email, templateGeneric);
                return;
            }

            Object otpObj = variables.get("otp");
            if (otpObj == null) {
                String templateGeneric = template;
                emailService.sendHtml(email, (String) payload.getOrDefault("subject", "Thông báo"), templateGeneric, variables);
                log.info("Sent generic email to {} using template {}", email, templateGeneric);
                return;
            }

            String otp = otpObj.toString();
            Integer ttl;
            Object expiryObj = variables.get("expiry_minutes");
            if (expiryObj == null) {
                ttl = 10;
            } else if (expiryObj instanceof Number) {
                ttl = ((Number) expiryObj).intValue();
            } else {
                try {
                    ttl = Integer.parseInt(expiryObj.toString());
                } catch (Exception e) {
                    ttl = 10;
                }
            }

            OffsetDateTime expiresAt = OffsetDateTime.now().plusMinutes(ttl);
            String reqId = Optional.ofNullable(payload.get("correlation_id")).map(Object::toString).orElse(java.util.UUID.randomUUID().toString());

            String fullName = null;
            if (variables.containsKey("fullName") && variables.get("fullName") != null) {
                fullName = variables.get("fullName").toString();
            } else if (variables.containsKey("displayName") && variables.get("displayName") != null) {
                fullName = variables.get("displayName").toString();
            } else {
                try {
                    fullName = email.contains("@") ? email.substring(0, email.indexOf("@")) : "";
                } catch (Exception e) {
                    fullName = "";
                }
            }

            String resetUrl = variables.containsKey("resetUrl") ? String.valueOf(variables.get("resetUrl")) : null;

            Map<String, Object> model = new HashMap<>();
            model.put("otp", otp);
            model.put("ttlMinutes", ttl);
            model.put("expiresAt", expiresAt.format(DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm:ss")));
            model.put("requestId", reqId);
            model.put("clientIp", payload.getOrDefault("clientIp", ""));
            model.put("fullName", fullName);
            model.put("appName", appName);
            model.put("resetUrl", resetUrl);

            emailService.sendHtml(email, "Mã OTP đặt lại mật khẩu", "otp", model);
            log.info("Sent OTP email to {}", email);

        } catch (Exception ex) {
            log.error("Failed notify consumer: {}", ex.getMessage(), ex);
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> extractModelForTemplate(Map<String, Object> variables) {
        if (variables == null) return Map.of();
        Object maybeModel = variables.get("model");
        if (maybeModel instanceof Map) {
            return (Map<String, Object>) maybeModel;
        }
        return variables;
    }
}
