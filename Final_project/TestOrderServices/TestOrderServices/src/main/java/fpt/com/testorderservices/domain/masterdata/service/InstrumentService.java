package fpt.com.testorderservices.domain.masterdata.service;

import fpt.com.testorderservices.domain.masterdata.dto.InstrumentDto;
import fpt.com.testorderservices.domain.masterdata.entity.Instrument;
import fpt.com.testorderservices.domain.masterdata.repository.InstrumentRepository;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional
public class InstrumentService {

    private final InstrumentRepository repository;


    public List<InstrumentDto> getAll() {
        return repository.findAll()
                .stream()
                .sorted(Comparator.comparing(Instrument::getCreatedAt).reversed())
                .map(this::toDto)
                .collect(Collectors.toList());
    }


    private InstrumentDto toDto(Instrument e) {
        return new InstrumentDto(
                e.getId(),
                e.getCode(),
                e.getName(),
                e.getModel(),
                e.getManufacturer(),
                e.getCreatedAt(),
                e.getUpdatedAt()
        );
    }
}
