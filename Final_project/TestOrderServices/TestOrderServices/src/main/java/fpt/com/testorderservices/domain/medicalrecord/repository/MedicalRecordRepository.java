package fpt.com.testorderservices.domain.medicalrecord.repository;

import fpt.com.testorderservices.domain.medicalrecord.entity.MedicalRecord;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface MedicalRecordRepository extends JpaRepository<MedicalRecord, UUID>, JpaSpecificationExecutor<MedicalRecord> {

    List<MedicalRecord> findByPatientIdAndIsDeletedFalse(UUID patientId);

    Page<MedicalRecord> findByPatientIdAndIsDeletedFalse(UUID patientId, Pageable pageable);

    // 1. Kiểm tra xem mã đã tồn tại chưa
    boolean existsByRecordCode(String recordCode);

    // 2. Lấy mã hồ sơ lớn nhất (SỬA LẠI ĐỂ KHỚP VỚI SERVICE)
    // - Thêm tham số Pageable pageable
    // - Bỏ "LIMIT 1" trong Query (Pageable sẽ tự xử lý)
    // - Trả về List<String>
    @Query("SELECT m.recordCode FROM MedicalRecord m WHERE m.recordCode LIKE :prefix% ORDER BY m.recordCode DESC")
    List<String> findLastRecordCode(@Param("prefix") String prefix, Pageable pageable);
}