package fpt.com.laboratorymanagementbackend.common.util;

import java.time.OffsetDateTime;
import java.time.ZoneId;

public final class TimeUtils {
    private static final ZoneId ZONE_VN = ZoneId.of("Asia/Ho_Chi_Minh");

    public static String toIsoWithZone(OffsetDateTime ts) {
        if (ts == null) return null;
        return ts.atZoneSameInstant(ZONE_VN).toOffsetDateTime().toString();
    }

    public static String formatForVn(OffsetDateTime ts, java.time.format.DateTimeFormatter fmt) {
        if (ts == null) return null;
        return ts.atZoneSameInstant(ZONE_VN).format(fmt);
    }
}
