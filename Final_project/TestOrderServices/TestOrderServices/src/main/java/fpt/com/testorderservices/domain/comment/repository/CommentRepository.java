package fpt.com.testorderservices.domain.comment.repository;

import fpt.com.testorderservices.domain.comment.entity.Comment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.*;

@Repository
public interface CommentRepository extends JpaRepository<Comment, UUID> {

    List<Comment> findByTestOrder_Id(UUID testOrderId);

    List<Comment> findByTestResult_Id(UUID testResultId);
}
