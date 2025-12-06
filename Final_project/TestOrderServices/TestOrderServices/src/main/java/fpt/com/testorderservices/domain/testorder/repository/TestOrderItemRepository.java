package fpt.com.testorderservices.domain.testorder.repository;

import fpt.com.testorderservices.domain.testorder.entity.TestOrderItem;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface TestOrderItemRepository extends JpaRepository<TestOrderItem, UUID> {

    List<TestOrderItem> findByTestOrderId(UUID testOrderId);

}
