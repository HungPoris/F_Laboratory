package fpt.com.laboratorymanagementbackend.common.exception;

import org.springframework.http.HttpStatus;

import java.util.Map;

public class UnauthorizedException extends AppException {
    public UnauthorizedException(String code) {
        super(code, HttpStatus.UNAUTHORIZED);
    }
    public UnauthorizedException(String code, Map<String,Object> params) {
        super(code, HttpStatus.UNAUTHORIZED, params);
    }
}
