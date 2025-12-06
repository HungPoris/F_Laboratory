package fpt.com.testorderservices.common.constants;


/**
 * Chứa các hằng số dùng chung trong toàn hệ thống.
 */
public final class Constants {

    private Constants() {} // Ngăn tạo instance

    public static final String API_PREFIX = "/api/v1";

    // Date format
    public static final String DATE_PATTERN = "yyyy-MM-dd";
    public static final String DATETIME_PATTERN = "yyyy-MM-dd HH:mm:ss";

    // Common messages
    public static final String MSG_SUCCESS = "Operation successful";
    public static final String MSG_CREATED = "Resource created successfully";
    public static final String MSG_DELETED = "Resource deleted successfully";
    public static final String MSG_NOT_FOUND = "Resource not found";
}
