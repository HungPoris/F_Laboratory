package fpt.com.testorderservices.domain.masterdata.repository;

import fpt.com.testorderservices.domain.masterdata.entity.TestTypeReagent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface TestTypeReagentRepository
        extends JpaRepository<TestTypeReagent, UUID> {

    List<TestTypeReagent> findByTestType_Id(UUID testTypeId);
}
