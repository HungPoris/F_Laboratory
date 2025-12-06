package fpt.com.testorderservices.event;

/**
 * Danh sách mã sự kiện (theo bảng Event Table trong SRS).
 */
public enum EventType {
    TEST_ORDER_CREATED("E_00001"),
    TEST_ORDER_UPDATED("E_00002"),
    TEST_ORDER_DELETED("E_00003"),
    TEST_RESULT_MODIFIED("E_00004"),
    COMMENT_ADDED("E_00005"),
    COMMENT_UPDATED("E_00006"),
    COMMENT_DELETED("E_00007"),
    REVIEW_COMPLETED("E_00008"),
    INSTRUMENT_ACTIVATED("E_00009"),
    USER_LOCKED("E_00010");

    private final String code;

    EventType(String code) {
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
