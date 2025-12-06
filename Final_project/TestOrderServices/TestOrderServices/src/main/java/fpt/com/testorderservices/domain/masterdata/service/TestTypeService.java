package fpt.com.testorderservices.domain.masterdata.service;

import fpt.com.testorderservices.domain.masterdata.dto.TestTypeDto;
import fpt.com.testorderservices.domain.masterdata.entity.TestType;
import fpt.com.testorderservices.domain.masterdata.repository.TestTypeRepository;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional
public class TestTypeService {

    private final TestTypeRepository repository;


    public List<TestTypeDto> getAll() {
        return repository.findAll()
                .stream()
                .sorted(Comparator.comparing(TestType::getCreatedAt).reversed())
                .map(this::toDto)
                .collect(Collectors.toList());
    }

    private TestTypeDto toDto(TestType e) {
        return new TestTypeDto(
                e.getId(),
                e.getCode(),
                e.getName(),
                e.getDescription(),
                e.getCategory(),
                e.getMethod(),
                e.getUnit(),
                e.getReferenceMin(),
                e.getReferenceMax(),
                e.getCreatedAt(),
                e.getUpdatedAt()
        );
    }
}
