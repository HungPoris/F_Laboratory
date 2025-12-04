CREATE SCHEMA IF NOT EXISTS iamservice_db;
SET search_path = iamservice_db, public;

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA iamservice_db;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA iamservice_db;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA iamservice_db;



CREATE TABLE IF NOT EXISTS iamservice_db.vn_province (
                                                         code varchar(10) PRIMARY KEY,
    name varchar(255) NOT NULL,
    english_name varchar(255),
    decree varchar(255)
    );


CREATE TABLE IF NOT EXISTS iamservice_db.vn_commune (
                                                        code varchar(10) PRIMARY KEY,
    name varchar(255) NOT NULL,
    english_name varchar(255),
    administrative_level varchar(32),
    province_code varchar(10) NOT NULL REFERENCES iamservice_db.vn_province(code) ON DELETE CASCADE,
    district_code varchar(10),
    province_name varchar(255),
    decree varchar(255)
    );
CREATE INDEX IF NOT EXISTS idx_vn_commune_province ON iamservice_db.vn_commune(province_code);
CREATE INDEX IF NOT EXISTS idx_vn_commune_name ON iamservice_db.vn_commune(lower(name));

CREATE TABLE IF NOT EXISTS outbox_events (
                                             event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    topic VARCHAR(255) NOT NULL,
    payload TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent BOOLEAN NOT NULL DEFAULT FALSE,
    sent_at TIMESTAMPTZ
    );

CREATE INDEX IF NOT EXISTS idx_outbox_unsent ON iamservice_db.outbox_events (sent) WHERE (sent = false);

CREATE TABLE IF NOT EXISTS users (
                                     user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username citext NOT NULL,
    email citext NOT NULL,
    phone_number VARCHAR(20),
    full_name VARCHAR(255) NOT NULL,
    identity_number VARCHAR(50),
    gender VARCHAR(10) CHECK (gender IN ('male','female')),
    date_of_birth DATE,
    address TEXT,
    age_years INTEGER,
    password_hash VARCHAR(255),
    password_algorithm VARCHAR(20) DEFAULT 'ARGON2ID',
    password_updated_at TIMESTAMPTZ DEFAULT now(),
    password_expires_at TIMESTAMPTZ,
    must_change_password BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    is_locked BOOLEAN DEFAULT false,
    locked_at TIMESTAMPTZ,
    locked_until TIMESTAMPTZ,
    locked_reason TEXT,
    failed_login_attempts INTEGER DEFAULT 0,
    last_failed_login_at TIMESTAMPTZ,
    last_successful_login_at TIMESTAMPTZ,
    last_activity_at TIMESTAMPTZ,
    last_login_user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    created_by UUID,
    updated_at TIMESTAMPTZ DEFAULT now(),
    updated_by UUID
    );

DROP INDEX IF EXISTS iamservice_db.idx_users_email_ci;
DROP INDEX IF EXISTS iamservice_db.idx_users_username_ci;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_ci ON iamservice_db.users (lower((email)::text));
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_ci ON iamservice_db.users (lower((username)::text));

CREATE OR REPLACE FUNCTION iamservice_db.update_age_years()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.date_of_birth IS NOT NULL THEN
    NEW.age_years := EXTRACT(YEAR FROM age(NEW.date_of_birth));
ELSE
    NEW.age_years := NULL;
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_age_years ON iamservice_db.users;
CREATE TRIGGER trg_update_age_years
    BEFORE INSERT OR UPDATE OF date_of_birth ON iamservice_db.users
    FOR EACH ROW
    EXECUTE FUNCTION iamservice_db.update_age_years();

CREATE TABLE IF NOT EXISTS roles (
                                     role_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_code VARCHAR(50) NOT NULL,
    role_name VARCHAR(255) NOT NULL,
    role_description TEXT,
    is_system_role BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
    );

CREATE UNIQUE INDEX IF NOT EXISTS idx_roles_code ON iamservice_db.roles (role_code);

