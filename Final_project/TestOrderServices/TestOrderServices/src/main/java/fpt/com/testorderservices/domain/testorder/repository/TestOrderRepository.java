package fpt.com.testorderservices.domain.testorder.repository;

import fpt.com.testorderservices.domain.testorder.entity.TestOrder;
import fpt.com.testorderservices.domain.testorder.entity.TestOrderStatus;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface TestOrderRepository extends JpaRepository<TestOrder, UUID> {

    @EntityGraph(attributePaths = {"medicalRecord", "medicalRecord.patient"})
    Page<TestOrder> findByIsDeletedFalse(Pageable pageable);

    @Query("SELECT COUNT(o) FROM TestOrder o WHERE o.orderNumber LIKE CONCAT(:prefix, '%')")
    int countByOrderNumberStartingWith(@Param("prefix") String prefix);

    @EntityGraph(attributePaths = {"medicalRecord", "medicalRecord.patient"})
    Page<TestOrder> findByMedicalRecord_MedicalRecordIdAndIsDeletedFalse(UUID medicalRecordId, Pageable pageable);
}