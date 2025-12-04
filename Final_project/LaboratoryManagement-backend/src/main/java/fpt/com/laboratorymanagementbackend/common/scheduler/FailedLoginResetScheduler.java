package fpt.com.laboratorymanagementbackend.common.scheduler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.connection.RedisConnection;
import org.springframework.data.redis.core.Cursor;
import org.springframework.data.redis.core.RedisConnectionUtils;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ScanOptions;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.Objects;
import java.util.concurrent.atomic.AtomicLong;

@Component
public class FailedLoginResetScheduler {
    private static final Logger log = LoggerFactory.getLogger(FailedLoginResetScheduler.class);

    private final StringRedisTemplate redis;

    @Value("${app.otp.fail.prefix:iam:login:failed:}")
    private String failPrefix;

    @Value("${app.otp.fail.reset-threshold:4}")
    private int threshold;

    @Value("${app.otp.fail.reset-dry-run:false}")
    private boolean dryRun;

    private static final String LUA =
            "local v = redis.call('GET', KEYS[1])\n" +
                    "if not v then return 0 end\n" +
                    "local num = tonumber(v)\n" +
                    "if not num then redis.call('DEL', KEYS[1]); return 1 end\n" +
                    "if num < tonumber(ARGV[1]) then redis.call('DEL', KEYS[1]); return 1 end\n" +
                    "return 0\n";

    public FailedLoginResetScheduler(StringRedisTemplate redis) {
        this.redis = redis;
    }

    @Scheduled(cron = "0 0 23 * * *", zone = "Asia/Ho_Chi_Minh")
    public void resetSmallFailedAttempts() {
        DefaultRedisScript<Long> script = new DefaultRedisScript<>();
        script.setScriptText(LUA);
        script.setResultType(Long.class);

        AtomicLong scanned = new AtomicLong(0);
        AtomicLong deleted = new AtomicLong(0);
        AtomicLong kept = new AtomicLong(0);

        RedisConnection conn = Objects.requireNonNull(redis.getConnectionFactory()).getConnection();
        try (Cursor<byte[]> cursor = conn.scan(ScanOptions.scanOptions().match(failPrefix + "*").count(1000).build())) {
            while (cursor.hasNext()) {
                byte[] keyBytes = cursor.next();
                scanned.incrementAndGet();
                String key = new String(keyBytes, StandardCharsets.UTF_8);

                try {
                    if (dryRun) {
                        String val = redis.opsForValue().get(key);
                        if (val != null) {
                            try {
                                int attempts = Integer.parseInt(val);
                                if (attempts < threshold) {
                                    deleted.incrementAndGet(); // count as would-delete
                                } else {
                                    kept.incrementAndGet();
                                }
                            } catch (NumberFormatException nfe) {
                                deleted.incrementAndGet();
                            }
                        }
                    } else {
                        Long res = redis.execute(script, Collections.singletonList(key), String.valueOf(threshold));
                        if (res != null && res == 1L) {
                            deleted.incrementAndGet();
                        } else {
                            kept.incrementAndGet();
                        }
                    }
                } catch (Exception e) {
                }
            }
        } catch (Exception e) {
        } finally {
            try {
                RedisConnectionUtils.releaseConnection(conn, Objects.requireNonNull(redis.getConnectionFactory()));
            } catch (Exception ignored) {}
        }

    }
}
