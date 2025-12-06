package fpt.com.testorderservices.domain.comment.service;

import fpt.com.testorderservices.domain.comment.dto.*;
import fpt.com.testorderservices.domain.comment.entity.Comment;
import fpt.com.testorderservices.domain.comment.repository.CommentRepository;
import fpt.com.testorderservices.domain.result.entity.TestResult;
import fpt.com.testorderservices.domain.testorder.entity.TestOrder;
import jakarta.persistence.EntityNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.security.access.AccessDeniedException;

import java.time.OffsetDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional
public class CommentService {

    private final CommentRepository repository;

    // ---------------------------------------------------------
    // GET COMMENTS BY ORDER ID
    // ---------------------------------------------------------
    public List<CommentDto> getByTestOrderId(UUID testOrderId) {
        return repository.findByTestOrder_Id(testOrderId)
                .stream()
                .sorted(Comparator.comparing(
                        Comment::getCreatedAt,
                        Comparator.nullsLast(Comparator.naturalOrder())
                ))
                .map(this::toDto)
                .collect(Collectors.toList());
    }


    // ---------------------------------------------------------
    // GET COMMENTS BY RESULT ID
    // ---------------------------------------------------------
    public List<CommentDto> getByTestResultId(UUID testResultId) {
        return repository.findByTestResult_Id(testResultId)
                .stream()
                .sorted(Comparator.comparing(
                        Comment::getCreatedAt,
                        Comparator.nullsLast(Comparator.naturalOrder())
                ))
                .map(this::toDto)
                .collect(Collectors.toList());
    }


    // ---------------------------------------------------------
    // GET COMMENT BY ID
    // ---------------------------------------------------------
    public Optional<CommentDto> getById(UUID id) {
        return repository.findById(id).map(this::toDto);
    }

    // ---------------------------------------------------------
    // CREATE COMMENT
    // ---------------------------------------------------------
    public CommentDto create(CommentCreateDto dto, UUID createdBy) {
        if (dto.getTestOrderId() == null && dto.getTestResultId() == null) {
            throw new IllegalArgumentException("Comment must belong to either a Test Order or a Test Result");
        }

        Comment entity = fromCreateDto(dto, createdBy);
        Comment saved = repository.save(entity);
        return toDto(saved);
    }

    // ---------------------------------------------------------
    // UPDATE COMMENT (OWNER ONLY HANDLED BY CONTROLLER)
    // ---------------------------------------------------------
    public CommentDto update(UUID id, CommentUpdateDto dto, UUID updatedBy) {

        Comment entity = repository.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("Comment not found with id: " + id));

        if (dto.getCommentText() != null && !dto.getCommentText().isBlank()) {
            entity.setCommentText(dto.getCommentText());
        }

        if (dto.getCommentType() != null) {
            entity.setCommentType(dto.getCommentType());
        }

        entity.setUpdatedBy(updatedBy);
        entity.setUpdatedAt(OffsetDateTime.now());

        Comment updated = repository.save(entity);
        return toDto(updated);
    }

    // ---------------------------------------------------------
    // DELETE COMMENT (OWNER ONLY)
    // ---------------------------------------------------------
    public CommentDto delete(UUID id, UUID userId) {

        Comment entity = repository.findById(id)
                .orElseThrow(() -> new EntityNotFoundException("Comment not found with id: " + id));

        // Check owner
        if (!entity.getCreatedBy().equals(userId)) {
            throw new AccessDeniedException("Bạn không có quyền xóa comment của người khác.");
        }

        // Convert dto before delete
        CommentDto dto = toDto(entity);

        // Delete
        repository.delete(entity);

        return dto; // IMPORTANT: return for WebSocket broadcast
    }

    // ---------------------------------------------------------
    // ENTITY → DTO
    // ---------------------------------------------------------
    private CommentDto toDto(Comment e) {

        CommentDto.UserSummary createdUser = null;
        if (e.getCreatedBy() != null) {
            createdUser = new CommentDto.UserSummary(e.getCreatedBy(), "");
        }

        CommentDto.UserSummary updatedUser = null;
        if (e.getUpdatedBy() != null) {
            updatedUser = new CommentDto.UserSummary(e.getUpdatedBy(), "");
        }

        return CommentDto.builder()
                .id(e.getId())
                .testOrderId(e.getTestOrder() != null ? e.getTestOrder().getId() : null)
                .testResultId(e.getTestResult() != null ? e.getTestResult().getId() : null)
                .commentText(e.getCommentText())
                .commentType(e.getCommentType())

                .createdAt(e.getCreatedAt())
                .updatedAt(e.getUpdatedAt())
              .createdBy(createdUser)
                .updatedBy(updatedUser)
                .build();
    }

    // ---------------------------------------------------------
    // DTO → ENTITY
    // ---------------------------------------------------------
    private Comment fromCreateDto(CommentCreateDto dto, UUID createdBy) {

        Comment entity = new Comment();
        entity.setCommentText(dto.getCommentText());
        entity.setCommentType(dto.getCommentType());
        entity.setCreatedBy(createdBy);
        entity.setCreatedAt(OffsetDateTime.now());

        if (dto.getTestOrderId() != null) {
            entity.setTestOrder(TestOrder.builder().id(dto.getTestOrderId()).build());
        }

        if (dto.getTestResultId() != null) {
            entity.setTestResult(TestResult.builder().id(dto.getTestResultId()).build());
        }

        return entity;
    }
}
