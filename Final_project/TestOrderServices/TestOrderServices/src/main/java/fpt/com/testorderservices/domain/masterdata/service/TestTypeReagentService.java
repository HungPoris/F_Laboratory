package fpt.com.testorderservices.domain.masterdata.service;

import fpt.com.testorderservices.domain.masterdata.dto.TestTypeReagentDto;
import fpt.com.testorderservices.domain.masterdata.entity.TestTypeReagent;
import fpt.com.testorderservices.domain.masterdata.repository.TestTypeReagentRepository;
import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class TestTypeReagentService {

    private final TestTypeReagentRepository repo;


    private TestTypeReagentDto toDto(TestTypeReagent e) {
        return TestTypeReagentDto.builder()
                .id(e.getId())
                .testTypeId(e.getTestType().getId())
                .testTypeCode(e.getTestType().getCode())
                .testTypeName(e.getTestType().getName())
                .reagentId(e.getReagent().getId())
                .reagentName(e.getReagent().getName())
                .build();
    }


    public List<TestTypeReagentDto> getAll() {
        return repo.findAll()
                .stream()
                .map(this::toDto)
                .toList();
    }
}
