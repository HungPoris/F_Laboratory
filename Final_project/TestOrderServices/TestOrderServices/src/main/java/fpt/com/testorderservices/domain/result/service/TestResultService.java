package fpt.com.testorderservices.domain.result.service;

import fpt.com.testorderservices.domain.comment.dto.CommentDto;
import fpt.com.testorderservices.domain.comment.service.CommentService;

import fpt.com.testorderservices.domain.masterdata.entity.TestType;
import fpt.com.testorderservices.domain.masterdata.entity.Instrument;
import fpt.com.testorderservices.domain.masterdata.entity.Reagent;
import fpt.com.testorderservices.domain.masterdata.repository.TestTypeInstrumentRepository;
import fpt.com.testorderservices.domain.masterdata.repository.TestTypeReagentRepository;
import fpt.com.testorderservices.domain.masterdata.repository.TestTypeRepository;
import fpt.com.testorderservices.domain.masterdata.repository.InstrumentRepository;
import fpt.com.testorderservices.domain.masterdata.repository.ReagentRepository;

import fpt.com.testorderservices.domain.result.dto.*;
import fpt.com.testorderservices.domain.result.entity.TestResult;
import fpt.com.testorderservices.domain.result.repository.TestResultRepository;

import fpt.com.testorderservices.domain.testorder.entity.TestOrderItem;
import fpt.com.testorderservices.domain.testorder.repository.TestOrderItemRepository;


import jakarta.persistence.EntityNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional
public class TestResultService {

    private final TestResultRepository repository;
    private final TestOrderItemRepository testOrderItemRepository;
    private final CommentService commentService;
    private final TestTypeInstrumentRepository testTypeInstrumentRepository;
    private final TestTypeReagentRepository testTypeReagentRepository;
    private final TestResultRepository testResultRepository;
    private final TestTypeRepository testTypeRepository;
    private final InstrumentRepository instrumentRepository;
    private final ReagentRepository reagentRepository;

    public List<TestResultDto> getByTestOrderItemId(UUID itemId) {
        return repository.findByTestOrderItem_Id(itemId)
                .stream()
                .map(this::toDto)
                .collect(Collectors.toList());
    }


    public Optional<TestResultDto> getById(UUID id) {
        return repository.findById(id).map(this::toDto);
    }

    public TestResultDto create(TestResultCreateDto dto, UUID createdBy, String name) {

        TestOrderItem item = testOrderItemRepository.findById(dto.getTestOrderItemId())
                .orElseThrow(() -> new EntityNotFoundException("TestOrderItem not found"));
        if (testResultRepository.existsByTestOrderItem_Id(item.getId())) {
            throw new IllegalStateException("Result already exists for this TestOrderItem");
        }
        TestType testType = item.getTestType();
        UUID instrumentId = testTypeInstrumentRepository.findFirstByTestType_Id(testType.getId())
                .map(m -> m.getInstrument().getId())
                .orElseThrow(() -> new IllegalStateException("No instrument mapped for this TestType"));
        UUID reagentId = testTypeReagentRepository.findByTestType_Id(testType.getId())
                .stream()
                .findFirst()
                .map(m -> m.getReagent().getId())
                .orElseThrow(() -> new IllegalStateException("No reagent mapped for this TestType"));

        Double value = dto.getResultValue();
        Double min = testType.getReferenceMin();
        Double max = testType.getReferenceMax();

        String flag = calculateFlag(value, min, max);

        TestResult result = TestResult.builder()
                .testOrder(item.getTestOrder())
                .testOrderItem(item)
                .testType(testType)
                .instrumentId(instrumentId)
                .reagentId(reagentId)
                .resultValue(dto.getResultValue())
                .resultUnit(dto.getResultUnit())
                .resultText(dto.getResultText())
                .referenceRangeMin(min)
                .referenceRangeMax(max)
                .interpretation(dto.getInterpretation())
                .flagType(flag)
                .processedAt(OffsetDateTime.now())
                .processedBy(createdBy)
                .versionNumber(1)
                .reviewedAt(OffsetDateTime.now())
                .build();
        TestResult saved = testResultRepository.save(result);
        item.setStatus("COMPLETED");
        item.setFlagType(saved.getFlagType());
        testOrderItemRepository.save(item);
        return toDto(saved);
    }


    private String getUserNameByUuid(UUID userId) {
        if (userId == null) return "Unknown";
        return "User " + userId.toString().substring(0, 5);
    }

    private TestResultDto.UserSummary toUserSummary(UUID userId) {
        if (userId == null) return null;
        return new TestResultDto.UserSummary(userId, getUserNameByUuid(userId));
    }


    private TestResultDto toDto(TestResult e) {
        List<CommentDto> comments = commentService.getByTestResultId(e.getId());
        String testTypeName = testTypeRepository.findById(e.getTestType().getId())
                .map(TestType::getName)
                .orElse(null);

        String instrumentName = instrumentRepository.findById(e.getInstrumentId())
                .map(Instrument::getName)
                .orElse(null);

        String reagentName = reagentRepository.findById(e.getReagentId())
                .map(Reagent::getName)
                .orElse(null);

        return TestResultDto.builder()
                .id(e.getId())

                .testTypeName(testTypeName)
                .instrumentName(instrumentName)
                .reagentName(reagentName)

                .testOrderId(e.getTestOrder().getId())
                .testOrderItemId(e.getTestOrderItem().getId())
                .testTypeId(e.getTestType().getId())
                .instrumentId(e.getInstrumentId())
                .reagentId(e.getReagentId())

                .resultValue(e.getResultValue())
                .resultText(e.getResultText())
                .resultUnit(e.getResultUnit())
                .referenceRangeMin(e.getReferenceRangeMin())
                .referenceRangeMax(e.getReferenceRangeMax())
                .interpretation(e.getInterpretation())
                .flagType(e.getFlagType())

                .processedAt(e.getProcessedAt())
                .reviewedAt(e.getReviewedAt())

                .processedBy(toUserSummary(e.getProcessedBy()))
                .reviewedBy(toUserSummary(e.getReviewedBy()))

                .versionNumber(e.getVersionNumber())
                .comments(comments)
                .build();
    }

    public TestResultDto update(UUID id, TestResultUpdateDto dto, UUID updatedBy) {

        TestResult entity = repository.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("TestResult not found: " + id));

        if (dto.getResultValue() != null) entity.setResultValue(dto.getResultValue());
        if (dto.getResultText() != null) entity.setResultText(dto.getResultText());
        if (dto.getResultUnit() != null) entity.setResultUnit(dto.getResultUnit());
        if (dto.getReferenceRangeMin() != null) entity.setReferenceRangeMin(dto.getReferenceRangeMin());
        if (dto.getReferenceRangeMax() != null) entity.setReferenceRangeMax(dto.getReferenceRangeMax());
        if (dto.getInterpretation() != null) entity.setInterpretation(dto.getInterpretation());

        String newFlag = calculateFlag(
                entity.getResultValue(),
                entity.getReferenceRangeMin(),
                entity.getReferenceRangeMax()
        );
        entity.setFlagType(newFlag);
        entity.setVersionNumber(entity.getVersionNumber() + 1);
        TestResult saved = repository.save(entity);
        TestOrderItem item = saved.getTestOrderItem();
        item.setStatus("COMPLETED");
        item.setFlagType(saved.getFlagType());
        testOrderItemRepository.save(item);

        return toDto(saved);
    }

    private String calculateFlag(Double value, Double min, Double max) {
        if (value != null) {
            if (min != null && value < min) return "LOW";
            else if (max != null && value > max) return "HIGH";
            else return "NORMAL";
        }
        return null;
    }

}