CREATE TABLE IF NOT EXISTS privileges (
                                          privilege_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    privilege_code VARCHAR(100) NOT NULL,
    privilege_name VARCHAR(255) NOT NULL,
    privilege_description TEXT,
    privilege_category VARCHAR(50),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
    );

CREATE UNIQUE INDEX IF NOT EXISTS idx_privileges_code ON iamservice_db.privileges (privilege_code);

CREATE TABLE IF NOT EXISTS role_privileges (
                                               role_id UUID NOT NULL,
                                               privilege_id UUID NOT NULL,
                                               PRIMARY KEY (role_id, privilege_id),
    CONSTRAINT role_privileges_role_id_fkey FOREIGN KEY (role_id) REFERENCES iamservice_db.roles(role_id) ON DELETE CASCADE,
    CONSTRAINT role_privileges_privilege_id_fkey FOREIGN KEY (privilege_id) REFERENCES iamservice_db.privileges(privilege_id) ON DELETE CASCADE
    );

CREATE TABLE IF NOT EXISTS user_roles (
                                          user_id UUID NOT NULL,
                                          role_id UUID NOT NULL,
                                          assigned_at TIMESTAMPTZ DEFAULT now(),
    assigned_by UUID,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    PRIMARY KEY (user_id, role_id),
    CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES iamservice_db.users(user_id) ON DELETE CASCADE,
    CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES iamservice_db.roles(role_id) ON DELETE CASCADE
    );

CREATE TABLE IF NOT EXISTS refresh_tokens (
                                              token_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    token_hash VARCHAR(512) NOT NULL,
    token_family_id UUID NOT NULL,
    access_token_jti VARCHAR(255),
    ip_address VARCHAR,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT true,
    is_revoked BOOLEAN DEFAULT false,
    revoked_at TIMESTAMPTZ,
    revoked_reason TEXT,
    last_used_at TIMESTAMPTZ,
    CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES iamservice_db.users(user_id) ON DELETE CASCADE
    );

CREATE INDEX IF NOT EXISTS idx_refresh_user_active ON iamservice_db.refresh_tokens (user_id) WHERE (is_active = true AND is_revoked = false);

CREATE TABLE IF NOT EXISTS system_configurations (
                                                     config_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    config_key VARCHAR(100) NOT NULL,
    config_value TEXT NOT NULL,
    config_type VARCHAR(50) CHECK (config_type IN ('STRING','INTEGER','BOOLEAN')),
    config_category VARCHAR(50),
    description TEXT,
    default_value TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
    );

CREATE UNIQUE INDEX IF NOT EXISTS idx_sysconfig_key ON iamservice_db.system_configurations (config_key);

CREATE TABLE IF NOT EXISTS login_history (
                                             history_id UUID DEFAULT gen_random_uuid() NOT NULL,
    user_id UUID NOT NULL,
    login_method VARCHAR(50) NOT NULL CHECK (login_method IN ('PASSWORD','REFRESH_TOKEN')),
    ip_address VARCHAR NOT NULL,
    user_agent TEXT,
    device_fingerprint VARCHAR(512),
    device_info JSONB,
    geolocation JSONB,
    attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    success BOOLEAN NOT NULL,
    failure_reason VARCHAR(255),
    session_id UUID,
    refresh_token_id UUID,
    PRIMARY KEY (history_id, attempted_at)
    ) PARTITION BY RANGE (attempted_at);

CREATE TABLE IF NOT EXISTS login_history_default PARTITION OF iamservice_db.login_history DEFAULT;
ALTER TABLE IF EXISTS iamservice_db.login_history_default ADD CONSTRAINT IF NOT EXISTS login_history_default_pkey PRIMARY KEY (history_id, attempted_at);
CREATE INDEX IF NOT EXISTS login_hist_user_idx ON iamservice_db.login_history (user_id, attempted_at DESC);
CREATE INDEX IF NOT EXISTS login_hist_ip_idx ON iamservice_db.login_history (ip_address, attempted_at DESC);

CREATE OR REPLACE FUNCTION iamservice_db.publish_event(p_channel TEXT, p_payload TEXT)
RETURNS VOID AS $$
BEGIN
  PERFORM pg_notify(p_channel, p_payload);
