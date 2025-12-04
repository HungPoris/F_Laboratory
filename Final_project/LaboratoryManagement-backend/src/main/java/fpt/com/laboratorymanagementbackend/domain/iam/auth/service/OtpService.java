package fpt.com.laboratorymanagementbackend.domain.iam.auth.service;

import org.springframework.stereotype.Service;
import org.springframework.data.redis.core.StringRedisTemplate;
import java.time.OffsetDateTime;
import java.time.Duration;
import java.util.UUID;
import java.util.Map;
import java.util.HashMap;
import java.util.Optional;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import com.fasterxml.jackson.databind.ObjectMapper;
import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import java.security.SecureRandom;
import java.security.MessageDigest;

@Service
public class OtpService {
    private final StringRedisTemplate redis;
    private final RabbitTemplate rabbit;
    private final OutboxService outbox;
    private final ObjectMapper mapper;
    private final UserRepository userRepository;
    private final SecureRandom rnd = new SecureRandom();
    @Value("${app.otp.prefix:iam:otp:forgot:}")
    private String otpPrefix;
    @Value("${app.otp.ttl-seconds:600}")
    private int otpTtl;
    @Value("${app.otp.fail.threshold:5}")
    private int otpFailThreshold;
    @Value("${app.otp.fail.prefix:iam:otp:fail:}")
    private String otpFailPrefix;
    @Value("${app.otp.rate.prefix:iam:otp:rate:}")
    private String otpRatePrefix;
    @Value("${app.otp.rate.window-seconds:60}")
    private int otpRateWindow;
    @Value("${app.otp.rate.max-per-window:5}")
    private int otpRateMax;
    @Value("${app.otp.pepper:default_pepper}")
    private String pepper;
    public OtpService(StringRedisTemplate redis, RabbitTemplate rabbit, OutboxService outbox, ObjectMapper mapper, UserRepository userRepository) {
        this.redis = redis;
        this.rabbit = rabbit;
        this.outbox = outbox;
        this.mapper = mapper;
        this.userRepository = userRepository;
    }
    private String hmac(String value) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(pepper.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] out = mac.doFinal(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : out) sb.append(String.format("%02x", b));
            return sb.toString();
        } catch (Exception ex) {
            throw new RuntimeException(ex);
        }
    }
    private String generateNumericOtp(int digits) {
        int bound = (int)Math.pow(10, digits);
        int v = rnd.nextInt(bound);
        return String.format("%0" + digits + "d", v);
    }
    public Optional<Map<String,String>> startForgot(String usernameOrEmail, String ip, String ua) {
        String keyRate = otpRatePrefix + usernameOrEmail;
        Long cnt = redis.opsForValue().increment(keyRate, 1);
        if (cnt != null && cnt == 1) redis.expire(keyRate, Duration.ofSeconds(otpRateWindow));
        if (cnt != null && cnt > otpRateMax) return Optional.empty();
        Optional<User> ou = userRepository.findByUsernameIgnoreCase(usernameOrEmail);
        if (ou.isEmpty()) ou = userRepository.findByEmailIgnoreCase(usernameOrEmail);
        if (ou.isEmpty()) return Optional.empty();
        User u = ou.get();
        String correlationId = UUID.randomUUID().toString();
        String otp = generateNumericOtp(6);
        String otpHash = hmac(otp);
        String redisKey = otpPrefix + u.getUserId().toString() + ":" + correlationId;
        Map<String,String> hm = new HashMap<>();
        hm.put("otp_hash", otpHash);
        hm.put("created_at", OffsetDateTime.now().toString());
        hm.put("expires_at", OffsetDateTime.now().plusSeconds(otpTtl).toString());
        hm.put("attempts", "0");
        hm.put("request_ip", ip == null ? "" : ip);
        hm.put("request_ua", ua == null ? "" : ua);
        redis.opsForHash().putAll(redisKey, hm);
        redis.expire(redisKey, Duration.ofSeconds(otpTtl));
        Map<String,Object> notify = Map.of(
                "correlation_id", correlationId,
                "user_id", u.getUserId().toString(),
                "to", Map.of("email", u.getEmail()),
                "template", "otp",
                "variables", Map.of("otp", otp, "expiry_minutes", otpTtl/60),
                "fullName", u.getFullName(),
                "clientIp", ip
        );
        try {
            rabbit.convertAndSend("lab.notify.exchange", "notify.otp.send", notify);
        } catch (Exception ex) {
            try {
                rabbit.convertAndSend("", "lab.notify.queue", notify);
            } catch (Exception ignore) {
            }
        }
        outbox.publish("lab.audit.events", Map.of("event","OTP_REQUESTED","user_id", u.getUserId().toString(),"correlation_id", correlationId));
        return Optional.of(Map.of("correlationId", correlationId, "userId", u.getUserId().toString()));
    }
    public enum VerifyResult { OK, INVALID, BLOCKED, EXPIRED, NOT_FOUND }
    public VerifyResult verifyOtp(String userId, String correlationId, String otp) {
        String redisKey = otpPrefix + userId + ":" + correlationId;
        if (!Boolean.TRUE.equals(redis.hasKey(redisKey))) return VerifyResult.EXPIRED;
        Object stored = redis.opsForHash().get(redisKey, "otp_hash");
        if (stored == null) return VerifyResult.EXPIRED;
        String storedHash = stored.toString();
        String providedHash = hmac(otp);
        boolean match = MessageDigest.isEqual(storedHash.getBytes(StandardCharsets.UTF_8), providedHash.getBytes(StandardCharsets.UTF_8));
        if (match) {
            redis.opsForHash().put(redisKey, "verified", "1");
            redis.opsForHash().put(redisKey, "verified_at", OffsetDateTime.now().toString());
            redis.expire(redisKey, Duration.ofSeconds(otpTtl));
            outbox.publish("lab.audit.events", Map.of("event","OTP_VERIFIED","user_id", userId,"correlation_id",correlationId));
            return VerifyResult.OK;
        } else {
            Long attempts = redis.opsForHash().increment(redisKey, "attempts", 1);
            if (attempts == null) attempts = 0L;
            if (attempts >= otpFailThreshold) {
                redis.delete(redisKey);
                outbox.publish("lab.audit.events", Map.of("event","OTP_BLOCKED","user_id", userId,"correlation_id",correlationId));
                return VerifyResult.BLOCKED;
            } else {
                return VerifyResult.INVALID;
            }
        }
    }
    public boolean resetPasswordIfVerified(String userId, String correlationId, String newPassword, java.util.function.BiConsumer<String,String> passwordUpdater) {
        String redisKey = otpPrefix + userId + ":" + correlationId;
        if (!Boolean.TRUE.equals(redis.hasKey(redisKey))) {
            return false;
        }
        Object v = redis.opsForHash().get(redisKey, "verified");
        String verified = v != null ? v.toString() : null;
        if (!"1".equals(verified)) return false;
        Optional<User> ou = userRepository.findById(java.util.UUID.fromString(userId));
        if (ou.isEmpty()) return false;
        try {
            passwordUpdater.accept(userId, newPassword);
        } catch (Exception e) {
            return false;
        }
        redis.delete(redisKey);
        outbox.publish("lab.audit.events", Map.of("event","PASSWORD_RESET","user_id", userId));
        return true;
    }
}
