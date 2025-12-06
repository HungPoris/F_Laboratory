package fpt.com.testorderservices.common.util;

import lombok.*;
import org.springframework.data.domain.Page;

import java.util.List;

/**
 * Chuẩn hóa phản hồi phân trang cho danh sách dữ liệu.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PaginationResponse<T> {

    private List<T> items;
    private int currentPage;
    private int totalPages;
    private long totalElements;
    private int pageSize;

    public static <T> PaginationResponse<T> fromPage(Page<T> page) {
        return PaginationResponse.<T>builder()
                .items(page.getContent())
                .currentPage(page.getNumber())
                .totalPages(page.getTotalPages())
                .totalElements(page.getTotalElements())
                .pageSize(page.getSize())
                .build();
    }
}
