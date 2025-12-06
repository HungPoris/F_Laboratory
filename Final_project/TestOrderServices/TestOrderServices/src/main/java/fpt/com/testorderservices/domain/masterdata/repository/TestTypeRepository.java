package fpt.com.testorderservices.domain.masterdata.repository;

import fpt.com.testorderservices.domain.masterdata.entity.TestType;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface TestTypeRepository extends JpaRepository<TestType, UUID> {

    Optional<TestType> findById(UUID id);
}
