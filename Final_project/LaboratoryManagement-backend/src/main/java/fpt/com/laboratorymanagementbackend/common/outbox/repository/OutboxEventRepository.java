package fpt.com.laboratorymanagementbackend.common.outbox.repository;

import fpt.com.laboratorymanagementbackend.common.outbox.entity.OutboxEvent;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

@Repository
public interface OutboxEventRepository extends JpaRepository<OutboxEvent, UUID> {
    List<OutboxEvent> findTop100BySentFalseOrderByCreatedAtAsc();

    @Modifying
    @Query("delete from OutboxEvent o where o.sent = true and o.createdAt < :cutoff")
    int purgeSentOlderThan(OffsetDateTime cutoff);
}
