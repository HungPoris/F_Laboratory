-- V4__admin_only_lock_reason.sql
SET search_path = iamservice_db, public;

-- 1) Cập nhật function: khóa do admin mở + reason tiếng Anh
CREATE OR REPLACE FUNCTION iamservice_db.handle_failed_login(p_user_id UUID, p_threshold INT DEFAULT 5)
RETURNS VOID AS $$
DECLARE
v_attempts INT;
    v_reason TEXT := 'Temporarily locked due to ' || p_threshold || ' incorrect password attempts';
BEGIN
UPDATE iamservice_db.users
SET failed_login_attempts = COALESCE(failed_login_attempts, 0) + 1,
    last_failed_login_at = now()
WHERE user_id = p_user_id
    RETURNING failed_login_attempts INTO v_attempts;

PERFORM iamservice_db.publish_event('lab.audit.events',
        jsonb_build_object('event','LOGIN_FAILED','user_id',p_user_id,'attempts',v_attempts,'timestamp',now())::text);

    IF v_attempts IS NOT NULL AND v_attempts >= p_threshold THEN
UPDATE iamservice_db.users
SET is_locked = TRUE,
    locked_at = now(),
    locked_until = NULL,
    locked_reason = v_reason
WHERE user_id = p_user_id;

PERFORM iamservice_db.publish_event('lab.audit.events',
            jsonb_build_object('event','USER_LOCKED','user_id',p_user_id,'locked_until',NULL,'reason',v_reason,'mode','ADMIN_ONLY','timestamp',now())::text);
END IF;
END;
$$ LANGUAGE plpgsql;

-- 2) Dọn dữ liệu vi phạm trước khi thêm CHECK
UPDATE iamservice_db.users
SET locked_until = NULL
WHERE is_locked IS TRUE AND locked_until IS NOT NULL;

-- Nếu bạn muốn chuẩn hóa luôn reason cho các account đang bị khóa mà chưa có lý do:
UPDATE iamservice_db.users
SET locked_reason = 'Temporarily locked due to 5 incorrect password attempts'
WHERE is_locked IS TRUE AND (locked_reason IS NULL OR locked_reason = '');

-- 3) Thêm CHECK an toàn: NOT VALID, rồi VALIDATE
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'ck_users_admin_only_lock'
      AND conrelid = 'iamservice_db.users'::regclass
  ) THEN
ALTER TABLE iamservice_db.users DROP CONSTRAINT ck_users_admin_only_lock;
END IF;
END$$;

ALTER TABLE iamservice_db.users
    ADD CONSTRAINT ck_users_admin_only_lock
        CHECK ((is_locked IS DISTINCT FROM TRUE) OR (locked_until IS NULL)) NOT VALID;

ALTER TABLE iamservice_db.users
    VALIDATE CONSTRAINT ck_users_admin_only_lock;

-- 4) Index tối ưu
CREATE INDEX IF NOT EXISTS idx_users_is_locked ON iamservice_db.users (is_locked, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_failed_attempts ON iamservice_db.users (failed_login_attempts);

-- 5) Giữ job reset <5 (nếu function đã có, bước này idempotent)
CREATE OR REPLACE FUNCTION iamservice_db.reset_failed_attempts_after_2300()
RETURNS INTEGER AS $$
DECLARE v_count INT;
BEGIN
UPDATE iamservice_db.users
SET failed_login_attempts = 0
WHERE failed_login_attempts > 0
  AND failed_login_attempts < 5
  AND is_locked = FALSE;
GET DIAGNOSTICS v_count = ROW_COUNT;

PERFORM iamservice_db.publish_event('lab.scheduled.events',
        jsonb_build_object('event','RESET_FAILED_ATTEMPTS','rows',v_count,'timestamp',now())::text);
RETURN v_count;
END;
$$ LANGUAGE plpgsql;
