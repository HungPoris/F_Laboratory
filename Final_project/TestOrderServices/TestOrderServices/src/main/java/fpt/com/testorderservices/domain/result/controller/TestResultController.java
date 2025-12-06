package fpt.com.testorderservices.domain.result.controller;

import fpt.com.testorderservices.common.service.MailService;
import fpt.com.testorderservices.domain.comment.dto.CommentDto;
import fpt.com.testorderservices.domain.comment.service.CommentService;
import fpt.com.testorderservices.domain.result.dto.*;
import fpt.com.testorderservices.domain.result.service.TestResultService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/test-results")
@RequiredArgsConstructor
public class TestResultController {

    private final TestResultService service;
    private final CommentService commentService;

    @GetMapping("/by-item/{itemId}")
    @PreAuthorize("hasAuthority('test_order.review') or hasRole('ADMIN')")
    public ResponseEntity<List<TestResultDto>> getByItemId(@PathVariable UUID itemId) {
        List<TestResultDto> results = service.getByTestOrderItemId(itemId);
        return results.isEmpty()
                ? ResponseEntity.noContent().build()
                : ResponseEntity.ok(results);
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('test_order.review') or hasRole('ADMIN')")
    public ResponseEntity<TestResultDto> getById(
            @PathVariable UUID id,
            @AuthenticationPrincipal String userId
    ) {
        return service.getById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    @PreAuthorize("hasAuthority('test_order.create') or hasRole('ADMIN')")
    public ResponseEntity<TestResultDto> createTestResult(
            @RequestBody TestResultCreateDto dto,
            @AuthenticationPrincipal String userId,
            @RequestHeader(value = "X-User-Name", required = false) String name
    ) {
        if (userId == null || userId.isBlank()) {
            return ResponseEntity.badRequest().build();
        }

        UUID createdBy = UUID.fromString(userId);

        TestResultDto created = service.create(dto, createdBy, name);
        return ResponseEntity.ok(created);
    }

    @GetMapping("/{resultId}/comments")
    @PreAuthorize("hasAuthority('test_order.review') or hasRole('ADMIN')")
    public ResponseEntity<List<CommentDto>> getComments(@PathVariable UUID resultId) {
        List<CommentDto> comments = commentService.getByTestResultId(resultId);
        return comments.isEmpty()
                ? ResponseEntity.noContent().build()
                : ResponseEntity.ok(comments);
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('test_order.modify') or hasRole('ADMIN')")
    public ResponseEntity<TestResultDto> updateTestResult(
            @PathVariable UUID id,
            @RequestBody TestResultUpdateDto dto,
            @AuthenticationPrincipal String userId
    ) {

        if (userId == null || userId.isBlank()) {
            return ResponseEntity.badRequest().build();
        }

        UUID updatedBy = UUID.fromString(userId);
        TestResultDto updated = service.update(id, dto, updatedBy);
        return ResponseEntity.ok(updated);
    }

}
