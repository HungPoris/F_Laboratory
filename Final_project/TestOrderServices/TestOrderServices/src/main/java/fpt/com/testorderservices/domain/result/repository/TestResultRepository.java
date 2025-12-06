package fpt.com.testorderservices.domain.result.repository;

import fpt.com.testorderservices.domain.result.entity.TestResult;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.UUID;

@Repository
public interface TestResultRepository extends JpaRepository<TestResult, UUID> {

    @Override
    @EntityGraph(attributePaths = {"testType", "testOrderItem", "testOrder"})
    Page<TestResult> findAll(Pageable pageable);

    @EntityGraph(attributePaths = {"testType", "testOrder"})
    List<TestResult> findByTestOrderItem_Id(UUID testOrderItemId);

    boolean existsByTestOrderItem_Id(UUID testOrderItemId);

}