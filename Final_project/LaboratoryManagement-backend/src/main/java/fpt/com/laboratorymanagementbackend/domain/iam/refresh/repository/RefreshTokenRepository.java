package fpt.com.laboratorymanagementbackend.domain.iam.refresh.repository;

import fpt.com.laboratorymanagementbackend.domain.iam.refresh.entity.RefreshToken;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.stereotype.Repository;
import java.util.Optional;
import java.util.UUID;
import java.time.OffsetDateTime;
import java.util.List;

@Repository
public interface RefreshTokenRepository extends JpaRepository<RefreshToken, UUID> {
    Optional<RefreshToken> findByTokenHashAndIsActiveTrueAndIsRevokedFalse(String tokenHash);
    List<RefreshToken> findByUserIdAndIsActiveTrueAndIsRevokedFalseAndExpiresAtAfter(UUID userId, OffsetDateTime ts);
    List<RefreshToken> findTop100ByIsRevokedTrueAndRevokedAtBefore(OffsetDateTime cutoff);

    @Modifying
    @Transactional
    @Query("update RefreshToken r set r.isActive = false, r.isRevoked = true, r.revokedAt = current_timestamp where r.expiresAt < ?1 and r.isActive = true")
    int revokeExpired(OffsetDateTime cutoff);

    @Modifying
    @Transactional
    @Query("delete from RefreshToken r where r.expiresAt < ?1")
    int deleteExpired(OffsetDateTime cutoff);
}
