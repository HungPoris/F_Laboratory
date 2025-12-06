package fpt.com.testorderservices.domain.masterdata.service;

import fpt.com.testorderservices.domain.masterdata.dto.ReagentDto;
import fpt.com.testorderservices.domain.masterdata.entity.Reagent;
import fpt.com.testorderservices.domain.masterdata.repository.ReagentRepository;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional
public class ReagentService {

    private final ReagentRepository repository;


    public List<ReagentDto> getAll() {
        return repository.findAll()
                .stream()
                .sorted(Comparator.comparing(Reagent::getExpirationDate).reversed())
                .map(this::toDto)
                .collect(Collectors.toList());
    }


    private ReagentDto toDto(Reagent e) {
        return new ReagentDto(
                e.getId(),
                e.getName(),
                e.getBatchNumber(),
                e.getExpirationDate(),
                e.getSupplier()
        );
    }
}
