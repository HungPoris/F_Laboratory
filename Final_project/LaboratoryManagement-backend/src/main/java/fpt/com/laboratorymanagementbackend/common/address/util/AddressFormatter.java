package fpt.com.laboratorymanagementbackend.common.address.util;

public final class AddressFormatter {
    private AddressFormatter() {}
    public static String full(String house, String communeName, String provinceName) {
        String h = house == null ? "" : house.trim();
        String c = communeName == null ? "" : communeName.trim();
        String p = provinceName == null ? "" : provinceName.trim();
        StringBuilder sb = new StringBuilder();
        if (!h.isBlank()) sb.append(h);
        if (!c.isBlank()) { if (sb.length()>0) sb.append(", "); sb.append(c); }
        if (!p.isBlank()) { if (sb.length()>0) sb.append(", "); sb.append(p); }
        return sb.toString();
    }
}
