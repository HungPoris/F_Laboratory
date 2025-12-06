package fpt.com.testorderservices.domain.comment.controller;

import fpt.com.testorderservices.domain.comment.dto.*;
import fpt.com.testorderservices.domain.comment.service.CommentService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.*;

@RestController
@RequestMapping("/api/v1/comments")
@RequiredArgsConstructor
public class CommentController {

    private final CommentService service;
    private final SimpMessagingTemplate messagingTemplate;

    // ===========================
    // GET BY TEST ORDER
    // ===========================
    @GetMapping("/by-order/{orderId}")
    @PreAuthorize("hasAuthority('test_order.review') or hasRole('ADMIN')")
    public ResponseEntity<List<CommentDto>> getByTestOrderId(@PathVariable UUID orderId) {
        List<CommentDto> comments = service.getByTestOrderId(orderId);
        return comments.isEmpty()
                ? ResponseEntity.noContent().build()
                : ResponseEntity.ok(comments);
    }

    // ===========================
    // GET BY TEST RESULT
    // ===========================
    @GetMapping("/by-result/{resultId}")
    @PreAuthorize("hasAuthority('test_order.review') or hasRole('ADMIN')")
    public ResponseEntity<List<CommentDto>> getByTestResultId(@PathVariable UUID resultId) {
        List<CommentDto> comments = service.getByTestResultId(resultId);
        return comments.isEmpty()
                ? ResponseEntity.noContent().build()
                : ResponseEntity.ok(comments);
    }

    // ===========================
    // GET BY ID
    // ===========================
    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('test_order.review') or hasRole('ADMIN')")
    public ResponseEntity<CommentDto> getById(@PathVariable UUID id) {
        return service.getById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    // ===========================
    // CREATE COMMENT
    // ===========================
    @PostMapping
    @PreAuthorize("hasAuthority('comment.add') or hasRole('ADMIN')")
    public ResponseEntity<?> create(
            @RequestBody CommentCreateDto dto,
            @AuthenticationPrincipal String userId
    ) {
        UUID createdBy = UUID.fromString(userId);
        CommentDto created = service.create(dto, createdBy);

        // Determine ROOM
        String roomId = created.getTestOrderId() != null
                ? created.getTestOrderId().toString()
                : created.getTestResultId().toString();

        // WS event
        messagingTemplate.convertAndSend(
                "/topic/comments/" + roomId,
                new CommentEventDto("created", created)
        );

        return ResponseEntity.ok(created);
    }

    // ===========================
    // UPDATE COMMENT
    // ===========================
    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('comment.modify') or hasRole('ADMIN')")
    public ResponseEntity<CommentDto> update(@PathVariable UUID id,
                                             @RequestBody CommentUpdateDto dto,
                                             @AuthenticationPrincipal String userId) {

        if (userId == null || userId.isBlank()) {
            return ResponseEntity.badRequest().build();
        }

        UUID updatedBy = UUID.fromString(userId);
        CommentDto updated = service.update(id, dto, updatedBy);

        // ROOM for order or result
        String roomId = updated.getTestOrderId() != null
                ? updated.getTestOrderId().toString()
                : updated.getTestResultId().toString();

        // WS broadcast
        messagingTemplate.convertAndSend(
                "/topic/comments/" + roomId,
                new CommentEventDto("updated", updated)
        );

        return ResponseEntity.ok(updated);
    }

    // ===========================
    // DELETE COMMENT
    // ===========================
    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('comment.delete') or hasRole('ADMIN')")
    public ResponseEntity<Void> delete(@PathVariable UUID id,
                                       @AuthenticationPrincipal String userId) {

        if (userId == null || userId.isBlank()) {
            return ResponseEntity.badRequest().build();
        }

        UUID requesterId = UUID.fromString(userId);

        CommentDto deleted = service.delete(id, requesterId);

        // ROOM
        String roomId = deleted.getTestOrderId() != null
                ? deleted.getTestOrderId().toString()
                : deleted.getTestResultId().toString();

        // WS broadcast
        messagingTemplate.convertAndSend(
                "/topic/comments/" + roomId,
                new CommentEventDto("deleted", deleted)
        );

        return ResponseEntity.noContent().build();
    }
}
