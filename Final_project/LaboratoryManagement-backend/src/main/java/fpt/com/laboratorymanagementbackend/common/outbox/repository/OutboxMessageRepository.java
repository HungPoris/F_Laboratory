package fpt.com.laboratorymanagementbackend.common.outbox.repository;


import fpt.com.laboratorymanagementbackend.common.outbox.entity.OutboxMessage;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import jakarta.transaction.Transactional;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public interface OutboxMessageRepository extends JpaRepository<OutboxMessage, UUID> {
    @Query("SELECT o FROM OutboxMessage o WHERE o.status = 'PENDING' ORDER BY o.createdAt ASC")
    List<OutboxMessage> findPending();
    @Transactional
    @Modifying
    @Query("UPDATE OutboxMessage o SET o.status = ?2, o.publishedAt = ?3, o.attempts = ?4 WHERE o.id = ?1 AND o.status = 'PENDING'")
    int markAs(UUID id, String status, OffsetDateTime publishedAt, Integer attempts);
}
