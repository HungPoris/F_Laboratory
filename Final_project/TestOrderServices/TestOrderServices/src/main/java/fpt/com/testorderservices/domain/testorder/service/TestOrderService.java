package fpt.com.testorderservices.domain.testorder.service;

import fpt.com.testorderservices.common.exception.BusinessException;
import fpt.com.testorderservices.common.util.PaginationResponse;
import fpt.com.testorderservices.domain.comment.dto.CommentDto;
import fpt.com.testorderservices.domain.comment.service.CommentService;
import fpt.com.testorderservices.domain.masterdata.entity.TestType;
import fpt.com.testorderservices.domain.masterdata.repository.TestTypeRepository;
import fpt.com.testorderservices.domain.medicalrecord.entity.MedicalRecord;
import fpt.com.testorderservices.domain.medicalrecord.repository.MedicalRecordRepository;
import fpt.com.testorderservices.domain.testorder.dto.*;
import fpt.com.testorderservices.domain.testorder.entity.*;
import fpt.com.testorderservices.domain.testorder.repository.TestOrderItemRepository;
import fpt.com.testorderservices.domain.testorder.repository.TestOrderRepository;
import fpt.com.testorderservices.security.dto.InternalUserSummaryResponse;
import fpt.com.testorderservices.security.service.IamExternalService;

import jakarta.persistence.EntityNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.*;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
@RequiredArgsConstructor
@Transactional
public class TestOrderService {

    private final TestOrderRepository repository;
    private final MedicalRecordRepository medicalRecordRepository;
    private final CommentService commentService;
    private final TestOrderItemService itemService;

    private final TestTypeRepository testTypeRepository;
    private final TestOrderItemRepository testOrderItemRepository;
    private final IamExternalService iamExternalService; // ✅ Inject IAM Service

    private static final String EMAIL_REGEX = "^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+$";

    private String generateOrderNumber() {
        String datePrefix = LocalDate.now().format(DateTimeFormatter.ofPattern("ddMMyy"));
        int count = repository.countByOrderNumberStartingWith(datePrefix);
        return datePrefix + "-TO" + (count + 1);
    }

    private void validateEmail(String email) {
        if (email != null && !email.isBlank() && !Pattern.matches(EMAIL_REGEX, email)) {
            throw new BusinessException("Invalid email format.");
        }
    }

    private void validateTestTypeIds(List<UUID> testTypeIds) {
        if (testTypeIds == null || testTypeIds.isEmpty()) {
            throw new BusinessException("The test type list must not be empty.");
        }
    }


    private Map<UUID, InternalUserSummaryResponse> fetchUserMap(List<TestOrder> orders) {
        if (orders == null || orders.isEmpty()) return Collections.emptyMap();

        List<UUID> userIds = orders.stream()
                .flatMap(o -> Stream.of(o.getCreatedBy(), o.getUpdatedBy(), o.getRunBy(), o.getReviewedBy()))
                .filter(Objects::nonNull)
                .collect(Collectors.toList());

        return iamExternalService.getUsersInfo(userIds);
    }


    private TestOrderDto.UserSummary buildUserSummary(UUID userId, Map<UUID, InternalUserSummaryResponse> userMap) {
        if (userId == null) return null;
        InternalUserSummaryResponse userInfo = userMap.get(userId);
        String displayName = "Unknown";
        if (userInfo != null) {
            displayName = (userInfo.getFullName() != null && !userInfo.getFullName().isBlank())
                    ? userInfo.getFullName()
                    : userInfo.getUsername();
        }
        return new TestOrderDto.UserSummary(userId, displayName);
    }

    // ===================================================================================
    // GET ALL (List thường)
    // ===================================================================================
    public List<TestOrderDto> getAll() {
        List<TestOrder> orders = repository.findAll().stream()
                .filter(o -> !o.isDeleted())
                .sorted(Comparator.comparing(TestOrder::getCreatedAt).reversed())
                .collect(Collectors.toList());

        Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(orders);

        return orders.stream()
                .map(o -> toDto(o, userMap))
                .collect(Collectors.toList());
    }



