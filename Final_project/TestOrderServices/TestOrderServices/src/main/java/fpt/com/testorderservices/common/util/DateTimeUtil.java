package fpt.com.testorderservices.common.util;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

import static fpt.com.testorderservices.common.constants.Constants.DATETIME_PATTERN;

/**
 * Helper xử lý định dạng thời gian trong hệ thống.
 */
public class DateTimeUtil {

    private DateTimeUtil() {}

    public static String format(LocalDateTime dateTime) {
        if (dateTime == null) return null;
        return dateTime.format(DateTimeFormatter.ofPattern(DATETIME_PATTERN));
    }
}
