package fpt.com.laboratorymanagementbackend.common.exception;

import org.springframework.http.HttpStatus;

import java.util.Map;

public class BadRequestException extends AppException {
    public BadRequestException(String code) {
        super(code, HttpStatus.BAD_REQUEST);
    }
    public BadRequestException(String code, Map<String,Object> params) {
        super(code, HttpStatus.BAD_REQUEST, params);
    }
}
