package fpt.com.testorderservices.domain.masterdata.service;

import fpt.com.testorderservices.domain.masterdata.entity.Flagging;
import fpt.com.testorderservices.domain.masterdata.repository.FlaggingRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class FlaggingService {

    private final FlaggingRepository flaggingRepository;


    public List<Flagging> getActiveRulesByTestType(UUID testTypeId) {
        return flaggingRepository.findByTestType_IdAndIsActive(testTypeId, true);
    }

    public String evaluateFlag(UUID testTypeId, Double value) {

        if (value == null) return "NORMAL";

        List<Flagging> rules = flaggingRepository
                .findByTestType_IdOrderByFlagLevelDesc(testTypeId);

        // Loop từng rule
        for (Flagging rule : rules) {
            if (!Boolean.TRUE.equals(rule.getIsActive())) continue;

            if (matchRule(rule, value)) {
                return rule.getFlagLevel(); // Trả về flag_level trong DB
            }
        }


        return "NORMAL";
    }

    // ================================
    // RULE MATCHING ENGINE
    // ================================
    private boolean matchRule(Flagging rule, Double value) {
        String type = rule.getConditionType();

        switch (type) {

            case "LESS_THAN":
                return rule.getTargetValue() != null &&
                        value < rule.getTargetValue();

            case "GREATER_THAN":
                return rule.getTargetValue() != null &&
                        value > rule.getTargetValue();

            case "EQUAL":
                return rule.getTargetValue() != null &&
                        Double.compare(value, rule.getTargetValue()) == 0;

            case "RANGE":
                return rule.getMinValue() != null &&
                        rule.getMaxValue() != null &&
                        value >= rule.getMinValue() &&
                        value <= rule.getMaxValue();

            case "BETWEEN":
                return rule.getMinValue() != null &&
                        rule.getMaxValue() != null &&
                        value > rule.getMinValue() &&
                        value < rule.getMaxValue();

            default:
                return false;
        }
    }
}
