package fpt.com.testorderservices.domain.testorder.service;

import fpt.com.testorderservices.domain.masterdata.entity.TestType;
import fpt.com.testorderservices.domain.masterdata.repository.TestTypeRepository;
import fpt.com.testorderservices.domain.testorder.dto.TestOrderItemDto;
import fpt.com.testorderservices.domain.testorder.entity.TestOrder;
import fpt.com.testorderservices.domain.testorder.entity.TestOrderItem;
import fpt.com.testorderservices.domain.testorder.repository.TestOrderItemRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.stream.Collectors;
@Service
@RequiredArgsConstructor
public class TestOrderItemService {

    private final TestOrderItemRepository repository;
    private final TestTypeRepository testTypeRepository;

    public List<TestOrderItem> createItems(TestOrder order, List<UUID> testTypeIds) {

        List<TestType> types = testTypeRepository.findAllById(testTypeIds);

        List<TestOrderItem> items = types.stream()
                .map(type -> TestOrderItem.builder()
                        .testOrder(order)
                        .testType(type)
                        .status("PENDING")
                        .build())
                .toList();

        return repository.saveAll(items);
    }

    public List<TestOrderItemDto> findDtoByOrderId(UUID orderId) {
        return repository.findByTestOrderId(orderId)
                .stream()
                .map(this::toDto)
                .toList();
    }

    private TestOrderItemDto toDto(TestOrderItem item) {
        return TestOrderItemDto.builder()
                .id(item.getId())
                .testTypeId(item.getTestType().getId())
                .testTypeCode(item.getTestType().getCode())
                .testTypeName(item.getTestType().getName())
                .status(item.getStatus())
                .flagType(item.getFlagType())
                .build();
    }
    public void deleteItem(UUID itemId) {
        if (!repository.existsById(itemId)) {
            throw new RuntimeException("Test Order Item not found");
        }
        repository.deleteById(itemId);
    }

}


