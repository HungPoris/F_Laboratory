package fpt.com.laboratorymanagementbackend.domain.iam.user.repository;

import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface UserRepository extends JpaRepository<User, UUID> {

    @EntityGraph(attributePaths = {"roles", "roles.privileges"})
    Optional<User> findByUsernameIgnoreCase(String username);

    @EntityGraph(attributePaths = {"roles", "roles.privileges"})
    Optional<User> findByEmailIgnoreCase(String email);

    @EntityGraph(attributePaths = {"roles", "roles.privileges"})
    Optional<User> findByUsernameIgnoreCaseOrEmailIgnoreCase(String username, String email);

    boolean existsByUsernameIgnoreCase(String username);
    boolean existsByEmailIgnoreCase(String email);

    @EntityGraph(attributePaths = {"roles", "roles.privileges"})
    Page<User> findAll(Pageable pageable);

    @EntityGraph(attributePaths = {"roles"})
    @Query("SELECT u FROM User u")
    Page<User> findAllWithRoles(Pageable pageable);

    @Query("SELECT u FROM User u WHERE u.isActive = true AND u.isLocked = false AND (CASE WHEN u.lastSuccessfulLoginAt IS NOT NULL THEN u.lastSuccessfulLoginAt ELSE u.createdAt END) < :threshold")
    List<User> findActiveButInactiveSince(@Param("threshold") OffsetDateTime threshold);

    @Modifying
    @Transactional
    @Query("UPDATE User u SET u.lockedUntil = :until, u.isLocked = true, u.lockedAt = :now WHERE u.userId = :userId")
    int setLockedUntil(@Param("userId") UUID userId, @Param("until") OffsetDateTime until, @Param("now") OffsetDateTime now);

    @Modifying
    @Transactional
    @Query("UPDATE User u SET u.lockedUntil = null, u.isLocked = false, u.lockedAt = null WHERE u.userId = :userId")
    int clearLock(@Param("userId") UUID userId);

    @EntityGraph(attributePaths = {"roles"})
    @Query("SELECT DISTINCT u FROM User u LEFT JOIN u.roles r WHERE " +
            "(:q IS NULL OR :q = '' OR " +
            "LOWER(u.fullName) LIKE LOWER(CONCAT('%', :q, '%')) OR " +
            "LOWER(u.username) LIKE LOWER(CONCAT('%', :q, '%')) OR " +
            "LOWER(u.email) LIKE LOWER(CONCAT('%', :q, '%'))) AND " +
            "(:status IS NULL OR :status = 'all' OR " +
            "(:status = 'active' AND u.isActive = true AND u.isLocked = false) OR " +
            "(:status = 'locked' AND u.isLocked = true) OR " +
            "(:status = 'disabled' AND u.isActive = false)) AND " +
            "(:role IS NULL OR :role = '' OR r.roleCode = :role)")
    Page<User> searchWithFilters(
            @Param("q") String q,
            @Param("status") String status,
            @Param("role") String role,
            Pageable pageable
    );
}