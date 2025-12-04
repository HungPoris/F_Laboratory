package fpt.com.laboratorymanagementbackend.common.address.service;

import fpt.com.laboratorymanagementbackend.common.address.dto.AddressFormatted;
import fpt.com.laboratorymanagementbackend.common.address.dto.AddressInput;
import fpt.com.laboratorymanagementbackend.common.address.entity.Commune;
import fpt.com.laboratorymanagementbackend.common.address.entity.Province;
import fpt.com.laboratorymanagementbackend.common.address.repository.CommuneRepository;
import fpt.com.laboratorymanagementbackend.common.address.repository.ProvinceRepository;
import fpt.com.laboratorymanagementbackend.common.address.util.AddressFormatter;
import org.springframework.stereotype.Service;

@Service
public class AddressFormatService {
    private final ProvinceRepository provinceRepo;
    private final CommuneRepository communeRepo;

    public AddressFormatService(ProvinceRepository p, CommuneRepository c) { this.provinceRepo = p; this.communeRepo = c; }

    public AddressFormatted format(AddressInput in) {
        String pName = in.getProvinceCode() == null ? null : provinceRepo.findById(in.getProvinceCode()).map(Province::getName).orElse(null);
        String cName = in.getCommuneCode() == null ? null : communeRepo.findById(in.getCommuneCode()).map(Commune::getName).orElse(null);
        String full = AddressFormatter.full(in.getHouse(), cName, pName);
        return new AddressFormatted(full, pName, cName);
    }
}