INSERT INTO iamservice_db.outbox_events(topic, payload) VALUES (p_channel, p_payload);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION iamservice_db.handle_failed_login(p_user_id UUID, p_threshold INT DEFAULT 5)
RETURNS VOID AS $$
DECLARE v_attempts INT;
BEGIN
UPDATE iamservice_db.users
SET failed_login_attempts = COALESCE(failed_login_attempts,0) + 1,
    last_failed_login_at = now()
WHERE user_id = p_user_id
    RETURNING failed_login_attempts INTO v_attempts;

PERFORM iamservice_db.publish_event('lab.audit.events',
    jsonb_build_object('event','LOGIN_FAILED','user_id',p_user_id,'attempts',v_attempts,'timestamp',now())::text);

  IF v_attempts IS NOT NULL AND v_attempts >= p_threshold THEN
UPDATE iamservice_db.users
SET is_locked = TRUE,
    locked_at = now(),
    locked_until = now() + INTERVAL '30 minutes',
    locked_reason = 'Exceeded ' || p_threshold || ' failed login attempts'
WHERE user_id = p_user_id;

PERFORM iamservice_db.publish_event('lab.audit.events',
      jsonb_build_object('event','USER_LOCKED','user_id',p_user_id,'locked_until',now()+INTERVAL '30 minutes')::text);
END IF;
END;
$$ LANGUAGE plpgsql;

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

CREATE OR REPLACE FUNCTION iamservice_db.admin_disable_user(p_user_id UUID, p_admin_id UUID, p_reason TEXT)
RETURNS VOID AS $$
BEGIN
UPDATE iamservice_db.refresh_tokens
SET is_active = FALSE, is_revoked = TRUE, revoked_at = now(), revoked_reason = COALESCE(p_reason,'DELETED_BY_ADMIN')
WHERE user_id = p_user_id AND is_active = TRUE;

DELETE FROM iamservice_db.users WHERE user_id = p_user_id;

PERFORM iamservice_db.publish_event('lab.audit.events',
    jsonb_build_object('event','USER_DELETED_BY_ADMIN','user_id',p_user_id,'admin_id',p_admin_id,'reason',p_reason,'timestamp',now())::text);
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS iamservice_db.outbox_messages (
                                                             id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    exchange varchar(255) NOT NULL,
    routing_key varchar(255) NOT NULL,
    payload text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    published_at timestamptz,
    attempts integer DEFAULT 0,
    status varchar(20) NOT NULL DEFAULT 'PENDING'
    );

CREATE INDEX IF NOT EXISTS idx_outbox_messages_status_created ON iamservice_db.outbox_messages(status, created_at);

CREATE OR REPLACE FUNCTION iamservice_db.fn_log_outbox_messages_insert()
RETURNS trigger AS $$
BEGIN
INSERT INTO iamservice_db.outbox_events(topic, payload, created_at, sent)
VALUES (NEW.routing_key, NEW.payload, now(), FALSE);
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_outbox_messages_after_insert ON iamservice_db.outbox_messages;
CREATE TRIGGER trg_outbox_messages_after_insert
    AFTER INSERT ON iamservice_db.outbox_messages
    FOR EACH ROW
    EXECUTE FUNCTION iamservice_db.fn_log_outbox_messages_insert();

CREATE OR REPLACE FUNCTION iamservice_db.fn_mark_outbox_sent(p_id uuid)
RETURNS void AS $$
DECLARE v_payload text; v_routing text;
BEGIN
SELECT payload, routing_key INTO v_payload, v_routing
FROM iamservice_db.outbox_messages
WHERE id = p_id;

IF FOUND THEN
UPDATE iamservice_db.outbox_messages
SET status = 'SENT',
    published_at = now(),
    attempts = COALESCE(attempts,0) + 1
WHERE id = p_id;

INSERT INTO iamservice_db.outbox_events(topic, payload, created_at, sent, sent_at)
VALUES (
           'OUTBOX_SENT',
           jsonb_build_object('outbox_id', p_id, 'routing_key', v_routing, 'payload', v_payload)::text,
           now(),
           TRUE,
           now()
       );
