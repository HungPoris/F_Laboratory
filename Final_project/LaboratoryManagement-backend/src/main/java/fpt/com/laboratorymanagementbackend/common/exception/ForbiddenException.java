package fpt.com.laboratorymanagementbackend.common.exception;

import org.springframework.http.HttpStatus;

import java.util.Map;

public class ForbiddenException extends AppException {
    public ForbiddenException(String code) {
        super(code, HttpStatus.FORBIDDEN);
    }
    public ForbiddenException(String code, Map<String,Object> params) {
        super(code, HttpStatus.FORBIDDEN, params);
    }
}
