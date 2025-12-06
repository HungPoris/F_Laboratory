package fpt.com.testorderservices.domain.medicalrecord.repository;

import fpt.com.testorderservices.domain.medicalrecord.entity.MedicalRecordAccessLog;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.UUID;

public interface MedicalRecordAccessLogRepository extends JpaRepository<MedicalRecordAccessLog, UUID> {
}