    // ===================================================================================
    // GET BY ID
    // ===================================================================================
    public Optional<TestOrderDto> getById(UUID id) {
        return repository.findById(id)
                .filter(o -> !o.isDeleted())
                .map(order -> {
                    Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(Collections.singletonList(order));
                    return toDto(order, userMap);
                });
    }

    // ===================================================================================
    // GET BY MEDICAL RECORD ID WITH PAGING
    // ===================================================================================
    public PaginationResponse<TestOrderDto> getByMedicalRecordIdPaging(UUID medicalRecordId, int page, int size) {
        Sort sort = Sort.by(
                Sort.Order.desc("priority"),
                Sort.Order.asc("status"),
                Sort.Order.desc("createdAt")
        );

        Pageable pageable = PageRequest.of(page, size, sort);
        Page<TestOrder> pageResult = repository.findByMedicalRecord_MedicalRecordIdAndIsDeletedFalse(medicalRecordId, pageable);

        Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(pageResult.getContent());

        List<TestOrderDto> dtos = pageResult.getContent().stream()
                .map(o -> toDto(o, userMap))
                .collect(Collectors.toList());

        return PaginationResponse.<TestOrderDto>builder()
                .items(dtos)
                .currentPage(pageResult.getNumber())
                .totalPages(pageResult.getTotalPages())
                .totalElements(pageResult.getTotalElements())
                .pageSize(pageResult.getSize())
                .build();
    }

    public TestOrderDto create(TestOrderCreateDto dto, UUID createdBy) {

        validateTestTypeIds(dto.getTestTypeIds());
        validateEmail(dto.getEmail());

        MedicalRecord record = medicalRecordRepository.findById(dto.getMedicalRecordId())
                .orElseThrow(() -> new EntityNotFoundException("Medical record not found"));

        var patient = record.getPatient();
        if (patient == null) {
            throw new IllegalStateException("Medical record has no linked patient");
        }

        Date dob = null;
        if (patient.getDob() != null) {
            dob = java.sql.Date.valueOf(patient.getDob());
        }

        Integer age = (dob != null)
                ? OffsetDateTime.now().getYear() - patient.getDob().getYear()
                : null;

        TestOrder entity = TestOrder.builder()
                .orderNumber(generateOrderNumber())
                .patientName(patient.getFullName())
                .gender(patient.getGender())
                .phoneNumber(patient.getContactNumber())
                .address(patient.getAddress())
                .dateOfBirth(dob)
                .age(age)
                .email(
                        (dto.getEmail() != null && !dto.getEmail().isBlank())
                                ? dto.getEmail()
                                : patient.getEmail()
                )
                .priority(dto.getPriority() != null ? dto.getPriority() : TestOrderPriority.NORMAL)
                .clinicalNotes(dto.getClinicalNotes())
                .status(TestOrderStatus.PENDING)
                .medicalRecord(record)
                .createdBy(createdBy)
                .createdAt(OffsetDateTime.now())
                .isDeleted(false)
                .build();

        TestOrder saved = repository.save(entity);
        itemService.createItems(saved, dto.getTestTypeIds());

        Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(Collections.singletonList(saved));
        return toDto(saved, userMap);
    }

    public TestOrderDto update(UUID id, TestOrderUpdateDto dto, UUID updatedBy) {
        validateEmail(dto.getEmail());

        TestOrder entity = repository.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("Test order not found: " + id));

        if (entity.isDeleted())
            throw new IllegalStateException("Cannot update deleted order");

        if (dto.getMedicalRecordId() != null) {
            MedicalRecord record = medicalRecordRepository.findById(dto.getMedicalRecordId())
                    .orElseThrow(() -> new EntityNotFoundException("Medical record not found"));
            entity.setMedicalRecord(record);
        }

        if (dto.getEmail() != null) entity.setEmail(dto.getEmail());
        if (dto.getPriority() != null) entity.setPriority(dto.getPriority());
        if (dto.getStatus() != null) entity.setStatus(dto.getStatus());
        if (dto.getClinicalNotes() != null) entity.setClinicalNotes(dto.getClinicalNotes());