END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS iamservice_db.screens (
                                                     screen_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    screen_code VARCHAR(100) NOT NULL,
    path VARCHAR(255) NOT NULL,
    base_path VARCHAR(255),
    component_name VARCHAR(255),
    component_key VARCHAR(255),
    title VARCHAR(255) NOT NULL,
    icon VARCHAR(100),
    ordering INTEGER DEFAULT 0,
    parent_code VARCHAR(100),
    is_menu BOOLEAN DEFAULT TRUE,
    is_default BOOLEAN DEFAULT FALSE,
    is_public BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
    );

CREATE UNIQUE INDEX IF NOT EXISTS ux_screens_code ON iamservice_db.screens (screen_code);
DROP INDEX IF EXISTS iamservice_db.ux_screens_path;
CREATE INDEX IF NOT EXISTS idx_screens_parent_code ON iamservice_db.screens (parent_code);
CREATE INDEX IF NOT EXISTS idx_screens_base_path ON iamservice_db.screens (base_path);
CREATE UNIQUE INDEX IF NOT EXISTS ux_screens_default_true ON iamservice_db.screens (is_default) WHERE is_default = true;

CREATE TABLE IF NOT EXISTS iamservice_db.screen_actions (
                                                            action_code VARCHAR(50) PRIMARY KEY,
    action_name VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
    );

