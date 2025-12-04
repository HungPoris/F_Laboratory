package fpt.com.laboratorymanagementbackend.common.exception;

import org.springframework.http.HttpStatus;

import java.util.Map;

public class NotFoundException extends AppException {
    public NotFoundException(String code) {
        super(code, HttpStatus.NOT_FOUND);
    }
    public NotFoundException(String code, Map<String,Object> params) {
        super(code, HttpStatus.NOT_FOUND, params);
    }
}