        entity.setUpdatedBy(updatedBy);
        entity.setUpdatedAt(OffsetDateTime.now());

        TestOrder updated = repository.save(entity);

        Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(Collections.singletonList(updated));
        return toDto(updated, userMap);
    }

    public void delete(UUID id, UUID deletedBy) {
        TestOrder entity = repository.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("Test order not found: " + id));

        entity.setDeleted(true);
        entity.setUpdatedBy(deletedBy);
        entity.setUpdatedAt(OffsetDateTime.now());
        repository.save(entity);
    }

    public Optional<TestOrderDto> getDetail(UUID id) {
        return repository.findById(id)
                .filter(o -> !o.isDeleted())
                .map(order -> {
                    Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(Collections.singletonList(order));
                    TestOrderDto dto = toDto(order, userMap);
                    dto.setItems(itemService.findDtoByOrderId(order.getId()));
                    return dto;
                });
    }

    // ===================================================================================
    // ADD ITEMS TO EXISTING ORDER
    // ===================================================================================
    public List<TestOrderItemDto> addItemsToOrder(UUID orderId, List<UUID> testTypeIds, UUID createdBy) {
        TestOrder order = repository.findById(orderId)
                .orElseThrow(() -> new EntityNotFoundException("TestOrder not found"));

        for (UUID typeId : testTypeIds) {
            boolean exists = order.getItems().stream()
                    .anyMatch(i -> i.getTestType().getId().equals(typeId));

            if (exists) continue;

            TestType tt = testTypeRepository.findById(typeId)
                    .orElseThrow(() -> new EntityNotFoundException("TestType not found"));

            TestOrderItem item = TestOrderItem.builder()
                    .testOrder(order)
                    .testType(tt)
                    .status("PENDING")
                    .build();

            testOrderItemRepository.save(item);
        }

        return itemService.findDtoByOrderId(orderId);
    }

    private TestOrderDto toDto(TestOrder e, Map<UUID, InternalUserSummaryResponse> userMap) {
        List<CommentDto> comments = commentService.getByTestOrderId(e.getId());
        var itemDtos = itemService.findDtoByOrderId(e.getId());

        List<UUID> testTypeIds = itemDtos != null
                ? itemDtos.stream()
                .map(TestOrderItemDto::getTestTypeId)
                .collect(Collectors.toList())
                : Collections.emptyList();

        return TestOrderDto.builder()
                .id(e.getId())
                .orderNumber(e.getOrderNumber())
                .medicalRecordId(
                        e.getMedicalRecord() != null ? e.getMedicalRecord().getMedicalRecordId() : null
                )
                .patientId(
                        e.getMedicalRecord() != null && e.getMedicalRecord().getPatient() != null
                                ? e.getMedicalRecord().getPatient().getPatientId()
                                : null
                )
                .patientName(e.getPatientName())
                .age(e.getAge())
                .gender(e.getGender())
                .phoneNumber(e.getPhoneNumber())
                .email(e.getEmail())
                .address(e.getAddress())
                .dateOfBirth(e.getDateOfBirth())
                .status(e.getStatus())
                .priority(e.getPriority())
                .clinicalNotes(e.getClinicalNotes())
                .medicalRecordSnapshot(e.getMedicalRecordSnapshot())
                .createdAt(e.getCreatedAt())
                .updatedAt(e.getUpdatedAt())
                .runAt(e.getRunAt())
                .reviewedAt(e.getReviewedAt())
                .createdBy(buildUserSummary(e.getCreatedBy(), userMap))
                .updatedBy(buildUserSummary(e.getUpdatedBy(), userMap))
                .runBy(buildUserSummary(e.getRunBy(), userMap))
                .reviewedBy(buildUserSummary(e.getReviewedBy(), userMap))
                .testTypeIds(testTypeIds)
                .comments(comments)
                .items(itemDtos)
                .build();
    }
}