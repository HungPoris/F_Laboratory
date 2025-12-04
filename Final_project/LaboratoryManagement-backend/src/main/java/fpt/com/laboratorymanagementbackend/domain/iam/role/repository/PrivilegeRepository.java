package fpt.com.laboratorymanagementbackend.domain.iam.role.repository;

import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Privilege;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;
import java.util.UUID;

public interface PrivilegeRepository extends JpaRepository<Privilege, UUID> {
    Optional<Privilege> findByPrivilegeCode(String privilegeCode);

    @Query("SELECT p FROM Privilege p WHERE LOWER(COALESCE(p.privilegeCode, '')) LIKE CONCAT('%', :kw, '%') OR LOWER(COALESCE(p.privilegeName, '')) LIKE CONCAT('%', :kw, '%') OR LOWER(COALESCE(p.privilegeDescription, '')) LIKE CONCAT('%', :kw, '%')")
    Page<Privilege> searchByKeyword(@Param("kw") String kw, Pageable pageable);
}
