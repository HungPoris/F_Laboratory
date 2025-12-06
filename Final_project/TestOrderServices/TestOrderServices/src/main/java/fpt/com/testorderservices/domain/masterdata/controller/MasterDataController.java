package fpt.com.testorderservices.domain.masterdata.controller;

import fpt.com.testorderservices.domain.masterdata.dto.TestTypeDto;
import fpt.com.testorderservices.domain.masterdata.service.TestTypeService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/v1")
@RequiredArgsConstructor
public class MasterDataController {

    private final TestTypeService testTypeService;
    @GetMapping("/test-types")
    public List<TestTypeDto> getTestTypes()  {
        return testTypeService.getAll();
    }
}
