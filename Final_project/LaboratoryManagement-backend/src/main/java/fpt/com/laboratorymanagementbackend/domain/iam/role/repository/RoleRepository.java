package fpt.com.laboratorymanagementbackend.domain.iam.role.repository;

import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Role;
import io.lettuce.core.dynamic.annotation.Param;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

@Repository
public interface RoleRepository extends JpaRepository<Role, UUID> {
    Optional<Role> findByRoleCode(String roleCode);
    Page<Role> findAll(Pageable pageable);
    @Query("SELECT r FROM Role r " +
            "WHERE (:q IS NULL OR :q = '' OR " +
            "LOWER(r.roleName) LIKE LOWER(CONCAT('%', :q, '%')) OR " +
            "LOWER(r.roleCode) LIKE LOWER(CONCAT('%', :q, '%')) OR " +
            "LOWER(r.roleDescription) LIKE LOWER(CONCAT('%', :q, '%'))" +
            ")")
    Page<Role> searchByQ(@Param("q") String q, Pageable pageable);
    @Query("SELECT r FROM Role r " +
            "WHERE (:q IS NULL OR :q = '' OR " +
            "LOWER(r.roleName) LIKE LOWER(CONCAT('%', :q, '%')) OR " +
            "LOWER(r.roleCode) LIKE LOWER(CONCAT('%', :q, '%')) OR " +
            "LOWER(r.roleDescription) LIKE LOWER(CONCAT('%', :q, '%'))" +
            ") AND (" +
            ":status IS NULL OR :status = '' OR :status = 'any' OR " +
            "(:status = 'active' AND r.active = true) OR " +
            "(:status = 'inactive' AND r.active = false)" +
            ")")
    Page<Role> searchByQAndStatus(@Param("q") String q,
                                  @Param("status") String status,
                                  Pageable pageable);

}
