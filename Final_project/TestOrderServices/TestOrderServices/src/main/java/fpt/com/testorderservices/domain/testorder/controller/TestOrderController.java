package fpt.com.testorderservices.domain.testorder.controller;

import fpt.com.testorderservices.common.util.PaginationResponse;
import fpt.com.testorderservices.domain.comment.dto.CommentDto;
import fpt.com.testorderservices.domain.comment.service.CommentService;
import fpt.com.testorderservices.domain.testorder.dto.*;
import fpt.com.testorderservices.domain.testorder.service.TestOrderItemService;
import fpt.com.testorderservices.domain.testorder.service.TestOrderService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/test-orders")
@RequiredArgsConstructor
public class TestOrderController {

    private final TestOrderService service;
    private final CommentService commentService;
    private final TestOrderItemService testOrderItemService;


    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('test_order.review') or hasRole('ADMIN')")
    public ResponseEntity<TestOrderDto> getTestOrderById(@PathVariable UUID id) {
        return service.getById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping("/by-medical-record/{medicalRecordId}")
    @PreAuthorize("hasAuthority('test_order.review') or hasRole('ADMIN')")
    public ResponseEntity<PaginationResponse<TestOrderDto>> getTestOrdersByMedicalRecordId(
            @PathVariable UUID medicalRecordId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size
    ) {
        return ResponseEntity.ok(service.getByMedicalRecordIdPaging(medicalRecordId, page, size));
    }


    @PostMapping
    @PreAuthorize("hasAuthority('test_order.create') or hasRole('ADMIN')")
    public ResponseEntity<?> createTestOrder(
            @Valid @RequestBody TestOrderCreateDto dto,
            BindingResult result,
            @AuthenticationPrincipal String userId
    ) {
        if (result.hasErrors()) {
            Map<String, String> errors = new HashMap<>();
            result.getFieldErrors().forEach(err -> errors.put(err.getField(), err.getDefaultMessage()));
            return ResponseEntity.badRequest().body(errors);
        }
        if (userId == null) {
            return ResponseEntity.badRequest().body("Invalid user token");
        }

        TestOrderDto created = service.create(dto, UUID.fromString(userId));
        return ResponseEntity.ok(created);
    }


    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('test_order.modify') or hasRole('ADMIN')")
    public ResponseEntity<?> updateTestOrder(
            @PathVariable UUID id,
            @Valid @RequestBody TestOrderUpdateDto dto,
            BindingResult result,
            @AuthenticationPrincipal String userId
    ) {
        if (result.hasErrors()) {
            Map<String, String> errors = new HashMap<>();
            result.getFieldErrors().forEach(err -> errors.put(err.getField(), err.getDefaultMessage()));
            return ResponseEntity.badRequest().body(errors);
        }

        if (userId == null) {
            return ResponseEntity.badRequest().body("Invalid user token");
        }

        TestOrderDto updated = service.update(id, dto, UUID.fromString(userId));
        return ResponseEntity.ok(updated);
    }


    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('test_order.delete') or hasRole('ADMIN')")
    public ResponseEntity<Void> deleteTestOrder(
            @PathVariable UUID id,
            @AuthenticationPrincipal String userId
    ) {
        if (userId == null) {
            return ResponseEntity.badRequest().build();
        }

        service.delete(id, UUID.fromString(userId));
        return ResponseEntity.noContent().build();
    }


    @GetMapping("/{orderId}/comments")
    @PreAuthorize("hasAuthority('test_order.review') or hasRole('ADMIN')")
    public ResponseEntity<List<CommentDto>> getComments(@PathVariable UUID orderId) {
        List<CommentDto> comments = commentService.getByTestOrderId(orderId);
        return comments.isEmpty()
                ? ResponseEntity.noContent().build()
                : ResponseEntity.ok(comments);
    }

    @GetMapping("/{id}/detail")
    @PreAuthorize("hasAuthority('test_order.view_detail') or hasRole('ADMIN')")
    public ResponseEntity<TestOrderDto> getTestOrderDetail(@PathVariable UUID id) {
        return service.getDetail(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping("/{id}/add-items")
    @PreAuthorize("hasAuthority('test_order.modify') or hasRole('ADMIN')")
    public ResponseEntity<?> addItems(
            @PathVariable UUID id,
            @RequestBody Map<String, List<UUID>> body,
            @AuthenticationPrincipal String userId
    ) {
        List<UUID> testTypeIds = body.get("testTypeIds");

        if (testTypeIds == null || testTypeIds.isEmpty()) {
            return ResponseEntity.badRequest().body("Missing testTypeIds");
        }

        if (userId == null) {
            return ResponseEntity.badRequest().body("Invalid user token");
        }
        List<TestOrderItemDto> items =
                service.addItemsToOrder(id, testTypeIds, UUID.fromString(userId));

        return ResponseEntity.ok(items);
    }


    @DeleteMapping("/items/{itemId}")
    @PreAuthorize("hasAuthority('test_order.modify') or hasRole('ADMIN')")
    public ResponseEntity<Void> deleteItem(@PathVariable UUID itemId) {
        testOrderItemService.deleteItem(itemId);
        return ResponseEntity.noContent().build();
    }
}