INSERT INTO iamservice_db.screen_actions(action_code, action_name) VALUES
                                                                       ('VIEW','View'),
                                                                       ('CREATE','Create'),
                                                                       ('UPDATE','Update'),
                                                                       ('DELETE','Delete'),
                                                                       ('EXPORT','Export'),
                                                                       ('IMPORT','Import'),
                                                                       ('APPROVE','Approve')
    ON CONFLICT (action_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS iamservice_db.privilege_screen (
                                                              privilege_id UUID NOT NULL,
                                                              screen_id UUID NOT NULL,
                                                              action_code VARCHAR(50) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (privilege_id, screen_id, action_code),
    CONSTRAINT ps_privilege_fk FOREIGN KEY (privilege_id) REFERENCES iamservice_db.privileges(privilege_id) ON DELETE CASCADE,
    CONSTRAINT ps_screen_fk FOREIGN KEY (screen_id) REFERENCES iamservice_db.screens(screen_id) ON DELETE CASCADE,
    CONSTRAINT ps_action_fk FOREIGN KEY (action_code) REFERENCES iamservice_db.screen_actions(action_code) ON DELETE RESTRICT
    );

CREATE INDEX IF NOT EXISTS idx_ps_screen ON iamservice_db.privilege_screen (screen_id, action_code) WHERE (is_active = TRUE);
CREATE INDEX IF NOT EXISTS idx_ps_privilege ON iamservice_db.privilege_screen (privilege_id) WHERE (is_active = TRUE);

CREATE OR REPLACE VIEW iamservice_db.v_user_allowed_screens AS
SELECT DISTINCT
    u.user_id,
    s.screen_id,
    s.screen_code,
    s.path,
    s.base_path,
    s.title,
    COALESCE(s.icon,'') AS icon,
    s.ordering AS ordering,
    s.is_menu AS is_menu,
    s.is_active AS is_active
FROM iamservice_db.users u
         JOIN iamservice_db.screens s ON s.is_active = TRUE AND s.is_public = TRUE
WHERE u.is_active = TRUE
UNION
SELECT DISTINCT
    u.user_id,
    s.screen_id,
    s.screen_code,
    s.path,
    s.base_path,
    s.title,
    COALESCE(s.icon,'') AS icon,
    COALESCE(s.ordering,0) AS ordering,
    s.is_menu AS is_menu,
    s.is_active AS is_active
FROM iamservice_db.users u
         JOIN iamservice_db.user_roles ur ON ur.user_id = u.user_id AND ur.is_active = TRUE
         JOIN iamservice_db.roles r ON r.role_id = ur.role_id AND r.is_active = TRUE
         JOIN iamservice_db.role_privileges rp ON rp.role_id = r.role_id
         JOIN iamservice_db.privileges p ON p.privilege_id = rp.privilege_id AND p.is_active = TRUE
         JOIN iamservice_db.privilege_screen ps ON ps.privilege_id = p.privilege_id AND ps.is_active = TRUE AND ps.action_code = 'VIEW'
         JOIN iamservice_db.screens s ON s.screen_id = ps.screen_id AND s.is_active = TRUE
WHERE u.is_active = TRUE;

CREATE OR REPLACE VIEW iamservice_db.v_user_screen_actions AS
SELECT DISTINCT
    u.user_id,
    s.screen_id,
    s.screen_code,
    ps.action_code
FROM iamservice_db.users u
         JOIN iamservice_db.user_roles ur ON ur.user_id = u.user_id AND ur.is_active = TRUE
         JOIN iamservice_db.roles r ON r.role_id = ur.role_id AND r.is_active = TRUE
         JOIN iamservice_db.role_privileges rp ON rp.role_id = r.role_id
         JOIN iamservice_db.privileges p ON p.privilege_id = rp.privilege_id AND p.is_active = TRUE
         JOIN iamservice_db.privilege_screen ps ON ps.privilege_id = p.privilege_id AND ps.is_active = TRUE
         JOIN iamservice_db.screens s ON s.screen_id = ps.screen_id AND s.is_active = TRUE
WHERE u.is_active = TRUE;

CREATE OR REPLACE FUNCTION iamservice_db.fn_accessible_screens(p_user UUID)
RETURNS JSONB AS $$
DECLARE v_codes JSONB;
BEGIN
SELECT COALESCE(jsonb_agg(screen_code ORDER BY screen_code), '[]'::jsonb) INTO v_codes
FROM (
         SELECT DISTINCT screen_code
         FROM iamservice_db.v_user_allowed_screens
         WHERE user_id = p_user AND COALESCE(is_menu, TRUE) = TRUE
     ) t;
RETURN jsonb_build_object('accessible_screens', v_codes);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION iamservice_db.fn_can_access_base_path(p_user UUID, p_base_path TEXT)
RETURNS BOOLEAN AS $$
BEGIN
RETURN EXISTS (
    SELECT 1
    FROM iamservice_db.v_user_allowed_screens
    WHERE user_id = p_user
      AND (base_path = p_base_path OR path = p_base_path)
);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION iamservice_db.fn_user_actions_for_screen(p_user UUID, p_screen_code VARCHAR)
RETURNS JSONB AS $$
DECLARE v_actions JSONB;
BEGIN
SELECT COALESCE(jsonb_agg(action_code ORDER BY action_code), '[]'::jsonb)
INTO v_actions
FROM iamservice_db.v_user_screen_actions
WHERE user_id = p_user AND screen_code = p_screen_code;
RETURN jsonb_build_object('screenId', p_screen_code, 'actions', v_actions);
END;
$$ LANGUAGE plpgsql STABLE;

UPDATE iamservice_db.screens
SET base_path = COALESCE(base_path, regexp_replace(path, '/:[^/]+', '', 'g'))
WHERE path IS NOT NULL AND (base_path IS NULL OR base_path = '');

CREATE OR REPLACE VIEW iamservice_db.v_screens_all AS
SELECT
    screen_id,
    screen_code,
    path,
    base_path,
    component_name,
    component_key,
    title,
    icon,
    ordering,
    parent_code,
    is_menu,
    is_public,
    is_active
FROM iamservice_db.screens
ORDER BY ordering NULLS LAST, title NULLS LAST;

CREATE OR REPLACE VIEW iamservice_db.v_user_menu AS
SELECT
    vas.user_id,
    s.screen_code,
    s.path,
    s.base_path,
    s.title,
    s.icon,
    s.parent_code,
    s.ordering
FROM iamservice_db.v_user_allowed_screens vas
         JOIN iamservice_db.screens s ON s.screen_code = vas.screen_code
WHERE s.is_menu = TRUE AND s.is_active = TRUE
ORDER BY s.ordering NULLS LAST, s.title NULLS LAST;
