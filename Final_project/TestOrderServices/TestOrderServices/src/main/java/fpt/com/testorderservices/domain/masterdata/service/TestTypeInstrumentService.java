package fpt.com.testorderservices.domain.masterdata.service;

import fpt.com.testorderservices.domain.masterdata.dto.TestTypeInstrumentDto;
import fpt.com.testorderservices.domain.masterdata.entity.TestTypeInstrument;
import fpt.com.testorderservices.domain.masterdata.repository.TestTypeInstrumentRepository;
import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class TestTypeInstrumentService {

    private final TestTypeInstrumentRepository repo;


    private TestTypeInstrumentDto toDto(TestTypeInstrument e) {
        return TestTypeInstrumentDto.builder()
                .id(e.getId())
                .testTypeId(e.getTestType().getId())
                .testTypeCode(e.getTestType().getCode())
                .testTypeName(e.getTestType().getName())
                .instrumentId(e.getInstrument().getId())
                .instrumentCode(e.getInstrument().getCode())
                .instrumentName(e.getInstrument().getName())
                .build();
    }


    public List<TestTypeInstrumentDto> getAll() {
        return repo.findAll()
                .stream()
                .map(this::toDto)
                .toList();
    }
}
