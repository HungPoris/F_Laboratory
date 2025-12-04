package fpt.com.laboratorymanagementbackend.common.exception;

import org.springframework.http.HttpStatus;

import java.util.Map;

public class ConflictException extends AppException {
    public ConflictException(String code) {
        super(code, HttpStatus.CONFLICT);
    }
    public ConflictException(String code, Map<String,Object> params) {
        super(code, HttpStatus.CONFLICT, params);
    }
}
