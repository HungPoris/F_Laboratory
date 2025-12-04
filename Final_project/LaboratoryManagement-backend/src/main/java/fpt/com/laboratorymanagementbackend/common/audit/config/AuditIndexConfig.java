package fpt.com.laboratorymanagementbackend.common.audit.config;

import com.mongodb.MongoCommandException;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.model.IndexOptions;
import org.bson.Document;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Bean;
import org.springframework.data.mongodb.core.MongoTemplate;
import java.time.Duration;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;

@Configuration
public class AuditIndexConfig {

    private static final Logger log = LoggerFactory.getLogger(AuditIndexConfig.class);

    @Bean
    public boolean ensureAuditIndexes(MongoTemplate mongoTemplate,
                                      @Value("${app.audit.ttl-days:180}") long ttlDays) {
        MongoCollection<Document> coll = mongoTemplate.getCollection("audit_logs");

        try {
            IndexOptions uniqueIfExists = new IndexOptions()
                    .unique(true)
                    .partialFilterExpression(new Document("eventId", new Document("$exists", true)));

            coll.createIndex(new Document("eventId", 1), uniqueIfExists);
        } catch (MongoCommandException ex) {
            log.warn("Could not create partial unique index on eventId: {}", ex.getMessage());
        } catch (Exception ex) {
            log.warn("Unexpected error creating eventId index: {}", ex.getMessage(), ex);
        }

        try {
            coll.createIndex(new Document()
                    .append("event", 1)
                    .append("username", 1)
                    .append("createdAt", -1));
        } catch (Exception ex) {
            log.warn("Could not create compound audit index: {}", ex.getMessage(), ex);
        }

        try {
            long ttlSeconds = Duration.ofDays(ttlDays).getSeconds();
            IndexOptions ttlOptions = new IndexOptions().expireAfter(ttlSeconds, java.util.concurrent.TimeUnit.SECONDS);
            coll.createIndex(new Document("createdAt", 1), ttlOptions);
        } catch (Exception ex) {
            log.warn("Could not create TTL index on createdAt: {}", ex.getMessage(), ex);
        }

        return true;
    }
}
