package fpt.com.laboratorymanagementbackend.common.exception;

import org.springframework.http.HttpStatus;

import java.util.Map;

public class AppException extends RuntimeException {
    private final String code;
    private final HttpStatus status;
    private final Map<String, Object> params;

    public AppException(String code, HttpStatus status) {
        super(code);
        this.code = code;
        this.status = status;
        this.params = null;
    }

    public AppException(String code, HttpStatus status, Map<String, Object> params) {
        super(code);
        this.code = code;
        this.status = status;
        this.params = params;
    }

    public String getCode() {
        return code;
    }

    public HttpStatus getStatus() {
        return status;
    }

    public Map<String, Object> getParams() {
        return params;
    }
}
