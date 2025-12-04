package fpt.com.laboratorymanagementbackend.common.exception;

import org.springframework.http.HttpStatus;

import java.util.Map;

public class BusinessException extends AppException {
    public BusinessException(String code) {
        super(code, HttpStatus.BAD_REQUEST);
    }
    public BusinessException(String code, Map<String,Object> params) {
        super(code, HttpStatus.BAD_REQUEST, params);
    }
}
