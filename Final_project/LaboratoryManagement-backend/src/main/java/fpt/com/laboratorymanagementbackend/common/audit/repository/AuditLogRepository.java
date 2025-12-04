package fpt.com.laboratorymanagementbackend.common.audit.repository;

import fpt.com.laboratorymanagementbackend.common.audit.model.AuditLog;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.stereotype.Repository;
import java.util.UUID;

@Repository
public interface AuditLogRepository extends MongoRepository<AuditLog, String> {
    boolean existsByEventId(UUID eventId);
}
