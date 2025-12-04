--
-- PostgreSQL database dump
--

\restrict hc3Zkm6RTK3Igp8s8cZmSL6t7BgPrS2Ay1fTQ1nMFmVTN9KObicVEcsdE3lKwZb

-- Dumped from database version 16.10 (Debian 16.10-1.pgdg13+1)
-- Dumped by pg_dump version 18.1

-- Started on 2025-11-27 08:57:22 +07

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 9 (class 2615 OID 32829)
-- Name: iamservice_db; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA iamservice_db;


--
-- TOC entry 282 (class 1255 OID 32983)
-- Name: admin_disable_user(uuid, uuid, text); Type: FUNCTION; Schema: iamservice_db; Owner: -
--

CREATE FUNCTION iamservice_db.admin_disable_user(p_user_id uuid, p_admin_id uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
UPDATE iamservice_db.users
SET is_active = FALSE,
    updated_by = p_admin_id,
    updated_at = now()
WHERE user_id = p_user_id;
UPDATE iamservice_db.refresh_tokens
SET is_active = FALSE, is_revoked = TRUE, revoked_at = now(), revoked_reason = COALESCE(p_reason,'DISABLED_BY_ADMIN')
WHERE user_id = p_user_id AND is_active = TRUE;
PERFORM iamservice_db.publish_event('lab.audit.events', jsonb_build_object('event','USER_DISABLED_BY_ADMIN','user_id',p_user_id,'admin_id',p_admin_id,'reason',p_reason,'timestamp',now()));
END;
$$;


--
-- TOC entry 274 (class 1255 OID 32984)
-- Name: fn_accessible_screens(uuid); Type: FUNCTION; Schema: iamservice_db; Owner: -
--

CREATE FUNCTION iamservice_db.fn_accessible_screens(p_user uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE v_codes JSONB;
BEGIN
  SELECT COALESCE(
    jsonb_agg(screen_code ORDER BY screen_code),
    '[]'::jsonb
  ) INTO v_codes
  FROM (
    SELECT DISTINCT screen_code
    FROM iamservice_db.v_user_allowed_screens
    WHERE user_id = p_user
    -- XÓA DÒNG: AND COALESCE(is_menu, TRUE) = TRUE
  ) t;
  RETURN jsonb_build_object('accessible_screens', v_codes);
END;
$$;


--
-- TOC entry 267 (class 1255 OID 32985)
-- Name: fn_can_access_base_path(uuid, text); Type: FUNCTION; Schema: iamservice_db; Owner: -
--

CREATE FUNCTION iamservice_db.fn_can_access_base_path(p_user uuid, p_base_path text) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM iamservice_db.v_user_allowed_screens
    WHERE user_id = p_user
      AND (base_path = p_base_path OR path = p_base_path)
  );
END;
$$;


--
-- TOC entry 271 (class 1255 OID 32986)
-- Name: fn_user_actions_for_screen(uuid, character varying); Type: FUNCTION; Schema: iamservice_db; Owner: -
--

CREATE FUNCTION iamservice_db.fn_user_actions_for_screen(p_user uuid, p_screen_code character varying) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE v_actions JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(action_code ORDER BY action_code), '[]'::jsonb)
  INTO v_actions
  FROM iamservice_db.v_user_screen_actions
  WHERE user_id = p_user AND screen_code = p_screen_code;

  RETURN jsonb_build_object('screenId', p_screen_code, 'actions', v_actions);
END;
$$;


--
-- TOC entry 256 (class 1255 OID 32987)
-- Name: handle_failed_login(uuid, integer); Type: FUNCTION; Schema: iamservice_db; Owner: -
--

CREATE FUNCTION iamservice_db.handle_failed_login(p_user_id uuid, p_threshold integer DEFAULT 5) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- TOC entry 243 (class 1255 OID 32988)
-- Name: publish_event(text, jsonb); Type: FUNCTION; Schema: iamservice_db; Owner: -
--

CREATE FUNCTION iamservice_db.publish_event(p_channel text, p_payload jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM pg_notify(p_channel, p_payload::text);
INSERT INTO iamservice_db.outbox_events(topic, payload) VALUES (p_channel, p_payload);
END;
$$;


--
-- TOC entry 340 (class 1255 OID 32989)
-- Name: reset_failed_attempts_after_2300(); Type: FUNCTION; Schema: iamservice_db; Owner: -
--

CREATE FUNCTION iamservice_db.reset_failed_attempts_after_2300() RETURNS integer
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- TOC entry 254 (class 1255 OID 32990)
-- Name: update_age_years(); Type: FUNCTION; Schema: iamservice_db; Owner: -
--

CREATE FUNCTION iamservice_db.update_age_years() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.age_years := EXTRACT(YEAR FROM age(NEW.date_of_birth));
RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 219 (class 1259 OID 32991)
-- Name: flyway_schema_history; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.flyway_schema_history (
    installed_rank integer NOT NULL,
    version character varying(50),
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
);


--
-- TOC entry 220 (class 1259 OID 32997)
-- Name: login_history; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.login_history (
    history_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    login_method character varying(50) NOT NULL,
    ip_address character varying NOT NULL,
    user_agent text,
    device_fingerprint character varying(512),
    device_info jsonb,
    geolocation jsonb,
    attempted_at timestamp with time zone DEFAULT now() NOT NULL,
    success boolean NOT NULL,
    failure_reason character varying(255),
    session_id uuid,
    refresh_token_id uuid,
    CONSTRAINT login_history_login_method_check CHECK (((login_method)::text = ANY (ARRAY[('PASSWORD'::character varying)::text, ('PASSKEY'::character varying)::text, ('REFRESH_TOKEN'::character varying)::text])))
)
PARTITION BY RANGE (attempted_at);


--
-- TOC entry 221 (class 1259 OID 33003)
-- Name: login_history_default; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.login_history_default (
    history_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    login_method character varying(50) NOT NULL,
    ip_address character varying NOT NULL,
    user_agent text,
    device_fingerprint character varying(512),
    device_info jsonb,
    geolocation jsonb,
    attempted_at timestamp with time zone DEFAULT now() NOT NULL,
    success boolean NOT NULL,
    failure_reason character varying(255),
    session_id uuid,
    refresh_token_id uuid,
    CONSTRAINT login_history_login_method_check CHECK (((login_method)::text = ANY (ARRAY[('PASSWORD'::character varying)::text, ('PASSKEY'::character varying)::text, ('REFRESH_TOKEN'::character varying)::text])))
);


--
-- TOC entry 222 (class 1259 OID 33011)
-- Name: outbox_events; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.outbox_events (
    event_id uuid DEFAULT gen_random_uuid() NOT NULL,
    topic character varying(255) NOT NULL,
    payload text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sent boolean DEFAULT false NOT NULL,
    sent_at timestamp with time zone
);


--
-- TOC entry 223 (class 1259 OID 33019)
-- Name: outbox_messages; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.outbox_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    exchange character varying(255) NOT NULL,
    routing_key character varying(255) NOT NULL,
    payload text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    published_at timestamp with time zone,
    attempts integer DEFAULT 0,
    status character varying(20) DEFAULT 'PENDING'::character varying NOT NULL
);


--
-- TOC entry 224 (class 1259 OID 33028)
-- Name: privilege_screen; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.privilege_screen (
    privilege_id uuid NOT NULL,
    screen_id uuid NOT NULL,
    action_code character varying(50) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 225 (class 1259 OID 33034)
-- Name: privileges; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.privileges (
    privilege_id uuid DEFAULT gen_random_uuid() NOT NULL,
    privilege_code character varying(100) NOT NULL,
    privilege_name character varying(255) NOT NULL,
    privilege_description text,
    privilege_category character varying(50),
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 226 (class 1259 OID 33043)
-- Name: refresh_tokens; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.refresh_tokens (
    token_id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token_hash character varying(512) NOT NULL,
    token_family_id uuid NOT NULL,
    access_token_jti character varying(255),
    ip_address character varying,
    user_agent text,
    created_at timestamp with time zone DEFAULT now(),
    expires_at timestamp with time zone NOT NULL,
    is_active boolean DEFAULT true,
    is_revoked boolean DEFAULT false,
    revoked_at timestamp with time zone,
    revoked_reason text,
    last_used_at timestamp with time zone
);


--
-- TOC entry 227 (class 1259 OID 33052)
-- Name: role_privileges; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.role_privileges (
    role_id uuid NOT NULL,
    privilege_id uuid NOT NULL
);


--
-- TOC entry 228 (class 1259 OID 33055)
-- Name: roles; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.roles (
    role_id uuid DEFAULT gen_random_uuid() NOT NULL,
    role_code character varying(50) NOT NULL,
    role_name character varying(255) NOT NULL,
    role_description text,
    is_system_role boolean DEFAULT false,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 229 (class 1259 OID 33065)
-- Name: screen_actions; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.screen_actions (
    action_code character varying(50) NOT NULL,
    action_name character varying(100) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- TOC entry 230 (class 1259 OID 33071)
-- Name: screens; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.screens (
    screen_id uuid DEFAULT gen_random_uuid() NOT NULL,
    screen_code character varying(100) NOT NULL,
    path character varying(255) NOT NULL,
    base_path character varying(255),
    title character varying(255) NOT NULL,
    icon character varying(100),
    ordering integer DEFAULT 0,
    parent_code character varying(100),
    is_menu boolean DEFAULT true,
    is_default boolean DEFAULT false,
    is_public boolean DEFAULT false,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    component_name character varying(255),
    component_key character varying(255)
);


--
-- TOC entry 231 (class 1259 OID 33084)
-- Name: system_configurations; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.system_configurations (
    config_id uuid DEFAULT gen_random_uuid() NOT NULL,
    config_key character varying(100) NOT NULL,
    config_value text NOT NULL,
    config_type character varying(50),
    config_category character varying(50),
    description text,
    default_value text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT system_configurations_config_type_check CHECK (((config_type)::text = ANY (ARRAY[('STRING'::character varying)::text, ('INTEGER'::character varying)::text, ('BOOLEAN'::character varying)::text])))
);


--
-- TOC entry 232 (class 1259 OID 33093)
-- Name: user_roles; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.user_roles (
    user_id uuid NOT NULL,
    role_id uuid NOT NULL,
    assigned_at timestamp with time zone DEFAULT now(),
    assigned_by uuid,
    expires_at timestamp with time zone,
    is_active boolean DEFAULT true
);


--
-- TOC entry 233 (class 1259 OID 33098)
-- Name: users; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.users (
    user_id uuid DEFAULT gen_random_uuid() NOT NULL,
    username iamservice_db.citext NOT NULL,
    email iamservice_db.citext NOT NULL,
    phone_number character varying(20),
    full_name character varying(255) NOT NULL,
    identity_number character varying(50),
    gender character varying(10),
    date_of_birth date,
    address text,
    age_years integer,
    password_hash character varying(255),
    password_algorithm character varying(20) DEFAULT 'ARGON2ID'::character varying,
    password_updated_at timestamp with time zone DEFAULT now(),
    password_expires_at timestamp with time zone,
    must_change_password boolean DEFAULT false,
    is_active boolean DEFAULT true,
    is_locked boolean DEFAULT false,
    locked_at timestamp with time zone,
    locked_until timestamp with time zone,
    locked_reason text,
    failed_login_attempts integer DEFAULT 0,
    last_failed_login_at timestamp with time zone,
    last_successful_login_at timestamp with time zone,
    last_activity_at timestamp with time zone,
    last_login_user_agent text,
    created_at timestamp with time zone DEFAULT now(),
    created_by uuid,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by uuid,
    CONSTRAINT ck_users_admin_only_lock CHECK (((is_locked IS DISTINCT FROM true) OR (locked_until IS NULL))),
    CONSTRAINT users_gender_check CHECK (((gender)::text = ANY (ARRAY[('male'::character varying)::text, ('female'::character varying)::text])))
);


--
-- TOC entry 234 (class 1259 OID 33114)
-- Name: v_screens_all; Type: VIEW; Schema: iamservice_db; Owner: -
--

CREATE VIEW iamservice_db.v_screens_all AS
 SELECT screen_id,
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
  ORDER BY ordering, title;


--
-- TOC entry 235 (class 1259 OID 33118)
-- Name: v_user_allowed_screens; Type: VIEW; Schema: iamservice_db; Owner: -
--

CREATE VIEW iamservice_db.v_user_allowed_screens AS
 SELECT DISTINCT u.user_id,
    s.screen_id,
    s.screen_code,
    s.path,
    s.base_path,
    s.title,
    COALESCE(s.icon, ''::character varying) AS icon,
    s.ordering,
    s.is_menu,
    s.is_active
   FROM (iamservice_db.users u
     JOIN iamservice_db.screens s ON (((s.is_active = true) AND (s.is_public = true))))
  WHERE (u.is_active = true)
UNION
 SELECT DISTINCT u.user_id,
    s.screen_id,
    s.screen_code,
    s.path,
    s.base_path,
    s.title,
    COALESCE(s.icon, ''::character varying) AS icon,
    COALESCE(s.ordering, 0) AS ordering,
    s.is_menu,
    s.is_active
   FROM ((((((iamservice_db.users u
     JOIN iamservice_db.user_roles ur ON (((ur.user_id = u.user_id) AND (ur.is_active = true))))
     JOIN iamservice_db.roles r ON (((r.role_id = ur.role_id) AND (r.is_active = true))))
     JOIN iamservice_db.role_privileges rp ON ((rp.role_id = r.role_id)))
     JOIN iamservice_db.privileges p ON (((p.privilege_id = rp.privilege_id) AND (p.is_active = true))))
     JOIN iamservice_db.privilege_screen ps ON (((ps.privilege_id = p.privilege_id) AND (ps.is_active = true))))
     JOIN iamservice_db.screens s ON (((s.screen_id = ps.screen_id) AND (s.is_active = true))))
  WHERE (u.is_active = true);


--
-- TOC entry 236 (class 1259 OID 33123)
-- Name: v_user_menu; Type: VIEW; Schema: iamservice_db; Owner: -
--

CREATE VIEW iamservice_db.v_user_menu AS
 SELECT vas.user_id,
    s.screen_code,
    s.path,
    s.base_path,
    s.title,
    s.icon,
    s.parent_code,
    s.ordering
   FROM (iamservice_db.v_user_allowed_screens vas
     JOIN iamservice_db.screens s ON (((s.screen_code)::text = (vas.screen_code)::text)))
  WHERE ((s.is_menu = true) AND (s.is_active = true))
  ORDER BY s.ordering, s.title;


--
-- TOC entry 237 (class 1259 OID 33128)
-- Name: v_user_screen_actions; Type: VIEW; Schema: iamservice_db; Owner: -
--

CREATE VIEW iamservice_db.v_user_screen_actions AS
 SELECT DISTINCT u.user_id,
    s.screen_id,
    s.screen_code,
    ps.action_code
   FROM ((((((iamservice_db.users u
     JOIN iamservice_db.user_roles ur ON (((ur.user_id = u.user_id) AND (ur.is_active = true))))
     JOIN iamservice_db.roles r ON (((r.role_id = ur.role_id) AND (r.is_active = true))))
     JOIN iamservice_db.role_privileges rp ON ((rp.role_id = r.role_id)))
     JOIN iamservice_db.privileges p ON (((p.privilege_id = rp.privilege_id) AND (p.is_active = true))))
     JOIN iamservice_db.privilege_screen ps ON (((ps.privilege_id = p.privilege_id) AND (ps.is_active = true))))
     JOIN iamservice_db.screens s ON (((s.screen_id = ps.screen_id) AND (s.is_active = true))))
  WHERE (u.is_active = true);


--
-- TOC entry 238 (class 1259 OID 33133)
-- Name: vn_commune; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.vn_commune (
    code character varying(50) NOT NULL,
    name character varying(255) NOT NULL,
    english_name character varying(255),
    administrative_level character varying(32),
    province_code character varying(50) NOT NULL,
    district_code character varying(10),
    province_name character varying(255),
    decree character varying(255)
);


--
-- TOC entry 239 (class 1259 OID 33138)
-- Name: vn_province; Type: TABLE; Schema: iamservice_db; Owner: -
--

CREATE TABLE iamservice_db.vn_province (
    code character varying(10) NOT NULL,
    name character varying(255) NOT NULL,
    english_name character varying(255),
    decree character varying(255)
);


--
-- TOC entry 3494 (class 0 OID 0)
-- Name: login_history_default; Type: TABLE ATTACH; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.login_history ATTACH PARTITION iamservice_db.login_history_default DEFAULT;


--
-- TOC entry 3774 (class 0 OID 32991)
-- Dependencies: 219
-- Data for Name: flyway_schema_history; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.flyway_schema_history (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success) FROM stdin;
0	\N	<< Flyway Schema Creation >>	SCHEMA	"iamservice_db"	\N	postgres	2025-10-26 12:10:10.361847	0	t
2	2	seed	SQL	V2__seed.sql	1252849330	postgres	2025-10-26 12:10:10.564272	22	t
3	3	role privileges mapping	SQL	V3__role_privileges_mapping.sql	-2007784882	postgres	2025-10-26 12:10:10.594331	4	t
1	1	schema	SQL	V1__schema.sql	960860908	postgres	2025-10-26 12:10:10.392182	149	t
4	4	admin only lock reason	SQL	V4__admin_only_lock_reason.sql	-1120999756	postgres	2025-11-05 21:44:11.308101	59	t
\.


--
-- TOC entry 3775 (class 0 OID 33003)
-- Dependencies: 221
-- Data for Name: login_history_default; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.login_history_default (history_id, user_id, login_method, ip_address, user_agent, device_fingerprint, device_info, geolocation, attempted_at, success, failure_reason, session_id, refresh_token_id) FROM stdin;
\.


--
-- TOC entry 3776 (class 0 OID 33011)
-- Dependencies: 222
-- Data for Name: outbox_events; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.outbox_events (event_id, topic, payload, created_at, sent, sent_at) FROM stdin;
613b186a-bfec-46a8-8e5c-ade758e86f6e	lab.audit.events	42694	2025-11-22 07:53:39.786129+00	t	2025-11-22 07:53:39.786146+00
925429f2-50d2-4858-a088-2b8ab5132ef1	lab.audit.events	42695	2025-11-22 07:54:15.246241+00	t	2025-11-22 07:54:15.246246+00
70abacac-33da-40a1-b5a0-8024429c1424	lab.audit.events	42696	2025-11-22 07:57:25.787974+00	t	2025-11-22 07:57:25.78798+00
c81c4a5d-2b75-4465-b3a6-06ef59ee1c9c	lab.audit.events	42697	2025-11-22 07:57:40.932101+00	t	2025-11-22 07:57:40.932106+00
7849ebb8-0142-4df7-9e78-05c295b6cd7f	lab.audit.events	42698	2025-11-22 07:57:46.076562+00	t	2025-11-22 07:57:46.076569+00
343946d8-3bae-48fc-85bf-b069b6c1967a	lab.audit.events	42699	2025-11-22 07:58:16.242508+00	t	2025-11-22 07:58:16.242511+00
e9b12673-1f5e-43c7-a6a1-af17c8012d39	lab.audit.events	42700	2025-11-22 07:58:21.395957+00	t	2025-11-22 07:58:21.395968+00
a4404870-872d-444b-b7ce-7d6b7a3ca398	lab.audit.events	42701	2025-11-22 07:58:31.557002+00	t	2025-11-22 07:58:31.557006+00
fbd83c9d-af66-4d70-98ea-eee50a21c1cb	lab.audit.events	42702	2025-11-22 07:58:51.702175+00	t	2025-11-22 07:58:51.702179+00
49aede89-24fa-4704-931c-694406cfb947	lab.audit.events	42703	2025-11-22 07:58:51.840539+00	t	2025-11-22 07:58:51.840543+00
56a83d73-c930-47a5-8ba7-e7a886a81a85	lab.audit.events	42704	2025-11-22 07:58:51.972036+00	t	2025-11-22 07:58:51.97204+00
8506ef12-d1c5-40b1-9b80-20dff8867bb2	lab.audit.events	42705	2025-11-22 07:58:52.108581+00	t	2025-11-22 07:58:52.108585+00
ee40c78e-7286-48ad-b6b0-b6d11753c861	lab.audit.events	42706	2025-11-22 07:58:52.250449+00	t	2025-11-22 07:58:52.250455+00
97baa27b-51f6-4cbf-9b3a-314ff6681368	lab.audit.events	42707	2025-11-22 07:58:52.391417+00	t	2025-11-22 07:58:52.391423+00
6b79db6c-5704-4462-aea7-36e009402118	lab.audit.events	42708	2025-11-22 07:58:52.528446+00	t	2025-11-22 07:58:52.52845+00
c34674a9-ad0f-4d80-aee0-e71a02dc79a6	lab.audit.events	42709	2025-11-22 07:58:52.657421+00	t	2025-11-22 07:58:52.657426+00
0b91b07a-1966-461b-b207-09ec23b632cc	lab.audit.events	42710	2025-11-22 07:58:52.792738+00	t	2025-11-22 07:58:52.792743+00
5bfd5148-ebbe-41b0-9e2e-540fa108d2e7	lab.audit.events	42711	2025-11-22 07:59:42.960935+00	t	2025-11-22 07:59:42.960939+00
a7372e79-9e49-4e02-bbb9-a73ac4a1e52c	lab.audit.events	42712	2025-11-22 08:01:43.202442+00	t	2025-11-22 08:01:43.202447+00
5cf1fe6b-50a6-42e2-9e01-a2a7929f4863	lab.audit.events	42713	2025-11-22 08:01:53.36219+00	t	2025-11-22 08:01:53.362194+00
16b09fbe-279a-4460-91cb-9739c0b0e5a4	lab.audit.events	42714	2025-11-22 08:01:53.492588+00	t	2025-11-22 08:01:53.492593+00
cb99656d-961f-4d12-840b-20c0fde1a3cf	lab.audit.events	42715	2025-11-22 08:02:03.628928+00	t	2025-11-22 08:02:03.628931+00
49ab368e-5306-438e-aa2f-69135cfb9963	lab.audit.events	42716	2025-11-22 08:02:08.770729+00	t	2025-11-22 08:02:08.770732+00
26937649-88c0-4c2b-8b4f-ce25d2a62c90	lab.audit.events	42717	2025-11-22 08:02:23.920428+00	t	2025-11-22 08:02:23.920432+00
ca5b4a0c-f895-4ff9-9156-12f7f3ce53ad	lab.audit.events	42718	2025-11-22 08:02:29.08848+00	t	2025-11-22 08:02:29.088484+00
990b6f26-81cc-4cd5-a595-425765022ca1	lab.audit.events	42719	2025-11-22 08:05:19.342343+00	t	2025-11-22 08:05:19.342348+00
cfaf43dc-7904-4771-8598-08be54f7ba22	lab.audit.events	42720	2025-11-22 08:05:19.474761+00	t	2025-11-22 08:05:19.474764+00
dbbdbaa9-a238-414c-a92e-0ba7bc361b40	lab.audit.events	42721	2025-11-22 08:05:39.615947+00	t	2025-11-22 08:05:39.61595+00
9901f4c6-c4c5-49a6-8227-17a6330e8bcc	lab.audit.events	42722	2025-11-22 08:05:39.749152+00	t	2025-11-22 08:05:39.749155+00
872774c9-a15f-4e10-ad4c-97107f7d0313	lab.audit.events	42723	2025-11-22 08:06:09.901089+00	t	2025-11-22 08:06:09.901092+00
dd7cc161-1938-4d9e-a9d5-8e90a4ba1712	lab.audit.events	42724	2025-11-22 08:06:10.03185+00	t	2025-11-22 08:06:10.031861+00
7d09f48a-c3e8-4d85-b303-d251d2ce7123	lab.audit.events	42725	2025-11-22 08:06:15.165124+00	t	2025-11-22 08:06:15.165128+00
2c050014-70ea-47ff-898e-ddfdce864147	lab.audit.events	42726	2025-11-22 08:06:15.295328+00	t	2025-11-22 08:06:15.295331+00
9cb14a71-ab1d-48ee-b0f5-78e2d16f2038	lab.audit.events	42727	2025-11-22 08:06:25.438396+00	t	2025-11-22 08:06:25.438399+00
def8d301-b5ba-4595-8c92-69e85727e44d	lab.audit.events	42728	2025-11-22 08:06:25.585772+00	t	2025-11-22 08:06:25.585776+00
687d9462-77a6-4c07-b2ba-36eb2a8068ef	lab.audit.events	42729	2025-11-22 08:06:25.742903+00	t	2025-11-22 08:06:25.742906+00
69476209-40df-43dc-a8d4-aae94cb7914a	lab.audit.events	42762	2025-11-22 14:38:26.638567+00	t	2025-11-22 14:38:26.63857+00
6015a1d3-31d1-447d-9b31-f51b13abcf72	lab.audit.events	42763	2025-11-22 14:38:26.774566+00	t	2025-11-22 14:38:26.774569+00
cae5d233-0814-41be-a193-dd6123e5b398	lab.audit.events	42764	2025-11-22 14:38:36.88525+00	t	2025-11-22 14:38:36.885253+00
aca090f7-cd47-43b9-be73-5f0b2a90eff0	lab.audit.events	42765	2025-11-22 14:38:42.000454+00	t	2025-11-22 14:38:42.000458+00
5a38da52-8ea4-46a0-a0e2-b770af675b6d	lab.audit.events	42766	2025-11-22 14:38:57.129373+00	t	2025-11-22 14:38:57.129377+00
7dd96aa2-c749-4e4a-b995-16aa3ac79b42	lab.audit.events	42767	2025-11-22 14:39:12.268671+00	t	2025-11-22 14:39:12.268676+00
7f9bc773-c1a4-4d4e-9433-20688d656851	lab.audit.events	42768	2025-11-22 14:39:22.393334+00	t	2025-11-22 14:39:22.393336+00
14c2ad89-6401-417f-b1f9-969ddad3320c	lab.audit.events	42769	2025-11-22 14:39:22.505903+00	t	2025-11-22 14:39:22.505906+00
1122e362-b703-41d3-b737-806d4a313082	lab.audit.events	42775	2025-11-22 14:59:43.81056+00	t	2025-11-22 14:59:43.810563+00
f7fd5f7a-5ca4-4ec6-9349-947ef0421097	lab.audit.events	42776	2025-11-22 14:59:43.921954+00	t	2025-11-22 14:59:43.921957+00
c21bc27a-5305-4aad-a1c8-2039a63cbafe	lab.audit.events	42777	2025-11-22 15:00:09.047456+00	t	2025-11-22 15:00:09.047458+00
1909e5b5-0923-492b-aff8-8cc2c689058e	lab.audit.events	42778	2025-11-22 15:00:19.164769+00	t	2025-11-22 15:00:19.164773+00
53fec3a0-ffd0-4e70-8615-59355c2f4e1e	lab.audit.events	42779	2025-11-22 15:00:19.283583+00	t	2025-11-22 15:00:19.283586+00
a5da2d11-0e39-4dc6-badf-a73c1abd8bbc	lab.audit.events	42780	2025-11-22 15:00:24.398066+00	t	2025-11-22 15:00:24.398069+00
32aa5278-fce6-4a5e-affd-4952a0c19bd8	lab.audit.events	42781	2025-11-22 15:00:24.510012+00	t	2025-11-22 15:00:24.510016+00
ba24d6ed-5561-4c92-8c2e-941b149a9bcc	lab.audit.events	42782	2025-11-22 15:00:24.620074+00	t	2025-11-22 15:00:24.620077+00
94faff12-f8c3-4e98-b019-da66f87e4172	lab.audit.events	42783	2025-11-22 15:00:24.730002+00	t	2025-11-22 15:00:24.730005+00
8e091adc-18cf-43ef-97ec-d2adfaf7bd0c	lab.audit.events	42784	2025-11-22 15:00:29.844909+00	t	2025-11-22 15:00:29.844912+00
1292ed4f-ae4f-4c4f-ad51-70f555ce9e79	lab.audit.events	42797	2025-11-22 15:22:12.565851+00	t	2025-11-22 15:22:12.565856+00
5e6ddcdd-fd30-490f-9d91-a371f8a4f428	lab.audit.events	42798	2025-11-22 15:23:02.748875+00	t	2025-11-22 15:23:02.748878+00
d2e59980-fd6a-4155-b037-44591696994f	lab.audit.events	42799	2025-11-22 15:23:07.920406+00	t	2025-11-22 15:23:07.920409+00
adcae2e8-c974-467a-8619-bb4646c9a673	lab.audit.events	42800	2025-11-22 15:23:08.08696+00	t	2025-11-22 15:23:08.086963+00
7b7ede02-ad61-4a78-b18e-dd11ac4121f9	lab.audit.events	42811	2025-11-23 14:06:50.154957+00	t	2025-11-23 14:06:50.15496+00
24d992ae-d735-435b-bd92-267b0f574a38	lab.audit.events	42812	2025-11-23 14:07:55.572098+00	t	2025-11-23 14:07:55.572101+00
bd03aea0-ae3d-466f-8d78-39d6c5519db7	lab.audit.events	42813	2025-11-23 14:08:05.687234+00	t	2025-11-23 14:08:05.687238+00
e1997bdd-a6cc-4ca3-b669-435b96dfc53c	lab.audit.events	42814	2025-11-23 14:08:15.807004+00	t	2025-11-23 14:08:15.807007+00
bd61716d-9a52-46b9-ba2c-4056f9169546	lab.audit.events	42815	2025-11-23 14:08:51.227857+00	t	2025-11-23 14:08:51.22786+00
4eae4cd8-1cbe-42d0-a054-a0599981e694	lab.audit.events	42816	2025-11-23 14:09:01.350704+00	t	2025-11-23 14:09:01.35071+00
aad6d8f2-b219-43f6-8e89-f87d37495672	lab.audit.events	42817	2025-11-23 14:09:01.465337+00	t	2025-11-23 14:09:01.465341+00
c2f5894c-b78a-4248-8ee4-3c6f2c036d16	lab.audit.events	42818	2025-11-23 14:09:11.581582+00	t	2025-11-23 14:09:11.581585+00
1d7545ac-36fb-4ea7-a639-61239d49879d	lab.audit.events	42819	2025-11-23 14:09:16.708774+00	t	2025-11-23 14:09:16.708778+00
b825e157-d969-423d-8904-5c474600e575	lab.audit.events	42820	2025-11-23 14:10:06.841988+00	t	2025-11-23 14:10:06.841993+00
6cea4cfa-7a80-40a0-832d-a801db48a89a	lab.audit.events	42821	2025-11-23 14:10:26.960039+00	t	2025-11-23 14:10:26.960042+00
c356f694-e78f-411b-8dbf-dc181a9b7fe7	lab.audit.events	42845	2025-11-23 15:07:43.935132+00	t	2025-11-23 15:07:43.935141+00
12d9e9ab-7c31-4959-b134-bfa8fd2a21bc	lab.audit.events	42846	2025-11-23 15:07:49.109498+00	t	2025-11-23 15:07:49.109506+00
06ccd7d2-71f2-462c-bf4a-2787ff5d01f4	lab.audit.events	42847	2025-11-23 15:07:49.26745+00	t	2025-11-23 15:07:49.267455+00
b8002e39-6f6c-4c03-ab84-9cd858b2d6de	lab.audit.events	42875	2025-11-23 15:28:19.090894+00	t	2025-11-23 15:28:19.090897+00
7a2d89dc-3f3e-4f82-ae1a-a3af9e4b718e	lab.audit.events	42876	2025-11-23 15:28:19.238465+00	t	2025-11-23 15:28:19.238471+00
65a7e55b-095c-479e-acdb-85a4e111f3c8	lab.audit.events	42877	2025-11-23 15:28:34.38309+00	t	2025-11-23 15:28:34.383092+00
a03f2174-7ff3-48bf-b9b4-1d5515d7c177	lab.audit.events	42878	2025-11-23 15:28:34.52598+00	t	2025-11-23 15:28:34.525983+00
09e36270-22b4-4dae-8b25-8be4f82809f2	lab.audit.events	42879	2025-11-23 15:28:34.69112+00	t	2025-11-23 15:28:34.691124+00
277a2174-9d3d-420f-9ebd-76a432483b2f	lab.audit.events	42897	2025-11-23 15:45:48.125919+00	t	2025-11-23 15:45:48.125922+00
620d38df-3fc6-49ba-8786-beda07c78000	lab.audit.events	42898	2025-11-23 15:46:18.305427+00	t	2025-11-23 15:46:18.305429+00
dc6f76a7-ed23-459c-872c-32b7b02debc0	lab.audit.events	42920	2025-11-24 03:24:18.925725+00	t	2025-11-24 03:24:18.925727+00
b822d472-362c-4909-8519-906cb106866b	lab.audit.events	42924	2025-11-24 03:31:34.926893+00	t	2025-11-24 03:31:34.926896+00
c73f7007-e579-46c6-b0a2-3a1352189c0d	lab.audit.events	42925	2025-11-24 03:31:40.072259+00	t	2025-11-24 03:31:40.072277+00
6d80f47a-4227-4054-90ce-c3d09a8f4afb	lab.audit.events	42926	2025-11-24 03:31:50.224517+00	t	2025-11-24 03:31:50.224522+00
4875753b-27d1-4eb0-9d6c-f35a658f7fd2	lab.audit.events	42927	2025-11-24 03:32:00.371374+00	t	2025-11-24 03:32:00.371379+00
3726e2d1-1281-4ec0-b7db-109f2629ce86	lab.audit.events	42950	2025-11-24 03:35:18.613536+00	t	2025-11-24 03:35:18.613539+00
59cc0fd1-2f78-460f-821b-cc199f323c4b	lab.audit.events	42951	2025-11-24 03:35:18.743532+00	t	2025-11-24 03:35:18.743534+00
81d8f08c-900b-40b4-9009-0683e50d4676	lab.audit.events	42952	2025-11-24 03:35:18.867766+00	t	2025-11-24 03:35:18.867768+00
6eba3c33-c59c-4ffd-8ec7-e38cca99b6fc	lab.audit.events	42953	2025-11-24 03:35:18.992969+00	t	2025-11-24 03:35:18.992971+00
f679542c-4212-426e-bb48-54cffc6a2d23	lab.notify.queue	42730	2025-11-22 08:07:36.217207+00	t	2025-11-22 08:07:36.217229+00
75142cb2-b54f-4d90-acb2-cbf4d3d10f02	lab.audit.events	42731	2025-11-22 08:07:36.361069+00	t	2025-11-22 08:07:36.361076+00
fc1292a4-2761-41cb-bf23-edb0835efa40	lab.audit.events	42732	2025-11-22 08:07:36.504812+00	t	2025-11-22 08:07:36.504817+00
05a51e76-f958-4d6d-b39e-59d4ded2fded	lab.audit.events	42733	2025-11-22 08:07:41.639393+00	t	2025-11-22 08:07:41.639398+00
06262698-6e06-457f-a17f-a13430c6ce71	lab.audit.events	42734	2025-11-22 08:07:51.775644+00	t	2025-11-22 08:07:51.775651+00
9a46da26-66b0-44fa-919d-842d7276551c	lab.audit.events	42735	2025-11-22 08:08:11.915846+00	t	2025-11-22 08:08:11.91585+00
89958e6c-3ff5-473c-92f3-e57cbb4d6d86	lab.audit.events	42736	2025-11-22 08:08:32.065864+00	t	2025-11-22 08:08:32.065892+00
a0f3af62-7b32-4cf6-8c56-4964bf30fbc3	lab.audit.events	42740	2025-11-22 08:08:42.202177+00	t	2025-11-22 08:08:42.202181+00
4057e164-d7c0-4f80-89ff-05e13586df9c	lab.audit.events	42741	2025-11-22 08:11:02.441482+00	t	2025-11-22 08:11:02.441513+00
4e5c0777-591d-4e5b-83aa-d69177bf3996	lab.audit.events	42742	2025-11-22 08:11:17.581771+00	t	2025-11-22 08:11:17.581773+00
cd5af70b-5b3e-4d01-a818-c074dd828420	lab.audit.events	42743	2025-11-22 08:11:17.705647+00	t	2025-11-22 08:11:17.705649+00
f16038a4-4c3c-4530-8104-91d884558b36	lab.audit.events	42744	2025-11-22 08:11:32.839432+00	t	2025-11-22 08:11:32.839435+00
43c59a83-2850-4615-ac3c-aa3d7fc980a0	lab.audit.events	42745	2025-11-22 08:11:37.981766+00	t	2025-11-22 08:11:37.981769+00
d0316208-11c8-4079-bf7c-d08f3a596f29	lab.audit.events	42746	2025-11-22 08:11:43.125011+00	t	2025-11-22 08:11:43.125024+00
1dc21b6f-e694-4fbd-a746-c36d07ccfbc9	lab.audit.events	42747	2025-11-22 08:11:43.263262+00	t	2025-11-22 08:11:43.263265+00
0e707e03-87ef-463e-8f5b-d29bb6f0d809	lab.audit.events	42748	2025-11-22 08:12:38.443211+00	t	2025-11-22 08:12:38.443216+00
f55a088f-c83b-4913-8f2b-a80258900446	lab.audit.events	42749	2025-11-22 08:12:38.572924+00	t	2025-11-22 08:12:38.572928+00
416c4aab-5e12-4f5e-8398-5955159bc5de	lab.audit.events	42770	2025-11-22 14:49:12.901912+00	t	2025-11-22 14:49:12.901915+00
c5d3f981-dff0-4266-89ee-8d03c62feae4	lab.audit.events	42771	2025-11-22 14:49:23.018869+00	t	2025-11-22 14:49:23.018872+00
ed903020-71ae-4953-9726-24f6e457d903	lab.audit.events	42772	2025-11-22 14:49:23.134907+00	t	2025-11-22 14:49:23.134911+00
b021b5d1-eb1d-480c-a6ac-94df4a426981	lab.audit.events	42785	2025-11-22 15:00:49.970898+00	t	2025-11-22 15:00:49.9709+00
5ab7f367-4697-416b-babf-dfffcf370f6c	lab.audit.events	42786	2025-11-22 15:00:55.093024+00	t	2025-11-22 15:00:55.093026+00
ad5851cc-c63b-4a88-8f72-46b0312e027a	lab.audit.events	42787	2025-11-22 15:03:10.272087+00	t	2025-11-22 15:03:10.27209+00
f0811193-d312-4563-8987-9e43ba3c7802	lab.audit.events	42788	2025-11-22 15:03:50.407414+00	t	2025-11-22 15:03:50.407418+00
ba2380e4-4dc4-4e2e-b404-5e4f4b0081d8	lab.audit.events	42789	2025-11-22 15:04:15.528546+00	t	2025-11-22 15:04:15.52855+00
bbab3f69-915f-47f7-8842-9f15f5af7778	lab.audit.events	42801	2025-11-22 15:23:18.285981+00	t	2025-11-22 15:23:18.285984+00
0a3baff4-6ac2-420b-9b38-810924baf55f	lab.audit.events	42802	2025-11-22 15:23:18.477373+00	t	2025-11-22 15:23:18.477377+00
7e047ecf-c834-450b-8f99-8c841e92871c	lab.audit.events	42803	2025-11-22 15:23:23.676955+00	t	2025-11-22 15:23:23.676958+00
be87b8a6-533c-4649-b05a-d0b9602901ca	lab.audit.events	42804	2025-11-22 15:23:23.858602+00	t	2025-11-22 15:23:23.858607+00
3b110264-cf7e-4eea-8130-b4cfb6e5270b	lab.audit.events	42805	2025-11-22 15:24:09.050874+00	t	2025-11-22 15:24:09.050884+00
a32d33a1-32c2-46ee-9672-a869918c6f18	lab.audit.events	42806	2025-11-22 15:24:09.211659+00	t	2025-11-22 15:24:09.211662+00
dca6e10d-ce9b-4b9b-b713-c6a20a350183	lab.audit.events	42807	2025-11-22 15:24:19.386833+00	t	2025-11-22 15:24:19.386836+00
bb1fb8be-5946-43df-ba0c-28da00d7bf35	lab.audit.events	42808	2025-11-22 15:24:24.549134+00	t	2025-11-22 15:24:24.549137+00
04a1fed9-be22-479a-933c-b0b5467816bb	lab.audit.events	42809	2025-11-22 15:24:39.714887+00	t	2025-11-22 15:24:39.71489+00
d87fa8f9-4725-4745-8970-056eb1665812	lab.audit.events	42822	2025-11-23 14:18:07.255903+00	t	2025-11-23 14:18:07.255908+00
2aff9c36-8914-450d-920b-758987aecb30	lab.audit.events	42848	2025-11-23 15:09:19.510226+00	t	2025-11-23 15:09:19.510232+00
3b1133a4-3cba-4202-b556-c0b9bc6c3f8d	lab.audit.events	42849	2025-11-23 15:09:19.655945+00	t	2025-11-23 15:09:19.655951+00
cce085d1-843c-4334-8da7-10f4b56ed15d	lab.audit.events	42850	2025-11-23 15:09:24.806123+00	t	2025-11-23 15:09:24.806129+00
b98c10b3-ea82-4779-b569-df28ebfdd381	lab.audit.events	42851	2025-11-23 15:09:24.946462+00	t	2025-11-23 15:09:24.946473+00
b3ec4213-76b5-4f3f-bdc8-926018fd678a	lab.audit.events	42852	2025-11-23 15:09:35.10301+00	t	2025-11-23 15:09:35.103015+00
c8095c11-c78f-4c97-a7f0-cc715fe84e72	lab.audit.events	42853	2025-11-23 15:09:35.262531+00	t	2025-11-23 15:09:35.262535+00
d7b762c3-abd3-44b1-8075-ec0021d074d6	lab.audit.events	42854	2025-11-23 15:10:55.465987+00	t	2025-11-23 15:10:55.465991+00
013c841f-86d1-46d1-896d-7c781b40b890	lab.audit.events	42855	2025-11-23 15:10:55.601733+00	t	2025-11-23 15:10:55.601736+00
fe5a2bad-bc3d-47f4-92b0-79b766aaf8b1	lab.audit.events	42856	2025-11-23 15:10:55.74165+00	t	2025-11-23 15:10:55.741654+00
9c2ae7df-d3d0-4292-a50f-e7c9d3a0cdbe	lab.audit.events	42857	2025-11-23 15:12:35.949139+00	t	2025-11-23 15:12:35.949143+00
402f6cfd-e4e4-4c2c-9404-16243e6fd115	lab.audit.events	42880	2025-11-23 15:31:44.973915+00	t	2025-11-23 15:31:44.973919+00
c8a892f7-b251-4906-bc92-88dea907fed8	lab.audit.events	42881	2025-11-23 15:31:50.116974+00	t	2025-11-23 15:31:50.116977+00
52eb1b65-3333-43bb-87c6-0480e6806379	lab.audit.events	42882	2025-11-23 15:31:50.254012+00	t	2025-11-23 15:31:50.254014+00
d9e0d0ce-4814-4fe3-ab31-c8662f8bd4ae	lab.audit.events	42918	2025-11-24 03:15:48.44308+00	t	2025-11-24 03:15:48.443082+00
62add11e-eeba-4ac5-9cad-ff9aae118ad9	lab.audit.events	42919	2025-11-24 03:15:53.584115+00	t	2025-11-24 03:15:53.584117+00
f6aa53f7-a1b5-4f32-9215-ca954a1e18b6	lab.audit.events	42921	2025-11-24 03:29:49.189979+00	t	2025-11-24 03:29:49.189982+00
b9aaa9ca-e1cf-41f7-95d2-2c763c0c2679	lab.audit.events	42922	2025-11-24 03:29:54.331123+00	t	2025-11-24 03:29:54.331125+00
38e376b9-a35b-4886-8f0d-63fa0e7bf04e	lab.audit.events	42923	2025-11-24 03:29:59.473395+00	t	2025-11-24 03:29:59.473398+00
3c2fcbb2-ea36-413f-a255-6d9b45c9bf65	lab.audit.events	42928	2025-11-24 03:32:05.51411+00	t	2025-11-24 03:32:05.514115+00
34b5de9c-c29c-45c4-bcb2-d1480550b7c9	lab.audit.events	42929	2025-11-24 03:32:05.648965+00	t	2025-11-24 03:32:05.64897+00
49826a55-f5a0-4124-9386-75b997ee621a	lab.audit.events	42930	2025-11-24 03:32:05.795375+00	t	2025-11-24 03:32:05.795379+00
f2ee98f6-dfa9-424b-9c70-489de6061d17	lab.audit.events	42931	2025-11-24 03:32:10.938002+00	t	2025-11-24 03:32:10.938006+00
37b01bf4-ff69-4ea8-9d8d-f9279bcbac75	lab.audit.events	42934	2025-11-24 03:32:36.081333+00	t	2025-11-24 03:32:36.081337+00
6cf4180c-c6df-4314-b950-40554020fafd	lab.audit.events	42935	2025-11-24 03:32:51.222465+00	t	2025-11-24 03:32:51.22247+00
35e9fedd-edc4-479c-88f3-4412f1dd82fe	lab.audit.events	42936	2025-11-24 03:32:56.375175+00	t	2025-11-24 03:32:56.37519+00
0c1ae496-e62d-4917-b9e3-c924c0507aea	lab.audit.events	42937	2025-11-24 03:33:01.514316+00	t	2025-11-24 03:33:01.514318+00
af4ed3c4-bb0d-4202-8139-90aa18a03669	lab.audit.events	42938	2025-11-24 03:33:01.641902+00	t	2025-11-24 03:33:01.641905+00
3b560f3f-2c77-4201-8d68-9de232cec022	lab.audit.events	42939	2025-11-24 03:33:01.771367+00	t	2025-11-24 03:33:01.77137+00
bbcb38d9-7378-4508-a859-baf46be57484	lab.audit.events	42940	2025-11-24 03:33:01.898932+00	t	2025-11-24 03:33:01.898935+00
8acbb374-cd6e-4cd4-a949-c0212620e254	lab.audit.events	42941	2025-11-24 03:33:02.023793+00	t	2025-11-24 03:33:02.023796+00
98f5f1ba-6f79-4f35-8c72-54f30b59dede	lab.audit.events	42942	2025-11-24 03:33:07.159534+00	t	2025-11-24 03:33:07.159538+00
4b19fa70-1579-4888-af49-ccb56fd89a8e	lab.audit.events	42943	2025-11-24 03:33:07.289478+00	t	2025-11-24 03:33:07.289481+00
650d90f8-4a6a-4412-a437-c22ea205f14b	lab.audit.events	42944	2025-11-24 03:33:12.41897+00	t	2025-11-24 03:33:12.418973+00
2500d235-582b-4d9d-bf0a-a135a3d75f90	lab.audit.events	42945	2025-11-24 03:33:12.549126+00	t	2025-11-24 03:33:12.549128+00
fc2c6b08-119d-4833-9678-7228b3128593	lab.audit.events	42946	2025-11-24 03:34:48.029084+00	t	2025-11-24 03:34:48.029086+00
b5294f28-a0bc-46ec-b959-4cf0e214bed3	lab.audit.events	42947	2025-11-24 03:34:48.182111+00	t	2025-11-24 03:34:48.182114+00
45b7fb91-f8f1-47ae-9d64-b365a11280af	lab.audit.events	42948	2025-11-24 03:35:03.32292+00	t	2025-11-24 03:35:03.322922+00
d59d744b-e29b-4d11-82b8-30209af4f5ef	lab.audit.events	42949	2025-11-24 03:35:03.459775+00	t	2025-11-24 03:35:03.459777+00
4841856a-cff1-4fc8-84ba-aaec8e298db2	lab.audit.events	42955	2025-11-24 03:38:39.211929+00	t	2025-11-24 03:38:39.211932+00
556aeec5-bd91-48c2-9676-06a1d454792f	lab.audit.events	42956	2025-11-24 03:38:39.355394+00	t	2025-11-24 03:38:39.355398+00
bc889f81-e4be-4a52-b292-c794cc9803d8	lab.audit.events	42957	2025-11-24 03:41:19.570265+00	t	2025-11-24 03:41:19.570268+00
ba3ab6a1-661d-4b7c-988d-1ae80d13625a	lab.audit.events	42958	2025-11-24 03:41:19.719067+00	t	2025-11-24 03:41:19.719071+00
e2767d6d-8a19-4cea-ac63-aa50bef57c11	lab.audit.events	42959	2025-11-24 03:46:50.017014+00	t	2025-11-24 03:46:50.017017+00
e6086c0f-4154-4f2f-84a0-b7826fa05806	lab.audit.events	42960	2025-11-24 03:48:00.213957+00	t	2025-11-24 03:48:00.213961+00
829e5d75-dc4d-4c2c-94a7-39c031330c54	lab.audit.events	42961	2025-11-24 03:48:20.415622+00	t	2025-11-24 03:48:20.415648+00
de2c7ed8-0260-49ea-ad20-5584e166eae5	lab.audit.events	42962	2025-11-24 03:48:20.561077+00	t	2025-11-24 03:48:20.561083+00
285601ac-e930-4530-9899-7d3401efec31	lab.audit.events	42963	2025-11-24 03:48:30.696891+00	t	2025-11-24 03:48:30.696893+00
4c5f0b29-250a-48d9-bdf3-40e081381fa9	lab.audit.events	42964	2025-11-24 03:48:30.823781+00	t	2025-11-24 03:48:30.823784+00
e0c9d1ed-7a92-4d5e-8cac-0458e3b94c08	lab.audit.events	42965	2025-11-24 03:52:11.055316+00	t	2025-11-24 03:52:11.055319+00
28b36db9-b65d-42e9-9e86-024eb1b542c6	lab.audit.events	42966	2025-11-24 03:52:11.184094+00	t	2025-11-24 03:52:11.184106+00
28929786-124c-4e36-ac04-afa98bc5c1cd	lab.audit.events	42967	2025-11-24 03:57:31.44594+00	t	2025-11-24 03:57:31.445943+00
7dbd9e13-36a9-4d84-a75d-8f5cd4ff7790	lab.audit.events	42968	2025-11-24 03:57:36.582345+00	t	2025-11-24 03:57:36.582348+00
8932acb1-857e-40e3-a11b-70dd3e13e995	lab.audit.events	42969	2025-11-24 03:57:36.70897+00	t	2025-11-24 03:57:36.708973+00
38423451-f690-4a44-b050-527efdaf5f20	lab.audit.events	42750	2025-11-22 08:12:43.724419+00	t	2025-11-22 08:12:43.724422+00
9182a587-8388-4c35-b1ab-7696f2f30778	lab.audit.events	42751	2025-11-22 08:12:43.873547+00	t	2025-11-22 08:12:43.873549+00
60979469-94eb-4b41-a635-82bc4e74d699	lab.audit.events	42752	2025-11-22 08:12:54.015701+00	t	2025-11-22 08:12:54.015704+00
9aad466a-75a8-4a33-9877-949c3de88e6f	lab.audit.events	42753	2025-11-22 08:12:54.148075+00	t	2025-11-22 08:12:54.148078+00
49542709-ecad-417e-8d50-39698cc915d4	lab.audit.events	42754	2025-11-22 08:12:54.292413+00	t	2025-11-22 08:12:54.292417+00
44799b42-93a6-4e3b-b55f-c83cf87ebda6	lab.audit.events	42755	2025-11-22 08:12:54.421276+00	t	2025-11-22 08:12:54.421278+00
46f519da-d29b-4fd6-b2a6-f69e75e2b9d7	lab.audit.events	42756	2025-11-22 08:13:39.608072+00	t	2025-11-22 08:13:39.608074+00
8a657a40-a93f-4357-b58c-8841fdeda5e7	lab.audit.events	42757	2025-11-22 08:13:44.742735+00	t	2025-11-22 08:13:44.742738+00
9ba0f7ce-7036-47e4-8882-7c1bba060ebc	lab.audit.events	42758	2025-11-22 08:14:39.919257+00	t	2025-11-22 08:14:39.91926+00
6766f67c-c1ac-44d1-a219-5c083869a44f	lab.audit.events	42759	2025-11-22 08:14:40.047883+00	t	2025-11-22 08:14:40.047885+00
4f1fa8cf-c3a6-4de5-90b6-1b9febccdf27	lab.audit.events	42760	2025-11-22 08:14:45.18638+00	t	2025-11-22 08:14:45.186388+00
ec74f3fa-c008-46cd-9ffb-a9f6c0c693d7	lab.audit.events	42761	2025-11-22 08:15:00.332991+00	t	2025-11-22 08:15:00.332995+00
c3883cea-7332-4da1-b121-bf1aa15e5275	lab.audit.events	42773	2025-11-22 14:49:48.332591+00	t	2025-11-22 14:49:48.332596+00
513f0415-d67b-49b2-8494-c9b8f7832968	lab.audit.events	42774	2025-11-22 14:49:48.460068+00	t	2025-11-22 14:49:48.460073+00
15b74590-2ea5-418e-9e38-c1c43369a17b	lab.audit.events	42790	2025-11-22 15:15:45.922567+00	t	2025-11-22 15:15:45.92257+00
2e02852f-b3fa-4f5a-81f5-7dd48f48794f	lab.audit.events	42791	2025-11-22 15:16:11.113997+00	t	2025-11-22 15:16:11.114+00
a07d4334-b4a3-4741-b4e9-e8ab0c441646	lab.audit.events	42792	2025-11-22 15:16:11.289362+00	t	2025-11-22 15:16:11.289364+00
29826279-879b-415f-afd9-1dffa7287b35	lab.audit.events	42793	2025-11-22 15:16:21.462601+00	t	2025-11-22 15:16:21.462605+00
ef6b5dfc-59f1-42eb-9607-984907813ef7	lab.audit.events	42794	2025-11-22 15:16:26.63073+00	t	2025-11-22 15:16:26.630733+00
feb0e60d-286c-4ccc-81ce-6e396b7f6e26	lab.audit.events	42795	2025-11-22 15:16:31.797127+00	t	2025-11-22 15:16:31.79713+00
f47a1bf1-4557-4b95-937f-5d2c6cdbc60d	lab.audit.events	42796	2025-11-22 15:16:31.958324+00	t	2025-11-22 15:16:31.958327+00
9122b27f-dc5f-408b-aff2-8cad0a084207	lab.audit.events	42810	2025-11-23 13:14:28.520418+00	t	2025-11-23 13:14:28.52043+00
0d6fe8b4-7226-498b-867b-4c14e430eb19	lab.audit.events	42823	2025-11-23 14:42:48.973607+00	t	2025-11-23 14:42:48.973635+00
ae67bb3c-95d6-4d88-981e-a07c515fc9c6	lab.audit.events	42824	2025-11-23 14:42:49.147596+00	t	2025-11-23 14:42:49.147609+00
e640fe8d-b9f3-470d-b6d7-47ccb6923dce	lab.audit.events	42692	2025-11-22 06:34:56.839476+00	t	2025-11-22 06:34:56.839484+00
3c83f13f-9394-48d3-a6e3-6bbe6dc0515d	lab.audit.events	42693	2025-11-22 06:35:06.983426+00	t	2025-11-22 06:35:06.983434+00
54910513-5fae-405d-ac56-8b260aa44539	lab.audit.events	42825	2025-11-23 14:42:59.323103+00	t	2025-11-23 14:42:59.323125+00
b49b7d48-be5d-4d9e-b2e1-dabb26d37ca7	lab.audit.events	42826	2025-11-23 14:42:59.487814+00	t	2025-11-23 14:42:59.487822+00
9db115df-56cc-43d1-9aa8-c3adde4a30f0	lab.audit.events	42827	2025-11-23 14:42:59.64175+00	t	2025-11-23 14:42:59.641758+00
4d5ece8f-44a9-471a-b0a0-37fb8333af3c	lab.audit.events	42828	2025-11-23 14:42:59.794299+00	t	2025-11-23 14:42:59.794309+00
325e8685-d3aa-420b-9ce6-d12793ceb97e	lab.audit.events	42829	2025-11-23 14:42:59.951235+00	t	2025-11-23 14:42:59.951245+00
bbfd7126-cb20-451b-aa38-ace53a433f99	lab.audit.events	42830	2025-11-23 14:43:00.102392+00	t	2025-11-23 14:43:00.102401+00
87f6d9df-5893-4b6b-a5cb-99993cb323d4	lab.audit.events	42831	2025-11-23 14:43:00.251274+00	t	2025-11-23 14:43:00.251281+00
ba1782af-0d3b-49e2-877c-267b083100fb	lab.audit.events	42832	2025-11-23 14:43:00.399528+00	t	2025-11-23 14:43:00.399535+00
e505f8fa-9a98-47bb-b2cc-fe632079bfb1	lab.audit.events	42833	2025-11-23 14:43:00.547166+00	t	2025-11-23 14:43:00.547174+00
c084bfbd-4f12-4287-af0e-b51f2df0a4fb	lab.audit.events	42834	2025-11-23 14:43:00.696534+00	t	2025-11-23 14:43:00.696542+00
5e43f9bd-9a88-4080-b9d6-58c4ea1e6d71	lab.audit.events	42835	2025-11-23 14:45:41.329887+00	t	2025-11-23 14:45:41.329894+00
f0a43449-4a3b-4877-aa38-1888339f6a81	lab.audit.events	42836	2025-11-23 14:45:41.478431+00	t	2025-11-23 14:45:41.478437+00
6e2d8c01-5d85-43df-be43-2ca8174f41bc	lab.audit.events	42838	2025-11-23 14:45:51.6455+00	t	2025-11-23 14:45:51.645508+00
b06225ae-f43d-4cf1-b28b-d040a3f99a49	lab.audit.events	42839	2025-11-23 14:45:51.794655+00	t	2025-11-23 14:45:51.794662+00
68d173a2-1874-4988-af88-74359b4dbe34	lab.audit.events	42840	2025-11-23 14:45:51.946155+00	t	2025-11-23 14:45:51.946163+00
ce8f76f3-da6c-49b9-ad85-0ed01f8b7163	lab.audit.events	42841	2025-11-23 15:03:18.059139+00	t	2025-11-23 15:03:18.059146+00
21729fe0-fd35-47ee-88ba-a1b95de9151a	lab.audit.events	42842	2025-11-23 15:03:23.225963+00	t	2025-11-23 15:03:23.22597+00
9b24ff75-d256-4f75-a73d-5b75d7a001bf	lab.audit.events	42843	2025-11-23 15:03:48.41435+00	t	2025-11-23 15:03:48.414634+00
9cb54630-ff1b-4da9-a1fa-7b0aebc700d3	lab.audit.events	42844	2025-11-23 15:03:53.560431+00	t	2025-11-23 15:03:53.560439+00
e4f13d09-4398-4708-821a-4292e5db2531	lab.audit.events	42858	2025-11-23 15:12:46.101436+00	t	2025-11-23 15:12:46.10144+00
c3c9db9d-cd9c-491a-9a30-fe7814ff1539	lab.audit.events	42859	2025-11-23 15:12:51.255246+00	t	2025-11-23 15:12:51.25525+00
7c78d4d2-954c-4417-8f62-ebc9a5ef0561	lab.audit.events	42860	2025-11-23 15:12:51.412891+00	t	2025-11-23 15:12:51.412894+00
5b0973c3-6fec-4efe-844b-cc2551588fb3	lab.audit.events	42861	2025-11-23 15:13:01.572566+00	t	2025-11-23 15:13:01.572589+00
440df361-799c-450c-a5fc-9dd9c8e1f100	lab.audit.events	42862	2025-11-23 15:14:26.764883+00	t	2025-11-23 15:14:26.764887+00
c9ebaa30-5106-4d8a-9522-ea7fe567496e	lab.audit.events	42863	2025-11-23 15:14:26.905762+00	t	2025-11-23 15:14:26.905766+00
5f92c687-4a45-4b17-9024-d5f8f38b961f	lab.audit.events	42864	2025-11-23 15:14:32.044113+00	t	2025-11-23 15:14:32.044116+00
7cfc80db-c544-4383-86e7-129017976eb0	lab.audit.events	42865	2025-11-23 15:14:37.18621+00	t	2025-11-23 15:14:37.186213+00
7ed33e49-21e1-49b8-80e5-ce8b37a58844	lab.audit.events	42866	2025-11-23 15:14:52.33701+00	t	2025-11-23 15:14:52.337014+00
5dbc0b15-a7bd-44d7-94ba-9a2c608b2cfb	lab.audit.events	42867	2025-11-23 15:14:52.480893+00	t	2025-11-23 15:14:52.480897+00
e98f3c76-23a9-435b-af7a-0311a4780e66	lab.audit.events	42868	2025-11-23 15:15:12.653206+00	t	2025-11-23 15:15:12.653209+00
8deafcb6-e1b9-4816-9edc-454551b951ff	lab.audit.events	42869	2025-11-23 15:15:12.804038+00	t	2025-11-23 15:15:12.804407+00
0ecee42a-d8fb-43a3-af6d-43b83526bfc7	lab.audit.events	42870	2025-11-23 15:21:03.201447+00	t	2025-11-23 15:21:03.201451+00
d36c8280-039f-4112-937c-fa34c72948db	lab.audit.events	42871	2025-11-23 15:21:03.384379+00	t	2025-11-23 15:21:03.384382+00
9ab6aded-5112-46b2-ad4a-d4815cd49a59	lab.audit.events	42872	2025-11-23 15:21:48.578233+00	t	2025-11-23 15:21:48.578236+00
d9239702-f4fa-4f87-ac2d-1052894e3b92	lab.audit.events	42873	2025-11-23 15:21:48.729766+00	t	2025-11-23 15:21:48.729771+00
5fc990bb-27f1-45b6-9d1f-dfdd167cbf59	lab.audit.events	42883	2025-11-23 15:40:50.693408+00	t	2025-11-23 15:40:50.69341+00
9cb370bf-1896-4b56-8cb4-97ae80738796	lab.audit.events	42884	2025-11-23 15:40:50.836729+00	t	2025-11-23 15:40:50.836731+00
3b25e79e-d087-411a-ae26-496c90766e23	lab.audit.events	42885	2025-11-23 15:41:00.997881+00	t	2025-11-23 15:41:00.997893+00
c0554aec-ef76-4a13-b1d2-14c926289716	lab.audit.events	42886	2025-11-23 15:41:01.168515+00	t	2025-11-23 15:41:01.168519+00
c1ad4b32-6c8d-4c8e-97fa-ebf3d904c788	lab.audit.events	42887	2025-11-23 15:45:16.739941+00	t	2025-11-23 15:45:16.739943+00
fa296e22-1050-425e-bfee-e54391ca1a8a	lab.audit.events	42888	2025-11-23 15:45:21.882911+00	t	2025-11-23 15:45:21.882914+00
c410814d-be45-42f5-a50f-bb9dd073c7a0	lab.audit.events	42889	2025-11-23 15:45:22.024326+00	t	2025-11-23 15:45:22.024328+00
367dbc30-6b21-4983-936c-d6a99717a595	lab.audit.events	42890	2025-11-23 15:45:27.160571+00	t	2025-11-23 15:45:27.160574+00
cf72afab-71d0-4e31-965b-814ba1abee24	lab.audit.events	42891	2025-11-23 15:45:27.294899+00	t	2025-11-23 15:45:27.294901+00
08e15e14-29da-4255-ad8a-17fbb9d8bbc5	lab.audit.events	42892	2025-11-23 15:45:32.44203+00	t	2025-11-23 15:45:32.442032+00
aa1ff6dd-5caa-4205-a275-8ae1bffa2f2f	lab.audit.events	42893	2025-11-23 15:45:32.574864+00	t	2025-11-23 15:45:32.574866+00
1175f09d-faa1-4ae6-b60a-a016aa7f14c5	lab.audit.events	42894	2025-11-23 15:45:32.70709+00	t	2025-11-23 15:45:32.707092+00
3f39899a-9321-4c40-ae04-cd7e4d814452	lab.audit.events	42895	2025-11-23 15:45:32.836655+00	t	2025-11-23 15:45:32.836665+00
a80574e9-a3e3-4fa1-ad0f-f204dcab97fd	lab.audit.events	42896	2025-11-23 15:45:32.973094+00	t	2025-11-23 15:45:32.973096+00
10be7fbc-a9d5-4bc4-8166-cae51ab848b2	lab.audit.events	42899	2025-11-23 15:46:18.472346+00	t	2025-11-23 15:46:18.472349+00
41c02e19-2b04-4af5-9bf7-d5e43e1bcb6c	lab.audit.events	42900	2025-11-23 15:54:08.864182+00	t	2025-11-23 15:54:08.864184+00
eaed3d9b-1eed-4126-b5e4-0f895b8d29ce	lab.audit.events	42901	2025-11-23 15:54:24.009165+00	t	2025-11-23 15:54:24.009167+00
cb686d03-10c4-4b49-b80a-7f7193c24835	lab.audit.events	42902	2025-11-23 15:54:29.155084+00	t	2025-11-23 15:54:29.155086+00
86bb0386-0ae9-44a3-b699-a9c53395f15d	lab.audit.events	42903	2025-11-23 15:57:14.39609+00	t	2025-11-23 15:57:14.396093+00
fabac58e-b648-4716-bdc5-dead34cfd9a2	lab.audit.events	42904	2025-11-23 15:57:14.530077+00	t	2025-11-23 15:57:14.53008+00
91429e14-9f64-4d75-84b9-46246f1c438b	lab.audit.events	42905	2025-11-23 15:57:14.665042+00	t	2025-11-23 15:57:14.665044+00
398ae64e-21fb-4f1a-b002-003d5687cae0	lab.audit.events	42906	2025-11-23 15:57:34.812009+00	t	2025-11-23 15:57:34.812011+00
13cacd67-c79f-4c72-9a4c-3fdc5dd9adbd	lab.audit.events	42907	2025-11-23 15:57:44.956018+00	t	2025-11-23 15:57:44.95602+00
fa4b2d04-4dcc-45f8-be3b-2409d91fdcc7	lab.audit.events	42908	2025-11-23 15:57:50.108436+00	t	2025-11-23 15:57:50.10844+00
9f376c3e-8099-475a-ba09-6bcb209aef98	lab.audit.events	42910	2025-11-23 15:57:55.263498+00	t	2025-11-23 15:57:55.263501+00
8fef3c72-f767-4d67-9888-95f5916419cd	lab.audit.events	42911	2025-11-23 15:58:00.421098+00	t	2025-11-23 15:58:00.421104+00
411b95b9-e996-41eb-90b1-a74bd9a48030	lab.audit.events	42912	2025-11-23 15:58:00.567225+00	t	2025-11-23 15:58:00.567237+00
60e1d1e0-dbb1-4fb6-97c4-0b3f2f3e0457	lab.audit.events	42970	2025-11-24 04:00:56.956599+00	t	2025-11-24 04:00:56.956602+00
a66728e4-1131-4268-86aa-cf926c272bc2	lab.audit.events	42971	2025-11-24 04:03:42.188601+00	t	2025-11-24 04:03:42.188605+00
3725f92d-f506-4b0d-a9ff-c93c964f8871	lab.audit.events	42972	2025-11-24 04:03:47.325111+00	t	2025-11-24 04:03:47.325114+00
db8b26e7-5f0d-498f-8cee-f6a0d0cb4c90	lab.audit.events	42973	2025-11-24 04:10:02.625241+00	t	2025-11-24 04:10:02.625245+00
74e6d1e3-438c-4bdb-b6cb-e990a7544cb1	lab.audit.events	42974	2025-11-24 04:10:02.76038+00	t	2025-11-24 04:10:02.760383+00
1252ff9e-7132-437b-88f0-9749bf98a39c	lab.audit.events	42975	2025-11-24 04:10:07.890057+00	t	2025-11-24 04:10:07.89006+00
118a2f19-e260-4724-b6d8-be0f0beca2d1	lab.audit.events	42976	2025-11-24 04:10:08.015873+00	t	2025-11-24 04:10:08.015876+00
3728334e-541d-472d-95f3-4366e5b3d899	lab.audit.events	42977	2025-11-24 04:10:18.144876+00	t	2025-11-24 04:10:18.144879+00
d8f4cfc4-ac7d-42e5-aa8a-92d83b1f92e5	lab.audit.events	42978	2025-11-24 04:10:18.271844+00	t	2025-11-24 04:10:18.271846+00
047bbb2d-e6dd-42a0-8fa4-03cd43e05f2f	lab.audit.events	42979	2025-11-24 04:11:33.42435+00	t	2025-11-24 04:11:33.424353+00
3933af7a-4555-45c3-b4d7-96e530f52cbd	lab.audit.events	42980	2025-11-24 04:12:58.591063+00	t	2025-11-24 04:12:58.591067+00
deb0db03-0734-4a5f-8fb8-05d37fd86bfa	lab.audit.events	42981	2025-11-24 04:12:58.716584+00	t	2025-11-24 04:12:58.716586+00
b3ac83cb-6447-48d9-b05c-c1043c60096d	lab.audit.events	42982	2025-11-24 04:13:03.847063+00	t	2025-11-24 04:13:03.847068+00
9ecfb878-09f2-40fa-b081-fdbb3eb909da	lab.audit.events	42983	2025-11-24 04:13:03.971076+00	t	2025-11-24 04:13:03.971078+00
dad692c9-7b89-4b07-b28d-87fe481a78c9	lab.audit.events	42984	2025-11-24 04:13:14.103874+00	t	2025-11-24 04:13:14.103885+00
e036a524-bb3f-4a1b-abc6-9c2268be65e2	lab.audit.events	42985	2025-11-24 04:13:14.232894+00	t	2025-11-24 04:13:14.232897+00
62bae0d5-f20a-49d3-9362-bf3a7ccc3f8a	lab.audit.events	42986	2025-11-24 04:13:14.36051+00	t	2025-11-24 04:13:14.360513+00
8f61c542-644b-4b6e-80e5-ff5012c1e072	lab.audit.events	42987	2025-11-24 04:13:14.485415+00	t	2025-11-24 04:13:14.485418+00
bd118754-1c25-4bbf-9d50-cf691914b829	lab.audit.events	42988	2025-11-24 04:13:59.63486+00	t	2025-11-24 04:13:59.634863+00
39d7dfc0-2924-4703-9e6e-82be74045fec	lab.audit.events	42989	2025-11-24 04:13:59.763842+00	t	2025-11-24 04:13:59.763845+00
5cf21d7a-d3cd-42ed-bf54-bf4cfab684ba	lab.audit.events	42990	2025-11-24 04:14:04.895436+00	t	2025-11-24 04:14:04.895439+00
400e998b-71c4-41cd-95b2-6ba0543a9f2e	lab.audit.events	42991	2025-11-24 04:14:05.021782+00	t	2025-11-24 04:14:05.021786+00
2800662d-cb0e-43e8-b704-85570de89a9a	lab.audit.events	42992	2025-11-24 04:14:10.156606+00	t	2025-11-24 04:14:10.156609+00
7780b290-c5a7-4ded-8b2d-a9e3712f8c26	lab.audit.events	42993	2025-11-24 04:14:10.301055+00	t	2025-11-24 04:14:10.301059+00
34ba2c66-57ad-472e-85a1-f3c076f21bc8	lab.audit.events	42994	2025-11-24 04:14:10.429532+00	t	2025-11-24 04:14:10.429535+00
375e2792-95d6-4ffb-b033-250961b31859	lab.audit.events	42995	2025-11-24 04:14:10.563452+00	t	2025-11-24 04:14:10.563456+00
d6e0ecd7-e145-4618-8c77-9aa48ddaefaa	lab.audit.events	42997	2025-11-24 04:14:30.701796+00	t	2025-11-24 04:14:30.701799+00
c9273796-4611-42c0-808a-578a90aca48f	lab.audit.events	42998	2025-11-24 04:14:40.830654+00	t	2025-11-24 04:14:40.830656+00
01fb3dde-8136-45fd-9544-8189e035da99	lab.audit.events	42999	2025-11-24 04:15:10.979657+00	t	2025-11-24 04:15:10.979659+00
b3e7cd66-6590-4924-92a7-3083bbff2756	lab.audit.events	43000	2025-11-24 04:15:16.109956+00	t	2025-11-24 04:15:16.109958+00
0aa66ef5-fa83-48da-b257-8052655f5e3a	lab.audit.events	43001	2025-11-24 04:16:11.269077+00	t	2025-11-24 04:16:11.269083+00
82e0b740-e7a4-4672-9fd1-6346e69899bb	lab.audit.events	43002	2025-11-24 04:16:11.399737+00	t	2025-11-24 04:16:11.39974+00
6c0c595f-359b-4234-9c80-1d3dd6cea269	lab.audit.events	43003	2025-11-24 04:16:21.538119+00	t	2025-11-24 04:16:21.538123+00
75132ff5-cbf7-4005-a6c2-2add920ace49	lab.audit.events	43004	2025-11-24 04:20:16.762049+00	t	2025-11-24 04:20:16.762052+00
b1ef6ff7-d545-4ff3-ae7c-e1179ba58634	lab.audit.events	43005	2025-11-24 04:21:31.919547+00	t	2025-11-24 04:21:31.91955+00
abfd7898-0efe-45dc-bd1f-6b9d7005481c	lab.audit.events	43006	2025-11-24 04:22:47.103657+00	t	2025-11-24 04:22:47.10366+00
fa05d670-09c0-4887-8d4a-dadb6fee9fc3	lab.audit.events	43007	2025-11-24 04:26:02.334656+00	t	2025-11-24 04:26:02.334659+00
f2786945-ec31-4433-a1ff-95f9fd38a83c	lab.audit.events	43008	2025-11-24 04:26:32.476591+00	t	2025-11-24 04:26:32.476594+00
46da6d0b-8920-488b-a878-55c90a25d303	lab.audit.events	43009	2025-11-24 04:27:02.629004+00	t	2025-11-24 04:27:02.629007+00
4e36e09e-f964-4c3b-b2dd-d78df520ea33	lab.audit.events	43010	2025-11-24 04:27:02.757938+00	t	2025-11-24 04:27:02.757941+00
060166dc-ad9b-49c2-a392-1dee47774a5f	lab.audit.events	43011	2025-11-24 04:27:17.886798+00	t	2025-11-24 04:27:17.886801+00
1ef314dc-82eb-4c7c-97c3-2013657fc0d3	lab.audit.events	43012	2025-11-24 04:30:58.133963+00	t	2025-11-24 04:30:58.133966+00
aaadbd43-3f44-4f65-9ff7-3d46656f1973	lab.audit.events	43013	2025-11-24 04:31:03.264391+00	t	2025-11-24 04:31:03.264394+00
252696b2-f74f-4063-b8c6-38b9d61e8763	lab.audit.events	43014	2025-11-24 04:31:03.404533+00	t	2025-11-24 04:31:03.404539+00
b6cf2ca8-2c93-434e-8e78-ae84e5890635	lab.audit.events	43015	2025-11-24 04:38:08.755445+00	t	2025-11-24 04:38:08.755448+00
4dbc6477-e33d-4863-9225-0e9c9ecda20b	lab.audit.events	43016	2025-11-24 04:38:13.908052+00	t	2025-11-24 04:38:13.908056+00
36121b5a-7624-4934-a4a3-92aa1acab338	lab.audit.events	43017	2025-11-24 04:41:49.438858+00	t	2025-11-24 04:41:49.438861+00
660fbd11-53ba-4f0e-a7ca-baede091eabf	lab.audit.events	43018	2025-11-24 04:45:59.665621+00	t	2025-11-24 04:45:59.665624+00
4158b2ee-2152-4670-8148-72419fdc2631	lab.audit.events	43019	2025-11-24 04:46:39.812437+00	t	2025-11-24 04:46:39.81244+00
217defea-efb4-4ed0-95ce-8948a4688e1b	lab.audit.events	43020	2025-11-24 04:46:44.93859+00	t	2025-11-24 04:46:44.938597+00
4f723b5e-408a-48a5-ae84-046fa914843f	lab.audit.events	43021	2025-11-24 04:46:45.063867+00	t	2025-11-24 04:46:45.063869+00
7641a912-0700-4399-943d-3dc18b17c7e0	lab.audit.events	43022	2025-11-24 04:46:45.198044+00	t	2025-11-24 04:46:45.198048+00
44245cf6-ed1e-4a9d-8e2f-3892d6caab3d	lab.audit.events	43023	2025-11-24 04:46:45.333234+00	t	2025-11-24 04:46:45.333237+00
844f91a9-fe65-449a-ba4c-607231a1d078	lab.audit.events	43024	2025-11-24 04:46:50.467382+00	t	2025-11-24 04:46:50.467385+00
884d3624-2fa2-4b36-818c-bfe26153b408	lab.audit.events	43025	2025-11-24 04:47:00.61738+00	t	2025-11-24 04:47:00.617383+00
5a53b230-5782-47d4-9ba4-0819b2f3c3ea	lab.audit.events	43026	2025-11-24 04:47:10.75326+00	t	2025-11-24 04:47:10.753264+00
eab94e1e-47ad-4fd2-a25e-b2f6657b0198	lab.audit.events	43027	2025-11-24 04:47:20.881538+00	t	2025-11-24 04:47:20.881541+00
1ddbd399-bf18-40e2-86fd-14d24b936556	lab.audit.events	43028	2025-11-24 04:47:26.009575+00	t	2025-11-24 04:47:26.009578+00
130813d9-0910-4990-a7ec-055f9aa50ea8	lab.audit.events	43029	2025-11-24 04:48:01.437648+00	t	2025-11-24 04:48:01.437651+00
c193cbca-ea2b-47b6-8a3f-18eb82ff47c9	lab.audit.events	43030	2025-11-24 04:48:01.562169+00	t	2025-11-24 04:48:01.562172+00
2691ed41-3551-4a77-a988-990f3bf970ca	lab.audit.events	43031	2025-11-24 04:48:01.687015+00	t	2025-11-24 04:48:01.687018+00
a49fc43d-4835-41d0-98e2-23d6c38d1c72	lab.audit.events	43032	2025-11-24 04:48:01.808883+00	t	2025-11-24 04:48:01.808888+00
1ba8b2af-f02e-4041-8d45-89069435332a	lab.audit.events	43033	2025-11-24 04:54:57.104551+00	t	2025-11-24 04:54:57.104554+00
ff2c329f-b0b6-46df-951d-72799040aec4	lab.audit.events	43034	2025-11-24 04:57:02.324917+00	t	2025-11-24 04:57:02.324921+00
dfabc3bd-a3e1-499e-85a9-c1a552ab4830	lab.audit.events	43040	2025-11-24 12:19:02.650386+00	t	2025-11-24 12:19:02.650393+00
9a2e5051-6cbd-48d6-a3d2-df75c32e8808	lab.audit.events	43041	2025-11-24 12:19:22.80553+00	t	2025-11-24 12:19:22.805533+00
dbfeb70f-aa49-4599-b1d9-48154c03c6a5	lab.audit.events	43043	2025-11-24 12:19:52.950069+00	t	2025-11-24 12:19:52.950072+00
77155afa-050f-4d2a-a418-6a8256ec7aff	lab.audit.events	43044	2025-11-24 13:49:15.07319+00	t	2025-11-24 13:49:15.073197+00
fe51e184-5771-4c07-8d79-831d1e9a8b4c	lab.audit.events	43065	2025-11-25 03:26:22.594935+00	t	2025-11-25 03:26:22.594941+00
d22ef829-7fe9-4525-96ad-d5f13ed178bf	lab.audit.events	43066	2025-11-25 03:40:28.38605+00	t	2025-11-25 03:40:28.386057+00
ee927dd1-8ecf-4d24-9d56-3cff42e33a85	lab.audit.events	43067	2025-11-25 04:17:09.346039+00	t	2025-11-25 04:17:09.346041+00
8018c37d-fbfd-4c5c-af09-e7f26243ac4c	lab.audit.events	43073	2025-11-25 04:29:35.086554+00	t	2025-11-25 04:29:35.086567+00
185bf0c4-d133-46c3-938f-1fcd67d894d5	lab.audit.events	43074	2025-11-25 04:46:05.895145+00	t	2025-11-25 04:46:05.895148+00
f9e023ed-8b6e-4f59-9b80-a7777f0a3bf8	lab.audit.events	43075	2025-11-25 05:00:21.348599+00	t	2025-11-25 05:00:21.348602+00
7f044ef9-541f-4664-8471-1a0f5f9b7cfe	lab.audit.events	43076	2025-11-25 05:15:36.823555+00	t	2025-11-25 05:15:36.823558+00
f95ad320-73dd-4038-aad0-212b2fdbfeca	lab.audit.events	43077	2025-11-25 05:30:22.29802+00	t	2025-11-25 05:30:22.298023+00
d643caa8-d84b-4506-b2e4-5f68fe6c67f8	lab.audit.events	43078	2025-11-25 05:44:27.762891+00	t	2025-11-25 05:44:27.762902+00
d3cc8b12-5e67-4b44-8fec-2d1940c9ffa1	lab.audit.events	43079	2025-11-25 05:58:33.491195+00	t	2025-11-25 05:58:33.491198+00
6e30548e-5f7d-42a4-9bd9-0d8fa1251e38	lab.audit.events	43080	2025-11-25 06:12:43.936385+00	t	2025-11-25 06:12:43.936388+00
f28509db-a73d-4222-93f8-7e071951d08d	lab.audit.events	43081	2025-11-25 06:22:14.303546+00	t	2025-11-25 06:22:14.303549+00
1eee8a2d-6892-4d73-b9de-0ac25142a6ea	lab.audit.events	43087	2025-11-25 11:20:50.858438+00	t	2025-11-25 11:20:50.858445+00
60ff5e9f-93b3-4a21-884b-8c7fdd0b8b3b	lab.audit.events	43088	2025-11-25 12:18:07.609871+00	t	2025-11-25 12:18:07.609873+00
3f3eda3a-d811-47d0-8374-6110eba79ce2	lab.audit.events	43089	2025-11-25 12:26:13.187244+00	t	2025-11-25 12:26:13.187247+00
f10ea209-97da-437d-8d97-2c8e1a2fcc52	lab.audit.events	43090	2025-11-25 12:27:53.622929+00	t	2025-11-25 12:27:53.622931+00
36db21f4-c905-4f4d-a609-2bd04c93e159	lab.audit.events	43091	2025-11-25 12:27:58.736813+00	t	2025-11-25 12:27:58.736815+00
2c2dc28c-4c83-478b-a9d9-bce6e41e9761	lab.audit.events	43092	2025-11-25 12:27:58.848162+00	t	2025-11-25 12:27:58.848166+00
c86d5f23-347a-4fa5-8f83-eb74a9b9f2ea	lab.audit.events	43093	2025-11-25 12:28:03.96661+00	t	2025-11-25 12:28:03.966612+00
3b7dc19a-a0d0-4ade-8921-8aecb2ccc82b	lab.audit.events	43094	2025-11-25 12:28:04.082013+00	t	2025-11-25 12:28:04.082016+00
c689af63-3f16-41a3-b355-7ec10c66b114	lab.audit.events	43095	2025-11-25 12:28:09.19536+00	t	2025-11-25 12:28:09.195362+00
b097c659-157e-41f8-92a5-40073fc96df4	lab.audit.events	43096	2025-11-25 12:28:09.311053+00	t	2025-11-25 12:28:09.311055+00
c6862aff-98fe-457f-bf97-8dd637cac25d	lab.audit.events	43097	2025-11-25 12:28:09.424979+00	t	2025-11-25 12:28:09.424982+00
c8e832ea-3fd8-4892-9636-d0936b1813d2	lab.audit.events	43098	2025-11-25 12:28:09.538272+00	t	2025-11-25 12:28:09.538274+00
3d3d2f68-6d4e-495e-b572-5a44e5d4981f	lab.audit.events	43099	2025-11-25 12:32:24.756849+00	t	2025-11-25 12:32:24.756851+00
848b83f3-dc79-4e10-a37c-e8bd54edb2ad	lab.audit.events	43100	2025-11-25 12:35:09.955716+00	t	2025-11-25 12:35:09.955718+00
fae6b852-3997-460a-8e0b-da0a768d1612	lab.audit.events	43101	2025-11-25 12:39:05.181098+00	t	2025-11-25 12:39:05.1811+00
a0a199db-9b9d-4e4d-b313-a7107536c6c8	lab.audit.events	43102	2025-11-25 12:39:25.309224+00	t	2025-11-25 12:39:25.309226+00
df7d087f-e3a1-4845-afc4-4b61ebf883f1	lab.audit.events	43103	2025-11-25 12:39:25.423534+00	t	2025-11-25 12:39:25.423536+00
51afb638-b119-43b1-aab2-fb4805eda947	lab.audit.events	43104	2025-11-25 12:39:35.538355+00	t	2025-11-25 12:39:35.538357+00
bf5948e7-aa6e-4f8e-8106-87e6e7542a4e	lab.audit.events	43105	2025-11-25 12:39:45.650796+00	t	2025-11-25 12:39:45.650798+00
7ca8ea8d-4988-4c7c-8a08-e873c4304d5b	lab.audit.events	43106	2025-11-25 12:39:45.75941+00	t	2025-11-25 12:39:45.759412+00
da5fefe4-9247-412c-ad18-817d6d0edb2a	lab.audit.events	43107	2025-11-25 12:47:01.065868+00	t	2025-11-25 12:47:01.065871+00
c11a3da5-89f1-44ed-ba6b-f8f8b8937ba5	lab.audit.events	43108	2025-11-25 12:48:36.50027+00	t	2025-11-25 12:48:36.500276+00
2d62cdd2-5d98-4318-b076-37e13a6bff15	lab.audit.events	43109	2025-11-25 12:58:06.844995+00	t	2025-11-25 12:58:06.844997+00
6fa786ca-4eb4-40d5-a747-9c88b6fa4908	lab.audit.events	43110	2025-11-25 12:58:16.966566+00	t	2025-11-25 12:58:16.966569+00
130a200f-e375-4c48-b32b-9553d84051d5	lab.audit.events	43111	2025-11-25 12:58:17.076809+00	t	2025-11-25 12:58:17.076812+00
92154599-30da-4540-a45c-7d150ab42442	lab.audit.events	43112	2025-11-25 12:58:22.189535+00	t	2025-11-25 12:58:22.189547+00
6c27277b-496b-49c5-969c-529451bfd852	lab.audit.events	43133	2025-11-25 12:58:22.298202+00	t	2025-11-25 12:58:22.298204+00
550ec771-8c13-49ad-b33c-a37aca6de173	lab.audit.events	43134	2025-11-25 12:59:27.727538+00	t	2025-11-25 12:59:27.72754+00
abd14dda-d0fe-4fbc-b676-2720b5631a4d	lab.audit.events	43136	2025-11-25 13:01:03.171479+00	t	2025-11-25 13:01:03.171483+00
17263d59-7f15-4494-955f-6e2b80228a28	lab.audit.events	43137	2025-11-25 13:13:03.61147+00	t	2025-11-25 13:13:03.611473+00
5d5b6903-3360-42f8-87cd-70f19344b8fa	lab.audit.events	43138	2025-11-25 13:13:08.727398+00	t	2025-11-25 13:13:08.727401+00
4b395b88-59cb-4adf-97d3-583ea6729386	lab.audit.events	43139	2025-11-25 13:13:08.838667+00	t	2025-11-25 13:13:08.838669+00
635db2f2-d5ee-4a2e-91ae-7e917c0f61e0	lab.audit.events	43210	2025-11-25 13:16:24.072869+00	t	2025-11-25 13:16:24.072872+00
029f975c-87f3-473c-b7fc-67b428e6537a	lab.audit.events	43227	2025-11-25 13:21:09.330628+00	t	2025-11-25 13:21:09.33063+00
0880b0cb-b81b-4609-878f-b035806cd023	lab.audit.events	43228	2025-11-25 13:22:04.488367+00	t	2025-11-25 13:22:04.488369+00
d37334ba-f9d3-4f26-9d09-452a52b4bad8	lab.audit.events	43229	2025-11-25 13:29:14.791874+00	t	2025-11-25 13:29:14.791877+00
c2e5e478-ccef-4a9e-a814-a58c70ece41a	lab.audit.events	43230	2025-11-25 13:32:24.992822+00	t	2025-11-25 13:32:24.992825+00
b6c7f65c-cc2e-4922-afdd-b664b08df805	lab.audit.events	43231	2025-11-25 13:33:05.127869+00	t	2025-11-25 13:33:05.127872+00
a5753934-948e-485f-8bb6-9800d522394e	lab.audit.events	43232	2025-11-25 13:41:35.454666+00	t	2025-11-25 13:41:35.454668+00
ed2375fe-9467-493b-8471-f9d07a2c3d82	lab.audit.events	43233	2025-11-25 13:42:20.605455+00	t	2025-11-25 13:42:20.605458+00
ff7b1a20-4764-455a-8378-eff0f2c33865	lab.audit.events	43234	2025-11-25 13:42:56.023402+00	t	2025-11-25 13:42:56.023423+00
72d85bee-13b5-425c-ace5-d1da52fd79af	lab.audit.events	43235	2025-11-25 13:48:46.316373+00	t	2025-11-25 13:48:46.316384+00
ea9d3009-be5c-4cca-a9f8-c921bbd9f67c	lab.audit.events	43236	2025-11-25 13:49:06.448912+00	t	2025-11-25 13:49:06.448913+00
7d20ea5d-aef1-4282-bddb-de780a087ef5	lab.audit.events	43237	2025-11-25 13:54:26.690651+00	t	2025-11-25 13:54:26.690653+00
681b2082-6512-4da7-a691-5045c2d23182	lab.audit.events	43238	2025-11-25 13:56:51.862371+00	t	2025-11-25 13:56:51.862374+00
d137133e-5366-4d80-b99a-6d728e4361fd	lab.audit.events	43239	2025-11-25 13:58:22.0074+00	t	2025-11-25 13:58:22.007402+00
f19dff1f-3b1b-440e-b942-dfb90800123b	lab.audit.events	43240	2025-11-25 14:03:12.245961+00	t	2025-11-25 14:03:12.245963+00
c2458f65-7473-4d6d-b3c8-853cd6e5ea81	lab.audit.events	43241	2025-11-25 14:03:27.36337+00	t	2025-11-25 14:03:27.363372+00
2b113a94-fc61-47aa-99f4-ed785fbff765	lab.audit.events	43242	2025-11-25 14:09:17.606904+00	t	2025-11-25 14:09:17.606906+00
6e5e4f22-0b52-44db-b535-2f6368db5758	lab.audit.events	43243	2025-11-25 14:24:58.38547+00	t	2025-11-25 14:24:58.385472+00
786f9906-b00a-4d12-8d36-9574842f7d1f	lab.audit.events	43244	2025-11-25 14:25:08.502614+00	t	2025-11-25 14:25:08.502616+00
8d188783-1fc4-4eed-8a5e-047701fdf07f	lab.audit.events	43245	2025-11-25 14:26:43.940523+00	t	2025-11-25 14:26:43.940524+00
82fe75a0-3c04-411a-849c-6b945fafc365	lab.audit.events	43246	2025-11-25 14:47:24.544877+00	t	2025-11-25 14:47:24.544879+00
cb87d23d-da4b-4372-9bd1-5e1b6071aa7e	lab.audit.events	43247	2025-11-25 15:31:10.64041+00	t	2025-11-25 15:31:10.640413+00
cac27300-7985-402f-8b5c-f1757ba42250	lab.audit.events	43248	2025-11-25 15:45:11.083304+00	t	2025-11-25 15:45:11.083306+00
27109c64-961e-4b9d-8901-66495830fa81	lab.audit.events	43254	2025-11-25 16:42:37.464894+00	t	2025-11-25 16:42:37.464895+00
307f2158-aef8-4dab-b60f-d01c45adf7c4	lab.audit.events	43255	2025-11-25 18:25:50.100744+00	t	2025-11-25 18:25:50.100747+00
beeee31d-a5e6-4cea-bca5-570b6df58ffa	lab.audit.events	43256	2025-11-25 18:39:50.831367+00	t	2025-11-25 18:39:50.83137+00
5b6e26f0-e2f1-473a-aa83-38ce4ba320d9	lab.audit.events	43257	2025-11-25 19:01:01.689071+00	t	2025-11-25 19:01:01.689072+00
ab55e85d-d6c3-41b7-a2b6-6ae0b4645f95	lab.audit.events	43258	2025-11-25 19:15:02.131524+00	t	2025-11-25 19:15:02.131526+00
bc76bace-6d05-4a32-8708-9c8bc5c3e18d	lab.audit.events	43259	2025-11-25 19:29:07.847955+00	t	2025-11-25 19:29:07.847956+00
b8ee9ce5-0d80-4cd1-8c0b-a994088158f4	lab.audit.events	43260	2025-11-25 19:43:13.68157+00	t	2025-11-25 19:43:13.681572+00
e61d5ee7-6665-4a13-af6b-c91325ec5582	lab.audit.events	43261	2025-11-25 19:57:19.123512+00	t	2025-11-25 19:57:19.123514+00
4f651a8f-b63d-4411-8709-e1ef79f2bf7a	lab.audit.events	43262	2025-11-25 20:11:24.857284+00	t	2025-11-25 20:11:24.857285+00
d1e705cc-a309-47af-83a3-78b642f85d04	lab.audit.events	43263	2025-11-25 20:25:25.575766+00	t	2025-11-25 20:25:25.575768+00
5ed93fab-a67c-490b-80c8-e60bc730f9d1	lab.audit.events	43264	2025-11-25 20:31:40.853038+00	t	2025-11-25 20:31:40.85304+00
a3b424b0-a774-4524-8675-8170ff8a073e	lab.audit.events	43265	2025-11-25 20:31:40.967712+00	t	2025-11-25 20:31:40.967714+00
788e106f-322b-41d2-bd4c-7dbb46eb5da0	lab.audit.events	43266	2025-11-25 20:31:46.088547+00	t	2025-11-25 20:31:46.088549+00
9cfd1168-3fbe-46c5-af80-6a0e76fcc16c	lab.audit.events	43267	2025-11-25 20:31:46.196343+00	t	2025-11-25 20:31:46.196345+00
8a749aae-342c-4710-ae5f-3e0bafb0c741	lab.audit.events	43268	2025-11-25 20:31:46.307375+00	t	2025-11-25 20:31:46.307376+00
ee8fe5c4-3a1d-407c-9e9e-61b3413d94fa	lab.audit.events	43290	2025-11-25 20:31:46.412964+00	t	2025-11-25 20:31:46.412965+00
607acf3d-995e-4647-b775-925cbb088b70	lab.audit.events	43291	2025-11-25 20:31:46.519059+00	t	2025-11-25 20:31:46.51906+00
b6bd0ba7-64f4-485e-8af4-cd8daf54410a	lab.audit.events	43292	2025-11-25 20:31:46.625337+00	t	2025-11-25 20:31:46.625339+00
bf8d714c-b172-48e4-98b9-ac3f415befeb	lab.audit.events	43293	2025-11-25 20:31:46.734311+00	t	2025-11-25 20:31:46.734313+00
9468476d-7f03-48e7-a345-1a9a178add9b	lab.audit.events	43294	2025-11-25 20:31:46.843203+00	t	2025-11-25 20:31:46.843204+00
0b0536ff-78be-453e-99df-8d52f1aa3600	lab.audit.events	43295	2025-11-25 20:31:46.95114+00	t	2025-11-25 20:31:46.951142+00
56c35044-383b-4807-aedc-fbe9291154b8	lab.audit.events	43296	2025-11-25 20:31:47.05582+00	t	2025-11-25 20:31:47.055822+00
9ebee2d5-7e68-4924-8abb-93fd9b45dc75	lab.audit.events	43297	2025-11-25 20:31:47.176528+00	t	2025-11-25 20:31:47.17653+00
1a6de7fe-c597-4f76-bfff-c0f017faccff	lab.audit.events	43298	2025-11-25 20:31:47.286353+00	t	2025-11-25 20:31:47.286355+00
775730dc-6138-45ca-be35-bc3df6493ae9	lab.audit.events	43299	2025-11-25 20:31:47.39255+00	t	2025-11-25 20:31:47.392551+00
728f4b92-0b14-4cb6-b969-6b0a2f73023a	lab.audit.events	43302	2025-11-25 20:31:47.499458+00	t	2025-11-25 20:31:47.499459+00
e4c3e406-bc5d-4a58-8669-ca9c09abf53c	lab.audit.events	43323	2025-11-26 00:01:57.477383+00	t	2025-11-26 00:01:57.477386+00
f20eb264-e2c6-4ada-a0a5-b766e5044b44	lab.audit.events	43324	2025-11-26 00:02:07.600552+00	t	2025-11-26 00:02:07.600554+00
047b2a2e-55a8-4338-95b3-fc362b32b3d9	lab.audit.events	43325	2025-11-26 00:02:22.718553+00	t	2025-11-26 00:02:22.718555+00
f7d7b766-9406-44dd-bdc9-b9109461a3a1	lab.audit.events	43349	2025-11-26 00:02:27.839902+00	t	2025-11-26 00:02:27.839905+00
b18b09fc-6109-44b2-9724-172d772358ca	lab.audit.events	43419	2025-11-26 00:02:32.958494+00	t	2025-11-26 00:02:32.9585+00
0ed84f2b-1181-49a3-b03a-7d73b2e9087f	lab.audit.events	43445	2025-11-26 00:02:33.069884+00	t	2025-11-26 00:02:33.069886+00
963b8c5c-ab61-4e8a-aa29-9a59006f3d00	lab.audit.events	43495	2025-11-26 00:02:33.176551+00	t	2025-11-26 00:02:33.176552+00
6a631268-6e6d-4cf2-a89b-368fe7df3ec1	lab.audit.events	43551	2025-11-26 00:02:38.287026+00	t	2025-11-26 00:02:38.287028+00
b03f5903-9b2b-421d-975f-577072ddeb03	lab.audit.events	43586	2025-11-26 00:02:48.404572+00	t	2025-11-26 00:02:48.404575+00
6e63798c-5601-4939-acb4-5ef9f0e618a0	lab.audit.events	43587	2025-11-26 00:07:28.910678+00	t	2025-11-26 00:07:28.91068+00
b21aeffe-0af1-43e7-bb9a-1b0e24bc63cd	lab.audit.events	43588	2025-11-26 00:16:14.504977+00	t	2025-11-26 00:16:14.504979+00
0357e447-425c-4411-a7d5-16b3357d7fea	lab.audit.events	43589	2025-11-26 00:18:24.702379+00	t	2025-11-26 00:18:24.702381+00
f740d988-0600-42dd-a190-bec11ae3ed7b	lab.audit.events	43642	2025-11-26 01:33:01.416124+00	t	2025-11-26 01:33:01.416126+00
1a08626a-493b-47df-8e81-2eafdf4d9ac8	lab.audit.events	43668	2025-11-26 01:33:26.552006+00	t	2025-11-26 01:33:26.552008+00
823fe1e4-e1e3-45b2-bf33-1df7f351a77d	lab.audit.events	43669	2025-11-26 01:33:31.665361+00	t	2025-11-26 01:33:31.66537+00
b8c62757-75a7-4760-830f-673296afb677	lab.audit.events	43681	2025-11-26 01:33:56.797535+00	t	2025-11-26 01:33:56.797537+00
ce9f4a0b-99a3-4c6f-94a8-298a10afb70c	lab.audit.events	43684	2025-11-26 01:37:46.998074+00	t	2025-11-26 01:37:46.998075+00
46359e72-ba23-45f7-9826-207ff7bce481	lab.audit.events	43714	2025-11-26 01:39:07.147084+00	t	2025-11-26 01:39:07.147086+00
c426d9ce-3146-405d-b78f-cd4e1f76494c	lab.audit.events	43715	2025-11-26 01:47:27.714863+00	t	2025-11-26 01:47:27.714865+00
a760ffeb-52f2-40b3-9a83-816ed3acf294	lab.audit.events	43716	2025-11-26 01:49:52.896023+00	t	2025-11-26 01:49:52.896026+00
428543ef-707c-4117-b7c1-2d7954f9ee95	lab.audit.events	43717	2025-11-26 01:50:18.021852+00	t	2025-11-26 01:50:18.021854+00
851bf64a-660b-4359-b977-bdef431e45ed	lab.audit.events	43718	2025-11-26 01:50:18.132088+00	t	2025-11-26 01:50:18.132089+00
dd5069aa-9c09-4a7c-a4be-ef44eeb935fb	lab.audit.events	43719	2025-11-26 01:50:33.248125+00	t	2025-11-26 01:50:33.248127+00
8666689e-f08f-4bc1-bbc7-5c666554fcbd	lab.audit.events	43720	2025-11-26 01:52:08.679269+00	t	2025-11-26 01:52:08.67927+00
1678071e-b4d6-4959-996d-ef000beeea84	lab.audit.events	43721	2025-11-26 01:54:38.862524+00	t	2025-11-26 01:54:38.862526+00
40ea9777-268f-44c4-8586-96301f972f21	lab.audit.events	43722	2025-11-26 01:56:24.018221+00	t	2025-11-26 01:56:24.018222+00
01ea7219-a6b1-4b75-b140-4ba0192410a7	lab.audit.events	43723	2025-11-26 01:56:29.135882+00	t	2025-11-26 01:56:29.135883+00
1b1e9011-b639-46b6-916a-7705bf542b57	lab.audit.events	43724	2025-11-26 02:05:04.732176+00	t	2025-11-26 02:05:04.732179+00
4d348b65-3ebf-4d5f-8dc8-dcedbca8b43e	lab.audit.events	43725	2025-11-26 02:10:30.021618+00	t	2025-11-26 02:10:30.02162+00
9c1734bc-8486-4238-b8d4-1522fda661c5	lab.audit.events	43726	2025-11-26 02:24:35.728905+00	t	2025-11-26 02:24:35.728906+00
cd55d2af-707c-4bcd-a9f7-c5570077dee1	lab.audit.events	43728	2025-11-26 02:24:45.848177+00	t	2025-11-26 02:24:45.848179+00
727a9a54-2663-4098-8412-9329a408e26b	lab.audit.events	43729	2025-11-26 02:28:51.057309+00	t	2025-11-26 02:28:51.057332+00
62ceb143-c8fa-472d-b3d9-ec8ec21a06c6	lab.audit.events	43730	2025-11-26 02:29:51.19235+00	t	2025-11-26 02:29:51.192352+00
06677c72-a03d-459f-981c-c2b35f80f650	lab.audit.events	43731	2025-11-26 02:36:06.704555+00	t	2025-11-26 02:36:06.704557+00
25027266-7ec1-4055-b239-6fbf7e739e90	lab.audit.events	43736	2025-11-26 02:36:06.818564+00	t	2025-11-26 02:36:06.818565+00
a8a63779-5679-463c-9ab9-6f4cbbb60697	lab.audit.events	43778	2025-11-26 02:36:06.929349+00	t	2025-11-26 02:36:06.92935+00
fec02d36-9606-4434-852c-498fca0d41d2	lab.audit.events	43798	2025-11-26 02:36:07.041358+00	t	2025-11-26 02:36:07.04136+00
5d02b131-1161-4d51-8675-60b5754dd90f	lab.audit.events	43799	2025-11-26 02:36:07.147569+00	t	2025-11-26 02:36:07.14757+00
9638a715-904a-4913-b938-4ffd265c31d6	lab.audit.events	43807	2025-11-26 02:36:07.255507+00	t	2025-11-26 02:36:07.255508+00
b4f90818-f4db-480d-85e6-a1a3e49b2da8	lab.audit.events	43822	2025-11-26 02:36:07.368431+00	t	2025-11-26 02:36:07.368433+00
3523f6b7-e2f1-4f45-8073-33ac6b7485ea	lab.audit.events	43865	2025-11-26 02:36:07.48225+00	t	2025-11-26 02:36:07.482253+00
7efbf94b-b0fe-4a12-8ec9-cb44b27b623e	lab.audit.events	43879	2025-11-26 02:36:07.594084+00	t	2025-11-26 02:36:07.594086+00
a5b8c366-0008-4007-8cae-81c033303c02	lab.audit.events	43922	2025-11-26 02:36:12.710646+00	t	2025-11-26 02:36:12.710648+00
ad62a62d-a91f-4135-bc16-3f186cb22fa0	lab.audit.events	44044	2025-11-26 02:36:12.820361+00	t	2025-11-26 02:36:12.820363+00
1a107098-b35c-46ff-9b08-c4e7e8f8ccc0	lab.audit.events	44085	2025-11-26 02:36:12.924966+00	t	2025-11-26 02:36:12.924967+00
5988bb7b-0014-43d2-9cf4-14c68b740e15	lab.audit.events	44125	2025-11-26 02:36:43.043403+00	t	2025-11-26 02:36:43.043404+00
0e7be3a6-43ae-459a-9bc5-91fc8264d8f5	lab.audit.events	44163	2025-11-26 02:36:48.156341+00	t	2025-11-26 02:36:48.156342+00
8205b01b-4e93-4d67-a4c2-9cf7ee08cfee	lab.audit.events	44181	2025-11-26 02:36:48.269334+00	t	2025-11-26 02:36:48.269337+00
39eff8db-73ce-42a7-9546-13b402436c6e	lab.audit.events	44182	2025-11-26 02:36:48.380593+00	t	2025-11-26 02:36:48.380595+00
d512b8c0-5684-4f39-b520-1f8994a52f8a	lab.audit.events	44207	2025-11-26 02:36:48.487685+00	t	2025-11-26 02:36:48.487687+00
6e9bc7e4-6041-4a67-9dbb-05a39aa176ff	lab.audit.events	44233	2025-11-26 02:36:53.604004+00	t	2025-11-26 02:36:53.604006+00
49f55d70-358f-421a-bf72-c47490b9d40d	lab.audit.events	44234	2025-11-26 02:36:53.711867+00	t	2025-11-26 02:36:53.711869+00
33e1e0f7-6c5c-420e-a7a5-1923c61fbab2	lab.audit.events	44252	2025-11-26 02:36:53.821397+00	t	2025-11-26 02:36:53.821398+00
bbc69b1e-766d-40a5-80fa-26e556009f6f	lab.audit.events	44297	2025-11-26 02:36:53.925892+00	t	2025-11-26 02:36:53.925894+00
65209782-5f6d-4b21-9e32-9ca3569d06bc	lab.audit.events	44330	2025-11-26 02:36:54.034356+00	t	2025-11-26 02:36:54.034357+00
0a4def1e-8750-4e48-a371-67625bd81196	lab.audit.events	44331	2025-11-26 02:36:54.140916+00	t	2025-11-26 02:36:54.140917+00
380ced79-66fb-4570-9479-f63872673000	lab.audit.events	44336	2025-11-26 02:36:54.250893+00	t	2025-11-26 02:36:54.250895+00
093c036a-b017-4309-ab43-8896c93e5610	lab.audit.events	44337	2025-11-26 02:36:54.363401+00	t	2025-11-26 02:36:54.363403+00
6da90014-9010-4a58-bdcd-c5cfd55a0510	lab.audit.events	44348	2025-11-26 02:36:59.47948+00	t	2025-11-26 02:36:59.479481+00
b1199cc1-5fba-4d0d-970d-5aaec951c464	lab.audit.events	44350	2025-11-26 02:37:29.60452+00	t	2025-11-26 02:37:29.604522+00
e76d9c5c-0bbf-4094-9098-8e449fb4e88c	lab.audit.events	44351	2025-11-26 02:37:54.735248+00	t	2025-11-26 02:37:54.73525+00
1fd32ec9-20cc-4df9-8a91-ef02a230b3ad	lab.audit.events	44352	2025-11-26 02:37:59.846634+00	t	2025-11-26 02:37:59.846636+00
399148b3-ae13-4a98-9992-d35110cbd9cf	lab.audit.events	44353	2025-11-26 02:38:04.962303+00	t	2025-11-26 02:38:04.962305+00
f542195e-ca71-4cec-bf4f-4ca403b73b10	lab.audit.events	44354	2025-11-26 02:38:05.072921+00	t	2025-11-26 02:38:05.072923+00
32d2bcf8-f3d7-4940-b595-b9d3c6e27f93	lab.audit.events	44355	2025-11-26 02:38:05.18194+00	t	2025-11-26 02:38:05.181941+00
a50b7165-9b26-436a-9180-1e74d3c89f48	lab.audit.events	44356	2025-11-26 02:38:10.298851+00	t	2025-11-26 02:38:10.298852+00
a48d73b1-3f0c-4ceb-b1a6-c6683e225606	lab.audit.events	44357	2025-11-26 02:39:00.435354+00	t	2025-11-26 02:39:00.435356+00
cb5d146f-7be0-4352-93e1-26adac175286	lab.audit.events	44358	2025-11-26 02:44:50.679712+00	t	2025-11-26 02:44:50.679713+00
9c1529d0-c034-43e6-b816-e6bb1d44da80	lab.audit.events	44359	2025-11-26 02:44:55.791631+00	t	2025-11-26 02:44:55.791633+00
7e1fcd19-6610-410f-b65d-f5148cd3d0f8	lab.audit.events	44360	2025-11-26 02:44:55.89757+00	t	2025-11-26 02:44:55.897571+00
78f9f5ec-9821-44a9-83eb-8f5ad561a0c0	lab.audit.events	44361	2025-11-26 02:44:56.007145+00	t	2025-11-26 02:44:56.007147+00
de0a7219-00be-4c2a-9f6e-cf6a34021021	lab.audit.events	44362	2025-11-26 02:45:06.119968+00	t	2025-11-26 02:45:06.119973+00
497cf4d4-d0e8-4e2a-8d53-0724f06c00fe	lab.audit.events	44363	2025-11-26 02:45:06.227675+00	t	2025-11-26 02:45:06.227677+00
d65e9e08-fdd6-4140-b7f5-2efd7669bb8a	lab.audit.events	44364	2025-11-26 02:45:11.337399+00	t	2025-11-26 02:45:11.337401+00
5dbd95aa-761c-4695-91e4-c1add5fadbef	lab.audit.events	44365	2025-11-26 02:45:11.444817+00	t	2025-11-26 02:45:11.444818+00
ac37cca6-548d-47b1-8bbd-1cff03f0fd46	lab.audit.events	44366	2025-11-26 02:54:17.039038+00	t	2025-11-26 02:54:17.03904+00
7f2011b3-e903-4122-aea3-6fac4a1bb5d7	lab.audit.events	44367	2025-11-26 02:54:27.15943+00	t	2025-11-26 02:54:27.159439+00
e38230a1-f1b8-4ba2-ba36-4e44acc482f3	lab.audit.events	44368	2025-11-26 02:54:37.271737+00	t	2025-11-26 02:54:37.27174+00
e0bf0642-478d-4578-9d35-5464565042d7	lab.audit.events	44369	2025-11-26 02:55:42.689884+00	t	2025-11-26 02:55:42.689885+00
1ef1f3c8-a6b3-43fe-8671-3fb95da72fc1	lab.audit.events	44370	2025-11-26 02:56:02.811872+00	t	2025-11-26 02:56:02.811874+00
2a4a9680-1f24-4562-8201-cf0cde03e1a3	lab.audit.events	44371	2025-11-26 02:56:07.935952+00	t	2025-11-26 02:56:07.935954+00
4e515675-f1d1-408d-8f4e-9cfbe0da4d6a	lab.audit.events	44372	2025-11-26 02:56:13.055951+00	t	2025-11-26 02:56:13.055953+00
c55f6930-bb67-4c30-92a9-c8ce801e04e8	lab.audit.events	44373	2025-11-26 02:56:18.189515+00	t	2025-11-26 02:56:18.189516+00
f7bd4a0b-4b2b-49a4-b33c-03001e300d6c	lab.audit.events	44374	2025-11-26 02:56:23.300417+00	t	2025-11-26 02:56:23.300419+00
dbd1b4fe-78fb-4338-8926-e42e1363a533	lab.audit.events	44375	2025-11-26 02:57:48.442036+00	t	2025-11-26 02:57:48.442037+00
aa0194d0-8633-45ab-8840-c72fc4acb98d	lab.audit.events	44376	2025-11-26 03:07:43.810033+00	t	2025-11-26 03:07:43.810035+00
3e8417ce-78bf-4798-ab04-2ca4182fffa6	lab.audit.events	44377	2025-11-26 03:12:44.102235+00	t	2025-11-26 03:12:44.102237+00
bdab6cbc-2c3a-49a7-bd50-817398684290	lab.audit.events	44378	2025-11-26 03:18:49.634529+00	t	2025-11-26 03:18:49.634531+00
3ab045da-316a-4c27-8470-df430a895cea	lab.audit.events	44379	2025-11-26 03:21:44.853318+00	t	2025-11-26 03:21:44.853319+00
f4a756ad-1925-4d55-a008-a55af065e3b2	lab.audit.events	44383	2025-11-26 03:26:45.105252+00	t	2025-11-26 03:26:45.105254+00
4b768145-23b6-4fa1-9c47-879838a00920	lab.audit.events	44384	2025-11-26 03:29:45.309941+00	t	2025-11-26 03:29:45.309943+00
7d3a9325-128b-4ecc-aa05-7ed3be8941a6	lab.audit.events	44385	2025-11-26 03:37:35.673413+00	t	2025-11-26 03:37:35.673422+00
3c84cbbf-bf92-404b-9a98-76963d48c85a	lab.audit.events	44386	2025-11-26 03:46:46.05006+00	t	2025-11-26 03:46:46.050063+00
d8883985-f41f-4fb5-8998-504a87164150	lab.audit.events	44387	2025-11-26 04:01:41.587832+00	t	2025-11-26 04:01:41.587834+00
e008feb0-6f28-4421-bbb4-c9b4f7b94dfd	lab.audit.events	44388	2025-11-26 04:02:47.044947+00	t	2025-11-26 04:02:47.044949+00
1bbfe4dd-b523-44bb-a596-f52655d71a17	lab.audit.events	44389	2025-11-26 04:02:57.177532+00	t	2025-11-26 04:02:57.177534+00
8bf47a1e-1852-43c6-9507-7677fc82830d	lab.audit.events	44390	2025-11-26 04:03:27.325586+00	t	2025-11-26 04:03:27.325588+00
a474f2b0-03ea-4605-92e0-3b3b27d411b8	lab.audit.events	44391	2025-11-26 04:04:22.490024+00	t	2025-11-26 04:04:22.490025+00
2eee19e7-0fe8-41de-89e1-e65de49f32d0	lab.audit.events	44392	2025-11-26 04:04:57.916633+00	t	2025-11-26 04:04:57.916635+00
d87d58f8-46b0-4fa3-81e7-bbb95c1332e7	lab.audit.events	44393	2025-11-26 04:04:58.052372+00	t	2025-11-26 04:04:58.052373+00
6896f739-b867-44a9-baf8-95c9c52361e7	lab.audit.events	44394	2025-11-26 04:04:58.176858+00	t	2025-11-26 04:04:58.17686+00
560c43bc-c3ad-4a57-a5fb-74f6bef30d1f	lab.audit.events	44395	2025-11-26 04:16:58.597396+00	t	2025-11-26 04:16:58.597398+00
8d9fca7a-5832-4ab6-b7b6-2e3fa2581a18	lab.audit.events	44397	2025-11-26 04:20:13.814421+00	t	2025-11-26 04:20:13.814423+00
29027f5a-26eb-4b62-a387-339c8e9ee26a	lab.audit.events	44398	2025-11-26 04:20:33.954471+00	t	2025-11-26 04:20:33.954473+00
c592638f-bfc4-4480-97d3-78bb41988e6b	lab.audit.events	44399	2025-11-26 04:21:59.131395+00	t	2025-11-26 04:21:59.131398+00
61606611-5704-462a-af30-121bf02dfc5f	lab.audit.events	44400	2025-11-26 04:21:59.264959+00	t	2025-11-26 04:21:59.264961+00
74ea47bb-97e2-47ae-ac4e-077fa243f7d2	lab.audit.events	44401	2025-11-26 04:22:09.398453+00	t	2025-11-26 04:22:09.398456+00
513ae311-dda8-4d49-9483-fe55d6fe0ce1	lab.audit.events	44402	2025-11-26 04:31:29.737553+00	t	2025-11-26 04:31:29.737554+00
1f54c717-94d1-407d-a992-0ed94a0f45b5	lab.audit.events	44403	2025-11-26 04:37:20.012685+00	t	2025-11-26 04:37:20.012687+00
58be8593-c15f-4879-aeef-c0b8492cbc61	lab.audit.events	44404	2025-11-26 04:37:20.144348+00	t	2025-11-26 04:37:20.144349+00
5fade34a-be46-430d-92c6-014eafd35eaa	lab.audit.events	44405	2025-11-26 04:37:30.271975+00	t	2025-11-26 04:37:30.271977+00
3320cc3c-7a2e-4bf9-aec2-9c945f02c6b9	lab.audit.events	44406	2025-11-26 04:41:40.506958+00	t	2025-11-26 04:41:40.50696+00
0a43a866-5275-4bba-8ebb-0dfa980013b2	lab.audit.events	44407	2025-11-26 04:41:45.639134+00	t	2025-11-26 04:41:45.639137+00
d23b275c-507c-4e85-8bed-b37f35853b61	lab.audit.events	44408	2025-11-26 04:41:55.767025+00	t	2025-11-26 04:41:55.767027+00
ad84da63-84c3-49bf-9dd1-1911ac35883c	lab.audit.events	44409	2025-11-26 04:42:00.898817+00	t	2025-11-26 04:42:00.898828+00
66f0cd27-4ba2-4a16-8031-f795ba823ba7	lab.audit.events	44410	2025-11-26 04:42:01.028679+00	t	2025-11-26 04:42:01.028681+00
65d76450-8792-46b4-ba9a-53b18fe91fba	lab.notify.queue	44411	2025-11-26 04:44:01.235998+00	t	2025-11-26 04:44:01.235999+00
7e8f7eaa-2925-4368-b996-45470f7e6aca	lab.audit.events	44412	2025-11-26 04:44:01.36877+00	t	2025-11-26 04:44:01.368772+00
86b61f62-0129-48a5-933f-96edf7ace5d2	lab.audit.events	44413	2025-11-26 04:44:01.495469+00	t	2025-11-26 04:44:01.495471+00
acc40518-b06f-4d34-890f-6a5f5fa908f0	lab.audit.events	44414	2025-11-26 04:44:01.628542+00	t	2025-11-26 04:44:01.628544+00
7a7b5d8f-baf7-4909-98c0-ba0814ea9f79	lab.audit.events	44415	2025-11-26 05:20:07.821802+00	t	2025-11-26 05:20:07.821804+00
a798031d-8a2e-4a58-bb3f-730fea99426c	lab.audit.events	44416	2025-11-26 05:20:07.950886+00	t	2025-11-26 05:20:07.950888+00
aacbd488-d5e6-4a50-86f1-cc84fa655748	lab.audit.events	44417	2025-11-26 05:20:13.077147+00	t	2025-11-26 05:20:13.077149+00
7c9769be-d54d-4a54-8139-4a972687d6db	lab.audit.events	44418	2025-11-26 05:29:18.71598+00	t	2025-11-26 05:29:18.715982+00
cd05f79f-f6b9-4149-bc2e-ef79561d9bf8	lab.audit.events	44419	2025-11-26 05:32:13.946882+00	t	2025-11-26 05:32:13.946884+00
d82a875a-726a-4dc7-8977-2fd06c6659a7	lab.audit.events	44420	2025-11-26 05:35:39.175893+00	t	2025-11-26 05:35:39.175895+00
ee26065d-f812-4c4c-ac49-7846c981b482	lab.audit.events	44421	2025-11-26 05:35:59.319168+00	t	2025-11-26 05:35:59.31917+00
4f195731-043e-4387-9c28-1d370244cf76	lab.audit.events	44422	2025-11-26 05:37:54.511032+00	t	2025-11-26 05:37:54.511034+00
41e41676-8b10-48cc-b3a7-a19e0d4b3ec8	lab.audit.events	44423	2025-11-26 05:39:24.673858+00	t	2025-11-26 05:39:24.673865+00
884f8891-3dc7-41b2-9704-8112b2bc0781	lab.audit.events	44424	2025-11-26 05:44:19.936392+00	t	2025-11-26 05:44:19.936397+00
9711dc5b-bf0f-4133-802e-e6e9bd5bb290	lab.audit.events	44425	2025-11-26 05:46:10.124956+00	t	2025-11-26 05:46:10.124958+00
2f3a9b70-bf60-4d44-9a2c-113c9af01059	lab.audit.events	44426	2025-11-26 05:46:25.279358+00	t	2025-11-26 05:46:25.27936+00
ca465774-5ed3-481c-bd86-a0351a8ccf21	lab.audit.events	44427	2025-11-26 05:50:05.507448+00	t	2025-11-26 05:50:05.507449+00
51b17ace-5b84-4862-8fa7-f6654d6ca446	lab.audit.events	44428	2025-11-26 05:51:55.708451+00	t	2025-11-26 05:51:55.708453+00
62a33203-f7f1-4d84-b69a-0fbd15afe107	lab.audit.events	44429	2025-11-26 05:55:31.204237+00	t	2025-11-26 05:55:31.204238+00
964cbe7d-231c-4ef8-8822-8ab420b70082	lab.audit.events	44435	2025-11-26 06:12:21.715323+00	t	2025-11-26 06:12:21.715325+00
7d44fbfd-fefc-47b6-a61b-9b3145a2452c	lab.audit.events	44436	2025-11-26 06:12:21.852666+00	t	2025-11-26 06:12:21.852668+00
5da16f9e-7ebb-48a7-a135-2f97b94dfb81	lab.audit.events	44437	2025-11-26 06:12:26.981174+00	t	2025-11-26 06:12:26.981175+00
6a81bb76-b168-4c6d-8b82-09ffdf90dd2e	lab.audit.events	44438	2025-11-26 06:12:42.113945+00	t	2025-11-26 06:12:42.113946+00
3d233d31-330d-4304-9d1f-9e3db6d1f421	lab.audit.events	44439	2025-11-26 06:13:02.255713+00	t	2025-11-26 06:13:02.255714+00
f4c6ef25-67d4-4032-bf2b-9838fc2e45e7	lab.audit.events	44440	2025-11-26 06:13:07.383978+00	t	2025-11-26 06:13:07.383979+00
0a741aa6-75cd-4c74-aebd-04f6f1a5cb29	lab.audit.events	44441	2025-11-26 06:13:52.528323+00	t	2025-11-26 06:13:52.528324+00
9aede42f-b4f4-417f-8bf9-5aa92b027a54	lab.audit.events	44442	2025-11-26 06:13:57.662566+00	t	2025-11-26 06:13:57.662567+00
6eb2727b-479d-489f-89be-9e47699b73e6	lab.audit.events	44443	2025-11-26 06:14:02.794966+00	t	2025-11-26 06:14:02.794968+00
04cc3ef8-39ba-47d6-a24f-7dc5cba867d8	lab.notify.queue	44444	2025-11-26 06:17:03.009348+00	t	2025-11-26 06:17:03.009349+00
0b496284-a190-4ce3-bee4-2049c1596464	lab.audit.events	44445	2025-11-26 06:17:03.135542+00	t	2025-11-26 06:17:03.135544+00
af59cd50-4fa0-4142-a46b-8a4b1b540b68	lab.audit.events	44446	2025-11-26 06:17:03.262876+00	t	2025-11-26 06:17:03.262878+00
43e5346c-059d-429f-9696-66d351ee1876	lab.audit.events	44447	2025-11-26 06:17:08.39137+00	t	2025-11-26 06:17:08.391372+00
c1c3f4bc-6e6e-45be-8aa8-d4d0c1c13b76	lab.audit.events	44448	2025-11-26 06:17:28.529549+00	t	2025-11-26 06:17:28.529551+00
801391d2-3553-4a9f-b3d3-00edccb0989d	lab.audit.events	44449	2025-11-26 06:17:28.66553+00	t	2025-11-26 06:17:28.665531+00
22f0acee-44fe-4e57-9bfa-0eceb36aa7cc	lab.audit.events	44450	2025-11-26 06:17:33.81657+00	t	2025-11-26 06:17:33.816572+00
43e39cde-05fc-4e2a-9544-f88dc8b8484d	lab.audit.events	44451	2025-11-26 06:17:33.946858+00	t	2025-11-26 06:17:33.94686+00
22e0c259-4bdc-4425-9d8e-a695fee59c33	lab.audit.events	44452	2025-11-26 06:18:04.096521+00	t	2025-11-26 06:18:04.096522+00
8bf45964-1b28-4977-8248-23111f6a1a6e	lab.audit.events	44453	2025-11-26 06:18:04.228068+00	t	2025-11-26 06:18:04.228069+00
597510a6-2b0a-4236-8e4f-f7a94ee8ab15	lab.audit.events	44454	2025-11-26 06:18:04.358969+00	t	2025-11-26 06:18:04.35897+00
fafa2193-99d2-4ebc-97d9-eee1dbfb3188	lab.audit.events	44455	2025-11-26 06:18:04.48898+00	t	2025-11-26 06:18:04.488981+00
b19af1cd-9290-4929-8366-98e34ea060c2	lab.audit.events	44456	2025-11-26 06:18:49.631907+00	t	2025-11-26 06:18:49.631909+00
983fbea8-50b4-4c24-9665-e6faa8310998	lab.audit.events	44457	2025-11-26 06:18:49.763906+00	t	2025-11-26 06:18:49.763907+00
aee4f8c0-fb33-4a54-b96b-b2c9480f2e7c	lab.audit.events	44458	2025-11-26 06:18:49.89184+00	t	2025-11-26 06:18:49.891841+00
b36faeaf-ed92-4012-b104-5217cf7c05a9	lab.audit.events	44460	2025-11-26 06:19:05.034252+00	t	2025-11-26 06:19:05.034253+00
7a9b05df-12ae-4256-9eba-ddcac58bb030	lab.audit.events	44461	2025-11-26 06:19:05.173386+00	t	2025-11-26 06:19:05.173388+00
ce55b7cc-a5a4-4c76-96e0-447804a316e3	lab.audit.events	44462	2025-11-26 06:19:05.314628+00	t	2025-11-26 06:19:05.31463+00
3caf8d45-df06-45a7-875e-e242406c6f1f	lab.audit.events	44463	2025-11-26 06:20:40.777014+00	t	2025-11-26 06:20:40.777015+00
134a85f0-c30d-4a90-bae7-bfbb29cd91b4	lab.audit.events	44464	2025-11-26 06:20:55.911061+00	t	2025-11-26 06:20:55.911063+00
68ea5289-c560-4632-8395-b8464e56ee68	lab.audit.events	44465	2025-11-26 06:21:11.050229+00	t	2025-11-26 06:21:11.05023+00
7a6da880-faaf-4a29-a544-34c41c85331e	lab.audit.events	44466	2025-11-26 06:21:16.178704+00	t	2025-11-26 06:21:16.178705+00
8246925b-367a-46bf-9ff9-ea8d49ee96b1	lab.audit.events	44467	2025-11-26 06:21:16.303339+00	t	2025-11-26 06:21:16.30334+00
1c56f630-b1fb-429f-a190-79b0c5b46066	lab.audit.events	44468	2025-11-26 06:21:51.73556+00	t	2025-11-26 06:21:51.735561+00
8f1ad76f-d62e-4bc0-9844-eba24534cd49	lab.audit.events	44469	2025-11-26 06:21:51.860673+00	t	2025-11-26 06:21:51.860674+00
af64d763-e302-42cd-91bf-4ba389b3e6e5	lab.audit.events	44470	2025-11-26 06:21:51.996951+00	t	2025-11-26 06:21:51.996953+00
9812630d-ce63-4ec9-a864-9c39dbfeec67	lab.audit.events	44471	2025-11-26 06:21:57.126493+00	t	2025-11-26 06:21:57.126495+00
6f72d3b3-5a6a-4997-a085-be33b0d2b00f	lab.audit.events	44472	2025-11-26 06:22:02.25442+00	t	2025-11-26 06:22:02.254423+00
021af559-a0bc-46f4-85bc-88510d8252e3	lab.audit.events	44473	2025-11-26 06:22:37.685924+00	t	2025-11-26 06:22:37.685926+00
cafe9c09-c688-4151-bba5-fc23170e5fb8	lab.audit.events	44474	2025-11-26 06:23:07.840356+00	t	2025-11-26 06:23:07.840358+00
d58d51ca-c39e-4403-acaa-889f1377951a	lab.audit.events	44475	2025-11-26 06:23:07.967121+00	t	2025-11-26 06:23:07.967123+00
8314a240-4a84-4d68-8dad-4e1064b439cf	lab.audit.events	44476	2025-11-26 06:23:33.154177+00	t	2025-11-26 06:23:33.154178+00
32e122cd-127d-4376-b5df-662041f57117	lab.audit.events	44477	2025-11-26 06:23:53.302083+00	t	2025-11-26 06:23:53.302085+00
49fd17ee-41ce-40ce-a194-03aa5b4af60e	lab.audit.events	44478	2025-11-26 06:23:53.433992+00	t	2025-11-26 06:23:53.433993+00
1e764def-6d12-45ee-8036-9ea306f016d0	lab.audit.events	44479	2025-11-26 06:24:03.569502+00	t	2025-11-26 06:24:03.569503+00
74b43b8f-dcca-4b52-a83c-4b0941c0072d	lab.audit.events	44480	2025-11-26 06:24:53.726414+00	t	2025-11-26 06:24:53.726416+00
ed372dea-653d-4e5e-9f6b-e7e70579a1e0	lab.audit.events	44481	2025-11-26 06:38:54.175879+00	t	2025-11-26 06:38:54.175881+00
92cb6f90-8aa3-4d45-a037-cbc610e0f30e	lab.audit.events	44482	2025-11-26 06:53:29.676465+00	t	2025-11-26 06:53:29.676467+00
d2273667-091c-47a7-8104-3b7dc8fcff32	lab.audit.events	44483	2025-11-26 06:59:19.971362+00	t	2025-11-26 06:59:19.971364+00
7800fac9-617f-40f0-8894-b206654e0169	lab.audit.events	44484	2025-11-26 07:00:25.423878+00	t	2025-11-26 07:00:25.42388+00
e8f5b6a3-a7e5-472b-b9c8-3ed6d54b7e06	lab.audit.events	44485	2025-11-26 07:01:30.873718+00	t	2025-11-26 07:01:30.873719+00
c77ebe19-7133-44b1-b8eb-775a1dcd0768	lab.audit.events	44486	2025-11-26 07:01:41.005915+00	t	2025-11-26 07:01:41.005918+00
40aa7f1e-695d-416b-9967-e0d903a123fe	lab.audit.events	44487	2025-11-26 07:03:36.197731+00	t	2025-11-26 07:03:36.197732+00
6f452c2f-c797-4780-a233-7dbfea61c17c	lab.audit.events	44488	2025-11-26 07:03:36.351332+00	t	2025-11-26 07:03:36.351338+00
4ff3254e-c387-446b-85d1-6408df2dc96e	lab.audit.events	44489	2025-11-26 07:03:56.50309+00	t	2025-11-26 07:03:56.503092+00
c803e680-9226-4c55-bb48-1eee915e0d12	lab.audit.events	44490	2025-11-26 07:13:46.858958+00	t	2025-11-26 07:13:46.85896+00
9f3a0cc8-7f1d-4ece-b09c-73eb0b0f9209	lab.audit.events	44491	2025-11-26 07:14:37.008848+00	t	2025-11-26 07:14:37.008849+00
b9d32073-0863-45b3-9a69-cd7ddce82e9e	lab.audit.events	44492	2025-11-26 07:21:37.327517+00	t	2025-11-26 07:21:37.327518+00
fc9b8ba2-abde-4757-a9ff-2dc08235efe3	lab.audit.events	44493	2025-11-26 07:21:37.455787+00	t	2025-11-26 07:21:37.455788+00
09da51f6-d471-456c-958d-fdf43745d218	lab.audit.events	44494	2025-11-26 07:21:42.582324+00	t	2025-11-26 07:21:42.582326+00
4c9a049f-a2f1-4688-af2b-8e2167608760	lab.audit.events	44495	2025-11-26 07:21:42.707311+00	t	2025-11-26 07:21:42.707313+00
06e7a6f4-46c0-4d7b-bae7-11b198552ba2	lab.audit.events	44496	2025-11-26 07:21:47.834952+00	t	2025-11-26 07:21:47.834953+00
0888bcf7-d5d9-4f72-b2a6-0e46ac245dfd	lab.audit.events	44497	2025-11-26 07:21:47.959346+00	t	2025-11-26 07:21:47.959348+00
e354be8f-f769-4933-88ae-1c403b0e1503	lab.audit.events	44498	2025-11-26 07:21:53.08586+00	t	2025-11-26 07:21:53.085861+00
d64e9140-9d73-4d40-89be-b98f0cd4e545	lab.audit.events	44499	2025-11-26 07:22:08.219857+00	t	2025-11-26 07:22:08.219858+00
51051651-94c7-495d-90e1-eb4d49099a32	lab.audit.events	44500	2025-11-26 07:22:28.355436+00	t	2025-11-26 07:22:28.355437+00
6688e5c9-1591-434b-96a2-ae71638fdd74	lab.audit.events	44501	2025-11-26 07:22:28.478598+00	t	2025-11-26 07:22:28.478599+00
c5ea5b99-12a8-47aa-9414-cbb40c66f91c	lab.audit.events	44502	2025-11-26 07:22:38.606962+00	t	2025-11-26 07:22:38.606964+00
5c5b8abe-e88d-40a9-8704-af1fbc2d5135	lab.audit.events	44503	2025-11-26 07:22:38.730905+00	t	2025-11-26 07:22:38.730907+00
cb10799c-65e5-4567-bf0d-9666fd4d008a	lab.audit.events	44504	2025-11-26 07:22:38.855634+00	t	2025-11-26 07:22:38.855637+00
b5b3830b-5e11-4d52-8cec-bc7b2a4a706d	lab.audit.events	44505	2025-11-26 07:23:08.99923+00	t	2025-11-26 07:23:08.999231+00
180aa9b8-2f0a-4ad7-8df4-1c22578c3710	lab.audit.events	44506	2025-11-26 07:23:09.126283+00	t	2025-11-26 07:23:09.126306+00
8010a36a-db7d-4c5a-b9f0-76ede0844ff5	lab.audit.events	44507	2025-11-26 07:23:29.272115+00	t	2025-11-26 07:23:29.272116+00
fa2d929f-be96-4595-90e4-7a478793d244	lab.audit.events	44508	2025-11-26 07:23:29.405866+00	t	2025-11-26 07:23:29.405868+00
47bbc922-73f2-492a-b570-f911278cfaaf	lab.audit.events	44509	2025-11-26 07:28:39.662868+00	t	2025-11-26 07:28:39.662869+00
d238ccb7-3d8a-4eeb-b41a-a87e7e615e57	lab.audit.events	44510	2025-11-26 07:28:39.79637+00	t	2025-11-26 07:28:39.796372+00
71a7a9d6-74f1-4ebc-a158-225a7e0cc0cf	lab.audit.events	44511	2025-11-26 07:29:19.944181+00	t	2025-11-26 07:29:19.944183+00
27626847-b13b-4f9c-9b87-0f704daa7a8b	lab.audit.events	44512	2025-11-26 07:29:20.066849+00	t	2025-11-26 07:29:20.06685+00
e054b4d8-2b45-47aa-8f67-9f45a4ddfd35	lab.audit.events	44513	2025-11-26 07:38:05.69772+00	t	2025-11-26 07:38:05.697722+00
e4007300-4ec2-4c34-bf3d-a48d05e42751	lab.audit.events	44514	2025-11-26 07:42:46.236883+00	t	2025-11-26 07:42:46.236884+00
cb52291a-e0f5-4a1e-8833-b77a122d1408	lab.audit.events	44516	2025-11-26 07:47:06.491992+00	t	2025-11-26 07:47:06.491993+00
65a185ef-ad48-45ce-8471-e1cad40ac47b	lab.audit.events	44517	2025-11-26 07:56:51.874091+00	t	2025-11-26 07:56:51.874093+00
74975eae-2f52-4991-885b-da8b25aaf4f5	lab.audit.events	44518	2025-11-26 08:01:07.11334+00	t	2025-11-26 08:01:07.113341+00
210e8944-093e-4da3-a660-2ea454baea22	lab.audit.events	44524	2025-11-26 08:16:27.598915+00	t	2025-11-26 08:16:27.598916+00
4ad3e63d-a635-4d63-8d18-bd8ca225bca1	lab.audit.events	44525	2025-11-26 08:29:28.033654+00	t	2025-11-26 08:29:28.033657+00
579d7b32-a68a-463d-894d-a5e48551f5b1	lab.audit.events	44526	2025-11-26 08:29:33.176351+00	t	2025-11-26 08:29:33.176353+00
dbb74fb0-13b5-4298-b77b-e0bd0aa43132	lab.audit.events	44527	2025-11-26 08:30:28.318148+00	t	2025-11-26 08:30:28.31815+00
da62b5a5-9570-4355-bcd8-a915882f8bb1	lab.audit.events	44528	2025-11-26 08:43:58.793547+00	t	2025-11-26 08:43:58.793549+00
9e01689d-1be6-4329-a49c-f0a4bda7ec09	lab.audit.events	44529	2025-11-26 08:44:03.934639+00	t	2025-11-26 08:44:03.93464+00
57cf04be-74de-41b1-9a21-fcdd8e18266b	lab.audit.events	44530	2025-11-26 09:00:29.483989+00	t	2025-11-26 09:00:29.48399+00
6682f9e6-8bd3-4072-a3c5-11b1b075cbd7	lab.audit.events	44531	2025-11-26 09:01:09.634835+00	t	2025-11-26 09:01:09.634836+00
024f528b-266a-4359-a1d8-9f8870db191d	lab.audit.events	44532	2025-11-26 09:04:04.863306+00	t	2025-11-26 09:04:04.863307+00
\.


--
-- TOC entry 3777 (class 0 OID 33019)
-- Dependencies: 223
-- Data for Name: outbox_messages; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.outbox_messages (id, exchange, routing_key, payload, created_at, published_at, attempts, status) FROM stdin;
0ca0760e-35c7-4955-b49c-24cedb1bcb06	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:53:38.985996+00	2025-11-22 07:53:39.773575+00	1	SENT
332ad4ff-19a4-43de-a5a4-e97532969f81	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:54:11.786892+00	2025-11-22 07:54:15.241337+00	1	SENT
9cbef55a-81ab-41df-997c-3c2816633a7a	notify.exchange	lab.audit.events	{"user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","event":"USER_UPDATED"}	2025-11-22 08:06:09.401855+00	2025-11-22 08:06:09.898854+00	1	SENT
d4a1ae32-b140-410d-99d3-73fb873459b6	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"245141e7-715c-4e08-8a86-8e2b8d0264d1","username":"BaoNPG"}	2025-11-22 07:57:23.620849+00	2025-11-22 07:57:25.773807+00	1	SENT
9c71fd65-646b-449c-8ad1-f420859dcaea	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 08:06:09.452479+00	2025-11-22 08:06:10.028894+00	1	SENT
bfd39c2f-c630-45f8-8166-c02044f62e86	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-22 07:57:40.582186+00	2025-11-22 07:57:40.926822+00	1	SENT
9a099e9c-1dde-4cdd-ac6b-08da57193137	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 15:16:07.41504+00	2025-11-22 15:16:11.110971+00	1	SENT
438b81f9-fe19-47af-94ec-0b51bf6eadc7	notify.exchange	lab.audit.events	{"role_id":"5d6c50ef-851b-4ea8-985b-2a94bea662c8","event":"ROLE_UPDATED"}	2025-11-22 07:58:13.793857+00	2025-11-22 07:58:16.239983+00	1	SENT
f7d5c6c7-8b3c-4dd8-a343-f9012e61de58	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:06:11.269351+00	2025-11-22 08:06:15.293386+00	1	SENT
2739cdca-e286-48e2-93f0-f0b8e4678fbf	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"f9775bae-4116-4505-bdda-745e9cfa61f6","username":"Hungtq"}	2025-11-22 07:58:21.083925+00	2025-11-22 07:58:21.389917+00	1	SENT
8cd73382-0544-4b49-9042-4838106f2dc1	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:16:09.580892+00	2025-11-22 15:16:11.281453+00	1	SENT
b8c529e0-8836-49e8-ab46-4f47037a667f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:58:29.508687+00	2025-11-22 07:58:31.544023+00	1	SENT
1ce7ad6a-904e-436a-b40f-0ea738f48602	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:06:21.110596+00	2025-11-22 08:06:25.735562+00	1	SENT
45aa7a74-b3ff-4074-b705-8b70fe91b78c	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Hungtq","jti":"a4ceb08a-b1ca-46ed-96a1-402bf854872b"}	2025-11-24 04:16:18.610251+00	2025-11-24 04:16:21.533667+00	1	SENT
2bcfd617-5731-4f33-9368-b18f0c62ae45	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"Hung","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:16:20.330602+00	2025-11-22 15:16:21.452871+00	1	SENT
438e2b13-8262-44c0-b8bb-1fdc0769e4a2	notify.exchange	lab.notify.queue	{"template":"welcome","variables":{"model":{"password":"t4#g7+rF","fullName":"Nguyễn Phạm Gia Bảo","username":"BaoNPG"}},"subject":"Welcome","to":{"email":"nhathuydt3@gmail.com"}}	2025-11-22 08:07:33.050609+00	2025-11-22 08:07:36.213405+00	1	SENT
956434db-b2c5-4015-adb8-5c256136d9c5	notify.exchange	lab.audit.events	{"event":"USER_CREATED_BY_ADMIN","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:07:33.052438+00	2025-11-22 08:07:36.353367+00	1	SENT
9bf6d209-ad5e-4f71-af9f-7dd8c0a9caee	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_CREATE","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:07:33.065882+00	2025-11-22 08:07:36.500394+00	1	SENT
1d5243f1-5b75-4efa-8af3-a395d0f58c78	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:16:23.827691+00	2025-11-22 15:16:26.628476+00	1	SENT
5bef0496-a8dd-4450-a45c-c06a9ae34901	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","attempts":1}	2025-11-22 07:58:46.931131+00	2025-11-22 07:58:51.697913+00	1	SENT
e82f326c-bb6a-4eba-9446-2b22c87759aa	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:58:46.934911+00	2025-11-22 07:58:51.836283+00	1	SENT
8a512346-7acc-4bc8-b35d-91d10d0d8aae	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","attempts":2}	2025-11-22 07:58:47.683532+00	2025-11-22 07:58:52.102913+00	1	SENT
eee1202e-1859-4eeb-ba3f-9ceda1bbe18b	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:58:47.687739+00	2025-11-22 07:58:52.23226+00	1	SENT
bdf0e721-f12f-4a5c-812d-28b72c5e82c5	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:58:47.993857+00	2025-11-22 07:58:52.38543+00	1	SENT
bd0a1f00-7ab9-43ad-ac74-e7644dd63ecb	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","attempts":3}	2025-11-22 07:58:48.438479+00	2025-11-22 07:58:52.525018+00	1	SENT
95f1ae1a-f009-4030-bfee-ebd5404e94e2	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:58:48.445809+00	2025-11-22 07:58:52.652615+00	1	SENT
49112aa3-e4d1-40e4-9a9d-f7574298c9e5	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:58:48.782729+00	2025-11-22 07:58:52.786408+00	1	SENT
1f55050b-977a-4bb1-8ccd-4dd8c9696d5d	notify.exchange	lab.audit.events	{"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","event":"ADMIN_USER_WELCOME"}	2025-11-22 08:07:37.583743+00	2025-11-22 08:07:41.635254+00	1	SENT
099d93d6-1002-44be-a990-9bb80afdbd24	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:12:41.098165+00	2025-11-22 08:12:43.87145+00	1	SENT
a2643fb3-b6b5-42a9-9638-c97bdc5ac8c6	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:16:31.41254+00	2025-11-22 15:16:31.956547+00	1	SENT
9d5b6f7c-62b2-4bda-9e6d-b005156b667f	notify.exchange	lab.audit.events	{"page":"0","status":"locked","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:13:37.557965+00	2025-11-22 08:13:39.601596+00	1	SENT
74542e0b-421e-40b3-8490-eaede1f9a93a	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:14:38.953813+00	2025-11-22 08:14:39.913074+00	1	SENT
64d3f918-c2dc-417a-b967-fb79f176bc3f	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:24:04.572998+00	2025-11-22 15:24:09.044846+00	1	SENT
71e8464b-efd7-4094-a1ec-32e4f09f9a17	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","attempts":1}	2025-11-22 14:49:22.251183+00	2025-11-22 14:49:23.016874+00	1	SENT
bd0cecca-2a8b-4532-a7c9-5ec62f597897	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 14:49:22.252278+00	2025-11-22 14:49:23.130368+00	1	SENT
fd4423d4-76d3-40cf-b6c0-6bffdbc1024f	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:24:04.796493+00	2025-11-22 15:24:09.208933+00	1	SENT
f9c73363-6723-4e12-8237-935eca11d2ea	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-22 14:49:43.444173+00	2025-11-22 14:49:48.325659+00	1	SENT
07f4fedd-b9c0-4113-a7ce-5c9c41327afc	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 14:49:45.832702+00	2025-11-22 14:49:48.455483+00	1	SENT
d11efdd7-523f-4b1c-84af-3ef62dc5b4d9	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:24:19.965613+00	2025-11-22 15:24:24.546444+00	1	SENT
efad4acf-db07-4d78-90d7-3c366d0ec23a	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 07:57:42.996748+00	2025-11-22 07:57:46.073192+00	1	SENT
82c35d4f-d59e-49c5-a220-ff80419ba6f4	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:06:11.057061+00	2025-11-22 08:06:15.159771+00	1	SENT
99381b88-dd8c-4d9c-9a7b-ff17c2b6c87d	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:58:47.288831+00	2025-11-22 07:58:51.969423+00	1	SENT
fbc5f243-3033-438d-8fab-04a403227c14	notify.exchange	lab.audit.events	{"page":"0","status":"locked","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:16:28.308659+00	2025-11-22 15:16:31.794008+00	1	SENT
c1049a3a-e2ea-473f-8205-7ced297b17cc	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"0a1217ea-ae9a-46c7-acc7-c7e401d5a95e","username":"Hungtq"}	2025-11-22 08:07:49.439515+00	2025-11-22 08:07:51.770879+00	1	SENT
ad960181-39c1-41f8-becf-b26cf5345fa9	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:28:15.13806+00	2025-11-23 15:28:19.227693+00	1	SENT
4b802f3d-4e30-4af3-bcb3-085db06b18f2	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:08:10.51227+00	2025-11-22 08:08:11.913794+00	1	SENT
43e970c0-dad1-4d99-b55d-6f4e3d1ccc1c	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"truongthanhj1999@gmail.com","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:24:14.928654+00	2025-11-22 15:24:19.383739+00	1	SENT
f159223b-3e95-43cd-aba1-c77cb7c60244	notify.exchange	lab.audit.events	{"event":"PROFILE_FIRST_LOGIN_PASSWORD_CHANGED","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:08:31.053373+00	2025-11-22 08:08:32.0604+00	1	SENT
b045e745-bd5f-4b9b-9042-cb1b5b383479	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:08:39.403886+00	2025-11-22 08:08:42.197689+00	1	SENT
88ba79aa-d766-4e23-9d14-0d633a5dd5b5	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:24:35.086479+00	2025-11-22 15:24:39.712591+00	1	SENT
ec189f3c-0967-406e-b4c7-5e86b3e606f0	notify.exchange	lab.audit.events	{"event":"OTP_REQUESTED","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","correlation_id":"67a83365-24c9-41c9-b7a5-a1b0ea8b1750"}	2025-11-23 14:18:04.595623+00	2025-11-23 14:18:07.250948+00	1	SENT
ee178fd3-33af-4db3-8974-776e14053e43	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","attempts":1}	2025-11-22 14:38:24.496591+00	2025-11-22 14:38:26.635424+00	1	SENT
5b197fae-f3a3-4a00-9a4a-b977bb2bf0b4	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-22 14:38:24.502277+00	2025-11-22 14:38:26.767401+00	1	SENT
c47a3222-d0ce-4ee8-a1e8-d5105aefa01c	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:28:32.39173+00	2025-11-23 15:28:34.671414+00	1	SENT
c9ac26d9-e7a9-47a6-a0f1-60a1af2ffdf8	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:03:51.205369+00	2025-11-23 15:03:53.553523+00	1	SENT
8456befa-3876-482b-ae16-e2eb08b11616	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-22 14:38:34.656177+00	2025-11-22 14:38:36.882628+00	1	SENT
0c5cb3d6-541c-4a31-8b97-c9cef62d8bc6	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 14:38:36.866936+00	2025-11-22 14:38:41.996378+00	1	SENT
0d5dd9ea-6520-4a97-8ab3-ed5208e68b76	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 14:39:18.838419+00	2025-11-22 14:39:22.50062+00	1	SENT
af42c57b-163c-4d89-8072-ae4c2f316bbb	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:07:43.561222+00	2025-11-23 15:07:43.921503+00	1	SENT
2859bb5c-c948-402b-9f2c-1dbc25443a84	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Tkace","user_id":"8152cf83-39bb-44cd-a1c2-0ca4095ff0bf"}	2025-11-23 15:31:39.901117+00	2025-11-23 15:31:44.966418+00	1	SENT
ef2c8619-a6a9-4b36-9c95-0032a5d7f51d	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 14:59:42.408646+00	2025-11-22 14:59:43.805621+00	1	SENT
2a5671ae-5119-47b5-a825-a48cb4c00129	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 14:59:42.624772+00	2025-11-22 14:59:43.919663+00	1	SENT
2fe50bb0-6bde-410e-8d20-2b85815a5f6b	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"Hungtq","status":"all"}	2025-11-23 15:07:48.373737+00	2025-11-23 15:07:49.262923+00	1	SENT
b31b2cc7-8a71-4d24-8a3f-72d3e541a21e	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-23 15:09:21.648832+00	2025-11-23 15:09:24.801488+00	1	SENT
0a40fd0d-7028-4865-ba3b-5c609d30bbdd	notify.exchange	lab.audit.events	{"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","event":"USER_UPDATED"}	2025-11-22 15:00:21.802893+00	2025-11-22 15:00:24.394386+00	1	SENT
abbf24eb-8b23-4d87-8a82-83df5ff93484	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 15:00:21.84514+00	2025-11-22 15:00:24.507718+00	1	SENT
c940aa32-0bfb-4c61-8718-c298a16a8814	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:00:24.237143+00	2025-11-22 15:00:24.725661+00	1	SENT
e8c7172f-cd7d-44e3-af56-fe5f0633c21b	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 15:00:48.243051+00	2025-11-22 15:00:49.965997+00	1	SENT
91bf2859-1938-4c41-8ca1-bdf174420526	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:14:22.815784+00	2025-11-23 15:14:26.900851+00	1	SENT
3cd23191-b970-462a-ae37-48db347e94ad	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-23 15:31:47.265879+00	2025-11-23 15:31:50.114402+00	1	SENT
1620736d-c709-4c69-be59-e98915cafab0	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-23 15:21:00.246689+00	2025-11-23 15:21:03.375773+00	1	SENT
cbcc3b45-fd8b-4c27-b605-b3e1d948a6de	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:31:49.890746+00	2025-11-23 15:31:50.251458+00	1	SENT
a31a3a19-9bf9-494a-85f9-d3d87e702f6d	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"active"}	2025-11-23 15:40:57.320715+00	2025-11-23 15:41:00.988146+00	1	SENT
ce69b9c0-e5b5-4b3a-ace1-c54f45193da1	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:41:00.077726+00	2025-11-23 15:41:01.149569+00	1	SENT
9ed8d9fb-f9bc-4753-b7b8-6423ff437634	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:45:17.217765+00	2025-11-23 15:45:21.877202+00	1	SENT
97827a79-2c1d-43dd-baad-8405dcca9b11	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:45:17.475661+00	2025-11-23 15:45:22.019923+00	1	SENT
3797567d-9cd7-4276-904a-9342570a5af0	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 15:45:22.313637+00	2025-11-23 15:45:27.156401+00	1	SENT
8f113562-0f51-47cb-b6fd-b0c4ada766df	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 15:45:22.577253+00	2025-11-23 15:45:27.290371+00	1	SENT
f958bb35-29a2-4769-8f72-9b09d821ec91	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:28:14.885961+00	2025-11-23 15:28:19.085002+00	1	SENT
706b3abc-9861-4a6a-9ec7-e3827dba8594	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 07:59:42.803004+00	2025-11-22 07:59:42.955482+00	1	SENT
a19298c1-2c43-4530-a7d8-e753363a2d32	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:22:10.857822+00	2025-11-22 15:22:12.561016+00	1	SENT
e81d0d18-247d-487a-bed2-9fe900776b48	notify.exchange	lab.audit.events	{"event":"USER_DELETED","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 08:06:20.88825+00	2025-11-22 08:06:25.429096+00	1	SENT
365cf35d-7806-41f4-a579-39093c0605f6	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","attempts":1}	2025-11-22 08:01:52.31199+00	2025-11-22 08:01:53.359862+00	1	SENT
8949643b-a375-4d10-9e84-542a07980b4c	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-22 08:01:52.315423+00	2025-11-22 08:01:53.490348+00	1	SENT
663cc906-fd9f-4fe9-958d-dabd1b5e7bcb	notify.exchange	lab.audit.events	{"user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","event":"ADMIN_USER_DELETE"}	2025-11-22 08:06:20.90908+00	2025-11-22 08:06:25.580408+00	1	SENT
70c1383f-576e-40b2-ad9a-d1bd5e9b1b29	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-22 08:02:01.47818+00	2025-11-22 08:02:03.6249+00	1	SENT
c74347af-e902-42a7-8458-4f728562a719	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:02:03.660666+00	2025-11-22 08:02:08.765906+00	1	SENT
09cf2655-d8bb-4bb9-be75-8296ab8f259d	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 14:38:55.095878+00	2025-11-22 14:38:57.124774+00	1	SENT
bfb5bec3-69fb-4559-aa9d-c4686b15649b	notify.exchange	lab.audit.events	{"role_id":"5d6c50ef-851b-4ea8-985b-2a94bea662c8","event":"ROLE_UPDATED"}	2025-11-22 08:02:21.625181+00	2025-11-22 08:02:23.915421+00	1	SENT
faac3ab8-bf8d-4485-a270-f55bd5484735	notify.exchange	lab.audit.events	{"role_id":"2dc3c99e-6f02-4e70-a41a-50d0e5eb5410","event":"ROLE_DELETED"}	2025-11-22 08:02:28.79576+00	2025-11-22 08:02:29.071511+00	1	SENT
a46c6965-016c-4307-bd4a-e554472e4d5e	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 14:39:18.590549+00	2025-11-22 14:39:22.391469+00	1	SENT
ecde867f-6249-4f93-9f25-066b4f530ed3	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:05:16.006559+00	2025-11-22 08:05:19.33577+00	1	SENT
41eb6d01-8490-4ddc-a06c-506aaa565967	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 15:23:07.096699+00	2025-11-22 15:23:07.916426+00	1	SENT
a300d658-faab-4e62-baad-bf2276062713	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:00:08.319646+00	2025-11-22 15:00:09.045433+00	1	SENT
5ffac2d5-57d3-4508-bc3c-2508687c5c01	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 15:23:07.281415+00	2025-11-22 15:23:08.083652+00	1	SENT
e10a83cf-68e6-4e9e-a34a-9bac16681979	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:00:24.058388+00	2025-11-22 15:00:24.616423+00	1	SENT
060d14c9-a3d1-4d5c-9322-e2bd85332c05	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:03:46.022692+00	2025-11-22 15:03:50.396152+00	1	SENT
2e6c5178-f168-421a-bd73-53b309295f70	notify.exchange	lab.audit.events	{"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","event":"USER_UPDATED"}	2025-11-22 15:23:15.758781+00	2025-11-22 15:23:18.283629+00	1	SENT
3479f97a-56bc-4086-ba69-a78888a5103a	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 15:23:15.769236+00	2025-11-22 15:23:18.468432+00	1	SENT
09cd8c6f-1805-4c3d-9ef0-c8eaf7f370cf	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:23:18.344152+00	2025-11-22 15:23:23.849461+00	1	SENT
d55e4c3b-a2cf-4d2b-9920-da6614f25d7b	notify.exchange	lab.audit.events	{"event":"OTP_REQUESTED","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","correlation_id":"84adb041-06ab-49a9-b380-6eabd5c560f8"}	2025-11-23 13:14:27.2741+00	2025-11-23 13:14:28.504498+00	1	SENT
ee295a00-b5cf-4402-82de-7803bc0b53ec	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:45.09277+00	2025-11-23 14:42:48.951004+00	1	SENT
fc32e5ef-d200-4d1b-a29e-e12e7f2fc99d	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:45.145878+00	2025-11-23 14:42:49.14179+00	1	SENT
93d08430-e0b0-447f-a480-73ab5480d12c	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":2,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:54.506121+00	2025-11-23 14:42:59.312622+00	1	SENT
95e382d7-afd6-479f-86e2-75774e0bdf80	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:54.515018+00	2025-11-23 14:42:59.480559+00	1	SENT
6537dbe5-9f73-4b8d-b16b-fe351390aa25	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":3,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:54.947353+00	2025-11-23 14:42:59.633489+00	1	SENT
926ff516-fa38-4f1d-9ca9-c0dc92ad624e	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:54.949534+00	2025-11-23 14:42:59.786354+00	1	SENT
9d560b64-2ca7-4426-9b23-8a1c3d5d1101	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":4,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:55.708392+00	2025-11-23 14:42:59.938608+00	1	SENT
052052c1-735a-442a-89ff-0a571e48292a	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:55.709995+00	2025-11-23 14:43:00.094313+00	1	SENT
ea21ef2d-c396-4849-a73e-af510b27fc67	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":5,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:56.256028+00	2025-11-23 14:43:00.245955+00	1	SENT
b8cf2f85-2936-470f-b795-e8d96e5a639e	notify.exchange	lab.audit.events	{"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","event":"USER_LOCKED","mode":"ADMIN_ONLY","reason":"Temporarily locked due to 5 incorrect password attempts"}	2025-11-23 14:42:56.365694+00	2025-11-23 14:43:00.391301+00	1	SENT
7789fbff-f6da-4380-9fc0-6782c142e3a0	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:56.378093+00	2025-11-23 14:43:00.53978+00	1	SENT
f1d6a579-88ae-40a5-b96b-07c7fd3051d5	notify.exchange	lab.audit.events	{"event":"USER_TEMP_LOCKED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:42:56.383783+00	2025-11-23 14:43:00.689582+00	1	SENT
e104b423-2c2a-4428-afba-19e80467b79a	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-23 14:45:37.034114+00	2025-11-23 14:45:41.327119+00	1	SENT
f6e810c7-8465-4935-9431-3aaab6849a38	notify.exchange	lab.audit.events	{"event":"USER_UNLOCKED","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:45:48.263179+00	2025-11-23 14:45:51.636165+00	1	SENT
ae360cf7-08af-4746-9b8e-91368e0947f0	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UNLOCK","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 14:45:48.280357+00	2025-11-23 14:45:51.78738+00	1	SENT
1bc769d7-7abd-45d0-9031-57551b71ccd0	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 14:45:48.580948+00	2025-11-23 14:45:51.939379+00	1	SENT
b1edcec7-63e1-4c2a-86e6-9c31d9d68205	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:13:56.436516+00	2025-11-24 04:13:59.631792+00	1	SENT
bf498764-98e8-48b0-be30-78d168bac239	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"e1a571fa-d19b-431d-9454-0fa3b134c395","username":"BaoNPG"}	2025-11-22 08:01:38.245314+00	2025-11-22 08:01:43.1895+00	1	SENT
1bcf9210-574c-4623-b569-9f6ac4f8a953	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"511fd456-c5cd-4fb8-b793-bf0eca131199","username":"BaoNPG"}	2025-11-22 08:11:00.823931+00	2025-11-22 08:11:02.428443+00	1	SENT
031dce4d-7d96-4ae9-9a3b-c0d1957d4012	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:05:16.242684+00	2025-11-22 08:05:19.472768+00	1	SENT
8d71a9ee-a26b-4fc6-85dd-1dc0b4cb18db	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:23:01.015384+00	2025-11-22 15:23:02.745359+00	1	SENT
96ee875b-0510-48bd-807e-263d1db97db4	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 08:05:38.478759+00	2025-11-22 08:05:39.609728+00	1	SENT
2619524a-1537-46e7-8eb2-3351f1f26f46	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","attempts":1}	2025-11-22 08:11:16.100586+00	2025-11-22 08:11:17.579406+00	1	SENT
9236c60f-f060-4c94-b663-8fa2f9b06f2f	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-22 08:11:16.101681+00	2025-11-22 08:11:17.703606+00	1	SENT
8dd5c13e-b354-43e1-9be0-a1c2d8bf39e7	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"987fa969-961f-4afb-98aa-636c3448bd87","username":"PhatNT"}	2025-11-23 14:06:46.275611+00	2025-11-23 14:06:50.148383+00	1	SENT
116a72bd-360b-4b12-80fa-7a3910c51b60	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-22 08:11:31.233742+00	2025-11-22 08:11:32.835974+00	1	SENT
865ea1c4-dbca-49ba-8ce3-336d404e6c52	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:11:33.549717+00	2025-11-22 08:11:37.976458+00	1	SENT
75b66634-72c6-4863-92dd-d5a01790d5b3	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","user_id":"987fa969-961f-4afb-98aa-636c3448bd87","username":"PhatNT"}	2025-11-23 14:07:54.965271+00	2025-11-23 14:07:55.568623+00	1	SENT
1481b2c6-ba0d-4be5-b066-ab64fbac774c	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:11:40.597621+00	2025-11-22 08:11:43.117408+00	1	SENT
0e5eb6c5-7880-4bfe-bc3c-2a89dfda5641	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"7b7a3614-26ec-4574-8866-b6237f425ce8","username":"PhatNT"}	2025-11-23 14:08:02.695877+00	2025-11-23 14:08:05.684771+00	1	SENT
c4ea6125-8464-4878-9b75-8d82923fe6f6	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:12:35.596956+00	2025-11-22 08:12:38.436868+00	1	SENT
1564bdbe-6da6-4b0f-9063-0f887a711217	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:12:35.871508+00	2025-11-22 08:12:38.566418+00	1	SENT
a2e345f6-2cbf-481c-881b-15e505b0bdcf	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:13:39.95175+00	2025-11-22 08:13:44.740453+00	1	SENT
c2dfdd06-21a7-4014-9dce-019f1acc2cca	notify.exchange	lab.audit.events	{"event":"OTP_REQUESTED","user_id":"987fa969-961f-4afb-98aa-636c3448bd87","correlation_id":"81ff278c-9eee-458b-a33a-7311443222fc"}	2025-11-23 14:08:11.111324+00	2025-11-23 14:08:15.804633+00	1	SENT
1180ee47-6c48-4c00-a447-a3075525104f	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:14:39.274917+00	2025-11-22 08:14:40.044382+00	1	SENT
bda80e66-e986-4bf5-8a23-9ec45a482508	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"60bb66bb-057f-4300-967e-329bba24733d","username":"Hungtq"}	2025-11-22 08:14:44.631315+00	2025-11-22 08:14:45.178445+00	1	SENT
b1d5f628-1140-48dd-8da2-03a8607ec40d	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-23 14:08:49.107401+00	2025-11-23 14:08:51.224014+00	1	SENT
698f8550-c2c9-4e45-a152-a03bc82f8d09	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:14:56.865571+00	2025-11-22 08:15:00.329271+00	1	SENT
96c98e0a-235b-4a40-a311-00a2c566a2a9	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 14:39:10.566674+00	2025-11-22 14:39:12.253735+00	1	SENT
c6c434f7-2e89-44a2-94e0-bea85c99609b	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","username":"Hungtq"}	2025-11-23 14:08:59.058773+00	2025-11-23 14:09:01.347755+00	1	SENT
9a8cc5b8-11cb-479d-b4a1-2f18f8f4d7ae	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 15:00:15.657405+00	2025-11-22 15:00:19.161436+00	1	SENT
993bb4e0-2791-4e61-b76c-9675d476d7ef	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 15:00:15.847795+00	2025-11-22 15:00:19.281374+00	1	SENT
518bec2d-fa59-42b8-98bd-4f28bcd33681	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"9ed04027-5b89-4f38-831b-4a73793b29da","username":"Hungtq"}	2025-11-23 14:09:07.843901+00	2025-11-23 14:09:11.577886+00	1	SENT
642f0c18-2200-4898-973f-ad06ca6f99d0	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"0769698f-d1cb-47fa-9330-152cb85e8c1e","username":"Hungtq"}	2025-11-22 15:00:27.719697+00	2025-11-22 15:00:29.842946+00	1	SENT
8b3885de-0ae0-42c4-9e0a-1914c6212d20	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:00:50.396521+00	2025-11-22 15:00:55.089441+00	1	SENT
d57b9db5-a59c-4937-9086-a9e291f14355	notify.exchange	lab.audit.events	{"event":"OTP_REQUESTED","user_id":"987fa969-961f-4afb-98aa-636c3448bd87","correlation_id":"b7dd5618-ad56-44b6-9ff7-29a0db28f2ee"}	2025-11-23 14:09:12.670706+00	2025-11-23 14:09:16.699553+00	1	SENT
dd72df75-b7ad-4f70-9c4c-63cf7ccd5c4d	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:03:06.212978+00	2025-11-22 15:03:10.26879+00	1	SENT
c7ecc5c8-0350-4a26-9a71-70daf2b0db36	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:04:15.12866+00	2025-11-22 15:04:15.520797+00	1	SENT
e0a62d64-b71c-4bc1-9c80-580f259db9a2	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","user_id":"987fa969-961f-4afb-98aa-636c3448bd87","username":"PhatNT"}	2025-11-23 14:10:04.615567+00	2025-11-23 14:10:06.839349+00	1	SENT
0e56dfd6-e2d8-4974-afc2-d8b50c372a12	notify.exchange	lab.audit.events	{"event":"OTP_REQUESTED","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4","correlation_id":"ed2f733d-b2e2-4a41-a615-33e3ba95e33b"}	2025-11-23 14:10:22.020454+00	2025-11-23 14:10:26.957386+00	1	SENT
dda1daf6-620c-428f-babc-1a6ba88e52f7	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 14:45:40.578116+00	2025-11-23 14:45:41.47515+00	1	SENT
2cc24c5f-2653-4d59-bae7-d396c1e12012	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:07:43.906759+00	2025-11-23 15:07:49.093191+00	1	SENT
4d16d530-01eb-403a-9837-a9ce523694f8	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"KhoaNPT","user_id":"bb8259df-3cb8-487a-ab91-2ef95a68aa44"}	2025-11-23 15:10:51.106971+00	2025-11-23 15:10:55.459513+00	1	SENT
a0e4b272-6907-4512-95dd-246c5af58810	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:10:54.013622+00	2025-11-23 15:10:55.597326+00	1	SENT
7c392d6f-fafb-478e-98de-eb436535f9dc	notify.exchange	lab.audit.events	{"role_code":"TESTAPI","event":"ROLE_CREATED"}	2025-11-23 15:12:33.65065+00	2025-11-23 15:12:35.945225+00	1	SENT
9751e9b7-b7a8-4da5-872c-fac3c132f484	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:13:56.679015+00	2025-11-24 04:13:59.759443+00	1	SENT
73b6a6ad-2f06-463c-bf14-75d93d0903c1	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"6d9a51de-fa84-480a-b10b-aa7b9d288fa6","username":"BaoNPG"}	2025-11-22 08:05:38.699983+00	2025-11-22 08:05:39.744995+00	1	SENT
94173ddd-4f5f-4f70-a158-c372fbc8938f	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:11:40.799823+00	2025-11-22 08:11:43.257393+00	1	SENT
72c0d190-e973-4bf4-99bf-2e06b3af58b9	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:23:18.129313+00	2025-11-22 15:23:23.674878+00	1	SENT
a422232c-4d4d-4b99-b7d2-751b5335679b	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:12:40.903631+00	2025-11-22 08:12:43.711392+00	1	SENT
091dd454-5da0-4b76-8566-85d448cc1b64	notify.exchange	lab.audit.events	{"event":"USER_BANNED","reason":"Disabled by administrator","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-23 15:28:32.126021+00	2025-11-23 15:28:34.379855+00	1	SENT
ae523a8e-bc5c-45ac-a8f1-11672cd7b05d	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-23 14:09:01.060682+00	2025-11-23 14:09:01.461559+00	1	SENT
05635e65-b04d-4f0b-800e-989ea1df3514	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_BAN","reason":"Disabled by administrator","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-23 15:28:32.163791+00	2025-11-23 15:28:34.52263+00	1	SENT
85e8a88f-c7c5-4faa-9812-ccfe8186c28c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 15:03:15.37401+00	2025-11-23 15:03:18.054765+00	1	SENT
dbaf7605-cae9-4fe6-86a4-0ac3b978e20c	notify.exchange	lab.audit.events	{"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","event":"USER_UPDATED"}	2025-11-22 08:12:50.102185+00	2025-11-22 08:12:54.01102+00	1	SENT
a2615cfb-3343-4f27-9a71-3ed4b726ac94	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","username":"BaoNPG"}	2025-11-22 08:12:50.121266+00	2025-11-22 08:12:54.145398+00	1	SENT
a345ca63-4847-435a-9b9d-31bc7b55cb1f	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:12:52.089458+00	2025-11-22 08:12:54.277114+00	1	SENT
c7479c4a-eb2c-42ba-9b91-c9e4468541a5	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 08:12:52.27021+00	2025-11-22 08:12:54.418467+00	1	SENT
c8ae29c8-e5c9-4819-8435-a8c318b64212	notify.exchange	lab.audit.events	{"event":"LOGOUT","jti":"25ae6d00-1114-41f9-9bf4-20d5773cf83a","username":"Hungtq"}	2025-11-22 14:49:08.121872+00	2025-11-22 14:49:12.891494+00	1	SENT
c08e40d7-ff4b-4ed5-93a5-a8949aa9a18e	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"e3f655d3-8fa5-427f-8103-671f4a64e7e4"}	2025-11-23 15:03:22.045395+00	2025-11-23 15:03:23.217906+00	1	SENT
03872366-ee05-459c-ac7a-9e44b201f503	notify.exchange	lab.audit.events	{"page":"0","status":"all","q":"","event":"ADMIN_USERS_LIST","size":"10","role":""}	2025-11-22 15:15:41.523099+00	2025-11-22 15:15:45.919081+00	1	SENT
9161d40a-f80d-4e52-901d-c577c0b3bfbf	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-23 15:03:47.922474+00	2025-11-23 15:03:48.408461+00	1	SENT
4991bbf7-d358-42f9-8797-10788274d3bb	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:40:49.635186+00	2025-11-23 15:40:50.68777+00	1	SENT
3e5bd83c-ca57-4e3c-bd13-1b0772d30a17	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:40:49.889494+00	2025-11-23 15:40:50.832454+00	1	SENT
a91cf754-9f2f-45ba-a74e-8a69876a1cf5	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:09:19.07243+00	2025-11-23 15:09:19.502335+00	1	SENT
54f5ebb2-bc0e-49b8-b712-3c13f166f895	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:09:19.347792+00	2025-11-23 15:09:19.64993+00	1	SENT
26e75a52-f732-4aad-b69a-ebe046215eee	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-23 15:09:21.95775+00	2025-11-23 15:09:24.9395+00	1	SENT
2dde9286-fba4-4bad-9324-8e55adfd4e03	notify.exchange	lab.audit.events	{"role_id":"e73c5b55-62ea-4ac7-972c-c461c2d52b2f","event":"ROLE_UPDATED"}	2025-11-23 15:45:13.506151+00	2025-11-23 15:45:16.734975+00	1	SENT
b06aad8c-e190-4aa2-83c2-c5d21984e2e6	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:09:33.591343+00	2025-11-23 15:09:35.094163+00	1	SENT
f39b5dbe-1b89-4b1b-b01d-8334c9687836	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:09:33.891791+00	2025-11-23 15:09:35.258537+00	1	SENT
4a5435ab-2bb2-4482-9711-ba56c36d8bd1	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:10:54.249805+00	2025-11-23 15:10:55.73935+00	1	SENT
b312f4c1-cb15-4b88-8400-06b1f513b1c1	notify.exchange	lab.audit.events	{"role_id":"e01c2375-fbf4-4a85-b32a-18340d2c93bc","event":"ROLE_DELETED"}	2025-11-23 15:12:40.9532+00	2025-11-23 15:12:46.096082+00	1	SENT
3c4dbb47-c81a-4f84-951d-4ac84b767583	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"KhoaNPT","jti":"28c86db1-ca9d-47a1-b875-9b467b18dff8"}	2025-11-23 15:12:46.123396+00	2025-11-23 15:12:51.249429+00	1	SENT
275a5903-82cb-4196-ac3d-67fc7ede1385	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Tkace","user_id":"8152cf83-39bb-44cd-a1c2-0ca4095ff0bf"}	2025-11-23 15:12:50.01784+00	2025-11-23 15:12:51.4074+00	1	SENT
a6ca63b3-5d1b-4142-8c05-025958cdee39	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Tkace","jti":"a5ca2d10-3e71-4b7d-a23f-67e04d3c60bf"}	2025-11-23 15:12:58.18455+00	2025-11-23 15:13:01.564309+00	1	SENT
9a7aac9c-b390-4e89-9665-749eac4f181d	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:14:22.44678+00	2025-11-23 15:14:26.760092+00	1	SENT
8978f7ee-7524-4d24-9bea-27205c850146	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:14:31.321712+00	2025-11-23 15:14:32.039737+00	1	SENT
c0d09c99-39c3-4bbe-b00b-3c2ccd21cef9	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Hungtq","jti":"b2cccf30-6ea1-4233-b0de-0d74975fdaa1"}	2025-11-23 15:14:33.80843+00	2025-11-23 15:14:37.18085+00	1	SENT
f69dc92c-a372-47e8-9acc-1d6be0f5a96f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-23 15:14:48.900347+00	2025-11-23 15:14:52.331843+00	1	SENT
625f23d7-bedd-41aa-9a0d-bbc5d7174d24	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:14:51.455708+00	2025-11-23 15:14:52.476108+00	1	SENT
51aa69dc-39b9-4c2a-ae7e-1a0a43a29dfd	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:15:10.517756+00	2025-11-23 15:15:12.649007+00	1	SENT
53dd8a6f-bf08-4386-8c6a-3cfa81b7451b	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:15:10.772605+00	2025-11-23 15:15:12.792513+00	1	SENT
c3e1bf95-b10a-49db-809a-1ee4de140caa	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-23 15:20:59.982912+00	2025-11-23 15:21:03.191365+00	1	SENT
27d46651-bf68-4ea9-b47d-8044630e1595	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:21:47.549023+00	2025-11-23 15:21:48.569003+00	1	SENT
2d0cb03b-0d35-4b07-9638-d7b9f8a65578	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:21:47.851058+00	2025-11-23 15:21:48.72014+00	1	SENT
7be2a46b-41d6-4621-a295-7a6783acaf0e	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:12:58.907807+00	2025-11-26 06:13:02.250717+00	1	SENT
d7be7536-a034-47f9-a098-bf9450dcc187	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:45:29.249607+00	2025-11-23 15:45:32.701368+00	1	SENT
63008839-0d85-40cc-98fe-cd5ceaae4f07	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"1095961e-f29c-429b-abde-bf90ac927d0a"}	2025-11-23 15:54:05.267582+00	2025-11-23 15:54:08.860101+00	1	SENT
a8642db7-f3d5-49f4-a701-b2894a0a8f4d	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:14:02.918659+00	2025-11-24 04:14:04.893803+00	1	SENT
7a2334e3-d951-43fa-80bc-24f8c3b5523c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-23 15:54:22.007747+00	2025-11-23 15:54:24.004722+00	1	SENT
a0d85152-b2ac-4206-9177-42e9a46aa25f	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:14:03.14991+00	2025-11-24 04:14:05.014988+00	1	SENT
97028d1d-c2d0-45dc-9448-f218dfe48fa5	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:54:24.678669+00	2025-11-23 15:54:29.147497+00	1	SENT
3b9ab6d5-0d67-4924-ac6f-76d5cf4a1138	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:14:09.788571+00	2025-11-24 04:14:10.424368+00	1	SENT
90c9b262-22ec-43e3-bc10-496711fcca39	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 04:20:14.934854+00	2025-11-24 04:20:16.756808+00	1	SENT
1fc2b84a-bc34-4946-8ef2-84b0a3048aca	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:21:29.413033+00	2025-11-24 04:21:31.914803+00	1	SENT
495bbde6-c220-4c70-afc3-f52eb1cc7dbf	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:22:43.143267+00	2025-11-24 04:22:47.099185+00	1	SENT
f24cf896-8de5-424d-96ad-229167b49303	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-24 04:26:00.337461+00	2025-11-24 04:26:02.33238+00	1	SENT
8e8f286f-dd19-4219-90e5-2bff556ae7fb	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"KhoaNPT","jti":"59c9b081-91ce-4e4a-bf8f-6b826d9a0b70"}	2025-11-24 04:26:30.523807+00	2025-11-24 04:26:32.47485+00	1	SENT
00a03601-8929-4a78-87a9-15b75c99378a	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-24 04:26:58.949736+00	2025-11-24 04:27:02.624891+00	1	SENT
edc3ce93-2fa4-44be-88cd-286e7b3efe9e	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:27:01.705097+00	2025-11-24 04:27:02.754372+00	1	SENT
ac5dbeae-b5e2-4562-832a-7c24794f8712	notify.exchange	lab.audit.events	{"role_id":"cc49e2f1-cdb2-42bd-9776-b641a22529bf","event":"ROLE_UPDATED"}	2025-11-24 04:27:15.501268+00	2025-11-24 04:27:17.8844+00	1	SENT
da2c40ad-6fda-4fd2-845d-1d03f63b7447	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:38:04.103013+00	2025-11-24 04:38:08.750698+00	1	SENT
a3618cda-a589-4ba3-93ed-ddcb3f5e34d5	notify.exchange	lab.audit.events	{"role_code":"DOCTOR","event":"ROLE_CREATED"}	2025-11-24 04:38:09.787516+00	2025-11-24 04:38:13.898377+00	1	SENT
daec9c4e-ddb3-403f-828f-755a9e1c628c	notify.exchange	lab.audit.events	{"role_id":"965b5367-7443-41c9-855f-a39113b7ec66","event":"ROLE_UPDATED"}	2025-11-24 04:41:48.029033+00	2025-11-24 04:41:49.435948+00	1	SENT
8a53163d-f74d-4ef7-843a-20af1299c30e	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:46:41.461754+00	2025-11-24 04:46:45.059967+00	1	SENT
f36e8e5c-caf7-4b08-8aa4-4453b0773cc7	notify.exchange	lab.audit.events	{"role_id":"d24c97cb-ead8-447c-8318-4631fdc928a2","event":"ROLE_UPDATED"}	2025-11-24 04:46:59.540557+00	2025-11-24 04:47:00.613987+00	1	SENT
286c640b-2ca7-4cca-ad15-3191d5dcbbf6	notify.exchange	lab.audit.events	{"role_id":"d24c97cb-ead8-447c-8318-4631fdc928a2","event":"ROLE_UPDATED"}	2025-11-24 04:47:09.602438+00	2025-11-24 04:47:10.751269+00	1	SENT
ea299e7a-f349-496b-bd20-b845a3d755d9	notify.exchange	lab.audit.events	{"role_code":"STAFF","event":"ROLE_CREATED"}	2025-11-24 04:47:16.359327+00	2025-11-24 04:47:20.879593+00	1	SENT
5dd3200d-8996-42ac-9e48-3012af24c160	notify.exchange	lab.audit.events	{"role_id":"965b5367-7443-41c9-855f-a39113b7ec66","event":"ROLE_DELETED"}	2025-11-24 04:47:21.832989+00	2025-11-24 04:47:26.0064+00	1	SENT
57e3b94c-6cf2-47d6-b3de-32bb7c28c48a	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:47:59.966351+00	2025-11-24 04:48:01.435854+00	1	SENT
1433dc0e-e547-4f19-8698-1709e9157603	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:48:00.177711+00	2025-11-24 04:48:01.55871+00	1	SENT
81284caf-3d1d-443a-9c53-24fbea034b24	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 04:57:00.766163+00	2025-11-24 04:57:02.320882+00	1	SENT
a9d0c175-8cf0-4edc-90ad-8fe651bb8e8f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 12:18:59.453411+00	2025-11-24 12:19:02.644542+00	1	SENT
e58935e8-8435-4b47-be77-66beeaeb822a	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 12:19:20.771328+00	2025-11-24 12:19:22.803457+00	1	SENT
052ec538-36e4-471c-9e4b-a6d317fc1d78	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 13:49:13.514906+00	2025-11-24 13:49:15.066176+00	1	SENT
69af3f50-e7f9-41b5-8f00-1664ee65dcf7	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 03:40:23.80551+00	2025-11-25 03:40:28.382467+00	1	SENT
51e15e07-fd49-40e0-b903-5387f3118d22	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 04:29:33.881259+00	2025-11-25 04:29:35.079552+00	1	SENT
0ffef55d-5166-410c-a6ce-6503b99c7889	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 05:00:17.742506+00	2025-11-25 05:00:21.344461+00	1	SENT
2963e570-f9fb-4524-b3bb-17586d5b0196	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 05:30:18.367068+00	2025-11-25 05:30:22.292625+00	1	SENT
e02fb197-2267-4959-a94e-4a25f827e1ea	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 05:58:28.978267+00	2025-11-25 05:58:33.488984+00	1	SENT
9c4dea0c-2f1d-41c1-9c8c-03eb9b1b9c4b	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 06:22:09.52388+00	2025-11-25 06:22:14.299633+00	1	SENT
1a389f8b-bd41-4b66-b5b6-b1d4eed45302	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 12:18:06.36409+00	2025-11-25 12:18:07.603972+00	1	SENT
ceda4bc6-3599-48c4-8c0d-1de250c1e8d2	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:27:54.814941+00	2025-11-25 12:27:58.843897+00	1	SENT
5a168a71-f91f-4995-aa51-8906666b6910	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:28:03.610273+00	2025-11-25 12:28:03.964838+00	1	SENT
27333289-1639-4151-b134-e389bfd99276	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:28:03.828569+00	2025-11-25 12:28:04.076495+00	1	SENT
cefa2090-4222-4020-a772-74a94610d610	notify.exchange	lab.audit.events	{"event":"USER_UPDATED","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 15:45:27.624731+00	2025-11-23 15:45:32.436697+00	1	SENT
d7988fb4-9423-49a6-aae2-725ec1d5e866	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 15:45:27.639452+00	2025-11-23 15:45:32.571392+00	1	SENT
1c84b357-9ce6-4b6e-9529-39c623fc8d6f	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:45:29.498031+00	2025-11-23 15:45:32.83337+00	1	SENT
c6aa1952-15d0-4562-8d5c-50e37b8a30c6	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-23 15:45:43.1359+00	2025-11-23 15:45:48.117727+00	1	SENT
b70c7d8b-e58f-44ce-a633-feef816050d8	notify.exchange	lab.audit.events	{"event":"USER_UPDATED","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:14:07.523021+00	2025-11-24 04:14:10.152859+00	1	SENT
d88714d9-154e-4f45-894b-284b7205a9e5	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"Tkace","user_id":"8152cf83-39bb-44cd-a1c2-0ca4095ff0bf"}	2025-11-23 15:46:14.483759+00	2025-11-23 15:46:18.295471+00	1	SENT
8b2228e6-b499-4a80-9c61-d29d5955c966	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Tkace","user_id":"8152cf83-39bb-44cd-a1c2-0ca4095ff0bf"}	2025-11-23 15:46:18.110201+00	2025-11-23 15:46:18.454414+00	1	SENT
de75669f-a8a9-4c45-b02d-aa15ea3215a1	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:14:07.530907+00	2025-11-24 04:14:10.294791+00	1	SENT
c431f9de-936f-44fe-a4e0-198d00cb5b54	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:14:10.021682+00	2025-11-24 04:14:10.557453+00	1	SENT
0bfa4718-50f5-4dbc-b8a3-173024c4091d	notify.exchange	lab.audit.events	{"event":"USER_UNBANNED","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-23 15:57:12.036944+00	2025-11-23 15:57:14.390767+00	1	SENT
794b154f-d5be-4dec-b67e-92050ac52a5b	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UNBAN","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-23 15:57:12.061688+00	2025-11-23 15:57:14.527483+00	1	SENT
72d0c195-7c0e-40da-8413-bea60130e09e	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:57:12.318676+00	2025-11-23 15:57:14.662197+00	1	SENT
e3aebeff-760c-46b5-882a-25b9d51e342d	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"KhoaNPT","user_id":"bb8259df-3cb8-487a-ab91-2ef95a68aa44"}	2025-11-24 04:30:57.953245+00	2025-11-24 04:30:58.129125+00	1	SENT
87c3e54d-73ac-465d-b83e-d8a31023fe22	notify.exchange	lab.audit.events	{"page":"0","role":"ADMIN","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:57:30.234679+00	2025-11-23 15:57:34.808617+00	1	SENT
341b6e1a-7ded-45d0-90b2-5c03a33a3ba7	notify.exchange	lab.audit.events	{"page":"0","role":"ADMIN","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:57:46.054761+00	2025-11-23 15:57:50.092391+00	1	SENT
324caacb-2a4e-4fc7-8337-061264d2622b	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:57:50.673475+00	2025-11-23 15:57:55.258478+00	1	SENT
5e070d0b-6f76-4a45-a271-ef9c3bf1f131	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:31:00.443534+00	2025-11-24 04:31:03.261459+00	1	SENT
a1340eeb-d671-4b7f-ba7c-70f0d24d4f03	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:31:00.658674+00	2025-11-24 04:31:03.39545+00	1	SENT
24cbf897-ac51-4a6f-935d-dd156b0e9f2c	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"KhoaNPT","jti":"140c2f1a-f74d-446f-a2c4-46a30baf5d01"}	2025-11-24 04:45:56.598322+00	2025-11-24 04:45:59.66163+00	1	SENT
fe47f31c-4e54-4bf0-b4cc-788f4873464f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"KhoaNPT","user_id":"bb8259df-3cb8-487a-ab91-2ef95a68aa44"}	2025-11-24 04:46:38.70599+00	2025-11-24 04:46:39.810382+00	1	SENT
e77745c4-794d-495c-ba07-fb71f87f0ca5	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:46:41.212653+00	2025-11-24 04:46:44.936637+00	1	SENT
65548ac1-2507-467d-ad2f-1f8436624946	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 04:46:41.719964+00	2025-11-24 04:46:45.193469+00	1	SENT
e079cc50-9404-4229-a294-d86838834d94	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-24 04:46:42.448691+00	2025-11-24 04:46:45.329446+00	1	SENT
b5c51061-02de-457b-ab7c-733584434530	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:46:45.254753+00	2025-11-24 04:46:50.463578+00	1	SENT
60aa77ce-7118-4705-bdca-571e783c761d	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:48:00.415326+00	2025-11-24 04:48:01.681359+00	1	SENT
a610ff7b-4ddf-4dc8-aab6-3ba036600e14	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:48:00.642329+00	2025-11-24 04:48:01.805956+00	1	SENT
48a86741-dd3e-4c85-bc27-ca4a2aafc034	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:54:52.4231+00	2025-11-24 04:54:57.101561+00	1	SENT
221ec547-86aa-41d4-b17d-1201874b5948	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 12:19:48.111532+00	2025-11-24 12:19:52.946455+00	1	SENT
4ce5684b-6186-4fde-b2c9-3eac96439919	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 03:26:20.642352+00	2025-11-25 03:26:22.587954+00	1	SENT
abff3e57-abc1-4303-8dab-0dbdbfaf82e3	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 04:17:07.616016+00	2025-11-25 04:17:09.34028+00	1	SENT
7afca972-f546-4e32-ac2e-54a8db3f061d	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 04:46:05.33686+00	2025-11-25 04:46:05.887383+00	1	SENT
30dcc4aa-12b1-4203-ae39-17919b5c7f86	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 05:15:33.142085+00	2025-11-25 05:15:36.818728+00	1	SENT
db6fb04d-9a6b-42c6-9b79-d398260ca290	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 05:44:25.431423+00	2025-11-25 05:44:27.760007+00	1	SENT
2f66af74-fe7f-40c8-8665-30ddda66b517	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 06:12:43.281998+00	2025-11-25 06:12:43.925475+00	1	SENT
b83f8966-2833-4a66-b68d-1c5717d98faf	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 11:20:50.638679+00	2025-11-25 11:20:50.854124+00	1	SENT
06d720e7-843d-4e53-a36d-ecaa81348de3	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:26:08.375945+00	2025-11-25 12:26:13.183048+00	1	SENT
445e9360-e98f-442c-a3c1-80bd981a5979	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:27:51.761979+00	2025-11-25 12:27:53.617961+00	1	SENT
8192987c-1d43-4514-97fb-49c8fa400725	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:27:54.59594+00	2025-11-25 12:27:58.73483+00	1	SENT
cc03ab71-c938-4662-aa7b-ca278548cb32	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-25 12:39:23.110891+00	2025-11-25 12:39:25.420847+00	1	SENT
cc8890ef-948c-42d6-af28-93428c2ba692	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:11:19.863029+00	2025-11-25 20:11:24.854071+00	1	SENT
47c3acf6-b6f3-48ab-a4f8-2dff4372ff0e	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Hungtq","jti":"e6bf72dd-d48e-4c0a-b8dd-b9e88a6c03eb"}	2025-11-23 15:45:32.202383+00	2025-11-23 15:45:32.967737+00	1	SENT
fc664a44-c29c-47a9-a86f-abc31077f50f	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:57:40.699815+00	2025-11-23 15:57:44.951851+00	1	SENT
7590ca99-2860-4d79-990b-7423ba0c939e	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:57:55.783748+00	2025-11-23 15:58:00.416304+00	1	SENT
638ddda0-f0f3-4fa1-8097-a5f6d6c093c2	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-23 15:57:56.040642+00	2025-11-23 15:58:00.559121+00	1	SENT
5eb0b113-d33d-4dd6-9a1f-3556993f27f7	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-24 03:15:48.077492+00	2025-11-24 03:15:48.439011+00	1	SENT
15bd3bff-5f5d-498e-bb6f-5341a8c2c7d7	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:15:51.184062+00	2025-11-24 03:15:53.582129+00	1	SENT
471ecada-c8be-40ec-8962-2acc6af1eb6e	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"Hungtq","status":"all"}	2025-11-24 03:24:16.584084+00	2025-11-24 03:24:18.922455+00	1	SENT
14412453-dc32-4ccb-86be-7380eed1122c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 03:29:44.472045+00	2025-11-24 03:29:49.186668+00	1	SENT
21edcf02-4e71-4ce7-a387-cd7e103a3d49	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-24 03:29:51.536528+00	2025-11-24 03:29:54.328058+00	1	SENT
c4417097-015d-4c2a-9e57-34f864211465	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 03:29:56.49276+00	2025-11-24 03:29:59.465506+00	1	SENT
0a7a86e9-cd22-4aa2-8034-bbc107dc3a08	notify.exchange	lab.audit.events	{"event":"OTP_REQUESTED","correlation_id":"8e89414d-bf6e-4f61-b0b9-a0d191deb2cd","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 03:31:33.242063+00	2025-11-24 03:31:34.924091+00	1	SENT
ac4fbb4a-669a-4b3f-93f8-de498c698720	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Hungtq","jti":"d0981665-31c5-4071-93ef-6d74fcbfa952"}	2025-11-24 03:31:36.429422+00	2025-11-24 03:31:40.067485+00	1	SENT
695c767c-ef88-492b-8f73-2593c4377954	notify.exchange	lab.audit.events	{"event":"OTP_REQUESTED","correlation_id":"f4cbd4fa-2fde-4663-afd7-dd594da32e41","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 03:31:49.109619+00	2025-11-24 03:31:50.220469+00	1	SENT
1b3c00f4-ba39-4006-a7e0-15ce8ad26801	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Tkace","user_id":"8152cf83-39bb-44cd-a1c2-0ca4095ff0bf"}	2025-11-24 03:31:57.091824+00	2025-11-24 03:32:00.365676+00	1	SENT
ad48f3ae-b9f8-48ac-b9b8-9b7056866b6a	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 03:32:01.090745+00	2025-11-24 03:32:05.508377+00	1	SENT
56ffaf47-324d-4ade-acb2-0265368fb24c	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Tkace","jti":"1e681209-f373-4f9c-8c90-31ef4b97ea9d"}	2025-11-24 03:32:03.566228+00	2025-11-24 03:32:05.645594+00	1	SENT
47d26627-2cce-4ded-a7d1-ce7058ed5823	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-24 03:32:03.929268+00	2025-11-24 03:32:05.788891+00	1	SENT
60dcda5e-f484-4a38-9c6f-10f32f00ac5b	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"KhoaNPT","user_id":"bb8259df-3cb8-487a-ab91-2ef95a68aa44"}	2025-11-24 03:32:07.789812+00	2025-11-24 03:32:10.934531+00	1	SENT
9eb2061a-fcef-42fc-be21-b73b356699ef	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"894a34d0-1321-4ead-8c26-8217c80410a3"}	2025-11-24 03:32:32.745775+00	2025-11-24 03:32:36.07836+00	1	SENT
db973bbc-9aa5-402a-968a-4482db757fbe	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-24 03:32:50.149842+00	2025-11-24 03:32:51.220598+00	1	SENT
52327c30-177e-4610-a12b-6aa2a0fdbf01	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:32:52.684469+00	2025-11-24 03:32:56.368656+00	1	SENT
2884ae5b-c397-428c-8ae0-7087b7d7fe1b	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"KhoaNPT","user_id":"bb8259df-3cb8-487a-ab91-2ef95a68aa44"}	2025-11-24 03:32:56.423839+00	2025-11-24 03:33:01.512545+00	1	SENT
0059aab1-120b-4ece-bdc2-21f51230b3c7	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:32:58.922657+00	2025-11-24 03:33:01.638369+00	1	SENT
045001a4-c42f-49c9-a4b0-6620542479b1	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-24 03:32:59.187603+00	2025-11-24 03:33:01.768628+00	1	SENT
4673c63b-8fdc-40ca-b14a-d915b6da9459	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:32:59.192595+00	2025-11-24 03:33:01.896381+00	1	SENT
9f907ebf-d27d-4cd3-b4f4-e9e953baa393	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-24 03:32:59.412831+00	2025-11-24 03:33:02.022182+00	1	SENT
ed022dcb-97c9-48f1-86ad-cf533dc01ee1	notify.exchange	lab.audit.events	{"event":"USER_UPDATED","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-24 03:33:06.018019+00	2025-11-24 03:33:07.157613+00	1	SENT
5a7b6559-f53c-42f9-bd34-b02c79069ad7	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-24 03:33:06.051602+00	2025-11-24 03:33:07.287657+00	1	SENT
9ee401f3-0f64-40c7-a83f-f7ab369fc0aa	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:33:08.303603+00	2025-11-24 03:33:12.414596+00	1	SENT
9bf53ea8-87b2-41d0-bd41-21dabde2ce35	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:33:08.535545+00	2025-11-24 03:33:12.544896+00	1	SENT
8eee6bd3-4125-4302-97da-3ec622f9963c	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:34:45.180583+00	2025-11-24 03:34:48.024434+00	1	SENT
d77159ea-eaa0-4328-8b6c-57b1d5d807ab	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:34:45.412566+00	2025-11-24 03:34:48.180444+00	1	SENT
eb9af41a-88b2-477c-8781-90c09a68d87b	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:35:00.327818+00	2025-11-24 03:35:03.320436+00	1	SENT
3722a794-f99b-40e9-8545-de2cc8f1a08f	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:35:00.558631+00	2025-11-24 03:35:03.455895+00	1	SENT
ff3a9c68-9de8-47d0-9356-5ed5e94a12b3	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:35:16.745704+00	2025-11-24 03:35:18.608787+00	1	SENT
10151cdb-698b-4817-9a8d-d00ff7072197	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:35:16.985281+00	2025-11-24 03:35:18.741786+00	1	SENT
c9624425-a50a-4d6b-ae57-3207ba4d7ef2	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:35:17.229614+00	2025-11-24 03:35:18.865115+00	1	SENT
53d55456-515b-4786-b696-7c76d0dc53c2	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:35:17.462471+00	2025-11-24 03:35:18.989433+00	1	SENT
8d46cb9d-56f9-4c94-a720-b1afa5843ea7	notify.exchange	lab.audit.events	{"role_id":"cc49e2f1-cdb2-42bd-9776-b641a22529bf","event":"ROLE_UPDATED"}	2025-11-24 04:14:26.924668+00	2025-11-24 04:14:30.699934+00	1	SENT
6bd98798-d3e0-4c83-b14e-0877048469d3	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 03:38:36.298015+00	2025-11-24 03:38:39.204775+00	1	SENT
6f4e3e2d-2505-4b6d-9d47-174daf79d640	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 03:38:36.510595+00	2025-11-24 03:38:39.336791+00	1	SENT
85c0ffbd-81d4-4f8c-b1a2-81827ef934c5	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 00:02:25.089964+00	2025-11-26 00:02:27.83288+00	1	SENT
5064e358-dd8a-44bf-a1a0-ae03b16052de	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Hungtq","jti":"ef8a6bf6-27f1-4732-8c50-5c25e2764cdb"}	2025-11-24 04:14:40.332928+00	2025-11-24 04:14:40.828744+00	1	SENT
fb72252a-e2fa-46d0-b8c8-7e8d4c6fa15d	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:41:15.084975+00	2025-11-24 03:41:19.565927+00	1	SENT
e1a5a6f4-5741-4d14-b355-e6f223daee1f	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:41:15.31553+00	2025-11-24 03:41:19.714456+00	1	SENT
2e2c9adc-e6ad-495b-bc02-1bd62eea52ec	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 03:46:45.631675+00	2025-11-24 03:46:50.014438+00	1	SENT
a8586b41-9b7e-407f-ae20-5af7273a2028	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-24 04:15:09.239647+00	2025-11-24 04:15:10.977455+00	1	SENT
822b47e0-9265-45dc-8348-ece4d5f6bd74	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"KhoaNPT","jti":"4e353a48-c758-418e-b145-7fc05d533fde"}	2025-11-24 03:47:55.606244+00	2025-11-24 03:48:00.20811+00	1	SENT
c9570a1f-0009-49db-aa4f-b96124cdc2c5	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:15:11.981542+00	2025-11-24 04:15:16.106425+00	1	SENT
1d9394c1-34bc-4710-9af4-10df128b94c5	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-24 03:48:17.684855+00	2025-11-24 03:48:20.395387+00	1	SENT
e2d08068-b688-4ca1-91f8-d5e0fdd9ebae	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:48:20.217719+00	2025-11-24 03:48:20.558537+00	1	SENT
dc233852-0384-4b2e-ae54-4a0d64057fbf	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"HungNQ","user_id":"ef8716fc-d175-4c54-870d-1c9313405fd0"}	2025-11-24 03:48:30.028761+00	2025-11-24 03:48:30.694375+00	1	SENT
5aab490a-f10d-4a29-b95c-cbc49b94443a	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"HungNQ","user_id":"ef8716fc-d175-4c54-870d-1c9313405fd0"}	2025-11-24 03:48:30.239447+00	2025-11-24 03:48:30.821881+00	1	SENT
07e16149-e908-407e-ad21-852d74e17503	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:16:09.743177+00	2025-11-24 04:16:11.26537+00	1	SENT
cd4fad4e-562f-4102-8b26-d53a810b7458	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:16:09.972647+00	2025-11-24 04:16:11.397904+00	1	SENT
e6d64d6e-4877-4830-94b4-3986f1c00f3a	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:52:06.645953+00	2025-11-24 03:52:11.052854+00	1	SENT
55b30d6c-b2aa-4be9-be7e-2e2de4496575	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:52:06.925651+00	2025-11-24 03:52:11.177767+00	1	SENT
2a03a3aa-bfe2-4fa1-ab2a-0a18c3ec3f28	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"KhoaNPT","user_id":"bb8259df-3cb8-487a-ab91-2ef95a68aa44"}	2025-11-24 03:57:30.378101+00	2025-11-24 03:57:31.441487+00	1	SENT
abcd511d-c8f3-4866-9cf7-2ec266262086	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:57:32.900712+00	2025-11-24 03:57:36.580441+00	1	SENT
94cb1a0e-6df2-44b5-96f7-7e0d0827e8ca	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 03:57:33.134707+00	2025-11-24 03:57:36.705429+00	1	SENT
e99fbc04-f180-46df-9068-7a08b6ec194a	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-24 04:00:56.213988+00	2025-11-24 04:00:56.954443+00	1	SENT
6cc6e525-84d2-48f5-bc91-c62dd9e40e50	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-24 04:03:40.401103+00	2025-11-24 04:03:42.185683+00	1	SENT
560c638f-c090-487e-935b-34c55b0ed14f	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:03:42.908849+00	2025-11-24 04:03:47.32145+00	1	SENT
d46111ab-61f9-4e2c-b85d-f4660cb5cedf	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:09:57.586234+00	2025-11-24 04:10:02.620178+00	1	SENT
3dcba33c-e861-43a8-b7d6-155d8d8e54eb	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:09:57.867486+00	2025-11-24 04:10:02.758367+00	1	SENT
b15cf00a-2ada-4709-af4b-643dded31969	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"Huhu","status":"all"}	2025-11-24 04:10:03.672735+00	2025-11-24 04:10:07.887176+00	1	SENT
107072db-a9ba-4978-8ed0-c25bb588806f	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:10:05.530572+00	2025-11-24 04:10:08.013143+00	1	SENT
9a0c9e42-4982-4997-a1f3-33008d7492cf	notify.exchange	lab.audit.events	{"page":"0","role":"LAB_MANAGER","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:10:14.003375+00	2025-11-24 04:10:18.141893+00	1	SENT
c138900e-5ec8-4dfb-9ae5-42f00daaa5f6	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:10:17.259626+00	2025-11-24 04:10:18.269956+00	1	SENT
f8e48c76-0eee-4576-a942-521f2827f418	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"KhoaNPT","user_id":"bb8259df-3cb8-487a-ab91-2ef95a68aa44"}	2025-11-24 04:11:31.109462+00	2025-11-24 04:11:33.422482+00	1	SENT
7ce28d27-2aaf-4572-90da-9015d2b9360b	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:12:54.196234+00	2025-11-24 04:12:58.586897+00	1	SENT
e32439d3-7296-4406-b3a9-6b94b4dd2b33	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:12:54.425641+00	2025-11-24 04:12:58.714798+00	1	SENT
44a74b67-b2fe-4db0-a5ae-15a5882ac97d	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:13:03.268994+00	2025-11-24 04:13:03.842841+00	1	SENT
1c1d6db5-3b92-4f99-aac6-532eb6d7124f	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:13:03.478119+00	2025-11-24 04:13:03.969366+00	1	SENT
825470a7-c5c8-4128-81e2-717ebbb8477a	notify.exchange	lab.audit.events	{"event":"USER_UPDATED","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:13:10.361131+00	2025-11-24 04:13:14.101871+00	1	SENT
cbc8095d-3ffc-436d-82b5-a26a0cbf9f6a	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-24 04:13:10.392492+00	2025-11-24 04:13:14.229809+00	1	SENT
d681b0dd-0043-4d5f-b421-0c33503e99a4	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:13:13.248271+00	2025-11-24 04:13:14.356027+00	1	SENT
057f3536-e3b8-4924-b370-ea979906e537	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-24 04:13:13.492062+00	2025-11-24 04:13:14.483786+00	1	SENT
4c91dbe4-64b1-4101-8c6f-0f3b25df11d9	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:25:24.452522+00	2025-11-25 20:25:25.573942+00	1	SENT
18d87436-d879-4cef-a900-4b68ffb4f23f	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:28:05.387278+00	2025-11-25 12:28:09.191739+00	1	SENT
94855b38-1e0e-4f2f-9d76-af621d7f8973	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:28:05.628574+00	2025-11-25 12:28:09.308768+00	1	SENT
d7731aaf-4044-4255-8916-f4eef1b67153	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 00:16:09.126944+00	2025-11-26 00:16:14.500139+00	1	SENT
338475df-347b-434e-b192-8ce4145c2729	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 00:18:19.944263+00	2025-11-26 00:18:24.698773+00	1	SENT
099d6ca6-8f4c-478d-8df5-b472a958c370	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 01:47:27.148015+00	2025-11-26 01:47:27.710306+00	1	SENT
9d6291db-6bca-4e18-8f78-f54a9af75e0d	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"d9c315eb-dd42-4cd5-846f-16fc6c0ed8cd"}	2025-11-26 01:49:51.905636+00	2025-11-26 01:49:52.88938+00	1	SENT
971249fe-82da-4763-bd7e-3eab0b6d03e0	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 01:50:13.889625+00	2025-11-26 01:50:18.01738+00	1	SENT
55d74034-65b9-489e-922f-74ccece12bd6	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 01:50:13.890432+00	2025-11-26 01:50:18.127174+00	1	SENT
39914c4a-9bb8-4b15-9fba-2b1733cf9564	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 01:50:29.78349+00	2025-11-26 01:50:33.246436+00	1	SENT
8a0af175-d53a-467e-a5a8-88d1444a2754	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 01:52:03.507146+00	2025-11-26 01:52:08.677051+00	1	SENT
ca49d91e-e30d-4293-8d11-a0ced1a33717	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 01:54:36.77116+00	2025-11-26 01:54:38.857406+00	1	SENT
e96f8294-9856-42af-9b82-237fadd8fd3a	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 01:56:20.441498+00	2025-11-26 01:56:24.015621+00	1	SENT
813255aa-bcd4-46b8-8785-bdd2885be562	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 01:56:25.363838+00	2025-11-26 01:56:29.133576+00	1	SENT
88e0ce74-847d-4a8e-b7d9-e1360dd2258d	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:24:34.33903+00	2025-11-26 02:24:35.726408+00	1	SENT
273ae47b-0c80-4957-883f-adecafba9f03	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 02:24:43.184678+00	2025-11-26 02:24:45.846579+00	1	SENT
99e8b166-48ee-4934-b0b4-80e043cb9bcd	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:28:45.992162+00	2025-11-26 02:28:51.055034+00	1	SENT
e1e4308f-070e-48b9-9543-3d9dfd4e1849	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:29:49.452618+00	2025-11-26 02:29:51.187958+00	1	SENT
3294a434-d882-4cde-9c98-b33a66072dd0	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:45.930138+00	2025-11-26 02:36:48.154434+00	1	SENT
a154d13d-9c46-49b9-8d81-36eb43c6560d	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:45.931886+00	2025-11-26 02:36:48.26632+00	1	SENT
8b01e49a-914e-44be-8d6f-0a14105da523	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":2,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:47.282862+00	2025-11-26 02:36:48.377055+00	1	SENT
8d861b51-e9b3-4f4b-a157-df0e19c88af7	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:47.283532+00	2025-11-26 02:36:48.485429+00	1	SENT
6575f158-3656-4305-8e7f-35dc0744b8c8	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":3,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:48.083932+00	2025-11-26 02:36:53.595664+00	1	SENT
f3091d0e-b934-46a9-b64c-1308976f01c7	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:48.084623+00	2025-11-26 02:36:53.708493+00	1	SENT
f28a6bf2-3409-4368-b870-98b106a99b08	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":4,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:48.950911+00	2025-11-26 02:36:53.818509+00	1	SENT
a7db6584-5144-427b-9cb6-eaa8fee1718a	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:48.952795+00	2025-11-26 02:36:53.92354+00	1	SENT
33540e76-4946-4b0f-89cb-1dcc7511b7df	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":5,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:49.836469+00	2025-11-26 02:36:54.032043+00	1	SENT
3848a021-d4f7-450b-93e3-158612526d3f	notify.exchange	lab.audit.events	{"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c","event":"USER_LOCKED","mode":"ADMIN_ONLY","reason":"Temporarily locked due to 5 incorrect password attempts"}	2025-11-26 02:36:49.92+00	2025-11-26 02:36:54.139415+00	1	SENT
7a0c4de8-a5b5-4a7d-9a36-c6de7078d5bb	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:49.920619+00	2025-11-26 02:36:54.247414+00	1	SENT
b5da5c39-4147-4095-a74a-ea96b1b6e48c	notify.exchange	lab.audit.events	{"event":"USER_TEMP_LOCKED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:36:49.920919+00	2025-11-26 02:36:54.358452+00	1	SENT
0da33f3c-7917-4380-80b0-78b568b57e0b	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 02:37:55.296572+00	2025-11-26 02:37:59.844735+00	1	SENT
f2de0d42-24f7-4ebb-8b5e-a3fa12a81faa	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 02:44:48.68996+00	2025-11-26 02:44:50.67772+00	1	SENT
8bb42160-9cfe-45a5-8f63-fc924fbf5b22	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"HungNQ","user_id":"ef8716fc-d175-4c54-870d-1c9313405fd0"}	2025-11-26 02:44:54.708517+00	2025-11-26 02:44:55.896114+00	1	SENT
0b7c128d-ba7a-47a0-8eb8-b19200ebbadf	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 02:45:09.971656+00	2025-11-26 02:45:11.332711+00	1	SENT
e4850b8e-145a-4b3f-8c85-d58683770aec	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 02:45:10.269567+00	2025-11-26 02:45:11.443274+00	1	SENT
c48b0ad6-1819-4332-a510-ab87fb3d6fb2	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:54:13.151687+00	2025-11-26 02:54:17.035773+00	1	SENT
7600b2e1-f557-479f-93b8-af3b7d3b3165	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Hungtq","jti":"b623af97-9f18-46cc-aa57-b79db2812426"}	2025-11-26 02:54:25.827652+00	2025-11-26 02:54:27.157854+00	1	SENT
f70f23de-9d95-432c-95f3-9736ef9e51c9	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 06:13:02.852975+00	2025-11-26 06:13:07.381405+00	1	SENT
d4fa67a0-6e81-4623-92c0-a063e006f25b	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:28:05.844578+00	2025-11-25 12:28:09.421716+00	1	SENT
b5b070e6-2ff4-4caa-8a21-e0fb39908776	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 12:28:06.068208+00	2025-11-25 12:28:09.530968+00	1	SENT
8c3c9ef0-30f0-45c6-9f35-55867b2a50d0	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 12:32:22.280063+00	2025-11-25 12:32:24.754386+00	1	SENT
55bd8782-8b49-46da-b0da-00accd1523f9	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:40.424858+00	2025-11-25 20:31:40.847966+00	1	SENT
890af07f-24ab-40c9-a8d9-6bc979ac3e42	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 12:35:05.166724+00	2025-11-25 12:35:09.947629+00	1	SENT
998e4c83-6b32-411a-8a25-57524de7dbd2	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:40.428921+00	2025-11-25 20:31:40.965947+00	1	SENT
9c7c529f-9b84-4a1d-8396-d653ac0f2f8e	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"8c47613c-bc8d-4919-98f8-3927e3cf846b"}	2025-11-25 12:39:02.057381+00	2025-11-25 12:39:05.174875+00	1	SENT
bb080e33-edd9-4a09-83b0-9456879f2e40	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-25 12:39:20.469872+00	2025-11-25 12:39:25.306972+00	1	SENT
0aa0dee4-d47c-4c77-a3dd-752427e42658	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-25 12:39:34.066522+00	2025-11-25 12:39:35.533897+00	1	SENT
2049ab44-1649-4a8a-b12e-7de0bad05947	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:40.766151+00	2025-11-25 20:31:46.083614+00	1	SENT
8cdaed82-714c-4816-acb9-4b5b75fb1c13	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":2,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:41.211006+00	2025-11-25 20:31:46.194572+00	1	SENT
8ee2beb6-4402-476f-b3c3-1dc96a822b71	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:41.211927+00	2025-11-25 20:31:46.302753+00	1	SENT
e2f8e0ef-8798-49b7-a5c0-efc188a25290	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:41.533343+00	2025-11-25 20:31:46.41143+00	1	SENT
e03c07eb-d9db-45bd-814c-71d8f4f00b90	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":3,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:41.985565+00	2025-11-25 20:31:46.517426+00	1	SENT
30acd9f1-0468-43a3-94ce-b434b44d452f	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:41.986342+00	2025-11-25 20:31:46.623806+00	1	SENT
9311a0f4-d0f3-414f-94b2-d64239a6293f	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:42.326993+00	2025-11-25 20:31:46.731423+00	1	SENT
17a9bd01-7d58-4915-b9cb-b46fb472ef41	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":4,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:42.840504+00	2025-11-25 20:31:46.8416+00	1	SENT
20318d0e-bcd2-4f0c-9c4a-0900312e7311	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:42.842361+00	2025-11-25 20:31:46.949603+00	1	SENT
055c90f0-46b3-4568-842e-3dada3ab9dc4	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:43.194858+00	2025-11-25 20:31:47.054434+00	1	SENT
013618fa-79c6-45b2-b4a4-b98b17d0f1cb	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":5,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:43.643475+00	2025-11-25 20:31:47.175169+00	1	SENT
4687b057-92e5-4ca7-a908-a42dbdc96d1e	notify.exchange	lab.audit.events	{"user_id":"987fa969-961f-4afb-98aa-636c3448bd87","event":"USER_LOCKED","mode":"ADMIN_ONLY","reason":"Temporarily locked due to 5 incorrect password attempts"}	2025-11-25 20:31:43.728711+00	2025-11-25 20:31:47.284743+00	1	SENT
a9784cd8-8012-4543-9042-a663e75b317c	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:43.729349+00	2025-11-25 20:31:47.389674+00	1	SENT
84709707-8a24-46ab-bd83-2404bd918d41	notify.exchange	lab.audit.events	{"event":"USER_TEMP_LOCKED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 20:31:43.729664+00	2025-11-25 20:31:47.496519+00	1	SENT
d83c222a-7827-4020-9bc7-92f6a94a4eb2	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 01:33:00.56558+00	2025-11-26 01:33:01.413851+00	1	SENT
0ca038a9-0957-4591-b3a8-1aea2f1b7a32	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 01:33:24.012684+00	2025-11-26 01:33:26.548858+00	1	SENT
6c5149a3-20ee-4660-b615-d5a74bb7779c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 01:33:30.179857+00	2025-11-26 01:33:31.660456+00	1	SENT
4e67f71a-d277-45b9-a44f-c0a789009f73	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 01:33:55.749898+00	2025-11-26 01:33:56.795459+00	1	SENT
6053f5ab-aac5-480d-ac7b-4344b3cb3a0f	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 02:05:03.72922+00	2025-11-26 02:05:04.728259+00	1	SENT
42216327-dd54-4408-9d79-64406771fa09	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:04.413683+00	2025-11-26 02:36:06.702461+00	1	SENT
a7f14451-4963-4882-9262-5c2e413a4d9d	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:04.416356+00	2025-11-26 02:36:06.816417+00	1	SENT
c755e536-ffe4-474f-8997-264c55228fe4	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:04.781474+00	2025-11-26 02:36:06.925496+00	1	SENT
becc7347-96db-4118-8e6a-2d486ed0ce1c	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":2,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:05.220005+00	2025-11-26 02:36:07.036583+00	1	SENT
52cd89a7-39fb-4da0-8a27-be535bfe5e8f	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:05.220855+00	2025-11-26 02:36:07.1458+00	1	SENT
7524905e-b9e8-4001-a4b4-8f24d6cc4b4e	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:05.540371+00	2025-11-26 02:36:07.253068+00	1	SENT
14530233-7ff1-4495-bb27-664c8859d6a5	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":3,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:05.977333+00	2025-11-26 02:36:07.362421+00	1	SENT
a020c11e-d561-4358-ac4e-7ae8ee536003	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:05.978075+00	2025-11-26 02:36:07.480658+00	1	SENT
f86f96b1-146c-4cd1-8584-3eec6988a954	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:06.297627+00	2025-11-26 02:36:07.589433+00	1	SENT
525aa60f-2e6d-463f-8db7-f7902d67daea	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-25 12:39:41.394506+00	2025-11-25 12:39:45.649031+00	1	SENT
55dd7aa5-2825-429f-a870-1e697df56f23	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-25 12:39:41.658616+00	2025-11-25 12:39:45.757748+00	1	SENT
a8225658-37e2-4751-acd2-a143205a99d0	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 12:46:56.8128+00	2025-11-25 12:47:01.062432+00	1	SENT
019ecbf7-897b-43b7-a9e9-6bd528118322	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-25 12:48:35.549629+00	2025-11-25 12:48:36.497448+00	1	SENT
d276f4f8-9ac0-44eb-a71b-8c3e119509d9	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 12:58:03.18688+00	2025-11-25 12:58:06.841941+00	1	SENT
979c663b-aa53-4378-965b-e77a7a50738a	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-25 12:58:14.311202+00	2025-11-25 12:58:16.964854+00	1	SENT
58acbd55-dff8-4c85-8ccd-2012e29fe1cf	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-25 12:58:14.312107+00	2025-11-25 12:58:17.073368+00	1	SENT
70f275a4-2686-46d4-8863-305e7ffc034b	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-25 12:58:19.312089+00	2025-11-25 12:58:22.187464+00	1	SENT
4b9e67c0-cc99-4d4d-ac9b-47a81b6a4146	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-25 12:58:22.031539+00	2025-11-25 12:58:22.296619+00	1	SENT
fd9b6f03-2925-440e-afd2-d3aeca6d2fb9	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-25 12:59:25.056649+00	2025-11-25 12:59:27.721373+00	1	SENT
f4f4a759-8b67-4811-b83b-6b8aba0bc981	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 13:00:59.847137+00	2025-11-25 13:01:03.166838+00	1	SENT
599b9f95-58b0-4ae1-9061-83617355180b	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-25 13:13:00.788043+00	2025-11-25 13:13:03.609721+00	1	SENT
e31b6cdc-e074-4478-a89e-871e018b708b	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-25 13:13:06.708593+00	2025-11-25 13:13:08.721858+00	1	SENT
55c40d63-9f62-4998-af36-02b082745cdd	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-25 13:13:06.977654+00	2025-11-25 13:13:08.836134+00	1	SENT
90168e5f-c238-4cc2-9e88-7433cdc024d4	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 13:16:19.562086+00	2025-11-25 13:16:24.068378+00	1	SENT
3aa3c9ae-0660-4e10-aae4-16a9a270d60b	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-25 13:21:07.842589+00	2025-11-25 13:21:09.326197+00	1	SENT
cd7454ed-a41c-43fa-9ece-7a693c92c8d6	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 13:22:00.904928+00	2025-11-25 13:22:04.484023+00	1	SENT
12ede1fc-aa73-489b-b2b9-32904d8fbc7e	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"LocLM","user_id":"2a04b41b-422f-455e-85c3-4c036e692b3c"}	2025-11-25 13:29:13.721046+00	2025-11-25 13:29:14.78811+00	1	SENT
05bed92b-02ea-47ae-84a9-64744a7b94e5	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 13:32:24.22852+00	2025-11-25 13:32:24.986913+00	1	SENT
f76891e7-03d3-446b-80d8-cf120cb5970c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-25 13:33:04.330754+00	2025-11-25 13:33:05.124919+00	1	SENT
80925a4e-7262-4bfe-99d8-9bd7c0106406	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"LocLM","user_id":"2a04b41b-422f-455e-85c3-4c036e692b3c"}	2025-11-25 13:41:34.795986+00	2025-11-25 13:41:35.452385+00	1	SENT
1edf4e67-4de2-4faf-8af3-0a5c94b28ecd	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"LocLM","user_id":"2a04b41b-422f-455e-85c3-4c036e692b3c"}	2025-11-25 13:42:16.025167+00	2025-11-25 13:42:20.598032+00	1	SENT
1e54b0a9-d932-4c23-acd0-faf1c08c1e17	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 13:42:51.013306+00	2025-11-25 13:42:56.020128+00	1	SENT
2b9ae6f3-fdbf-429f-b9e5-3c952df23cf3	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 13:48:42.671912+00	2025-11-25 13:48:46.309396+00	1	SENT
52057f63-a7b8-4d49-8b59-fc910587977c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 13:49:03.640912+00	2025-11-25 13:49:06.44569+00	1	SENT
89ee7025-de32-4da5-9844-c9b84e09702c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 13:54:26.281542+00	2025-11-25 13:54:26.68864+00	1	SENT
fe2d5498-e7d8-46dc-9bfc-a156e63fb9df	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"LocLM","user_id":"2a04b41b-422f-455e-85c3-4c036e692b3c"}	2025-11-25 13:56:50.134592+00	2025-11-25 13:56:51.856908+00	1	SENT
01736623-d298-4a4d-9541-137393d9efd9	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"LocLM","user_id":"2a04b41b-422f-455e-85c3-4c036e692b3c"}	2025-11-25 13:58:18.828801+00	2025-11-25 13:58:22.005369+00	1	SENT
18b46099-d9e3-455c-990c-a73b134a502d	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 14:03:07.852618+00	2025-11-25 14:03:12.243795+00	1	SENT
9e821ca1-c0ab-467a-adec-83b9c141294f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"LocLM","user_id":"2a04b41b-422f-455e-85c3-4c036e692b3c"}	2025-11-25 14:03:24.22223+00	2025-11-25 14:03:27.361761+00	1	SENT
20edbd97-833e-4ceb-a8b2-c4c6e7ea29a1	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"d183363b-9926-4c45-b1d9-05ac2628d482"}	2025-11-25 14:09:15.594441+00	2025-11-25 14:09:17.602899+00	1	SENT
2b3b73fe-c37a-4d67-8d19-efcdf74d5370	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 14:24:55.141052+00	2025-11-25 14:24:58.383003+00	1	SENT
6792de5a-9bd4-47d3-9d7d-a7c6a8152ea5	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 14:25:07.873385+00	2025-11-25 14:25:08.500152+00	1	SENT
1b6d4c99-b0bc-4f1c-9d08-8be79e7a8bb2	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 14:26:39.864064+00	2025-11-25 14:26:43.933974+00	1	SENT
45f5a5d6-a36d-487a-840a-c7689d1c04d2	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"LocLM","user_id":"2a04b41b-422f-455e-85c3-4c036e692b3c"}	2025-11-25 14:47:22.633894+00	2025-11-25 14:47:24.537655+00	1	SENT
0772c710-3e3d-4a0f-9c1e-b015b3bffa32	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 15:31:05.606927+00	2025-11-25 15:31:10.625581+00	1	SENT
b2c220bc-cac6-4465-9fca-37d004e67c6a	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 15:45:08.065979+00	2025-11-25 15:45:11.078383+00	1	SENT
289fb4f0-678e-4ccd-ae8b-451c5fb6839f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-25 16:42:35.605358+00	2025-11-25 16:42:37.462456+00	1	SENT
d0c82588-1b25-48cf-93bc-3d2402a92b16	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 18:25:46.35009+00	2025-11-25 18:25:50.093013+00	1	SENT
79c512be-f57a-4243-9b6b-9a3549a45d8d	notify.exchange	lab.audit.events	{"event":"LOGIN_BLOCKED_LOCKED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 00:01:54.275726+00	2025-11-26 00:01:57.469538+00	1	SENT
0c6a3a83-cfd9-4738-956f-17e201038789	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 18:39:49.897909+00	2025-11-25 18:39:50.822352+00	1	SENT
27a4ca26-3dd2-40fd-a708-ad7b14588dd8	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"Hung","status":"all"}	2025-11-26 06:13:48.96261+00	2025-11-26 06:13:52.526345+00	1	SENT
231a4d56-cbc9-424e-be52-8ba5a5470467	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 19:00:57.344243+00	2025-11-25 19:01:01.683127+00	1	SENT
3057ea49-d89f-434c-acbf-dd4b2a95f18d	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 00:02:07.276823+00	2025-11-26 00:02:07.596887+00	1	SENT
f4141c48-0cea-4c70-b5e2-6e2a55fb82ea	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 19:15:01.003159+00	2025-11-25 19:15:02.127429+00	1	SENT
788f4e9c-237e-42b6-b52a-17398c1c3256	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 19:29:05.734304+00	2025-11-25 19:29:07.844931+00	1	SENT
d34af7e2-3603-4daf-912b-82c41769fbae	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 00:02:22.30488+00	2025-11-26 00:02:22.714487+00	1	SENT
22d3ac0d-3791-42f8-9f7a-48e27da8ed84	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 19:43:10.690479+00	2025-11-25 19:43:13.676726+00	1	SENT
f0592d93-9d77-4580-a15e-945f5d8823b6	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-25 19:57:16.012349+00	2025-11-25 19:57:19.119088+00	1	SENT
e2356fb0-44ec-45a4-a45f-1adb102e9e1c	notify.exchange	lab.audit.events	{"event":"USER_UNLOCKED","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 00:02:30.2481+00	2025-11-26 00:02:32.95277+00	1	SENT
37e8b5e2-77bd-4fdc-a15c-4c23987482de	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UNLOCK","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 00:02:30.263384+00	2025-11-26 00:02:33.064982+00	1	SENT
d9e78459-8b8b-432d-97b6-e2821e94f7bb	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 00:02:30.504538+00	2025-11-26 00:02:33.173825+00	1	SENT
046b100e-2620-445f-af93-a88cf9ae2ce3	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Hungtq","jti":"c7132a99-1fc8-449e-af94-4c0fb6301adb"}	2025-11-26 00:02:36.179549+00	2025-11-26 00:02:38.285372+00	1	SENT
f57ed535-7a0d-43cd-a079-508429ceea45	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 00:02:47.875813+00	2025-11-26 00:02:48.40102+00	1	SENT
ee1b9bb5-4059-4115-8799-2b6587c29f7c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 00:07:24.683232+00	2025-11-26 00:07:28.907478+00	1	SENT
96c4f7ab-bf10-4c71-a74d-96eb791576fa	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 01:37:42.519007+00	2025-11-26 01:37:46.995633+00	1	SENT
70142470-8a9d-424c-b28b-60f36658e4f2	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 01:39:03.601891+00	2025-11-26 01:39:07.143372+00	1	SENT
fb4728f8-dbb5-447d-885a-1453facdb7fc	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:10:29.774853+00	2025-11-26 02:10:30.019664+00	1	SENT
efe06b09-4348-4180-be54-8d2bdce32f6c	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":4,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:06.739171+00	2025-11-26 02:36:12.707014+00	1	SENT
db28e257-0e94-453a-aeef-8b2418e8d54e	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:06.741853+00	2025-11-26 02:36:12.816149+00	1	SENT
cef07438-81e2-434a-b297-7a38fdda0f44	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:07.058463+00	2025-11-26 02:36:12.923422+00	1	SENT
087d8b92-45c7-49bb-bf65-91409689fb17	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"1a70fda0-c3e5-47be-8188-86cb5ec856b3"}	2025-11-26 02:36:40.545555+00	2025-11-26 02:36:43.039748+00	1	SENT
1f97c549-985b-419b-8f58-e9c86a2b5c0c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:36:58.958462+00	2025-11-26 02:36:59.477355+00	1	SENT
cc087045-7a47-4192-b518-f2c4e75cead5	notify.exchange	lab.audit.events	{"event":"LOGIN_BLOCKED_LOCKED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:37:26.847817+00	2025-11-26 02:37:29.602779+00	1	SENT
2e5bbf38-eb74-41fb-b998-c80b178f58f4	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 02:37:51.497816+00	2025-11-26 02:37:54.733666+00	1	SENT
6f81beef-667d-4844-bcb9-46efca48cc7f	notify.exchange	lab.audit.events	{"event":"USER_UNLOCKED","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:38:00.618903+00	2025-11-26 02:38:04.960528+00	1	SENT
a7d24a71-5fac-4bcb-a9e4-9c0bf76d4ab2	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UNLOCK","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:38:00.62609+00	2025-11-26 02:38:05.069856+00	1	SENT
3751d579-3276-4b79-925c-b3c62072fdee	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 02:38:00.892496+00	2025-11-26 02:38:05.178451+00	1	SENT
6101aaea-1cbe-4048-aef3-4c4e18ad462f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:38:05.04643+00	2025-11-26 02:38:10.296261+00	1	SENT
a9847f7c-4913-4683-bac5-f01d69981db4	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:39:00.0607+00	2025-11-26 02:39:00.430152+00	1	SENT
270ea295-4a42-43ca-a18e-412fbf4004a4	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 02:44:52.589569+00	2025-11-26 02:44:55.789317+00	1	SENT
fd0947c0-f7b0-479e-9dc6-cd974453068e	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"HungNQ","user_id":"ef8716fc-d175-4c54-870d-1c9313405fd0"}	2025-11-26 02:44:55.174568+00	2025-11-26 02:44:56.005582+00	1	SENT
141e9716-8492-4992-b2c2-2ee9d52b20dd	notify.exchange	lab.audit.events	{"event":"USER_UPDATED","user_id":"ef8716fc-d175-4c54-870d-1c9313405fd0"}	2025-11-26 02:45:05.412152+00	2025-11-26 02:45:06.118021+00	1	SENT
a2b85c43-0d09-48fa-b2a7-6f034be629d0	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","username":"HungNQ","user_id":"ef8716fc-d175-4c54-870d-1c9313405fd0"}	2025-11-26 02:45:05.426626+00	2025-11-26 02:45:06.224686+00	1	SENT
66d50c41-620f-4659-8ef2-9c46fb6670cc	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:54:33.946788+00	2025-11-26 02:54:37.268553+00	1	SENT
758a8d94-cdaa-4522-81a4-fc15b5f844e0	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:55:41.817418+00	2025-11-26 02:55:42.684905+00	1	SENT
9932f183-c5e0-45af-878e-3c451023e62a	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 02:56:01.419751+00	2025-11-26 02:56:02.808356+00	1	SENT
eec19508-d338-4621-a1ca-fdc1eac1ad0b	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 02:56:04.72655+00	2025-11-26 02:56:07.931796+00	1	SENT
c5880376-cc7a-487d-97d6-ef331dcf4868	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Hungtq","jti":"b1a58a20-5d39-42bb-b8c2-44c2627044ec"}	2025-11-26 02:56:11.513264+00	2025-11-26 02:56:13.050404+00	1	SENT
26eda948-a49b-4e53-a206-bfbd2f994bf8	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 02:56:14.178819+00	2025-11-26 02:56:18.184901+00	1	SENT
ca46401a-1304-4b5a-8108-31e8bf4bec87	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:56:18.463404+00	2025-11-26 02:56:23.298595+00	1	SENT
edae3609-7cc0-4d88-ba5c-42e443b598c1	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 02:57:44.548354+00	2025-11-26 02:57:48.440433+00	1	SENT
0e58a7a6-139f-4542-be64-9f0dfa5eb104	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 03:07:40.052774+00	2025-11-26 03:07:43.807105+00	1	SENT
1320ac53-9625-4311-9349-f4ec7b0a2ce5	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 03:12:40.660114+00	2025-11-26 03:12:44.093461+00	1	SENT
a30992d4-e301-47f4-bb1e-c807b29d8bdb	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 03:18:48.145076+00	2025-11-26 03:18:49.632371+00	1	SENT
d20e9206-428b-4c0f-b4b8-2f381e750952	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 03:21:44.435029+00	2025-11-26 03:21:44.850909+00	1	SENT
a82e5842-474b-45ae-92e5-f2b5971e9e7a	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 03:26:42.828335+00	2025-11-26 03:26:45.10195+00	1	SENT
e3689497-1f23-4a0e-95af-8f734a704317	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 03:29:41.118708+00	2025-11-26 03:29:45.306064+00	1	SENT
d7a7a50f-0091-4c3e-9289-1e5a6af30aeb	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 03:37:33.620582+00	2025-11-26 03:37:35.670452+00	1	SENT
bc250b22-2030-410b-bd00-a84c989e928a	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 03:46:42.428254+00	2025-11-26 03:46:46.045815+00	1	SENT
75099076-40e6-4d77-891e-73fe37e4fed5	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 04:01:40.015913+00	2025-11-26 04:01:41.58412+00	1	SENT
2c196381-a434-4710-91f5-7b9d87e311a5	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 04:02:44.168079+00	2025-11-26 04:02:47.041593+00	1	SENT
0551894b-7e64-44e0-b704-29e4cc7fb77e	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 04:02:54.879562+00	2025-11-26 04:02:57.173018+00	1	SENT
1d801151-6484-4c54-80c4-dbe2d0b50e35	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 04:03:22.407805+00	2025-11-26 04:03:27.321866+00	1	SENT
769110bd-4754-4d24-bb31-fd837ebce21a	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"PhatNT","jti":"54843567-72ba-402f-96dd-400c6420f528"}	2025-11-26 04:04:19.230799+00	2025-11-26 04:04:22.486741+00	1	SENT
d26ca26d-6bb4-41f1-ae06-aad86d2dbccb	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"b46b4c47-31c6-4ad2-9829-0332963bb646"}	2025-11-26 04:04:53.901531+00	2025-11-26 04:04:57.914453+00	1	SENT
332e7317-c8c1-4bc3-aeee-089a54b33594	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"minhbao","user_id":"b46b4c47-31c6-4ad2-9829-0332963bb646"}	2025-11-26 04:04:53.902737+00	2025-11-26 04:04:58.043816+00	1	SENT
71332681-bbe1-4a41-9ac1-91c9cac17f9f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"minhbao","user_id":"b46b4c47-31c6-4ad2-9829-0332963bb646"}	2025-11-26 04:04:56.031282+00	2025-11-26 04:04:58.174222+00	1	SENT
e054cc9f-70e0-4df4-b016-952fc5b5a4a5	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 04:16:56.511921+00	2025-11-26 04:16:58.593054+00	1	SENT
12e8f22d-702a-497e-83b5-ce95d2384d25	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 04:20:13.255371+00	2025-11-26 04:20:13.80998+00	1	SENT
ced2b6a9-1359-4cc3-85b7-a5acd2256d56	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 04:20:33.028513+00	2025-11-26 04:20:33.950428+00	1	SENT
12c99766-c51a-4d03-a4c8-b7aefa28315e	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 04:21:57.141004+00	2025-11-26 04:21:59.127694+00	1	SENT
2b8a3665-b987-4037-91ef-c05c53f86691	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 04:21:57.141949+00	2025-11-26 04:21:59.261432+00	1	SENT
a97633ae-264c-4cf7-af45-b65f2981c8ea	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 04:22:07.916952+00	2025-11-26 04:22:09.39637+00	1	SENT
547378ba-2aa1-461d-8ebf-7233535c51da	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 04:31:26.845465+00	2025-11-26 04:31:29.734946+00	1	SENT
68695485-2b86-48ce-81b3-638219b3e12e	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 04:37:16.725218+00	2025-11-26 04:37:20.009162+00	1	SENT
906df7c2-9310-4474-9f73-8b4407694db5	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 04:37:16.726727+00	2025-11-26 04:37:20.141617+00	1	SENT
ba64e6d3-c58a-435f-acaf-860847e042e7	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 04:37:27.411071+00	2025-11-26 04:37:30.270422+00	1	SENT
293000a8-3717-47ae-83c4-7095d0d363eb	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"b2dc17a7-8e49-41b8-b37e-626c7a7b8100"}	2025-11-26 04:41:39.638861+00	2025-11-26 04:41:40.504843+00	1	SENT
fbf2143c-c9f6-4f3d-bb0c-52afd7e11d97	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 04:41:40.822738+00	2025-11-26 04:41:45.635961+00	1	SENT
9fa5bd98-5248-4a57-8a0c-da8e91569bb2	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 04:41:52.199915+00	2025-11-26 04:41:55.764149+00	1	SENT
fcc75b0d-0836-4f28-8bbe-0d21bfe01d84	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 04:41:56.684719+00	2025-11-26 04:42:00.894364+00	1	SENT
de0a76d6-2df1-4963-86aa-70bde3490628	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 04:42:00.263647+00	2025-11-26 04:42:01.026014+00	1	SENT
975a671c-d6de-45c5-94b3-6a5ec1b03cd4	notify.exchange	lab.audit.events	{"event":"USER_CREATED_BY_ADMIN","username":"AnTV","user_id":"76f0e8e4-687f-4f7f-b2c4-b76fa8588ad6"}	2025-11-26 04:43:56.110937+00	2025-11-26 04:44:01.365621+00	1	SENT
7ceb82a0-8c57-48fe-9a2f-1f4b50f033da	notify.exchange	lab.audit.events	{"page":"0","role":"LAB_MANAGER","size":"10","event":"ADMIN_USERS_LIST","q":"Hung","status":"all"}	2025-11-26 06:13:55.73161+00	2025-11-26 06:13:57.659492+00	1	SENT
c29e7afe-884e-49f7-943d-1f320dbb2e5a	notify.exchange	lab.notify.queue	{"template":"welcome","variables":{"model":{"password":"Hg4g?BD9","fullName":"Trần Vỹ An","username":"AnTV"}},"subject":"Welcome","to":{"email":"hungtranxpf@localhost.com"}}	2025-11-26 04:43:56.105935+00	2025-11-26 04:44:01.231651+00	1	SENT
ee192568-8feb-4323-8c62-6e9893830358	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_CREATE","username":"AnTV","user_id":"76f0e8e4-687f-4f7f-b2c4-b76fa8588ad6"}	2025-11-26 04:43:56.1469+00	2025-11-26 04:44:01.493469+00	1	SENT
c7cd181a-40c8-4abf-833f-d48e8969b84e	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_WELCOME","user_id":"76f0e8e4-687f-4f7f-b2c4-b76fa8588ad6"}	2025-11-26 04:44:00.57415+00	2025-11-26 04:44:01.621367+00	1	SENT
46c3f722-bba6-43e1-aaa2-69f4b02c90c6	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"Hung","status":"all"}	2025-11-26 06:13:57.747525+00	2025-11-26 06:14:02.791409+00	1	SENT
bdb24704-46f8-4fe9-8278-0e40165cb11f	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 05:20:06.621094+00	2025-11-26 05:20:07.818035+00	1	SENT
f90a0a8d-1118-4ce9-858c-b3c75cf4ef29	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 05:20:06.625662+00	2025-11-26 05:20:07.949148+00	1	SENT
287f6e3d-8ebf-454e-ad79-5c069a8f396f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 05:20:12.207032+00	2025-11-26 05:20:13.075432+00	1	SENT
721ca76d-6fb2-4fae-bc9a-81704bb2209b	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 05:29:16.183393+00	2025-11-26 05:29:18.710725+00	1	SENT
2d60f6bf-e813-4419-8d7a-93b427173d77	notify.exchange	lab.notify.queue	{"template":"welcome","variables":{"model":{"password":"<]N5L5aU","fullName":"Trần Vũ Long","username":"LongTV"}},"subject":"Welcome","to":{"email":"nhath9470@gmail.com"}}	2025-11-26 06:16:58.704854+00	2025-11-26 06:17:03.004601+00	1	SENT
697c1672-57bd-4c58-bc48-7499b414d7c2	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"8a27fb22-5947-4cae-9fa2-fb6aec99dede"}	2025-11-26 05:32:12.944549+00	2025-11-26 05:32:13.938343+00	1	SENT
21f28eba-3ed5-439c-9b3d-22b88c201064	notify.exchange	lab.audit.events	{"event":"USER_CREATED_BY_ADMIN","username":"LongTV","user_id":"48eb3a7e-8ddb-4416-a6a8-a6f49033e362"}	2025-11-26 06:16:58.707582+00	2025-11-26 06:17:03.132488+00	1	SENT
47c6fcb1-1b04-47d0-9437-b9cc28f8ce2d	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 05:35:34.135977+00	2025-11-26 05:35:39.171856+00	1	SENT
a670e19b-3dc9-48b6-beec-234f8d55e2ae	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_CREATE","username":"LongTV","user_id":"48eb3a7e-8ddb-4416-a6a8-a6f49033e362"}	2025-11-26 06:16:58.726822+00	2025-11-26 06:17:03.257961+00	1	SENT
19e8e74a-ddbc-4821-95b5-2cc9dcc3027f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 05:35:59.091719+00	2025-11-26 05:35:59.315782+00	1	SENT
e5d85182-0a74-44fd-ab21-0aa92e1c6925	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 05:37:52.180276+00	2025-11-26 05:37:54.507849+00	1	SENT
588348b1-6857-46ee-8809-2a968bb0b9c3	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_WELCOME","user_id":"48eb3a7e-8ddb-4416-a6a8-a6f49033e362"}	2025-11-26 06:17:03.504676+00	2025-11-26 06:17:08.387137+00	1	SENT
30b04cfd-a581-4a39-a9a0-a56f82a736cc	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 05:39:22.068418+00	2025-11-26 05:39:24.66661+00	1	SENT
61f5dfbd-cf6e-42e0-b46b-d9401a8b4536	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 05:44:15.635541+00	2025-11-26 05:44:19.931345+00	1	SENT
43dbdc53-d35f-4032-882e-58022dc0643f	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"ThanhNT","jti":"1d7b6e80-1722-4916-b012-532e56a47dfe"}	2025-11-26 05:46:07.22533+00	2025-11-26 05:46:10.120978+00	1	SENT
6da46168-aaea-4094-b1fc-cab5f92c9024	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 06:17:25.539562+00	2025-11-26 06:17:28.525559+00	1	SENT
0e616454-f688-43cf-b503-5d10d2e1dd4c	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 05:46:23.34899+00	2025-11-26 05:46:25.270046+00	1	SENT
73fa57e5-bba1-4ba7-bd07-5a4aa150da21	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 05:50:03.169095+00	2025-11-26 05:50:05.505444+00	1	SENT
2a845b29-61e3-477e-b766-19c66eb31757	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 06:17:25.790265+00	2025-11-26 06:17:28.66237+00	1	SENT
69f3efda-3008-4346-98fc-51582c4868c7	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 05:51:55.462129+00	2025-11-26 05:51:55.705447+00	1	SENT
8c0e2b48-c9d9-47b4-9572-7c98d729fde0	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 05:55:26.374392+00	2025-11-26 05:55:31.202166+00	1	SENT
1a0ede8e-eb8c-49a6-a181-f9def24a829a	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"LongTV","user_id":"48eb3a7e-8ddb-4416-a6a8-a6f49033e362"}	2025-11-26 06:17:28.581462+00	2025-11-26 06:17:33.808227+00	1	SENT
aecd9ccc-28b4-4b49-afd9-6e9b253a95b0	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"LongTV","user_id":"48eb3a7e-8ddb-4416-a6a8-a6f49033e362"}	2025-11-26 06:17:28.835577+00	2025-11-26 06:17:33.943039+00	1	SENT
1248daea-a890-485b-b459-73570fd312b2	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:12:18.265598+00	2025-11-26 06:12:21.712008+00	1	SENT
4152ed58-0ca9-4c84-8087-81d9711fb75f	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:12:18.267079+00	2025-11-26 06:12:21.84943+00	1	SENT
3a711370-7e13-4736-bbf7-336d1fe1063f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:12:24.399118+00	2025-11-26 06:12:26.979417+00	1	SENT
d988372d-c00d-48d9-a309-70ebc0a73129	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 06:12:40.640839+00	2025-11-26 06:12:42.110601+00	1	SENT
2efaacfb-c9f2-44de-aa09-6db91202e3bd	notify.exchange	lab.audit.events	{"event":"USER_UPDATED","user_id":"48eb3a7e-8ddb-4416-a6a8-a6f49033e362"}	2025-11-26 06:18:01.765899+00	2025-11-26 06:18:04.094424+00	1	SENT
ebabd0a8-1aef-4982-81a8-0809aab15f95	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UPDATE","username":"LongTV","user_id":"48eb3a7e-8ddb-4416-a6a8-a6f49033e362"}	2025-11-26 06:18:01.771764+00	2025-11-26 06:18:04.22644+00	1	SENT
17906a56-ae82-4078-9fb7-d2497ec53501	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 06:18:03.692993+00	2025-11-26 06:18:04.357362+00	1	SENT
d3f00446-45c8-4588-9998-2de75f8b8bdc	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 06:18:03.951483+00	2025-11-26 06:18:04.487354+00	1	SENT
95708d30-97bf-40f1-98b1-520ae34c374a	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_BAN","reason":"Disabled by administrator","user_id":"76f0e8e4-687f-4f7f-b2c4-b76fa8588ad6"}	2025-11-26 06:18:47.86618+00	2025-11-26 06:18:49.762409+00	1	SENT
776656f9-e3f3-496a-b908-9938eb578bea	notify.exchange	lab.audit.events	{"event":"USER_BANNED","reason":"Disabled by administrator","user_id":"76f0e8e4-687f-4f7f-b2c4-b76fa8588ad6"}	2025-11-26 06:18:47.857569+00	2025-11-26 06:18:49.628857+00	1	SENT
ffa1f555-ee87-4017-8c0d-debc4f46b8e1	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 06:18:48.19052+00	2025-11-26 06:18:49.88872+00	1	SENT
3e8aa882-0dcc-4ddc-a8f3-5c012de0c082	notify.exchange	lab.audit.events	{"event":"USER_UNBANNED","user_id":"76f0e8e4-687f-4f7f-b2c4-b76fa8588ad6"}	2025-11-26 06:19:01.803923+00	2025-11-26 06:19:05.030967+00	1	SENT
30688aae-77eb-49bc-84a0-b821a3025120	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_UNBAN","user_id":"76f0e8e4-687f-4f7f-b2c4-b76fa8588ad6"}	2025-11-26 06:19:01.809018+00	2025-11-26 06:19:05.16076+00	1	SENT
14de2730-db58-4dcd-b5fd-fc654fa3945d	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 06:19:02.062164+00	2025-11-26 06:19:05.303201+00	1	SENT
8d2a53db-f95a-4346-a4b0-7aa9309c663a	notify.exchange	lab.audit.events	{"role_code":"STAFFLAB","event":"ROLE_CREATED"}	2025-11-26 06:20:35.325391+00	2025-11-26 06:20:40.774488+00	1	SENT
28f121f2-a725-4872-8e49-63f4ec01687c	notify.exchange	lab.audit.events	{"role_id":"c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e","event":"ROLE_UPDATED"}	2025-11-26 06:20:52.036933+00	2025-11-26 06:20:55.909345+00	1	SENT
cccc68bd-a21c-409e-aee8-aa5061515c6c	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:21:09.321585+00	2025-11-26 06:21:11.04858+00	1	SENT
220dbc3d-6eac-4722-ab19-311c843ca8e4	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:21:15.100538+00	2025-11-26 06:21:16.17699+00	1	SENT
11227b0d-2590-4a99-af13-0bb23ca19f28	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:21:15.357052+00	2025-11-26 06:21:16.301975+00	1	SENT
cabeb6c7-190f-4956-88fb-f0af355070fe	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:21:47.657942+00	2025-11-26 06:21:51.729378+00	1	SENT
fe20beef-c2a9-4600-a3ef-a6bbeacb1d79	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:21:48.132822+00	2025-11-26 06:21:51.858573+00	1	SENT
d01a36a3-dbc5-4907-9d89-a3540f14f581	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:21:51.260502+00	2025-11-26 06:21:51.99135+00	1	SENT
24aab21f-2322-4110-a498-6065f7a054df	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:21:51.514864+00	2025-11-26 06:21:57.124574+00	1	SENT
70436e4e-88fe-47cb-a8c6-a633cf2e6e0a	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:21:59.164582+00	2025-11-26 06:22:02.252613+00	1	SENT
2d70b336-bf69-4b9c-93a1-366eba037b7a	notify.exchange	lab.audit.events	{"event":"PROFILE_PASSWORD_CHANGED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:22:36.149712+00	2025-11-26 06:22:37.682432+00	1	SENT
78b5bbb0-e156-4d7b-84de-63fdbb001887	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:23:03.480106+00	2025-11-26 06:23:07.835448+00	1	SENT
b8ae55e3-3c36-4195-a111-e1eb3a9c7cae	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 06:23:06.519615+00	2025-11-26 06:23:07.964973+00	1	SENT
a3ac6f48-445a-4b92-b334-55d409ac02da	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:23:32.411518+00	2025-11-26 06:23:33.150369+00	1	SENT
b211c0d3-df90-4657-a68f-eb8735183d97	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:23:51.121454+00	2025-11-26 06:23:53.297368+00	1	SENT
817dbb71-f1e3-4eb4-86ab-5f377bf62317	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 06:23:51.385033+00	2025-11-26 06:23:53.429719+00	1	SENT
3d6b60af-1513-47f0-952b-58fb642e4787	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"Hungtq","jti":"7fcf8831-ebb9-42a9-b61d-bce80a389d29"}	2025-11-26 06:24:02.484076+00	2025-11-26 06:24:03.565026+00	1	SENT
482c19d9-4b30-4493-83da-3dad42823b25	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 06:24:49.519793+00	2025-11-26 06:24:53.721422+00	1	SENT
9fa99170-aecc-4a48-9933-a25862aacd1c	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 06:38:51.98794+00	2025-11-26 06:38:54.170673+00	1	SENT
b5743693-6760-462a-a5ba-3743a8a5f7ee	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 06:53:25.322192+00	2025-11-26 06:53:29.672443+00	1	SENT
7c52b3f1-51dd-40bd-be18-4684607f7d47	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 06:59:16.017143+00	2025-11-26 06:59:19.960704+00	1	SENT
fd6b5aae-2a1c-4aad-b5ac-b49f2e3c12d6	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 07:00:24.597114+00	2025-11-26 07:00:25.419361+00	1	SENT
88e60cf3-0538-4003-9918-49ea7350970b	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 07:01:29.299973+00	2025-11-26 07:01:30.871483+00	1	SENT
9e0bae69-bcee-4d22-84a7-c3e4ae012113	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 07:01:39.246323+00	2025-11-26 07:01:40.999476+00	1	SENT
e0890fb7-845d-44ed-9544-ece34daa98c9	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 07:03:31.331687+00	2025-11-26 07:03:36.194732+00	1	SENT
a282c2ce-ea78-4bb8-be9f-8d9d111d4f7d	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 07:03:31.567539+00	2025-11-26 07:03:36.339512+00	1	SENT
ce41ec3f-bb52-4ba0-aa8d-a1d90a71f0d7	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"BaoNPG","jti":"f979670c-62f0-4931-9c49-014634fb8306"}	2025-11-26 07:03:52.847166+00	2025-11-26 07:03:56.50157+00	1	SENT
659d62ac-fde3-4072-abda-4276694134bd	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 07:13:45.039185+00	2025-11-26 07:13:46.854017+00	1	SENT
6e3c6656-e58b-4762-8ff3-8ef366979fee	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 07:14:34.173756+00	2025-11-26 07:14:37.003722+00	1	SENT
1464ea70-1466-4880-acb0-ef0849a1cb4f	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":1,"user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 07:21:32.437627+00	2025-11-26 07:21:37.323644+00	1	SENT
c18ec6d5-65d9-4bcd-b096-d1750f18b4ff	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 07:21:32.441279+00	2025-11-26 07:21:37.452875+00	1	SENT
e8661d33-ea47-494b-b58c-51fb34556d0d	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED","attempts":2,"user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 07:21:38.314424+00	2025-11-26 07:21:42.579141+00	1	SENT
a2cbbb2f-aa0d-42f3-ad44-a8e571bb2f76	notify.exchange	lab.audit.events	{"event":"LOGIN_FAILED_BAD_PASSWORD","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 07:21:38.315573+00	2025-11-26 07:21:42.704403+00	1	SENT
85d50aa3-f828-4c31-b2a9-2ca625ae7718	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 07:21:43.984153+00	2025-11-26 07:21:47.8324+00	1	SENT
df327500-2756-4140-91f3-f0d7f49b9695	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 07:21:47.662065+00	2025-11-26 07:21:47.956306+00	1	SENT
cabc0347-1352-4876-a598-f18fc1039af2	notify.exchange	lab.audit.events	{"event":"PROFILE_VIEWED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 07:21:51.3137+00	2025-11-26 07:21:53.084405+00	1	SENT
c7f80793-dcbe-463b-911f-4c8d1f637252	notify.exchange	lab.audit.events	{"event":"PROFILE_PASSWORD_CHANGED","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 07:22:07.357829+00	2025-11-26 07:22:08.217426+00	1	SENT
e9060462-aca7-490c-9b04-f009e270238e	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 07:22:23.989856+00	2025-11-26 07:22:28.350879+00	1	SENT
1afeba81-5069-4849-b70e-f60ddef433a3	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 07:22:27.475049+00	2025-11-26 07:22:28.476271+00	1	SENT
4c4950c2-75dd-4b3a-b174-d60135166d6d	notify.exchange	lab.audit.events	{"event":"USER_DELETED","username":"LongTV","user_id":"48eb3a7e-8ddb-4416-a6a8-a6f49033e362"}	2025-11-26 07:22:33.929457+00	2025-11-26 07:22:38.603913+00	1	SENT
97c75440-bf7a-422e-9675-6bed5daad27b	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_DELETE","user_id":"48eb3a7e-8ddb-4416-a6a8-a6f49033e362"}	2025-11-26 07:22:33.937584+00	2025-11-26 07:22:38.72935+00	1	SENT
b942af7c-bc2c-436a-8f63-8734608ed200	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 07:22:34.334812+00	2025-11-26 07:22:38.852669+00	1	SENT
7722b747-d179-4bc5-bb70-e063277c11bd	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 07:23:05.209478+00	2025-11-26 07:23:08.993877+00	1	SENT
5e106373-30f3-41c4-81fd-426980715b03	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 07:23:05.477656+00	2025-11-26 07:23:09.124393+00	1	SENT
d853f431-3dcc-4113-be26-5274b793a35c	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 07:23:25.420533+00	2025-11-26 07:23:29.270402+00	1	SENT
6d7cdb2a-5797-4a5e-898a-86349f9d8b4f	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 07:23:29.022739+00	2025-11-26 07:23:29.400977+00	1	SENT
5687a9ce-c342-41c3-8e7e-9291464fb90a	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 07:28:36.252906+00	2025-11-26 07:28:39.658929+00	1	SENT
86e32dc8-726e-453d-bfc2-b78faf88416d	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 07:28:37.520588+00	2025-11-26 07:28:39.791853+00	1	SENT
49e27ddd-6540-4efa-b256-b0fabf40507a	notify.exchange	lab.audit.events	{"event":"ADMIN_USER_GET","username":"BaoNPG","user_id":"cd23d611-1644-4d29-b7b3-100f9458018c"}	2025-11-26 07:29:19.594073+00	2025-11-26 07:29:19.942428+00	1	SENT
8a50f564-c5b0-4f5e-9439-1e8500d70fdc	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 07:29:19.676874+00	2025-11-26 07:29:20.065217+00	1	SENT
8411af7a-ee58-4842-a3d3-fd388540b339	notify.exchange	lab.audit.events	{"event":"LOGOUT_NO_TOKEN"}	2025-11-26 07:38:04.984496+00	2025-11-26 07:38:05.695445+00	1	SENT
86b847e9-8c05-426c-8e1b-687848b54b16	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 07:42:43.206891+00	2025-11-26 07:42:46.231821+00	1	SENT
cf3b501c-ed87-4c07-b8ec-4155e3827864	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 07:47:03.003791+00	2025-11-26 07:47:06.487486+00	1	SENT
c76a856a-55bc-4e85-9441-0685e01d06d9	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"PhatNT","user_id":"987fa969-961f-4afb-98aa-636c3448bd87"}	2025-11-26 07:56:48.522247+00	2025-11-26 07:56:51.870935+00	1	SENT
36d564f6-c856-4b40-a3dc-09cc7d1fd91c	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 08:01:06.637684+00	2025-11-26 08:01:07.109724+00	1	SENT
8525f3de-d23b-4346-bc29-05d4539ba1ea	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 08:16:22.596233+00	2025-11-26 08:16:27.594126+00	1	SENT
79b8f6ba-6a72-49c1-8e9b-a184375c1120	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"Hungtq","user_id":"4135dbcc-c6fb-4781-afb3-90ee621dd9f4"}	2025-11-26 08:29:26.609148+00	2025-11-26 08:29:28.023433+00	1	SENT
14ba825d-c20e-4fef-9407-14f5e76fa770	notify.exchange	lab.audit.events	{"page":"0","role":"","size":"10","event":"ADMIN_USERS_LIST","q":"","status":"all"}	2025-11-26 08:29:29.847511+00	2025-11-26 08:29:33.171433+00	1	SENT
820fbb11-0eb2-4de0-b5d8-88b51ec70d3b	notify.exchange	lab.audit.events	{"event":"TOKEN_REFRESHED","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 08:30:24.971694+00	2025-11-26 08:30:28.316398+00	1	SENT
53d7495b-1fcc-4430-b72b-00f0e78898b7	notify.exchange	lab.audit.events	{"event":"LOGOUT","username":"ThanhNT","jti":"145e7aab-8313-4348-9159-42bd200d2c96"}	2025-11-26 08:43:58.138979+00	2025-11-26 08:43:58.786532+00	1	SENT
29a51052-c5cd-434b-a783-f6875f6be41b	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 08:44:00.273783+00	2025-11-26 08:44:03.931469+00	1	SENT
ce045d98-bfc2-4e65-b7ab-be4d364a09f6	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 09:00:25.656243+00	2025-11-26 09:00:29.478869+00	1	SENT
7129f417-c143-4f02-9857-b9371a40b855	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 09:01:08.777164+00	2025-11-26 09:01:09.630202+00	1	SENT
57d6c5c2-5bc9-4a7a-85c1-f54f1cddfd9f	notify.exchange	lab.audit.events	{"event":"LOGIN_SUCCESS","username":"ThanhNT","user_id":"c1d918d1-18d8-4837-a271-967d90f569a3"}	2025-11-26 09:04:01.68353+00	2025-11-26 09:04:04.85953+00	1	SENT
\.


--
-- TOC entry 3778 (class 0 OID 33028)
-- Dependencies: 224
-- Data for Name: privilege_screen; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.privilege_screen (privilege_id, screen_id, action_code, is_active, created_at, updated_at) FROM stdin;
faeaecd0-6dfd-46bf-b0cf-6862ea800890	7dd66b97-b412-4f46-b5e4-a8f0d8146be6	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
183c05fc-cd78-403b-8f5a-dd026a1122d3	7c66ed4b-76f7-4617-a058-bdd609829946	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
c9604fc2-9c8a-4c0c-b973-1f48378bbcd4	7c66ed4b-76f7-4617-a058-bdd609829946	CREATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
4df6d823-e27b-4039-9c99-ef950664b418	7c66ed4b-76f7-4617-a058-bdd609829946	UPDATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
a7dc0f69-59e6-4228-b5f2-78fdbbe58707	7c66ed4b-76f7-4617-a058-bdd609829946	DELETE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
7b8123ce-4091-4d5b-9733-6ae53710040a	7c66ed4b-76f7-4617-a058-bdd609829946	APPROVE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
197480b6-56e5-451f-bc2d-d9a3908abe85	7c66ed4b-76f7-4617-a058-bdd609829946	EXPORT	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
7e487309-ac5c-4223-abb3-a1cf1007d4ad	079787f7-bd41-4f97-afe4-da3805083f06	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
b0534608-9be9-4343-8bd7-f09b36df1d2a	079787f7-bd41-4f97-afe4-da3805083f06	CREATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
85cd9809-2aa6-4164-ab59-b5bb84e77746	079787f7-bd41-4f97-afe4-da3805083f06	UPDATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
cd944cee-9a4b-4ef7-a952-c30d048a86ab	079787f7-bd41-4f97-afe4-da3805083f06	DELETE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
7dd0003f-a9bb-4f9a-8fef-6574b8dc18a3	0f17109c-27d6-434b-a717-e7a5f62c2ba6	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
77cb55f9-c0de-4887-9bbe-3192e0110b48	72579e1e-934a-402e-86fe-8a50b2132788	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
ae861974-9e7d-49da-af85-1f80c2614f2d	72579e1e-934a-402e-86fe-8a50b2132788	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
db82b74c-5364-4818-a567-eafa8c98303c	72579e1e-934a-402e-86fe-8a50b2132788	APPROVE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
197480b6-56e5-451f-bc2d-d9a3908abe85	72579e1e-934a-402e-86fe-8a50b2132788	EXPORT	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
d5ed06c2-bc5a-4c54-ac79-890689344d6f	f5d7a587-028f-4283-bf60-252f8092e816	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
a995e224-4f27-402e-a0ce-d1cd93ee9673	f5d7a587-028f-4283-bf60-252f8092e816	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
3de0222f-006a-4bb5-b579-53113f15a455	f5d7a587-028f-4283-bf60-252f8092e816	CREATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
3eca6b24-ac69-49b8-b1f2-d39413b47098	f5d7a587-028f-4283-bf60-252f8092e816	CREATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
afedd297-90a6-4301-a948-760abfff586d	f5d7a587-028f-4283-bf60-252f8092e816	UPDATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
7d3a8dfd-68a8-435c-8653-555ac23197d3	f5d7a587-028f-4283-bf60-252f8092e816	UPDATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
dfd1216f-7c06-4e82-8839-cf4c0aac41f1	f5d7a587-028f-4283-bf60-252f8092e816	APPROVE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
77cb55f9-c0de-4887-9bbe-3192e0110b48	58d8c021-89f9-422c-b164-23a91840172d	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
3de0222f-006a-4bb5-b579-53113f15a455	58d8c021-89f9-422c-b164-23a91840172d	CREATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
95d8769a-eb52-4346-b175-1ecd4d235b48	58d8c021-89f9-422c-b164-23a91840172d	CREATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
afedd297-90a6-4301-a948-760abfff586d	58d8c021-89f9-422c-b164-23a91840172d	UPDATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
396b577b-36af-42e4-8103-46717b6611d4	58d8c021-89f9-422c-b164-23a91840172d	UPDATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
b7cf08b2-86bf-4c20-9a2a-93e3f0634db1	58d8c021-89f9-422c-b164-23a91840172d	DELETE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
ae861974-9e7d-49da-af85-1f80c2614f2d	96b972b2-22da-474e-9ab4-4233362e4759	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
d5ed06c2-bc5a-4c54-ac79-890689344d6f	96b972b2-22da-474e-9ab4-4233362e4759	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
3feb5a19-d45c-451f-8de3-88965a3ce576	96b972b2-22da-474e-9ab4-4233362e4759	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
3eca6b24-ac69-49b8-b1f2-d39413b47098	96b972b2-22da-474e-9ab4-4233362e4759	CREATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
7d3a8dfd-68a8-435c-8653-555ac23197d3	96b972b2-22da-474e-9ab4-4233362e4759	UPDATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
011748ae-74a0-42e5-baa3-3dda8ac90ccc	96b972b2-22da-474e-9ab4-4233362e4759	UPDATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
128531c7-903d-43e4-814d-895bd0bea3fe	96b972b2-22da-474e-9ab4-4233362e4759	UPDATE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
2ef43e9d-0eac-49c7-bd70-78bde0e9d689	96b972b2-22da-474e-9ab4-4233362e4759	DELETE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
622c94fc-23ab-496a-a659-d07ed4c1d9d1	96b972b2-22da-474e-9ab4-4233362e4759	APPROVE	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
77cb55f9-c0de-4887-9bbe-3192e0110b48	20d331a2-8a9c-4ae1-86e4-2be0697f7d5e	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
faeaecd0-6dfd-46bf-b0cf-6862ea800890	53b7e3f3-987f-445b-9daf-fb99fd9d5b58	VIEW	t	2025-11-03 02:12:10.914938+00	2025-11-03 02:12:10.914938+00
183c05fc-cd78-403b-8f5a-dd026a1122d3	65bb4df8-95bf-40af-9ff0-412ccc1bcf38	VIEW	t	2025-11-03 15:22:56.236771+00	2025-11-03 15:22:56.236771+00
c9604fc2-9c8a-4c0c-b973-1f48378bbcd4	65bb4df8-95bf-40af-9ff0-412ccc1bcf38	CREATE	t	2025-11-03 15:22:56.236771+00	2025-11-03 15:22:56.236771+00
183c05fc-cd78-403b-8f5a-dd026a1122d3	0f17109c-27d6-434b-a717-e7a5f62c2ba6	VIEW	t	2025-11-04 07:55:03.443737+00	2025-11-04 07:55:03.443737+00
c9604fc2-9c8a-4c0c-b973-1f48378bbcd4	0f17109c-27d6-434b-a717-e7a5f62c2ba6	CREATE	t	2025-11-04 07:55:03.443737+00	2025-11-04 07:55:03.443737+00
33aacb02-322e-43b7-8425-435aa44a6df3	0f17109c-27d6-434b-a717-e7a5f62c2ba6	VIEW	t	2025-11-04 14:42:40.364249+00	2025-11-04 14:42:40.364249+00
4df6d823-e27b-4039-9c99-ef950664b418	56534673-1ddc-46c9-8699-9a76f122f19d	UPDATE	t	2025-11-04 15:06:42.926679+00	2025-11-04 15:06:42.926679+00
183c05fc-cd78-403b-8f5a-dd026a1122d3	56534673-1ddc-46c9-8699-9a76f122f19d	VIEW	t	2025-11-04 15:30:09.609315+00	2025-11-04 15:30:09.609315+00
e0f990cd-78d3-40a2-b753-21a381b12b60	079787f7-bd41-4f97-afe4-da3805083f06	UPDATE	t	2025-11-05 00:49:54.785283+00	2025-11-05 00:49:54.785283+00
e0f990cd-78d3-40a2-b753-21a381b12b60	079787f7-bd41-4f97-afe4-da3805083f06	DELETE	t	2025-11-05 00:49:54.785283+00	2025-11-05 00:49:54.785283+00
e0f990cd-78d3-40a2-b753-21a381b12b60	079787f7-bd41-4f97-afe4-da3805083f06	CREATE	t	2025-11-05 00:49:54.785283+00	2025-11-05 00:49:54.785283+00
76021b2a-b5ba-4db5-84ba-1b8d426d227b	67f680af-8c8c-4404-9bb8-81c290e0343e	VIEW	t	2025-11-06 03:09:47.277135+00	2025-11-06 03:09:47.277135+00
76021b2a-b5ba-4db5-84ba-1b8d426d227b	980e91cf-9b85-4dcd-8f82-c50083f227f6	VIEW	t	2025-11-06 03:09:47.277135+00	2025-11-06 03:09:47.277135+00
525da488-8586-4710-b584-4c5417be4361	b896c088-392c-45fe-baba-a4f6dc0bef6e	UPDATE	t	2025-11-06 03:09:47.277135+00	2025-11-06 03:09:47.277135+00
33e1c04b-8c5e-4cca-9ddc-fa3a850ab4ed	62e7e1c8-a0e6-4e72-8962-5671229388e7	UPDATE	t	2025-11-06 03:09:47.277135+00	2025-11-06 03:09:47.277135+00
37c5bff7-38fb-498e-b3a5-328b36b14b83	0b136c74-253b-4f8b-9df8-43a90a3b1b23	VIEW	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
b21b3404-ca22-4cd8-b358-537c2eea6540	0b136c74-253b-4f8b-9df8-43a90a3b1b23	CREATE	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
475cddfe-0b9d-488d-aa16-93bc51f0a9ac	59d3fac0-b2dc-4d10-b8d2-0bcbce2f2990	VIEW	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
afa4572f-fe95-4822-af5f-58e1e5bc265d	59d3fac0-b2dc-4d10-b8d2-0bcbce2f2990	UPDATE	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
6e8df40a-8c61-4499-a323-a1484fc728b4	59d3fac0-b2dc-4d10-b8d2-0bcbce2f2990	DELETE	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
b21b3404-ca22-4cd8-b358-537c2eea6540	e462d048-d39d-4f1f-972e-7a29ef5a98fa	CREATE	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
afa4572f-fe95-4822-af5f-58e1e5bc265d	bcb70224-04b4-4b91-bb34-c15f242143bf	UPDATE	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
e4d4f092-7149-4d54-bdd9-c3469e2fadc0	39a54aba-d1f1-4e02-ba27-115bd28153e1	VIEW	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
77379757-4023-4299-b90c-beecc8534924	39a54aba-d1f1-4e02-ba27-115bd28153e1	VIEW	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
afa4572f-fe95-4822-af5f-58e1e5bc265d	39a54aba-d1f1-4e02-ba27-115bd28153e1	UPDATE	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
6e8df40a-8c61-4499-a323-a1484fc728b4	39a54aba-d1f1-4e02-ba27-115bd28153e1	DELETE	t	2025-11-11 16:17:16.91073+00	2025-11-11 16:17:16.91073+00
37c5bff7-38fb-498e-b3a5-328b36b14b83	2becf3ac-043f-42c1-ae5b-7f19cf4c8d49	VIEW	t	2025-11-11 16:24:30.065328+00	2025-11-11 16:24:30.065328+00
45bec9a1-53b3-486d-b414-e2f5dc97fa7a	3b0d72a0-0392-4d02-a5b6-0c67d570223c	CREATE	t	2025-11-13 14:42:17.781136+00	2025-11-13 14:42:17.781136+00
8c419f65-6604-4b42-87ce-02d3852a80e3	78c7dcb1-bef6-4cd4-8782-2d549aac5c0d	UPDATE	t	2025-11-13 14:43:17.582219+00	2025-11-13 14:43:17.582219+00
3de0222f-006a-4bb5-b579-53113f15a455	b440ca52-d1d0-49da-aa7e-0da8f21927b9	CREATE	t	2025-11-14 07:40:22.03071+00	2025-11-14 07:40:22.03071+00
2b601aaa-5463-47af-8858-f510a9d7d291	55bd1a46-45b3-457d-8715-d61c937e57a7	VIEW	t	2025-11-14 07:54:33.012368+00	2025-11-14 07:54:33.012368+00
afedd297-90a6-4301-a948-760abfff586d	605fb7ec-4ea5-4e1c-93dc-40eb5d19338f	UPDATE	t	2025-11-14 07:55:34.280571+00	2025-11-14 07:55:34.280571+00
2792802f-4f5c-41c6-a91e-bffaae95fe4c	e4021c05-4068-4439-90b2-aaca6cfc2690	VIEW	t	2025-11-14 07:57:41.506601+00	2025-11-14 07:57:41.506601+00
eb4aa561-e719-458c-83f2-d5f38519fec0	1c9fb5a0-a39c-4f16-a8ad-b9fb1d034709	VIEW	t	2025-11-20 13:32:56.911518+00	2025-11-20 13:32:56.911518+00
8307e64f-a352-4824-b901-6e592aa900f6	bcc4b91a-590d-4041-ab0a-1b2e71596bc6	VIEW	t	2025-11-21 02:13:18.472387+00	2025-11-21 02:13:18.472387+00
\.


--
-- TOC entry 3779 (class 0 OID 33034)
-- Dependencies: 225
-- Data for Name: privileges; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.privileges (privilege_id, privilege_code, privilege_name, privilege_description, privilege_category, is_active, created_at, updated_at) FROM stdin;
77cb55f9-c0de-4887-9bbe-3192e0110b48	system.read_only	Read-only	Chỉ được xem Patient Test Orders và kết quả của chúng.	SYSTEM	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
3de0222f-006a-4bb5-b579-53113f15a455	test_order.create	Create Test order	Tạo mới patient test order.	TEST_ORDER	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
afedd297-90a6-4301-a948-760abfff586d	test_order.modify	Modify Test order	Chỉnh sửa thông tin patient test order.	TEST_ORDER	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
26028ba2-9b3d-49d2-930a-50a4d3f7c6e1	test_order.delete	Delete Test order	Xoá patient test order.	TEST_ORDER	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
2b601aaa-5463-47af-8858-f510a9d7d291	test_order.review	Review test order	Review/Duyệt patient test order.	TEST_ORDER	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
95d8769a-eb52-4346-b175-1ecd4d235b48	comment.add	Add comment	Thêm bình luận cho test result.	COMMENT	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
396b577b-36af-42e4-8103-46717b6611d4	comment.modify	Modify comment	Chỉnh sửa bình luận.	COMMENT	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
b7cf08b2-86bf-4c20-9a2a-93e3f0634db1	comment.delete	Delete comment	Xoá bình luận.	COMMENT	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
534f9f40-1f79-449f-97bc-eccd51b044d1	config.view	View configuration	Xem cấu hình, bao gồm danh mục và thiết lập.	CONFIG	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
10fd436d-5d52-4ad0-84e0-238a1540e886	config.create	Create configuration	Tạo mới cấu hình.	CONFIG	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
6302e164-34d8-4aa9-9a27-2ea418ca57e5	config.modify	Modify configuration	Chỉnh sửa cấu hình.	CONFIG	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
1b75216d-fd16-4dea-a329-82131d0542d0	config.delete	Delete configuration	Xoá cấu hình.	CONFIG	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
183c05fc-cd78-403b-8f5a-dd026a1122d3	user.view	View user	Xem hồ sơ người dùng.	USER	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
c9604fc2-9c8a-4c0c-b973-1f48378bbcd4	user.create	Create user	Tạo người dùng mới.	USER	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
4df6d823-e27b-4039-9c99-ef950664b418	user.modify	Modify user	Chỉnh sửa người dùng.	USER	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
a7dc0f69-59e6-4228-b5f2-78fdbbe58707	user.delete	Delete user	Xoá người dùng.	USER	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
7b8123ce-4091-4d5b-9733-6ae53710040a	user.lock_unlock	Lock and Unlock user	Khoá/Mở khoá người dùng.	USER	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
7e487309-ac5c-4223-abb3-a1cf1007d4ad	role.view	View role	Xem các quyền của vai trò.	ROLE	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
b0534608-9be9-4343-8bd7-f09b36df1d2a	role.create	Create role	Tạo vai trò tuỳ chỉnh mới.	ROLE	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
85cd9809-2aa6-4164-ab59-b5bb84e77746	role.update	Update role	Cập nhật quyền của vai trò tuỳ chỉnh.	ROLE	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
cd944cee-9a4b-4ef7-a952-c30d048a86ab	role.delete	Delete role	Xoá vai trò tuỳ chỉnh.	ROLE	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
ae861974-9e7d-49da-af85-1f80c2614f2d	event_logs.view	View Event Logs	Xem nhật ký sự kiện.	SYSTEM	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
3eca6b24-ac69-49b8-b1f2-d39413b47098	reagent.add	Add Reagents	Thêm hoá chất/vật tư.	REAGENT	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
7d3a8dfd-68a8-435c-8653-555ac23197d3	reagent.modify	Modify Reagents	Chỉnh sửa hoá chất/vật tư.	REAGENT	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
2ef43e9d-0eac-49c7-bd70-78bde0e9d689	reagent.delete	Delete Reagents	Xoá hoá chất/vật tư.	REAGENT	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
b0e0973d-c22d-44b8-8d16-3c5a087dbd15	instrument.add	Add Instrument	Thêm thiết bị.	INSTRUMENT	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
d5ed06c2-bc5a-4c54-ac79-890689344d6f	instrument.view	View Instrument	Xem danh sách/trạng thái thiết bị.	INSTRUMENT	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
622c94fc-23ab-496a-a659-d07ed4c1d9d1	instrument.activate_deactivate	Activate/Deactivate Instrument	Kích hoạt/Vô hiệu hoá thiết bị.	INSTRUMENT	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
dfd1216f-7c06-4e82-8839-cf4c0aac41f1	blood_test.execute	Execute Blood Testing	Thực hiện xét nghiệm huyết học.	LAB	t	2025-10-26 05:10:10.585527+00	2025-10-26 05:10:10.585527+00
7dd0003f-a9bb-4f9a-8fef-6574b8dc18a3	privilege.all	All privileges	Quyền tất cả cho admin	SYSTEM	t	2025-11-03 01:21:15.79525+00	2025-11-03 01:21:15.79525+00
8f48d2cb-cd76-45ec-af2d-73efa8dde299	user.view_detail	View User Detail	Xem chi tiết thông tin người dùng.	USER	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
37c5bff7-38fb-498e-b3a5-328b36b14b83	patient.view	View All Patients	Xem danh sách tất cả bệnh nhân.	PATIENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
b21b3404-ca22-4cd8-b358-537c2eea6540	patient.create	Add Patient Record	Tạo hồ sơ bệnh nhân mới.	PATIENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
afa4572f-fe95-4822-af5f-58e1e5bc265d	patient.modify	Update Patient Record	Chỉnh sửa hồ sơ bệnh nhân.	PATIENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
6e8df40a-8c61-4499-a323-a1484fc728b4	patient.delete	Delete Patient Record	Xóa hồ sơ bệnh nhân.	PATIENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
475cddfe-0b9d-488d-aa16-93bc51f0a9ac	patient.view_detail	View Patient Detail	Xem chi tiết hồ sơ bệnh nhân.	PATIENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
2792802f-4f5c-41c6-a91e-bffaae95fe4c	test_order.view_detail	View Test Order Detail	Xem chi tiết patient test order.	TEST_ORDER	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
db82b74c-5364-4818-a567-eafa8c98303c	test_result.review	Review Test Results	Duyệt và xác nhận kết quả xét nghiệm.	TEST_RESULT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
de3d2157-11a1-4a7e-9d78-34551a97238b	test_result.ai_review	AI Auto Review	Tự động duyệt kết quả bằng AI.	TEST_RESULT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
b21ac688-9834-4291-8174-440657f23927	test_result.flag	Flag Abnormal Results	Đánh dấu kết quả bất thường.	TEST_RESULT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
197480b6-56e5-451f-bc2d-d9a3908abe85	report.export_excel	Export Excel	Xuất báo cáo Excel.	REPORT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
c80718c9-f972-4eaa-80ec-6fc5e77f0c20	report.print	Print Test Results	In kết quả xét nghiệm.	REPORT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
a995e224-4f27-402e-a0ce-d1cd93ee9673	reagent.view	View Reagents	Xem danh sách hóa chất/vật tư.	REAGENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
093c997a-e924-42e2-83d1-3f1afdfb5051	reagent.install	Install Reagents	Cài đặt hóa chất mới vào thiết bị.	REAGENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
bbe5f22c-bb3c-4722-b604-f28b2bd674a7	reagent.view_history	View Reagent History	Xem lịch sử sử dụng hóa chất.	REAGENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
011748ae-74a0-42e5-baa3-3dda8ac90ccc	instrument.change_mode	Change Instrument Mode	Chuyển đổi chế độ thiết bị (Ready/Maintenance/Inactive).	INSTRUMENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
128531c7-903d-43e4-814d-895bd0bea3fe	instrument.sync_config	Sync Configuration	Đồng bộ cấu hình thiết bị.	INSTRUMENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
71b0b31a-f254-4192-8f5c-bf6555db4ad0	instrument.check_status	Check Instrument Status	Kiểm tra trạng thái thiết bị.	INSTRUMENT	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
bd2c5881-2153-4fa5-87ac-74c956251952	blood_test.delete_results	Delete Raw Results	Xóa kết quả xét nghiệm thô (raw data).	LAB	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
8fb89f3a-7b6a-489f-80cc-737f1d16fb8b	event_logs.view_detail	View Event Log Detail	Xem chi tiết event log.	SYSTEM	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
3feb5a19-d45c-451f-8de3-88965a3ce576	monitoring.health_check	Health Check	Kiểm tra tình trạng hệ thống.	MONITORING	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
61ecfee8-5e1f-455b-9f44-630fd4fe41f7	monitoring.backup	Backup Test Results	Sao lưu kết quả xét nghiệm.	MONITORING	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
d991316b-7baf-485a-803d-f76c7f85df32	monitoring.sync	Sync Test Results	Đồng bộ kết quả xét nghiệm.	MONITORING	t	2025-11-03 01:53:13.513864+00	2025-11-03 01:53:13.513864+00
faeaecd0-6dfd-46bf-b0cf-6862ea800890	public.access	Public Access	Quyền truy cập công khai không cần đăng nhập.	SYSTEM	t	2025-11-03 02:08:49.163924+00	2025-11-03 02:08:49.163924+00
6165fe2d-d3bf-43b9-af1a-71432ba65ff7	user.ban_unban	Ban/Unban Users	Permission to ban or unban users from the system	USER_MANAGEMENT	t	2025-11-04 02:46:14.305269+00	2025-11-04 02:46:14.305269+00
f21e0710-0c2f-472b-8904-b3abecca9aad	privileges.create	Create Privilege	Tạo quyền tạo mới privilege	SYSTEM	t	2025-11-04 11:33:47.414075+00	2025-11-04 11:33:47.414075+00
e200f22c-7498-4014-9cf5-709dfd83d4f5	privileges.update	Update Privilege	Tạo quyền cập nhật privilege	SYSTEM	t	2025-11-04 11:33:47.414075+00	2025-11-04 11:33:47.414075+00
33aacb02-322e-43b7-8425-435aa44a6df3	privileges.view	View Privilege	Tạo quyền xem privilege	SYSTEM	t	2025-11-04 11:33:47.414075+00	2025-11-04 11:33:47.414075+00
21e34022-4e5f-4409-9a61-e73c8332859a	privileges.delete	Delete Privilege	Tạo quyền xóa privilege	SYSTEM	t	2025-11-04 11:33:47.414075+00	2025-11-04 11:33:47.414075+00
e0f990cd-78d3-40a2-b753-21a381b12b60	role.assignprivilege	 Role assign Privilege	Gán phân quyền cho vai trò	USER	t	2025-11-05 00:48:45.347465+00	2025-11-05 00:48:45.347465+00
525da488-8586-4710-b584-4c5417be4361	update.profile	Update profile	Update personal information	PROFILE	t	2025-11-06 03:01:18.838614+00	2025-11-06 03:01:18.838614+00
76021b2a-b5ba-4db5-84ba-1b8d426d227b	view.profile	View profile	View personal information	PROFILE	t	2025-11-06 03:02:06.268384+00	2025-11-06 03:02:06.268384+00
33e1c04b-8c5e-4cca-9ddc-fa3a850ab4ed	change.password	Change password	Update new password	SECURITY	t	2025-11-06 03:04:57.236006+00	2025-11-06 03:04:57.236006+00
04c9e7de-3536-43c9-b009-c608764d72d5	testorder_view	Test Order View	View list of Test Orders	TEST_ORDER	t	2025-11-11 06:41:18.913025+00	2025-11-11 06:41:18.913025+00
e4d4f092-7149-4d54-bdd9-c3469e2fadc0	medical_records.view	View medical records	View medical records	RECORD	t	2025-11-11 16:09:22.886724+00	2025-11-11 16:09:22.886724+00
45bec9a1-53b3-486d-b414-e2f5dc97fa7a	medical_records.create	Create medical records	Create medical records	RECORD	t	2025-11-11 16:10:02.029912+00	2025-11-11 16:10:02.029912+00
8c419f65-6604-4b42-87ce-02d3852a80e3	medical_records.edit	Edit medical records	Edit medical records	RECORD	t	2025-11-11 16:10:30.125983+00	2025-11-11 16:10:30.125983+00
77379757-4023-4299-b90c-beecc8534924	medical_records.detailed	View detailed medical records	View detailed medical records	RECORD	t	2025-11-11 16:11:31.642442+00	2025-11-11 16:11:31.642442+00
eb4aa561-e719-458c-83f2-d5f38519fec0	test_result.view	Test Result View	View test results	TEST_RESULT	t	2025-11-20 13:32:28.400351+00	2025-11-20 13:32:28.400351+00
8307e64f-a352-4824-b901-6e592aa900f6	view.all_medicalrecord	View all Medical Record	View all medical records	MEDICAL_RECORDS	t	2025-11-21 02:12:06.223355+00	2025-11-21 02:12:06.223355+00
\.


--
-- TOC entry 3780 (class 0 OID 33043)
-- Dependencies: 226
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.refresh_tokens (token_id, user_id, token_hash, token_family_id, access_token_jti, ip_address, user_agent, created_at, expires_at, is_active, is_revoked, revoked_at, revoked_reason, last_used_at) FROM stdin;
b2bbd4b4-2158-43d7-9e5c-12457be47a96	987fa969-961f-4afb-98aa-636c3448bd87	cda780daa07478045237af6583122b5de7c0b69e7b55c15149476b3c0c272941	4fc2a2df-bd95-440d-b4e4-f59c0375ab03	2e619672-5590-4512-b724-a83582051eb1	118.69.128.8	PostmanRuntime/7.50.0	2025-11-12 08:39:11.642161+00	2025-12-12 08:39:11.642166+00	t	f	\N	\N	2025-11-12 08:39:11.642195+00
ca9ae6cb-fe99-4c2c-ac2c-4b1f3de58240	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	234330703622a17c6bfa4a7a70c06ece1bd83806d408bda99e41a4d02c9a44db	145b58b8-47a5-45e9-a17a-5276054fa105	d4a9aeee-651c-48e8-9df7-062e49a1b818	125.235.175.228	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-12 08:39:49.006091+00	2025-12-12 08:39:49.006093+00	t	f	\N	\N	2025-11-12 08:39:49.0061+00
f3c14b4e-e7fd-4e7a-a7c1-240e14b708b4	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	0613d20e3520b93765cb3ace770a24b96f8213e5c52b899c7071adfe2c38815d	505830a0-963c-41b5-8340-c91a77620b12	b0f27d72-59f3-4dbf-80c4-5fcf6892ff53	125.235.175.228	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-12 08:39:56.101746+00	2025-12-12 08:39:56.101748+00	t	f	\N	\N	2025-11-12 08:39:56.101754+00
0df490cd-6655-4c6d-b984-41ca149cce0e	987fa969-961f-4afb-98aa-636c3448bd87	6129d9129dbbe350b2c36e643e43e7e3a8da923ad08126035499d755ff6cbfbb	44eb9fda-bb59-46aa-b734-9ccdf4cd9a91	84581f7d-b54b-4a24-9266-a049f93f096c	171.255.185.213	PostmanRuntime/7.50.0	2025-11-12 08:56:01.111792+00	2025-12-12 08:56:01.111794+00	t	f	\N	\N	2025-11-12 08:56:01.111811+00
fdaa3cc9-c5a2-46d2-a585-be1982ec003e	c1d918d1-18d8-4837-a271-967d90f569a3	3fe33d10f19993238018172626171c7a776c87f8f9db90be5ec9ffb211b086f5	0a622bb2-446c-41ef-8b46-0e49381f87f8	513c8229-c067-458e-822c-237babb38b97	171.255.185.213	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 08:56:33.331946+00	2025-12-12 08:56:33.331948+00	t	f	\N	\N	2025-11-12 08:56:33.331961+00
4c9b9cbb-ecc2-47c9-b3b1-6f27841a4631	bb8259df-3cb8-487a-ab91-2ef95a68aa44	847fb18398c76144b19e4691b4cf8d4c5dca76832a8568410e07a7ee2658a920	5bd60463-5ab2-405a-ad3c-b7d3a5be4646	8ca977b9-1c11-43c6-abe7-b05dadd002d2	171.253.248.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-12 09:18:24.075154+00	2025-12-12 09:18:24.075157+00	t	f	\N	\N	2025-11-12 09:18:24.075179+00
73b5c2f6-fd1a-45d1-b4c6-3e58d8cf5de9	bb8259df-3cb8-487a-ab91-2ef95a68aa44	f140a7723c41e956c2669c180663ddf4c218a2613d7f66cd12e13fbd42d7a208	76f81052-f382-4f69-885f-0e5d188b2059	b9a32b32-9866-48b1-8608-01714361a9f9	171.253.248.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-12 09:18:27.359109+00	2025-12-12 09:18:27.359112+00	t	f	\N	\N	2025-11-12 09:18:27.359118+00
5e5824c4-0d97-4740-a397-aaf77af7db57	987fa969-961f-4afb-98aa-636c3448bd87	ae0e78904bda9815c08742f96ef7ad2aa7687e9838d28dcd9de41c16421ca9e1	d29a2558-d493-4cb3-9c87-4ebdf9b24961	ae3590d5-c726-4831-ba36-8b7bbc733085	113.180.136.66	PostmanRuntime/7.50.0	2025-11-12 13:45:20.625887+00	2025-12-12 13:45:20.625892+00	t	f	\N	\N	2025-11-12 13:45:20.625938+00
ac12d373-0f17-41fc-9ef0-024bdabb7232	c1d918d1-18d8-4837-a271-967d90f569a3	eb4a3ee886fb749e0deb27a47a63858329f0d7db09205629a62b61362683d535	08b09af2-724e-4230-ba1d-b3423fcc2563	4e2a3314-8f01-4996-b9ba-86d56322e47a	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 13:47:44.571786+00	2025-12-12 13:47:44.571788+00	t	f	\N	\N	2025-11-12 13:47:44.57181+00
4f37137e-a4b4-4209-b275-2e9e350126c0	c1d918d1-18d8-4837-a271-967d90f569a3	ed072210004efbd4b1da52687a90984f9111074acc7f08d8759bcb257be71fc8	df12bec3-54ec-48e9-81a5-0634cc16e130	2ba94e4d-0255-4dae-9bf2-94314900d331	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 14:07:18.213892+00	2025-12-12 14:07:18.213895+00	t	f	\N	\N	2025-11-12 14:07:18.213921+00
9797ead1-1317-401b-a6ad-5f5eee5c6869	c1d918d1-18d8-4837-a271-967d90f569a3	7e08dcccc4abe33161f72f12e112be82bf14ab6ac4aea4e41b5d010dc05ac8b0	66c10e8a-981e-4aa2-8811-65c018dead8e	5772c855-872f-4da1-8c36-d426fc7f9cd3	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 14:23:16.661176+00	2025-12-12 14:23:16.661179+00	t	f	\N	\N	2025-11-12 14:23:16.661196+00
e8837a9d-0139-4b1b-9823-5a45e32cbdba	c1d918d1-18d8-4837-a271-967d90f569a3	02403cc97748288e317ceb2f9ac3b55a75b0c3c689ef446304ed9f568a59b002	4c647e42-f5ab-4a12-8df3-a5fe39644358	bb47d23c-25dd-45d1-8d8e-4112e818a006	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 14:24:00.650835+00	2025-12-12 14:24:00.650838+00	t	f	\N	\N	2025-11-12 14:24:00.650852+00
459d8c44-581d-4df7-87a7-59bc6a44bc1c	c1d918d1-18d8-4837-a271-967d90f569a3	d2817f577bee92de53bd59058bdc48d7fb1d4bc420b0b6550b43bd3718622f8b	bf5de383-0470-4888-a7d8-1d4300149cfb	f0e8bb25-78db-46a4-a8c9-41bd06f7a463	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 14:25:42.070453+00	2025-12-12 14:25:42.070455+00	t	f	\N	\N	2025-11-12 14:25:42.070467+00
79374ec3-8524-494a-9b25-b8809446ad65	c1d918d1-18d8-4837-a271-967d90f569a3	5a7e246eaa2b7cfc7f14b0ca14e1e30e4fd1dddab7f2bc2c75658c46e50cbf01	d4724634-3685-4b32-9f13-031a91c0a887	8c7449df-8a9f-4c4c-9d74-4edf9916af75	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 14:31:36.635898+00	2025-12-12 14:31:36.635901+00	t	f	\N	\N	2025-11-12 14:31:36.635925+00
9a92ab5c-b32f-46db-8ccd-7be5692468a3	c1d918d1-18d8-4837-a271-967d90f569a3	5da6a0ee7eb600941a1688578c3466e2d36ad1360108c5d610035a24ce43d9e4	b438d718-de9b-4758-8c71-1af91b2c324e	f08e0325-3d73-4abf-9d93-b366c4dc107a	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 14:37:15.889012+00	2025-12-12 14:37:15.889032+00	t	f	\N	\N	2025-11-12 14:37:15.889091+00
b53335f2-beab-40b9-bd4d-d2fa53791525	cd23d611-1644-4d29-b7b3-100f9458018c	50b32497288eea8ca9f7f46729f92f30e7baf730cf52d69bbaaf002538153414	bfddd691-d9f9-4a35-a27c-f3a16f3f95e8	b8e2a27a-23fd-4970-8e3c-d82e6d129643	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 08:08:10.507963+00	2025-12-22 08:08:10.50797+00	t	f	\N	\N	2025-11-22 08:08:10.507995+00
a6ecf3b4-89c5-4fbf-a088-434d647a7f28	c1d918d1-18d8-4837-a271-967d90f569a3	72bd766e36d81ba7bd349622f815e2850c9fbbeee0e5ca52d791360451160a76	9d9ce93b-9ebd-4913-9108-544bf3cbf328	c73ce0b4-ad4a-4552-8352-58ad981c0295	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 14:41:15.61825+00	2025-12-12 14:41:15.618254+00	f	t	2025-11-12 14:56:06.867815+00	rotated	2025-11-12 14:56:06.699808+00
bd4bd378-330c-4707-833d-8a254e65d298	c1d918d1-18d8-4837-a271-967d90f569a3	f37a7264dff85951d1c91e3bceca5b916c7bd8b4980dd7981b3411492e52a753	9d9ce93b-9ebd-4913-9108-544bf3cbf328	952e475e-5b08-4649-a3b8-9d83829cd495	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 15:10:09.594909+00	2025-12-12 15:10:09.59491+00	t	f	\N	\N	2025-11-12 15:10:09.594938+00
46a277b8-dc01-43f0-822e-c3c7c362a0e2	c1d918d1-18d8-4837-a271-967d90f569a3	7c092afc4a3f2f340b60610f9c0af2747d62968dd639789febff224e537a1ae9	9d9ce93b-9ebd-4913-9108-544bf3cbf328	da269bdd-faeb-4695-9667-559643d220a2	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 14:56:06.868098+00	2025-12-12 14:56:06.868099+00	f	t	2025-11-12 15:10:09.594647+00	rotated	2025-11-12 15:10:09.448269+00
85719988-6207-4a07-b36c-b368d0222ef9	c1d918d1-18d8-4837-a271-967d90f569a3	0b7d6189694c488a8a408dda6d1e880370a5072458f28955fb390642a6fac16c	3c67b9a9-b096-4558-a41b-42e0e7a50e9c	a1c3e313-f268-42d0-912a-7c74e595b90f	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 15:41:03.417748+00	2025-12-12 15:41:03.417749+00	t	f	\N	\N	2025-11-12 15:41:03.417774+00
3ba2bf35-0d90-46fe-8bfe-325d080f23cd	c1d918d1-18d8-4837-a271-967d90f569a3	e0f06ec0359d9576b32af3a29eb1070baabf8133f1fec442b871db2ae672a07a	3c67b9a9-b096-4558-a41b-42e0e7a50e9c	52a08031-e89b-4589-8cda-8bc952f32ee3	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 15:26:50.616989+00	2025-12-12 15:26:50.616992+00	f	t	2025-11-12 15:41:03.417462+00	rotated	2025-11-12 15:41:03.239904+00
b2d963fc-8f43-4696-b367-78b129128e48	c1d918d1-18d8-4837-a271-967d90f569a3	5768addbc59bc0ea580f77c94a7f729289211606cfd7759c95eaf03b0e53b189	97937646-f058-4950-8040-77650efb7c24	2fc8f976-cfad-491e-a963-fb3aab58de54	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 15:47:48.463216+00	2025-12-12 15:47:48.46322+00	t	f	\N	\N	2025-11-12 15:47:48.463261+00
fc037871-6b14-4bb7-a8cf-9206d6232b96	987fa969-961f-4afb-98aa-636c3448bd87	29a116e3c58b6180e7c54c9d0376c119a7eeedc0571ed7c140bb6a4e62e86dc2	1f0b65a4-06b0-4065-b229-7ca3a11d68aa	c67042c1-2156-4895-9920-986f5c3ff5e7	113.180.136.66	PostmanRuntime/7.50.0	2025-11-12 15:57:20.915676+00	2025-12-12 15:57:20.915679+00	t	f	\N	\N	2025-11-12 15:57:20.915708+00
582dfb1d-5205-4c60-8025-27cc20981f92	c1d918d1-18d8-4837-a271-967d90f569a3	93332714b3862347eda394878f23fb638ddcb4003510213324de5d212e6e89f8	019c20f9-2763-4b0a-a8b9-defb90f83589	80b42f37-8eef-40a9-99d9-755f807bfa21	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 16:12:19.428038+00	2025-12-12 16:12:19.428039+00	t	f	\N	\N	2025-11-12 16:12:19.428067+00
0dfcef1f-704b-4fda-9799-37b4dbdc4bf1	c1d918d1-18d8-4837-a271-967d90f569a3	64580a09a95a5489d72c4002c130a661ee9256570459aca3772c23cd540e4507	019c20f9-2763-4b0a-a8b9-defb90f83589	516eb99e-168b-4bb4-b9eb-a066381904e0	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-12 15:57:57.871763+00	2025-12-12 15:57:57.871765+00	f	t	2025-11-12 16:12:19.427779+00	rotated	2025-11-12 16:12:19.223312+00
1fe86f83-7611-4e23-84b8-8b76e2ca8c37	c1d918d1-18d8-4837-a271-967d90f569a3	9ba04df50d940ebd6f5acc1402922bc3f270c2a53f42ac8388cebbf02ddb68d3	c561997f-b9f4-4613-89f6-e139133f97d0	74c0a7ea-a3eb-4cf5-a783-c71c8b0535ce	113.161.234.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 04:58:02.723982+00	2025-12-13 04:58:02.723986+00	t	f	\N	\N	2025-11-13 04:58:02.72402+00
8858eeff-adfe-47e9-8485-7e7244071601	987fa969-961f-4afb-98aa-636c3448bd87	7e1793c8cf251707f7d29ae6684418ce05851f1cc966890db76a4d338b6609ec	9ea32b34-c803-48fe-a4af-67d1043ee7d3	efb6023c-77ac-452d-82ce-834404e56836	113.161.234.66	PostmanRuntime/7.50.0	2025-11-13 04:59:23.394973+00	2025-12-13 04:59:23.394976+00	t	f	\N	\N	2025-11-13 04:59:23.394999+00
2e206cb7-d513-4e34-84b6-f955f9760ce9	c1d918d1-18d8-4837-a271-967d90f569a3	fbbbd74b4c1e6e19fb4d4d15b351797d1338f88fea3bf1babcab982d330a7e74	1b4887d4-a721-41b9-a0e6-c61434d3f2d5	8be31854-defa-4b1b-ba10-717d79ca0cdd	14.241.182.163	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 05:10:26.870836+00	2025-12-13 05:10:26.870842+00	t	f	\N	\N	2025-11-13 05:10:26.870868+00
2b2de054-dc14-4279-8a5b-8a8dcd514c05	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	6f7e4cdde63e13eff9b004a35bd202d7e4d47c9d126b866737f774d32bb07769	3a754048-c0e7-4871-8a95-9ee805589a4f	207a7a9a-8095-4ce6-89e3-6b8494f992b1	1.54.252.240	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-13 09:49:21.741154+00	2025-12-13 09:49:21.74119+00	t	f	\N	\N	2025-11-13 09:49:21.741215+00
3a037bdf-7189-403a-a75c-791a83c09eed	cd23d611-1644-4d29-b7b3-100f9458018c	1ecdb655e981dfae6482f4120a4334a6e9ac3f1afec0f425605d320b02d6ccf5	184e6d53-1cb8-4552-818e-a67c38a267ff	511fd456-c5cd-4fb8-b793-bf0eca131199	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 08:08:39.401223+00	2025-12-22 08:08:39.40123+00	t	f	\N	\N	2025-11-22 08:08:39.401242+00
78547324-bd9a-4b1e-919e-5a75113dac06	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	5683199d1ef39dab328d82d5d41b6e1594a0b994268702a5ead954f5e1e6f8ba	600dfee0-53a7-4794-b051-14ce2190bca1	1e681209-f373-4f9c-8c90-31ef4b97ea9d	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 03:31:57.090503+00	2025-12-24 03:31:57.090513+00	t	f	\N	\N	2025-11-24 03:31:57.09053+00
d7a46586-afa5-4f4f-a965-dce3724a9fba	cd23d611-1644-4d29-b7b3-100f9458018c	2b5888d62b362391ea9d35fa7123210bd74a156939656655082e7083985f1aa2	cf590b39-f502-463b-8104-1f7356c11652	894a34d0-1321-4ead-8c26-8217c80410a3	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 03:32:03.927159+00	2025-12-24 03:32:03.927166+00	t	f	\N	\N	2025-11-24 03:32:03.927179+00
d4f3acef-408a-4f2c-aef3-1b5ccb2bc4d3	bb8259df-3cb8-487a-ab91-2ef95a68aa44	90def0fc9ebbdd3afb29b680156b5d1dd2ae40c0bd2c9852e7d96f07029863af	ff752bd1-1890-476b-ae8a-5defcd1dcb93	a47ee8ea-982f-46eb-871e-87697a967e82	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 03:32:07.778944+00	2025-12-24 03:32:07.778962+00	t	f	\N	\N	2025-11-24 03:32:07.778988+00
e0822633-0d54-4e4b-beb3-ff1bc5a8f098	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	ef060a8ff8e8a47f2a96b3873a0b78f62b6b8f5ba4185bc080a24c511c1e428b	2560b527-0958-4c47-8343-bc646b5aba66	b4bf7115-9e61-4dcd-99bc-94cb7cadf2b3	1.54.252.240	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-13 10:24:28.159275+00	2025-12-13 10:24:28.159333+00	t	f	\N	\N	2025-11-13 10:24:28.159376+00
1cc9b2b9-2a31-4732-b44d-57206cd1da7c	987fa969-961f-4afb-98aa-636c3448bd87	919224f2fbc76d49e833692c3e53ba16072d1450b7e233d29cfc9044709a2bb0	4f532fcf-381a-407a-8dc1-aa0d8cf4b72f	fd568d6b-bfe6-4a5a-9115-1398d0542a1a	171.233.121.226	PostmanRuntime/7.50.0	2025-11-13 10:29:10.302584+00	2025-12-13 10:29:10.302622+00	t	f	\N	\N	2025-11-13 10:29:10.302677+00
36961193-dd8a-4002-a867-b53f62f2d620	c1d918d1-18d8-4837-a271-967d90f569a3	5bc30601a9e8866dd5ebf8fec700b1165c25942bd1ba24efa4aac63aeb5bc62f	ae27001a-f9ec-4fb7-bdfe-74e6d63c32fc	d4804f19-55c1-43e0-a806-b659a239c5f0	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 10:32:17.835078+00	2025-12-13 10:32:17.835101+00	t	f	\N	\N	2025-11-13 10:32:17.835167+00
142bb57a-cdf7-49b2-8d7a-fea48ec2eebb	c1d918d1-18d8-4837-a271-967d90f569a3	ea5fe1419cb4de63279625bd735d53e53ebc812bcbcbfc28380378a35a53dc21	b7f6f0e5-f5e4-4247-a748-6e402e0c1b49	8443e8d6-0f70-4cb2-b6cc-1a52a0be74ab	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 10:33:06.603281+00	2025-12-13 10:33:06.603305+00	t	f	\N	\N	2025-11-13 10:33:06.603326+00
c986f164-f16b-47e7-9339-62e8f2bb7859	c1d918d1-18d8-4837-a271-967d90f569a3	59c33c491e77b0900bb184cfbc9a5fa69e6115dcf11eac732b70b4f99a8c2d1d	db433854-9101-4c11-b15d-6514bafb4674	aa0ea7da-bee6-4320-87b7-4707d0944e82	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 10:33:53.730998+00	2025-12-13 10:33:53.731006+00	t	f	\N	\N	2025-11-13 10:33:53.731018+00
97a52aa0-44c1-4b1a-baa7-1d2ec6ff8532	c1d918d1-18d8-4837-a271-967d90f569a3	f33c848d409b92a83d5c5cbfaf24b6b977ec79268856b850bef3ae45ad237d0e	12b1e4b2-d23e-4ffd-b2c8-6f03cf895a05	3a957252-1b3b-4347-89a3-6a5352f38310	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 10:34:55.251528+00	2025-12-13 10:34:55.25156+00	t	f	\N	\N	2025-11-13 10:34:55.251642+00
c06a20b1-13c9-4a33-8658-88b5daab440e	c1d918d1-18d8-4837-a271-967d90f569a3	f88506bd360167ba2ed1e894a0b6a2f0c5094a90b1088247c7d138c4b1ea4a25	4f0307ea-6026-4504-9302-28ceb7d12d5d	fc086786-3943-45e4-9b4b-ff4696c820b5	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 10:51:34.554549+00	2025-12-13 10:51:34.554576+00	t	f	\N	\N	2025-11-13 10:51:34.554615+00
c896a1a1-58d6-425a-81aa-6f90f5c06827	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	2c2e68c27b11d34edb8d78d7c097476c5c7294060dac540e0092d57442453d95	d3271ec8-49cf-45b3-8d96-4dd00849890b	5faa89b5-2189-4602-be2f-eca7ca95eef9	1.54.252.240	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-13 10:52:19.593743+00	2025-12-13 10:52:19.593761+00	t	f	\N	\N	2025-11-13 10:52:19.593784+00
c1379fd8-4caa-4c38-8b8d-3d02fbf87c94	c1d918d1-18d8-4837-a271-967d90f569a3	5a0a9d9cbe890fc165aed605c8d44d0fae2f798cbdf26c3fd7144bc8ba3a24c2	cb84aa21-71a1-4de4-a510-d5055e84afe9	3eb30f7e-8088-4fda-98d6-df4b074ebe79	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 10:55:56.209195+00	2025-12-13 10:55:56.20921+00	t	f	\N	\N	2025-11-13 10:55:56.209272+00
6355ee0f-ed19-4d48-bc77-62956bbdc954	2a04b41b-422f-455e-85c3-4c036e692b3c	bf65315bd0ddf70e4b3e831ecd8518014a882922d9ac74eb60bb79929f049b5f	2f494db6-004e-4f7c-8e27-d061a1a1601d	5b3a58fd-d8fe-49e2-950e-a1d97e70adf5	171.233.114.75	PostmanRuntime/7.39.1	2025-11-13 10:58:12.105995+00	2025-12-13 10:58:12.106009+00	t	f	\N	\N	2025-11-13 10:58:12.106071+00
42f122df-352c-41d2-ba5c-0efaa78d4523	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	08213abe5aeec08e925295e3fde47483311537731956cd92c38727a4227d8d93	387d53c3-b928-43c0-bab7-06b82d98f5de	fe8c1e1a-139a-48bd-976c-4a49995651bf	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 03:32:50.145713+00	2025-12-24 03:32:50.145719+00	t	f	\N	\N	2025-11-24 03:32:50.145762+00
9f7e251e-3d23-442a-83e9-5141baa03457	bb8259df-3cb8-487a-ab91-2ef95a68aa44	256fefff8468b1243f77c079e0f5d2b7f852a2c637cac067485ba0096676bc49	50292b73-2461-4d6e-bfcc-88a098e49947	4e353a48-c758-418e-b145-7fc05d533fde	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 03:32:56.420164+00	2025-12-24 03:32:56.42017+00	t	f	\N	\N	2025-11-24 03:32:56.420183+00
9925415e-bea1-4463-887b-94b40593c377	987fa969-961f-4afb-98aa-636c3448bd87	4bf22e05177aff2ccaa5af1ba4c2f69be1b4648b2175a25e07c6e8c71ecd42b5	dcf9ae86-35b0-435a-b529-554895920228	d1d2b2fa-0e5b-4df3-8e5d-41d0621f007c	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 03:32:01.087393+00	2025-12-24 03:32:01.087399+00	f	t	2025-11-24 03:46:45.627814+00	rotated	2025-11-24 03:46:45.42224+00
fafb4c0e-1d92-495c-870a-7535b8f52896	c1d918d1-18d8-4837-a271-967d90f569a3	4ff1ad5a517a1dae543a471608aa07594e679a1b47a6f3a300df9a2ea2d06802	c50bc243-4f5c-4846-a401-3a7bb8bd3128	51163ffd-2e42-4366-a569-98ca576e05b9	171.236.70.5	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-24 04:54:52.420544+00	2025-12-24 04:54:52.420558+00	t	f	\N	\N	2025-11-24 04:54:52.420651+00
3b963290-14eb-43e6-a043-d6e2f304bde8	987fa969-961f-4afb-98aa-636c3448bd87	5f714745c47e4a91dbe8ee07cfc36f2e3ec011a3626403b62cd0f702b4d3871c	9fefd4dc-88e6-4161-9ab6-c769874e7985	71a91223-d2c2-411b-8f65-086ab58ccb91	113.161.234.220	PostmanRuntime/7.49.1	2025-11-19 00:49:04.497114+00	2025-12-19 00:49:04.49712+00	t	f	\N	\N	2025-11-19 00:49:04.497176+00
ad806331-a8e2-43b6-bcde-a2c1e4ca1de6	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	87e55851b3b441c19e2ca532621805dec6015ab528219367ec66f1422d2c186a	85c0a328-1cb4-415c-a970-2cc98102ebce	60bb66bb-057f-4300-967e-329bba24733d	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 08:11:31.225462+00	2025-12-22 08:11:31.225465+00	t	f	\N	\N	2025-11-22 08:11:31.225495+00
dfe164ed-cd1e-436e-9f0e-976df392057a	cd23d611-1644-4d29-b7b3-100f9458018c	27230333b3cb689ea0b07fb4e35c76ce0d325e83b65563aa03fd8596b4b83778	e83805e0-794b-4573-b45f-acc7f71d2076	851a8c3c-4e47-46ae-8fe7-f961a02a9458	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 08:14:56.862748+00	2025-12-22 08:14:56.862754+00	t	f	\N	\N	2025-11-22 08:14:56.862798+00
1351aa55-2eaf-4303-a59e-aacb6b6bdc0a	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	61373c7ba04cb0ada66020987a9b781515d7212ec37bbb66b23eb4c5a27a1e54	5ca9966b-64e5-4d53-8be0-401877703d9b	653e172c-322b-48d1-a11a-161cb53e724f	1.54.252.240	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-13 11:17:12.249152+00	2025-12-13 11:17:12.249153+00	t	f	\N	\N	2025-11-13 11:17:12.249179+00
f80a9a3e-5fbb-44b6-9c85-fd46542daccb	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	ee182e62ef9d18d2164224c553052b81175debc73d667f9944d5538b1d60c1f8	5ca9966b-64e5-4d53-8be0-401877703d9b	5e71aead-2583-4196-b54a-673f03aaf2d6	1.54.252.240	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-13 11:02:12.776011+00	2025-12-13 11:02:12.776014+00	f	t	2025-11-13 11:17:12.248698+00	rotated	2025-11-13 11:17:11.981144+00
67c2f7c3-b5e3-4c98-9ec8-15357780f5ed	c1d918d1-18d8-4837-a271-967d90f569a3	02b0b9683a8274063db584384a0eacd29362d3ba9fb8ec5bdd83c576e5e1b90f	c9138536-5ebe-423a-8975-538d6c8f62f0	4ca8e444-68b3-415f-908f-63fc6ad351c0	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 11:22:33.203646+00	2025-12-13 11:22:33.203657+00	t	f	\N	\N	2025-11-13 11:22:33.203732+00
9ce0e8f9-ee6f-441b-bedf-64f65b8ed305	987fa969-961f-4afb-98aa-636c3448bd87	87ee5e02492341ccb1532bb2a844621eb02dbc55892a0d1df9944c88cffad2ae	769bdbfa-b541-4335-9f17-a07be1c3861e	291c01bc-1e66-4e45-9bb7-d10dc43a8cb7	171.233.121.226	PostmanRuntime/7.50.0	2025-11-13 13:11:30.454323+00	2025-12-13 13:11:30.454331+00	t	f	\N	\N	2025-11-13 13:11:30.454428+00
56c82f21-9f00-44b3-971e-69b3450e3afb	c1d918d1-18d8-4837-a271-967d90f569a3	73f240b4c72b5741a86549e581051b1a17e80b411c490cc609e8711b7dbb6ce8	ab691bee-811a-4a7b-891c-072887e5bab4	03707617-13b2-4ea2-8714-d4505f919b3a	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 13:12:41.340837+00	2025-12-13 13:12:41.34084+00	t	f	\N	\N	2025-11-13 13:12:41.340863+00
09907cc0-cdc0-4324-808b-2a09dc1fdfbf	c1d918d1-18d8-4837-a271-967d90f569a3	021b5b1229eb129ad7f3fc7f15782de77cfc5b65c80d05a3a7294a04cbefe86e	6c3f9dd6-1846-49ee-9ea3-8c4b5835a231	c6044377-2279-4e71-b07f-3780a66b12d9	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 13:14:26.233758+00	2025-12-13 13:14:26.233761+00	t	f	\N	\N	2025-11-13 13:14:26.233812+00
794aa2f7-e7aa-4cb3-8455-ac99f90ea5a1	c1d918d1-18d8-4837-a271-967d90f569a3	0178604c45726fbbcc60fb6f5a848d1bff87bbfb09a4be81484f01a5209e5c8c	1514fdbd-02bb-40d8-9f73-2eaca352af6c	a73ce44c-0ac7-4595-9456-28014ef6a040	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 13:14:59.794095+00	2025-12-13 13:14:59.794104+00	t	f	\N	\N	2025-11-13 13:14:59.794119+00
dfbcf90e-3519-42b3-a686-60451b27cebf	c1d918d1-18d8-4837-a271-967d90f569a3	7cf8def38a7d1c1dc6d61fddbe2c9494fbc68f97fc74b8d2e0791f5db221a3a1	d40019c7-048d-40e3-9b8e-343fd60252ef	7e9bbbe2-c456-4677-a485-33f71134a075	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 13:37:05.345979+00	2025-12-13 13:37:05.345988+00	t	f	\N	\N	2025-11-13 13:37:05.346086+00
6c88d430-fd28-4b2b-a651-ae486d4cbadb	c1d918d1-18d8-4837-a271-967d90f569a3	10d0f437932ebf07fa99f495dc6fa65779e625fcd74058f85e64cedb4fe7d335	b4d89af7-286d-4099-a370-f1f4ac23235a	a45709ed-904c-448b-af9e-ac690cf46961	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 14:21:40.11704+00	2025-12-13 14:21:40.117049+00	t	f	\N	\N	2025-11-13 14:21:40.117137+00
4f2c19d2-49e1-4741-883b-909be5945846	c1d918d1-18d8-4837-a271-967d90f569a3	286697356af86391431eeb819166249895507ea6c69a6ea9788e6105d9519c5b	25ddc0db-83f9-4d4f-9b63-c12c3acec688	ae305fee-f47f-44cb-8fba-60e452283630	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 14:38:57.163664+00	2025-12-13 14:38:57.163685+00	t	f	\N	\N	2025-11-13 14:38:57.16376+00
f08688e6-6cc6-4a03-8b92-53da4b3c0b60	987fa969-961f-4afb-98aa-636c3448bd87	c32ea273d3d27c665df429b3c28f41cfb125f7e5ad1a03cc80d27a58f5baa25f	dcf9ae86-35b0-435a-b529-554895920228	f46aae2b-9dd0-4d0c-94cd-7e411b93774b	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 03:46:45.628204+00	2025-12-24 03:46:45.628205+00	f	t	2025-11-24 04:00:56.207917+00	rotated	2025-11-24 04:00:55.96639+00
e5a9a0e3-ab98-45e1-a644-29f4755bbd12	987fa969-961f-4afb-98aa-636c3448bd87	488060686e173a7afa706c125739b285ef731280c89bbc3407eb936f1c4c90cb	e71df74a-1498-4d0a-bbc5-de84c32b0030	c95ff84b-0fba-4c54-9c58-ea317cbc2947	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 04:57:00.762558+00	2025-12-24 04:57:00.762582+00	t	f	\N	\N	2025-11-24 04:57:00.762669+00
6ed6e921-2ffc-425c-a305-71c72d1f0f40	987fa969-961f-4afb-98aa-636c3448bd87	dba0debeca4c9b2022ea5a249359430712257bd41ff16d3fe2717e505895c1f7	34aee667-da46-463b-8b99-650ae0f84afd	9dfb3a9d-63dc-49c0-ad23-1ca197e523b2	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 05:00:17.735548+00	2025-12-25 05:00:17.735549+00	t	f	\N	\N	2025-11-25 05:00:17.735561+00
c2540f8d-8a39-4d24-acd2-e6fb2cd63e86	cd23d611-1644-4d29-b7b3-100f9458018c	fe3cdf9963d6b27af02fa837c6102de048971f5c9e2ddfe3110fba17822346ec	a06ab41f-dbff-4d7f-bae7-e9a30c3150e5	2a664283-f778-4240-afd6-c540c7041042	58.186.28.4	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-25 06:22:09.518775+00	2025-12-25 06:22:09.518785+00	t	f	\N	\N	2025-11-25 06:22:09.518843+00
c7d15f54-644c-4f06-a018-2ad47719c247	987fa969-961f-4afb-98aa-636c3448bd87	9c8644a1389e7a64f50f8000dcedb72284e9bc9a55918b36a7120dea1bde81e9	d1535a6d-8149-45c6-8f65-c463995a9c96	4454e5b5-c68a-43a0-9f81-700128adf005	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 12:32:22.278809+00	2025-12-25 12:32:22.27881+00	f	t	2025-11-25 12:46:56.810827+00	rotated	2025-11-25 12:46:56.567557+00
3883f5bb-3b8a-490a-9ee2-03ddfc6de439	c1d918d1-18d8-4837-a271-967d90f569a3	f0646cd308b49793202517fe307a1fdec90df67feebf3637257a0fd5af224a7c	966a7a73-f910-4dcd-91cb-cf43283c9b35	76537a61-dd81-4a79-bfe6-c84f1ee3b727	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 12:48:35.547608+00	2025-12-25 12:48:35.54762+00	t	f	\N	\N	2025-11-25 12:48:35.547661+00
3ca5fff7-6414-42d7-84c7-162a5e9f2fbf	2a04b41b-422f-455e-85c3-4c036e692b3c	67a2c3ef3449b87229537f8a1613b928fe0df7308292bce63e5f230ea5acf375	97506fbb-0d3c-45c8-8d45-7d89e14fba31	34c21c82-d5eb-455b-bccf-bfc674030b56	171.233.114.75	PostmanRuntime/7.39.1	2025-11-25 13:41:34.783259+00	2025-12-25 13:41:34.783261+00	t	f	\N	\N	2025-11-25 13:41:34.785379+00
c8514f30-c47f-4a6c-978d-9f3248b7b88d	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	b41abbd967990400f73e75affa5cf68bf30bb8d90dbf32b09e2dd501c19811ac	ed1b9b22-a2e1-4b33-a9aa-4bd322dfc2cb	6c5f1adb-da85-44a1-8e4e-7c186852e688	1.54.252.240	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-13 14:49:55.970812+00	2025-12-13 14:49:55.970815+00	t	f	\N	\N	2025-11-13 14:49:55.97087+00
14452ee7-271b-49ed-94bd-9a37a911f386	c1d918d1-18d8-4837-a271-967d90f569a3	ea3772566a258050908a2cb5caa98ca2f50be6638d1ac7481bafaeb7b0df631a	94d13eb4-0a54-4092-84ed-76fb6794c6ee	c40c5171-d999-41c1-a218-d4af4fbcaddb	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 14:55:06.33054+00	2025-12-13 14:55:06.330551+00	t	f	\N	\N	2025-11-13 14:55:06.33062+00
33860d57-82c7-4aa1-8c3f-58eb0ff6f2a0	c1d918d1-18d8-4837-a271-967d90f569a3	70d35c08dc61504b371edb4dc4952bb9c71e9d08f41ffb2487c09538086e048a	73507bcd-d42d-4708-9425-556e7066871a	32a3c495-0fdc-4afd-9f4d-0f89de86671f	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 15:07:21.229505+00	2025-12-13 15:07:21.229508+00	t	f	\N	\N	2025-11-13 15:07:21.229553+00
4ee79ce4-35fc-4214-b8dc-2142aba0c6ce	c1d918d1-18d8-4837-a271-967d90f569a3	2be8e0bae60294c3d5e83e0fdea5b06f21b63af1da3ce298932eed81565f4a43	b0ffc87b-39e9-4c54-94d8-a5425fee5bfd	7423fa08-58fb-4190-906e-3612d45a5d26	171.233.121.226	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-13 15:08:07.72737+00	2025-12-13 15:08:07.727374+00	t	f	\N	\N	2025-11-13 15:08:07.727399+00
bf1a6a53-2e24-4135-a773-005e04a8bc6a	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	ca54c62888293b6edb8443724d10ea2d9bcee9e296258b30fc35ae1436e49bef	227ae997-0d44-4514-9eaa-c6eb1c1ee08a	7c9277d2-6370-4bc4-9101-bb456feafd00	1.54.252.240	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-13 15:17:54.151685+00	2025-12-13 15:17:54.151686+00	t	f	\N	\N	2025-11-13 15:17:54.151714+00
35335c5f-3a3a-4531-adcf-ff21a3004f64	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	467974f32ca4f575527c56e2c690d00959065666a4e20ae62abd217a8b3a5c90	227ae997-0d44-4514-9eaa-c6eb1c1ee08a	50655f73-f816-4e69-8f14-6be10eda91f9	1.54.252.240	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-13 15:03:13.86834+00	2025-12-13 15:03:13.868343+00	f	t	2025-11-13 15:17:54.149255+00	rotated	2025-11-13 15:17:53.975432+00
3f5a1e9d-a6e7-498d-af18-88e1d47ed368	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	97af1379eb418e4e71296d4a6d062e95cba7ecc4f4904b17e0df44beef8cb771	cbf40a32-5ceb-4252-9222-3d1bec72ae12	25ae6d00-1114-41f9-9bf4-20d5773cf83a	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 14:38:34.653896+00	2025-12-22 14:38:34.653899+00	t	f	\N	\N	2025-11-22 14:38:34.65393+00
b2920a22-b0dd-475c-b77a-3b0df6447f48	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	77b08f97105ef4ad01199c985c91bc904b4592bcba4e3ffb1184fcbc2163f94f	1d31ac24-c84c-4951-8ae9-3528cf515b00	f6a6972b-6311-40b8-9bd9-80cbdb348dc7	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 03:48:17.682629+00	2025-12-24 03:48:17.682632+00	t	f	\N	\N	2025-11-24 03:48:17.68266+00
ff1c5e32-6b6a-4a72-90c0-b56a95c30a61	987fa969-961f-4afb-98aa-636c3448bd87	a1158b871bfaa860d53a78da6f7fdbc4802bfd3faaaacd6a71d6495637d77436	b98e7f52-016c-4cff-a3bd-f5f2e4bee664	737255f8-de73-4a29-889c-4b0990b312de	171.236.70.111	PostmanRuntime/7.49.1	2025-11-24 12:18:59.450106+00	2025-12-24 12:18:59.450124+00	t	f	\N	\N	2025-11-24 12:18:59.450198+00
b2fa7373-fab6-4ed0-aba3-f368155b3727	987fa969-961f-4afb-98aa-636c3448bd87	96d94ba97cecee4cff9093857f260d12b9d7d0d986915ba67ece5371bcea9f3f	9b33614d-927c-4659-bd3d-ff9cb99f51de	a1014aa8-e2c8-48f2-a4c3-df40022735c7	171.236.70.111	PostmanRuntime/7.49.1	2025-11-24 12:19:20.76741+00	2025-12-24 12:19:20.767422+00	t	f	\N	\N	2025-11-24 12:19:20.767436+00
c6d47cbc-e600-4280-b65e-920a755c9414	987fa969-961f-4afb-98aa-636c3448bd87	2482078f51e00c4bb513195c2bc43277f18fd9711cf44a7f54e67609bf20b8e2	30cc8375-bcad-4826-a64c-b628b94d27b4	e0839be3-96bb-44fc-943a-8bd68d6a149b	171.236.70.111	PostmanRuntime/7.49.1	2025-11-24 12:19:48.104694+00	2025-12-24 12:19:48.104717+00	t	f	\N	\N	2025-11-24 12:19:48.104763+00
341574b6-88b9-42fd-a103-9dcbe5524b59	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	251f7ccc5e735355db75cea9d7cef3c0812b487e634232714c94f54cfdb1bd73	27763199-abec-496d-b40a-9a1e38743620	46e22265-ef52-4d73-bc2d-091858d92bdb	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 00:35:18.035895+00	2025-12-14 00:35:18.035897+00	t	f	\N	\N	2025-11-14 00:35:18.035936+00
ebc0cbd9-c0a4-40b6-aaaa-f7aad5742fda	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	1bd87e0d0868a2867f60fe5003a5c30988d949c21155465ab86f67d049bdecef	9b2bd9ca-a370-4a32-a41f-5fc86b30b5a9	a5fc1f0f-72eb-4bf2-88c1-2d7ec14b206c	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 01:21:02.013374+00	2025-12-14 01:21:02.013396+00	t	f	\N	\N	2025-11-14 01:21:02.013455+00
f6086d5d-cd98-424b-9c48-67dc8b3ddd74	987fa969-961f-4afb-98aa-636c3448bd87	ac6fd785043d134b74a4c1c03212baa83d6221e7aa4b491e74b093ca957f2d27	f7c05932-6590-491d-b96b-311010bc087f	fbd9890e-dfe8-4965-90a8-66415a2d1ac3	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 05:15:33.13702+00	2025-12-25 05:15:33.137022+00	f	t	2025-11-25 05:30:18.365406+00	rotated	2025-11-25 05:30:18.147995+00
c3c7c1b2-145e-4213-b401-374b02cb14fb	987fa969-961f-4afb-98aa-636c3448bd87	ee10109c52a0c8efac1f0e3894ea0d42eb11a7e792759ab5a6433c9b1ce3459c	f4348637-5de2-4128-bff4-4eb3b3580a7c	3b94c71b-3fab-49bd-aae8-498987cb0b17	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 11:20:50.632042+00	2025-12-25 11:20:50.632044+00	t	f	\N	\N	2025-11-25 11:20:50.63208+00
1edcb558-bb53-40bf-a802-9c5f57304124	987fa969-961f-4afb-98aa-636c3448bd87	ab0a2e6008711bda6fb1df9b8c9133b93466313bc3b330f30ffbbdfb70a5fc18	d1535a6d-8149-45c6-8f65-c463995a9c96	0005c93f-4de9-4513-999d-12a88bdab612	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 13:00:59.845922+00	2025-12-25 13:00:59.845923+00	t	f	\N	\N	2025-11-25 13:00:59.84594+00
2610d6e1-f2e3-4caf-9622-fcb01518f0b9	987fa969-961f-4afb-98aa-636c3448bd87	db45c875e854f896557dd76a51934062950391def49aedf37b8c36895b8adb17	d1535a6d-8149-45c6-8f65-c463995a9c96	4af4dc72-6f0d-434d-8790-38d697052b20	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 12:46:56.811152+00	2025-12-25 12:46:56.811153+00	f	t	2025-11-25 13:00:59.845568+00	rotated	2025-11-25 13:00:59.638959+00
ff29eb42-8f4a-4717-bb68-c9b58feb57a5	bb8259df-3cb8-487a-ab91-2ef95a68aa44	6b43e09be4c2ef19e7306eb66c8ea6ac0716a52c1e44b138a526a065ac31fe18	31fb0300-a0a8-4531-8498-0814e61975d3	0620ace7-26b3-4354-9c31-32594c47d0b8	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-14 01:53:15.565591+00	2025-12-14 01:53:15.565593+00	t	f	\N	\N	2025-11-14 01:53:15.565629+00
7f2de199-206d-44e6-b469-32e4187f7bfb	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	22e47e172c2924d5c6611098f2711a7923e1f8e145d012b2c557cb5f114f4dcf	43a9b559-fcd8-4b24-8cbf-bab108e7adaa	6502d1a1-1478-4809-a242-b80c136038a0	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-14 01:55:01.699842+00	2025-12-14 01:55:01.699847+00	t	f	\N	\N	2025-11-14 01:55:01.699906+00
0f5e6a60-6136-4544-9ed1-184fdf5bf204	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	e1535c2784cd47a80bd90fbe6d1fc511fe0f24fa12604ca61ec65188b918ca74	3a0391c9-60a6-434e-8fd1-ac71f4b7dbe4	a234e294-317e-45c9-8ebd-f94dea683157	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-14 01:55:38.589139+00	2025-12-14 01:55:38.589141+00	t	f	\N	\N	2025-11-14 01:55:38.589189+00
c3f2a538-0545-4d5e-aff2-b5042f6df040	bb8259df-3cb8-487a-ab91-2ef95a68aa44	5685f4bd9e80c7758769908acfae40e95099d5778d51b71dd72c94c1b6fbff9b	f5629fce-00ab-4cbb-8dab-8ce2deadf8cd	eae1383d-a48a-4753-b458-ae885e3915c4	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-14 01:56:22.086652+00	2025-12-14 01:56:22.086655+00	t	f	\N	\N	2025-11-14 01:56:22.086687+00
2ca9c948-b334-43a1-afa6-d8599a518632	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	4a113d43d98f19643cd0f649adf15dc1ae79dc261a5add53b4dc0df8f3c932cf	0f59ca91-1591-4711-b26d-18100847ff41	ab060f45-b15b-4d59-8c6e-3aa2f97f6c44	58.186.28.4	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-25 13:13:00.786651+00	2025-12-25 13:13:00.786652+00	t	f	\N	\N	2025-11-25 13:13:00.786698+00
713b14f0-4908-4cc5-9d09-4a28cd457316	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	01c3f4659851078c9b2513e4f9dde5ddaedd92f266e5ebc348e78cf544c3f1d2	0f59ca91-1591-4711-b26d-18100847ff41	d2a9542b-416d-4461-a282-af31f5ed7168	58.186.28.4	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-25 12:58:19.310389+00	2025-12-25 12:58:19.310391+00	f	t	2025-11-25 13:13:00.784282+00	rotated	2025-11-25 13:13:00.579853+00
fe66853c-53fc-40d0-8438-8e8c2ab745b9	2a04b41b-422f-455e-85c3-4c036e692b3c	db8019d8ae8cb66f50aa644d2ac16acb2a13e8ba4a72310a549a48fa0e7ca2f9	bdb67ba0-59b1-427b-8c0a-815aa79d5be4	f4ce1410-df32-4e7e-8c75-79bfa5b72eab	171.233.114.75	PostmanRuntime/7.39.1	2025-11-25 13:42:16.022405+00	2025-12-25 13:42:16.022407+00	t	f	\N	\N	2025-11-25 13:42:16.022425+00
3fa5ed36-9496-4315-a4ad-dec36db0cf95	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	f1c1576918488b4062e575c1490c1b646ce1627e2bd249166f54c96691c10179	09923537-19ee-48c3-bcaa-17ca99f47a83	4279c5f7-9773-43a2-ab24-a61f69f7a87b	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-14 02:11:43.085826+00	2025-12-14 02:11:43.085828+00	t	f	\N	\N	2025-11-14 02:11:43.085866+00
5776d83f-2fc5-4bb5-9a01-a4f705c54348	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	0f0e12b2faf881a6cc679f3adabf67fcf36a9c74736705fa8817da81f2f83b76	09923537-19ee-48c3-bcaa-17ca99f47a83	403aafbf-74ef-412d-9c54-ebc789da5175	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-14 01:56:49.749319+00	2025-12-14 01:56:49.749322+00	f	t	2025-11-14 02:11:43.085484+00	rotated	2025-11-14 02:11:42.903162+00
03678f2e-fd22-4e45-8c82-b1b8c9b18b0d	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	25d6e144780dc816d8f3bd6c6b223a5f342661d6790cd0db071c976dbb482cba	e2876034-46ea-40f2-893e-621d91d7886e	36845140-2a9d-4e70-aeb7-d57f05babfeb	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 02:20:19.645812+00	2025-12-14 02:20:19.645824+00	t	f	\N	\N	2025-11-14 02:20:19.645875+00
bc4d2b7e-5fb2-4fe4-8ab0-ae0713bdcc3f	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	9bc5eeabbfdb28f303ea9969ba1e0445a5a47f5ed53cc23943e97459dfcf287a	f31b8009-6b89-4a4d-8993-53a5e9184f06	c1acf22d-9129-49f1-b53a-bcceebc4d7bf	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 02:27:04.210259+00	2025-12-14 02:27:04.210262+00	t	f	\N	\N	2025-11-14 02:27:04.211318+00
3af62bd3-2dfd-458c-991a-c8172ac49b1e	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	823924d69b386d212677a06f44960bbff16b787fce79138242ad9c5131633a64	84f0efd7-ab1b-435d-ab0a-aa4102eabdae	c6c474ef-42fb-458e-aee2-a0a0a13ece72	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 02:28:29.98122+00	2025-12-14 02:28:29.981228+00	t	f	\N	\N	2025-11-14 02:28:29.981258+00
e26e6028-4f39-46ed-bb9c-09deafa6869d	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	c3535baf66dd84a0a332ebcbdd0a4290eaf45e3fe89dec5a374777c5d990581d	a4fd0ebe-cca9-4cb5-a278-8a1fc1f3af65	0769698f-d1cb-47fa-9330-152cb85e8c1e	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 14:49:43.438687+00	2025-12-22 14:49:43.438705+00	t	f	\N	\N	2025-11-22 14:49:43.438745+00
d46799f9-8908-4f09-bf1e-d8c284c098fb	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	a1d70b5795c35ce5ed2d241c4f1e8ee960d23d2a8b6f05f8467e417cd71316a9	61637da3-3519-4ac2-afaf-dd1b2d086285	c37961d3-ebc7-4eb0-8ec3-f0e7f0e770b9	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 02:31:46.609625+00	2025-12-14 02:31:46.60965+00	t	f	\N	\N	2025-11-14 02:31:46.60974+00
66535f00-16df-4b0a-9d7d-1f2ae5732f85	987fa969-961f-4afb-98aa-636c3448bd87	51cd88bcd9afa095cfb3e1f974be43f68bb8da5edd2170db1a509a3d3ecb88ed	f3fcc9fd-8159-4505-87bb-dcfc5cc6cc77	040c6257-7cb5-46fd-a311-29478dbfa425	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 02:45:55.341517+00	2025-12-14 02:45:55.341525+00	t	f	\N	\N	2025-11-14 02:45:55.341579+00
07c95147-be00-438f-92c7-213fb1e8c92f	987fa969-961f-4afb-98aa-636c3448bd87	85abe63f97f60f23061e459755db53c017d446297544a43279d0ec18d91cc841	cc8c4a91-d47f-4782-8e08-17264a8061f6	2555a13d-f2da-4a8f-b956-fdf9eba05e4d	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 02:46:41.42026+00	2025-12-14 02:46:41.420263+00	t	f	\N	\N	2025-11-14 02:46:41.420323+00
868de199-1b6b-4663-a414-9e607e1a5841	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	61e3506a0e6637a88667bbc0b7f877679e2cf29223656ee86d40d2439f713623	8d759080-082b-48bf-a82c-7a648d300067	5ad6f489-b82a-4e1c-80c6-caf0e6467c19	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 02:47:22.415054+00	2025-12-14 02:47:22.415057+00	t	f	\N	\N	2025-11-14 02:47:22.41507+00
071759f6-c83d-4ef3-a3f9-9a84c54d7360	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	3e732d0d3f74548628895250803954933af8160017fe75418328eecf69d65c5d	fe598e1f-41b8-4a44-82fb-deb53f6f295d	074077a6-0d6a-46dd-a454-a2ba7e68ace4	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 02:48:44.877263+00	2025-12-14 02:48:44.877266+00	t	f	\N	\N	2025-11-14 02:48:44.877312+00
f330a443-5edf-4925-8ba2-027763b13257	987fa969-961f-4afb-98aa-636c3448bd87	5d6c01146f1984acb1d32bfa6a610aeb4e3f5165e0d02f9f8f7a74dc7b624a38	b28da17a-9ca6-4615-af3d-c5b2b6cf5b84	9f54846a-b5d1-4c10-8254-6ba28ba86f52	42.114.44.105	PostmanRuntime/7.50.0	2025-11-14 02:52:48.242523+00	2025-12-14 02:52:48.242526+00	t	f	\N	\N	2025-11-14 02:52:48.242584+00
dfe1a0c0-ce59-4342-b168-54636dbbd638	987fa969-961f-4afb-98aa-636c3448bd87	112e833845c74765f51522ccd9b03ab7b1dcfc4aea813d982f9272ec1b462204	2f3f5369-0c4a-4e9b-a6bc-dc527472d90d	7706b076-d8d7-441f-ab27-7d42155bfb37	171.246.65.181	PostmanRuntime/7.49.1	2025-11-24 13:49:13.511894+00	2025-12-24 13:49:13.511943+00	t	f	\N	\N	2025-11-24 13:49:13.512024+00
4eb03d9a-55ed-4f79-b28d-f2fbe99bc7d5	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	14144c4cb68e73f60e4c2cebcfdb25f40d072f9678f562ec26de011728b33b4e	46bc06e0-b79f-4e69-8f7b-9a51e6bf58fa	49edc44b-bc58-4170-87da-e95bac401aae	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 03:10:35.318689+00	2025-12-14 03:10:35.31869+00	t	f	\N	\N	2025-11-14 03:10:35.318724+00
fdd03c09-42c5-4100-a67e-162d47f0b593	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	cd880aa6981c395c70d8d7c5645a549f59517c394511b8f9da8a36f94f910b42	46bc06e0-b79f-4e69-8f7b-9a51e6bf58fa	e2c77e30-cd90-4e8b-aff1-a559fed53909	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 02:55:35.373398+00	2025-12-14 02:55:35.373401+00	f	t	2025-11-14 03:10:35.318384+00	rotated	2025-11-14 03:10:35.122622+00
0fc01c82-0e50-4e9f-81b9-4f541c996648	987fa969-961f-4afb-98aa-636c3448bd87	0c4664aa60f9f3d48f764bcd8d3ba5590a01b15cf7722ca3a770e7dc8bab1127	14e0e2ad-8576-4c28-86fd-39e4509c7bda	06781cff-09da-490f-a775-6754f2c69896	42.114.44.105	PostmanRuntime/7.50.0	2025-11-14 03:11:30.405438+00	2025-12-14 03:11:30.405441+00	t	f	\N	\N	2025-11-14 03:11:30.405491+00
9f86f334-1112-4d4a-8d8c-e8867ddb1573	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	74b0afe8b04f4887824bda43ad80f38eb198afb5bba21b95fd8a6b67598112b0	5616fb8e-8246-453c-bbea-6ff294c4b1c0	63669a26-3bb9-406a-a3ad-ae72e7c19118	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 03:12:31.154706+00	2025-12-14 03:12:31.154709+00	t	f	\N	\N	2025-11-14 03:12:31.154758+00
95489927-5e84-45c2-861a-d351c4248a79	2a04b41b-422f-455e-85c3-4c036e692b3c	118635e2c099c047a14e5bd2618a1f111d8d6b126152c195632cb4bda9e00498	df67e0e8-03f8-4451-86f7-b777636891a2	a3c073ff-fff2-4251-9139-7cdb1d205154	171.233.114.75	PostmanRuntime/7.39.1	2025-11-25 14:03:24.221357+00	2025-12-25 14:03:24.221358+00	t	f	\N	\N	2025-11-25 14:03:24.221368+00
1732aeec-ab5f-4e2d-ba84-28559465ee68	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	0f8a73af8e523bdc385d905ea7cf2a181764474b2e9b32cb040969b8d51699c1	aa13e98d-855a-4dc8-9328-f163538a0ea3	93a8967a-8dd0-4d10-a64a-315fdb21e63f	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 03:31:21.74781+00	2025-12-14 03:31:21.747812+00	t	f	\N	\N	2025-11-14 03:31:21.747845+00
13bdb2c1-5a3a-47cf-89d6-f8b35c50a4f4	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	4afa1e2978b66ff0b4eab4a53156c149660b2508680c8162610258eb5b7fbb58	aa13e98d-855a-4dc8-9328-f163538a0ea3	3994fe89-33e8-49a1-a696-405e61c7b958	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 03:17:03.175125+00	2025-12-14 03:17:03.175128+00	f	t	2025-11-14 03:31:21.747471+00	rotated	2025-11-14 03:31:21.594169+00
838c55e6-4630-4874-a709-47fd78c0c581	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	84cb5c81b9b3e474a7db9227a838a9deeb9e4d48186bfd0ae06dd77af17d2a1d	71ad24c4-463d-46a3-82c3-528bff9e1997	895cb290-90eb-4416-8c5c-c6b9976c0166	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 03:44:26.215451+00	2025-12-14 03:44:26.215454+00	t	f	\N	\N	2025-11-14 03:44:26.215495+00
1973a8b3-67d8-4200-8d19-07ad5a6d282c	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	f9b24ae875b6da77ec1eece4b1a76a7cb557498beb7f2318c03abc65d6bbde01	332fda42-43ba-440e-b4d5-a95a31965f1d	b92f8f3a-7ab4-42a0-8490-1cf23cb0eeb7	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 03:44:46.867277+00	2025-12-14 03:44:46.867279+00	t	f	\N	\N	2025-11-14 03:44:46.868345+00
eee18ca1-6a25-48f8-92e5-b004d6db4aef	2a04b41b-422f-455e-85c3-4c036e692b3c	bf2fa94b85fd775f7362c686d7fba61c22cc35e6ac15926efbaa38a4c7bba60c	9477f3e0-92ef-49ec-bd46-b55b4343a0fa	2a4b9ea9-896f-40e0-8993-eee4742079d6	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-14 03:55:01.909743+00	2025-12-14 03:55:01.909756+00	t	f	\N	\N	2025-11-14 03:55:01.909816+00
ad51e2f1-0dc7-4478-900d-24052235a17e	2a04b41b-422f-455e-85c3-4c036e692b3c	67b6511b0235d0b23910ad67c402a24b84a2beda79adf3ae1776d03f3736e0e2	bd8665a0-27e0-4b9f-94e0-ce808c16ef81	a7a39bca-a917-49bb-af89-3ce86cb8c584	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-14 04:42:16.904836+00	2025-12-14 04:42:16.904843+00	t	f	\N	\N	2025-11-14 04:42:16.904891+00
f5b77cb3-0984-44f0-bf3d-b51af60e781a	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	65b224cafde5d25c0116b8d072b35b8c326fc4fc39d538dced3892a0247e1095	0388fbe1-7328-442b-9b9d-5daa1735ad1a	8c0b4abf-f163-402c-a6e0-108b6f0190bb	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 04:46:39.381447+00	2025-12-14 04:46:39.381453+00	t	f	\N	\N	2025-11-14 04:46:39.381532+00
5d3fcd58-e2b0-4dcf-a002-1f0cfc568354	987fa969-961f-4afb-98aa-636c3448bd87	8fbd5b2eeadb9c8f982547a19877944a569c1ce76dbce1b9b29a155609b86e7b	a5edf891-2d88-44bd-9144-7f3c314cf908	6d920972-602d-42d8-8232-d7dbc18e8bb9	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 06:20:23.667157+00	2025-12-14 06:20:23.667163+00	t	f	\N	\N	2025-11-14 06:20:23.667243+00
882d0188-a784-4744-bc4c-b2f4db6982ec	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	0640f40c0f5f7b07e74978016ab96ae98a8f550ddf866d1a2ecb677461b6d069	7d12a86c-ce9f-47ed-81e3-8d03fa91b56e	40971cd2-3e33-4d9b-9e9d-34a72cb71a9b	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 06:23:11.719591+00	2025-12-14 06:23:11.719594+00	t	f	\N	\N	2025-11-14 06:23:11.719627+00
b49a1005-9221-43be-981a-a3c05cab9e80	b46b4c47-31c6-4ad2-9829-0332963bb646	560153f48ddcae3c345c4e633b9f420fc75d43c2063ac2bd4e6d9c905432163b	c1f651a5-386d-4601-81ad-314e6e7d68f4	8b35c7d3-e9f9-44ed-a622-2d039ce08459	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 06:25:15.99918+00	2025-12-14 06:25:15.999187+00	t	f	\N	\N	2025-11-14 06:25:15.999212+00
7860b086-f155-4ec6-bb07-e7d7b5f176ba	b46b4c47-31c6-4ad2-9829-0332963bb646	1c854d86ee0f73d03ec9a54abf038e12e6c0fb7910d9271f3e45ba2c71989492	8e410711-83eb-4cc2-9052-06495acf5daa	16f3a2f6-611e-483f-b04e-87b1ff9dce02	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 06:26:00.528373+00	2025-12-14 06:26:00.528379+00	t	f	\N	\N	2025-11-14 06:26:00.528408+00
b72277fd-c830-404f-91f4-6bf578e23433	b46b4c47-31c6-4ad2-9829-0332963bb646	0cc58a8fc3b674387ade68c2ae46cc6d6f7da8b53791ff48d6d5607ace117fe7	00e71641-4bee-4f6d-95f9-84b064b13fd2	c74603d2-a6de-4e77-9cb6-841bc2827c3e	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 06:43:49.506758+00	2025-12-14 06:43:49.50677+00	t	f	\N	\N	2025-11-14 06:43:49.506838+00
a0cf31bf-599f-4d90-bf8b-53f6b634be02	b46b4c47-31c6-4ad2-9829-0332963bb646	1b6288b954b7fd70c573c0ade3027e53c95073a4e5b3f4539f3f3a2faa710837	37ddb4ab-d7d4-4f25-899c-f9c705c1b7f2	1cd38dd8-04cc-499b-9264-77bb5affb749	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 06:47:59.441965+00	2025-12-14 06:47:59.441968+00	t	f	\N	\N	2025-11-14 06:47:59.442018+00
5ffdd3ce-32cd-4890-ad0f-512d7f42a85e	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	38931bc323edd3e5c8416dab04696c5d08e555b507bab6cb91989c70a690260c	ca485c88-9d6c-4037-8063-0049a18c6f61	cbf5c3e6-1b01-4ad8-998b-e337479e8a23	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 06:54:55.698682+00	2025-12-14 06:54:55.698692+00	t	f	\N	\N	2025-11-14 06:54:55.698744+00
1ec712e6-b34e-4522-8fb4-4007584686c1	b46b4c47-31c6-4ad2-9829-0332963bb646	ef33b93b253ef056db8eb0c2e5af37a51517adafcf13a4a8d0b491c54709c129	4d2361cb-9f9d-408a-bc9e-6a038a8d4ab8	023551d8-962e-499e-b21f-cb214b18c155	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 06:55:44.981271+00	2025-12-14 06:55:44.981273+00	t	f	\N	\N	2025-11-14 06:55:44.981312+00
23b16583-1e83-4361-b05b-a4687fb5120b	b46b4c47-31c6-4ad2-9829-0332963bb646	ac1f906790f33a3d666f80032f1a93b52abee9a41ec88df825880c4cadca6bc8	00f07a32-4389-41be-9559-425dcca88556	856da683-3017-45fb-8763-6d1b9f72e60f	113.161.234.220	PostmanRuntime/7.50.0	2025-11-14 06:56:58.080811+00	2025-12-14 06:56:58.080813+00	t	f	\N	\N	2025-11-14 06:56:58.080829+00
50e35889-da25-4a1a-9187-b3662e631ee3	987fa969-961f-4afb-98aa-636c3448bd87	31673a6f6f58c90203b38e97793d912d8382c36b2be2ed71c6376796c24d7019	d84a4bd3-2b27-419b-95b3-1997edbca576	75fb7425-8f09-48b1-8dd5-80bde8ef4fe6	171.255.186.225	PostmanRuntime/7.50.0	2025-11-14 06:56:58.733478+00	2025-12-14 06:56:58.73348+00	t	f	\N	\N	2025-11-14 06:56:58.733492+00
7405a96c-42f7-4e02-9a83-d9f3012f338c	b46b4c47-31c6-4ad2-9829-0332963bb646	b668c64e500c0ebe29fe6d5102cf62968178c716b9e0587ca0ba5340ad609768	40b312da-01ac-4fae-9f25-36c0314a80e6	dae0f6cf-97ed-47f7-943d-02aa3c73253d	171.255.186.225	PostmanRuntime/7.50.0	2025-11-14 06:58:47.201407+00	2025-12-14 06:58:47.20142+00	t	f	\N	\N	2025-11-14 06:58:47.201471+00
7860b9ad-1210-40b9-a7a9-1feabc8fc11a	b46b4c47-31c6-4ad2-9829-0332963bb646	25ddb441974c14c6e68d04362d5ccee4f3c83cd38c4ee284bec2c77dc07ee463	0e6345b2-c167-4b35-b5b4-29a40d37dded	0a51deff-8285-4930-be1b-93ede5e5b4a9	171.255.186.225	PostmanRuntime/7.50.0	2025-11-14 07:00:03.628984+00	2025-12-14 07:00:03.628987+00	t	f	\N	\N	2025-11-14 07:00:03.629003+00
9103c73b-f921-4f78-9e62-13bf6ac7eef7	b46b4c47-31c6-4ad2-9829-0332963bb646	4bc26fa59fdcb8302d38deec3d5c976c34c2e920f4c355e7b1112c47dc48c6db	83d24acc-70a8-482e-ab14-683e0358fd75	9b2d2de0-0240-48ad-a11e-197ffdb9c639	113.161.234.220	PostmanRuntime/7.50.0	2025-11-14 07:00:37.357011+00	2025-12-14 07:00:37.357018+00	t	f	\N	\N	2025-11-14 07:00:37.357039+00
c0255c72-9fae-4666-940a-fc10804e675c	2a04b41b-422f-455e-85c3-4c036e692b3c	470ec36c0b76870e3c4bacb3e26688e2621c3072bde7338942fe3f4705c71cc9	d0db0dac-56f9-49c9-8561-8de3d15bde37	0c1bf7f1-3843-4865-86b5-65bf45dd0972	171.233.114.75	PostmanRuntime/7.39.1	2025-11-25 14:47:22.630819+00	2025-12-25 14:47:22.630833+00	t	f	\N	\N	2025-11-25 14:47:22.630915+00
82da178f-97e8-4fe5-9c53-58cdfd62c358	b46b4c47-31c6-4ad2-9829-0332963bb646	21359f97c171f3414c89c1bca9b208b8406bce1a0a5f6b4a27be538f7deb0450	80b4946c-57a9-4ab3-b75b-63f41efdc802	66cf1bd7-df0a-49dd-ab8a-b9c60316a1a3	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 07:27:19.285364+00	2025-12-14 07:27:19.285375+00	f	t	2025-11-14 07:37:56.800027+00	rotated	2025-11-14 07:37:56.671051+00
d9988f95-5c13-48f8-bc56-6dcb22089fba	b46b4c47-31c6-4ad2-9829-0332963bb646	3616f8f4a2f0e8b3da5ed6507ff204a4afaa085d8334fe11caf6461c4c2556dd	80b4946c-57a9-4ab3-b75b-63f41efdc802	f14c3615-becd-4cd6-84b0-84d7ab9cd14c	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 07:37:57.347393+00	2025-12-14 07:37:57.347394+00	t	f	\N	\N	2025-11-14 07:37:57.34741+00
1f7c5ee7-a214-4f0f-b7eb-3dd29d3f1cd3	b46b4c47-31c6-4ad2-9829-0332963bb646	176ff50a751acf21422c4b388b8914e3c3bd4e107f9a417730311b292940a7ab	80b4946c-57a9-4ab3-b75b-63f41efdc802	599ccadc-cb1a-43ec-8b2c-b94472aaddfc	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 07:37:56.800346+00	2025-12-14 07:37:56.800347+00	f	t	2025-11-14 07:37:57.34713+00	rotated	2025-11-14 07:37:57.221024+00
14e67a23-b794-4be1-99fb-deae52bd4760	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	6e67bdc9bde24adf4b770252d83670d70f13e4f40590faa74f17fa227e57c5a9	7b248d7d-7b00-4c85-9eb7-44873a2f3216	1e4b6908-4e44-4504-ae1d-070e0e59b25e	171.253.157.127	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 07:41:23.091639+00	2025-12-14 07:41:23.091649+00	t	f	\N	\N	2025-11-14 07:41:23.091703+00
e3c29f19-bf18-4cf1-8120-8941c4fb9ee3	b46b4c47-31c6-4ad2-9829-0332963bb646	dac2d896990948f69e9df9621a79c3af7f4826a5282aa2421d018cb19fcd0b9d	65fdee4a-0415-489a-b1a5-3a2f12578f11	40b709d1-8df6-4190-8dc8-31d2c72a8872	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 07:43:44.462657+00	2025-12-14 07:43:44.462669+00	t	f	\N	\N	2025-11-14 07:43:44.46274+00
3d3304d4-5883-417f-928f-c672f1fe10c0	b46b4c47-31c6-4ad2-9829-0332963bb646	08049b7cdd39b7a362d03afa6c7740396fa6ae9b63aec4c9f6138aee257dbbf3	b15fed14-f762-4ca2-8c27-101b069193d1	51c2f3cd-e48f-4962-9dd5-9fde071e77dc	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 08:15:11.208687+00	2025-12-14 08:15:11.208693+00	t	f	\N	\N	2025-11-14 08:15:11.208724+00
581baa12-73ac-4fde-b1e2-cea16449f1b8	b46b4c47-31c6-4ad2-9829-0332963bb646	33d24034d718ec55a3fcbbb757bb0efdabe41d6ba308862b53dfd27df9040d17	b15fed14-f762-4ca2-8c27-101b069193d1	26e61a80-e48e-40be-9d88-8246a4a8d4da	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 08:01:04.766832+00	2025-12-14 08:01:04.766844+00	f	t	2025-11-14 08:15:11.207262+00	rotated	2025-11-14 08:15:11.073814+00
41efc5cf-2ecd-4ed8-82b1-fbec5787e509	b46b4c47-31c6-4ad2-9829-0332963bb646	60c8b248d08cabafc8aad409bb52d972ce055bdce60f419fed86cf416ffff166	a521770e-5bf1-4997-bbee-ce2714300f49	87bb6ea9-8420-4c15-9287-8f9dbccb7912	113.161.234.220	PostmanRuntime/7.50.0	2025-11-14 08:27:15.284394+00	2025-12-14 08:27:15.284408+00	t	f	\N	\N	2025-11-14 08:27:15.284457+00
9dade50d-534a-4ffc-b3da-9997341517b3	b46b4c47-31c6-4ad2-9829-0332963bb646	fc0ac7136d211d35828d03fffcfdb9cfa5b22ecd702c9ea91423ffd49f8815a4	8ac50816-23cc-43f0-b31b-86a895045477	a824168c-7bf4-4bc8-bd52-4bf35462b6f7	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 08:44:30.041013+00	2025-12-14 08:44:30.041015+00	t	f	\N	\N	2025-11-14 08:44:30.041046+00
c355aaee-3c0c-45f0-a8be-5e97533d1ff7	b46b4c47-31c6-4ad2-9829-0332963bb646	6df71f12b5382bcbc939381558f2826e3d74bee3aecd0bd9088070d695db9e77	8ac50816-23cc-43f0-b31b-86a895045477	d6e78e2a-4baa-4588-b53d-04ead6cda043	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 08:30:24.595536+00	2025-12-14 08:30:24.595539+00	f	t	2025-11-14 08:44:30.0407+00	rotated	2025-11-14 08:44:29.898818+00
b23cff3b-a29d-4b81-afb1-30de741da2cd	b46b4c47-31c6-4ad2-9829-0332963bb646	94826b4452c0e7d254f9bf436a4474cdd54bb6520a7d5bb00342c4a2a83080bb	1d2f1a60-1c3f-429a-af3a-7146cc0f9b06	015f1f40-4b54-4da3-a8e9-8f9456daaedb	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 09:07:16.570414+00	2025-12-14 09:07:16.57042+00	t	f	\N	\N	2025-11-14 09:07:16.570469+00
33886cba-9dad-4b31-8bf7-7d3ea4a0d173	b46b4c47-31c6-4ad2-9829-0332963bb646	c89799c34dd7ab7e182b80291ec7b094ebd7af8dbfe6b30199f5218d1a7ae791	48754e14-f903-495c-8108-09373a58b8bf	00b753ed-e665-4c39-b2a7-920b62395f19	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-14 09:27:23.661327+00	2025-12-14 09:27:23.661339+00	t	f	\N	\N	2025-11-14 09:27:23.661394+00
f3abaf29-54a0-4139-ae2c-e69457a20cc5	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	8053650dd26e9d67612bfeae30288fad3d550639e073d9c477dca05324e30e8c	80763c63-1f65-4a7c-8743-bf707352a354	9e0cfbe6-f076-493a-bf3e-dd4aa491ac0a	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-15 08:38:14.118506+00	2025-12-15 08:38:14.118516+00	t	f	\N	\N	2025-11-15 08:38:14.118567+00
cbb1d163-855d-43d5-94b4-e2e06078455d	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	36fa133854d6691fe71bdc28f74520c2e78ea70190678d22fd9e071e4b491acf	e1631b81-b9c8-406f-b063-75572010c8ac	39b7541f-b7d8-4ed1-a25d-cdca0a79bbbc	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-15 09:22:06.55154+00	2025-12-15 09:22:06.551546+00	t	f	\N	\N	2025-11-15 09:22:06.551587+00
2a2a3a82-7a3f-40ba-afc0-a6ffb5c05caa	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	54ea9e694bf84c98970409e423c36bdedef204c944df04a39b0e30a4418aaa26	7c072d4b-9540-44ea-8e08-0fe96c6b4651	80eb7b40-3bd3-4d90-9bcf-0d1c4492cc96	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-15 16:14:48.347938+00	2025-12-15 16:14:48.347945+00	t	f	\N	\N	2025-11-15 16:14:48.347998+00
3518e027-1146-41d6-a7d2-8c3870c4611c	b46b4c47-31c6-4ad2-9829-0332963bb646	b53759c161fe95279cf417d14dd7f103caadf9978a741fc55b3bb596c1016bf6	9e96bdf2-9012-407c-9b4d-cda2cbec4828	eb0e8693-9dfa-42f4-9394-cbf1e80346e7	1.53.152.69	PostmanRuntime/7.49.1	2025-11-17 03:24:06.131233+00	2025-12-17 03:24:06.131243+00	t	f	\N	\N	2025-11-17 03:24:06.131276+00
95c70690-1081-4e60-b9e7-02c82ca3f87a	987fa969-961f-4afb-98aa-636c3448bd87	8813faad851e34668f0b0a1a38e766b20eb48fd86e88a819f884304250b50143	95fd766b-8aeb-4cbc-acd1-417d10977ee2	2c5345fe-389e-450f-aa46-66a94f4a214b	1.53.152.69	PostmanRuntime/7.49.1	2025-11-17 03:24:32.75715+00	2025-12-17 03:24:32.757159+00	t	f	\N	\N	2025-11-17 03:24:32.757172+00
94d4f49c-838b-4028-a00e-e562e01e2cc8	987fa969-961f-4afb-98aa-636c3448bd87	7f1219c1ed0b5b69ad485bb58672e764b0c55c38ee822dd137f563d27b2b65aa	d304e605-6cf3-4158-9090-a6c845e5a2ac	2c4163dc-9da0-4d3f-bea6-7471cf61af4e	1.53.152.69	PostmanRuntime/7.49.1	2025-11-17 04:22:17.376332+00	2025-12-17 04:22:17.376344+00	t	f	\N	\N	2025-11-17 04:22:17.376386+00
eeaf5a6d-8e1b-4efc-b090-7ccbf83de46f	987fa969-961f-4afb-98aa-636c3448bd87	7426cf6e5fa6ad9cd27a235ce074e609ebfaad28d95d1d1fff0712ce62c331d7	4a63fd9d-c0b7-4762-b885-7905f9d8b84f	40a256b3-ac94-41bf-a517-5f9513cc0aff	1.53.152.69	PostmanRuntime/7.49.1	2025-11-17 05:12:13.22659+00	2025-12-17 05:12:13.226602+00	t	f	\N	\N	2025-11-17 05:12:13.226638+00
39016ec4-2245-4e64-9f8a-d414e3c1218a	b46b4c47-31c6-4ad2-9829-0332963bb646	6886f54ccb3d2718324e69a566c5b549f79c441b5939394f2e1dfca7f4703bd1	72a52994-0427-4765-878a-7e8c3ec76cdf	7a4e0e0b-fe3c-4f56-869a-d89a28c79b9f	113.169.44.187	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-17 15:06:02.058572+00	2025-12-17 15:06:02.058602+00	t	f	\N	\N	2025-11-17 15:06:02.058634+00
d5d87116-4ad7-4270-b617-13ea8a914bb9	b46b4c47-31c6-4ad2-9829-0332963bb646	760c16dab620576a5fe760e19cdfb0d927efdf4f510ac88dfb2550deb1364c12	b6ba8e00-40d1-4603-80bb-3d9f4a41021f	528dbeaf-7d85-41b5-85f3-720cfedbae9c	113.169.44.187	PostmanRuntime/7.50.0	2025-11-17 15:11:07.926686+00	2025-12-17 15:11:07.926711+00	t	f	\N	\N	2025-11-17 15:11:07.92677+00
3efb2204-21a9-4f9a-a46d-792091ef39aa	b46b4c47-31c6-4ad2-9829-0332963bb646	c14cef0980c662ab54f760c7d289c33ff8c9605473efc479a5b30a9176ba511e	bc40645c-5912-4412-8164-42c74fef6b64	d8af53e3-6dc9-45db-b73e-22be221679eb	113.169.44.187	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-17 15:14:44.433691+00	2025-12-17 15:14:44.433711+00	t	f	\N	\N	2025-11-17 15:14:44.433749+00
83260084-a8eb-49ce-9ecf-9aff88aaed09	b46b4c47-31c6-4ad2-9829-0332963bb646	b93eb7d4d65b7a6e5b1820a200adec675a4eb9f8d51cb5608f15658698c8b1ea	4bb467f6-4559-4d04-94e4-735f3ab26ff1	7df5af3c-5ac4-41d4-a45c-d6c66c114f77	113.169.44.187	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-17 15:33:57.132224+00	2025-12-17 15:33:57.132234+00	t	f	\N	\N	2025-11-17 15:33:57.132273+00
ddf9ee05-6682-495f-b356-aa09a4fb82d3	987fa969-961f-4afb-98aa-636c3448bd87	b65530b979e375a19642b39e2c573b44511913a111ea256806eac63423752992	9eb1bd03-1ad5-4449-a6d3-a88d61043025	73c18341-4f3d-45a0-9109-93c0f6aacaaf	42.112.70.159	PostmanRuntime/7.49.1	2025-11-17 18:21:25.755165+00	2025-12-17 18:21:25.755182+00	t	f	\N	\N	2025-11-17 18:21:25.755249+00
ede46e4e-50c6-4b7b-b49b-26701b1517aa	987fa969-961f-4afb-98aa-636c3448bd87	d034ee126c8466d599c5b11a472349931aab26dd0347857d92f5583dfb296c66	80a4a17d-acc9-431d-afd1-111471730fda	4e689bbd-306e-4656-8fa6-8c47dbb1af55	42.112.70.159	PostmanRuntime/7.49.1	2025-11-17 18:30:55.151463+00	2025-12-17 18:30:55.15148+00	t	f	\N	\N	2025-11-17 18:30:55.151553+00
e8fef440-15b5-4864-8443-28709d053cd9	987fa969-961f-4afb-98aa-636c3448bd87	76bcf6191b2e8747c5beb06315419c514ee9757615dc369c6eee7f5fd1ddf0a1	ef94cfa6-35eb-49aa-9e7c-b10ce796755a	74ef680e-8df0-47a2-98d9-953fab5c3c80	42.112.70.159	PostmanRuntime/7.49.1	2025-11-17 18:52:35.950564+00	2025-12-17 18:52:35.950583+00	t	f	\N	\N	2025-11-17 18:52:35.950645+00
0a51e986-3bce-4fbf-8850-7e48edfa8251	987fa969-961f-4afb-98aa-636c3448bd87	ef884058426b60d0b0822b73d1c2d9e4333452d625c3aa27117eb54468a4a7f8	57e63302-fea6-45e9-a479-95bec21672a4	cfe8d876-af5d-4ecf-8744-3c8edcd062e1	42.112.70.159	PostmanRuntime/7.49.1	2025-11-17 19:01:39.540376+00	2025-12-17 19:01:39.540389+00	t	f	\N	\N	2025-11-17 19:01:39.540427+00
b3ba361e-121c-488d-9f19-d909e705b52f	987fa969-961f-4afb-98aa-636c3448bd87	d34d9b505e0dbcede36218455fa25ea0a8e8f7c4613ea9e73494ef88edb9e5ce	58755f22-ce9f-493a-9835-141f0adcfe81	971e63a7-cfaf-425c-8d78-c82f4b910e5c	42.112.70.159	PostmanRuntime/7.49.1	2025-11-17 19:20:49.851082+00	2025-12-17 19:20:49.851098+00	t	f	\N	\N	2025-11-17 19:20:49.851145+00
94b2c0e2-fff1-467d-b761-12ccfe8190e6	987fa969-961f-4afb-98aa-636c3448bd87	2f433ac3653930c0e0d8a7c96907ed04a2a25fa453231957967006b4f85e3f01	78b7139b-41b1-4f65-8500-1e10f43746e8	67418e18-7842-4d93-8701-d86f478afab5	42.112.70.159	PostmanRuntime/7.49.1	2025-11-17 19:45:19.640109+00	2025-12-17 19:45:19.640134+00	t	f	\N	\N	2025-11-17 19:45:19.640218+00
f144653a-e81b-48af-af37-d12d25bd2a30	987fa969-961f-4afb-98aa-636c3448bd87	57cb7d689300f0323815cded4c0dbd3b9f2aae78b5fa978519cea1a0ae76f531	26500733-076f-442f-8985-fd36f83f76fd	14c37a74-1587-4763-a8c8-fc2c2f5fb902	118.68.150.178	PostmanRuntime/7.49.1	2025-11-18 07:32:13.846684+00	2025-12-18 07:32:13.846696+00	t	f	\N	\N	2025-11-18 07:32:13.846749+00
50901c7b-ace7-4bd0-b16b-49a924f46eea	b46b4c47-31c6-4ad2-9829-0332963bb646	352c5df72686e0e6eff31568f6b9363d95867b2552baa1076ce6ac6f3ce82be6	bfc87aba-3b1d-451a-98e8-05684bb9c4c0	9f08d66d-4221-4049-bb8f-e98bafccf1d1	113.169.44.187	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 07:38:37.786268+00	2025-12-18 07:38:37.78628+00	t	f	\N	\N	2025-11-18 07:38:37.786329+00
fe78b1ec-b7c7-478b-9f1c-c0fefc7f7c2e	987fa969-961f-4afb-98aa-636c3448bd87	a371e37b30a680933eedd9a4c6ec3ab4991119f7adbb7e126dc9be48e4183276	6385e336-7747-49af-9038-1c0403c565b8	ad951357-d61d-40c6-b1d3-6a914e0e1abc	118.68.150.178	PostmanRuntime/7.49.1	2025-11-18 07:47:35.105198+00	2025-12-18 07:47:35.105215+00	t	f	\N	\N	2025-11-18 07:47:35.105263+00
2bc98447-08bf-4bab-9080-6e1dc9b39be1	b46b4c47-31c6-4ad2-9829-0332963bb646	308ec08d5cc43672d3c8625ee4be74c1fe7405e10e4f81c597b2672476982903	cc28659d-d6a3-4da8-b801-20db14b7f44a	652ea055-fbd0-4136-94f1-36726d935a5f	113.169.44.187	PostmanRuntime/7.49.1	2025-11-18 07:59:44.234051+00	2025-12-18 07:59:44.234067+00	t	f	\N	\N	2025-11-18 07:59:44.234104+00
388e075b-c151-4075-9b6d-e1d871241ce8	987fa969-961f-4afb-98aa-636c3448bd87	9698c395d61b6f7fd0a67aa7080391ad27c83777fe8ff745c2e78ba054972fc3	d06a1438-f77d-4f3b-9004-1556c11167aa	f5696e49-678e-465e-93d8-ce9280679540	118.68.150.178	PostmanRuntime/7.49.1	2025-11-18 08:10:23.927507+00	2025-12-18 08:10:23.92752+00	t	f	\N	\N	2025-11-18 08:10:23.927564+00
02336f0f-1cb6-44f3-af87-d5c220b8901e	b46b4c47-31c6-4ad2-9829-0332963bb646	789c113287c83a88c5ae37599827b73b98a8b692b53605bbe5da5964d940897c	d39f047a-4add-4874-bcd5-038e5671be20	ad0025d0-fca4-4c02-8157-c45839a297ba	113.169.44.187	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 08:20:04.324814+00	2025-12-18 08:20:04.324825+00	t	f	\N	\N	2025-11-18 08:20:04.324847+00
f90e8391-a725-4121-a4b4-46ca3d4f7214	b46b4c47-31c6-4ad2-9829-0332963bb646	071b829930efcee2a033dac65e0c6a701d56668e80c3db1ae1871fc06641abb5	2662afb7-b144-4d5c-a9eb-35a1f95d9b8b	9fb7a7f1-9469-4dd1-a1d6-4cc25d6cf8f1	113.169.44.187	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 08:44:24.094546+00	2025-12-18 08:44:24.094584+00	t	f	\N	\N	2025-11-18 08:44:24.09463+00
4920f198-aa02-4f97-9316-1fd8f4174b9c	b46b4c47-31c6-4ad2-9829-0332963bb646	b0a338f0b56371e3b54650f8a48cc9848978c8fbb98522abb91390b2f9b430b8	5eee7a1f-6ccd-44f7-afe8-ce430419a9cb	8a5fe5c8-a473-4fd6-a673-9d29b91d04e5	113.169.44.187	PostmanRuntime/7.49.1	2025-11-18 08:49:10.778876+00	2025-12-18 08:49:10.778901+00	t	f	\N	\N	2025-11-18 08:49:10.778942+00
c61b4e21-0c78-403e-b462-d1405dbe0f93	b46b4c47-31c6-4ad2-9829-0332963bb646	58d32b06edbe4634fce1130ebde4412248e3272164059849556cfdc014f96dc0	5fe7d43e-cf74-4001-a9cd-5751adc6597c	7b068af7-8ed2-4de9-8686-047e5c6313f9	113.169.44.187	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 09:01:38.958842+00	2025-12-18 09:01:38.958871+00	t	f	\N	\N	2025-11-18 09:01:38.958959+00
d943627d-eb69-40d0-b0b3-b8ba7d324cd6	987fa969-961f-4afb-98aa-636c3448bd87	1bbbfa42c62e2e755ca391b702c45b5b1419debebd195e2c42be9e1f02f6151d	f5a6c9e2-3d8d-4b74-9a10-a83d4c6b87f2	5f0cfae4-7c30-4aa9-9204-c1f00ec9d58b	118.68.150.178	PostmanRuntime/7.49.1	2025-11-18 09:23:07.055784+00	2025-12-18 09:23:07.055811+00	t	f	\N	\N	2025-11-18 09:23:07.055855+00
6bc1ac62-aaa4-40ec-aee8-0a4fa06276a8	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	4db09e0acc0aa2eff8e3a49acf55e044716a0dd4f3969b7191027e2bf408d964	9d8675ac-faaa-43b4-8282-ecb3d4ee8125	7ff33345-bcf1-4489-ae79-e0626b9f8d53	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-18 09:37:46.717+00	2025-12-18 09:37:46.717014+00	t	f	\N	\N	2025-11-18 09:37:46.717042+00
143d6426-4102-4346-bc98-d81c223831bb	cd23d611-1644-4d29-b7b3-100f9458018c	bacb5b9f1e12d91a8931833cdeb7bbea2b926ab4a22fe50dcfd488f5232ac278	511b74d1-deb7-4b60-b11e-f257f90b488a	a46d3b39-0541-4c34-a465-19c610f61a66	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 15:00:48.241179+00	2025-12-22 15:00:48.241182+00	t	f	\N	\N	2025-11-22 15:00:48.24122+00
58a44f55-af70-444f-bd93-6af86318b474	987fa969-961f-4afb-98aa-636c3448bd87	43e09bbe2ead7fa7b025564a1b4c53374aa7f1ee5490d79c056c257f593e6c10	dcf9ae86-35b0-435a-b529-554895920228	de864b91-ab71-4c57-874c-efc42b7fdfb9	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 04:00:56.208421+00	2025-12-24 04:00:56.208423+00	t	f	\N	\N	2025-11-24 04:00:56.208438+00
75e29284-1ccf-48b6-914c-fe09f35e24ec	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	f4ed4c0e04c50597088e4bd9056dc2c637d7f1c6133526039c80124e5e923087	37c88395-f643-4d3d-bc06-13e7aa6dcfc3	ef8a6bf6-27f1-4732-8c50-5c25e2764cdb	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 04:03:40.394786+00	2025-12-24 04:03:40.394799+00	t	f	\N	\N	2025-11-24 04:03:40.394865+00
dc4fa1da-db8b-45cc-876d-4901d1df0435	987fa969-961f-4afb-98aa-636c3448bd87	0838206f07081e22ae0a01bc08d2a52586a9e74682d4e6085a2ed0be0bce8648	a62614a2-856b-4439-9a05-72bbfac7c339	2124ef85-55cb-484a-ad51-1f834dea079c	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 03:26:20.632808+00	2025-12-25 03:26:20.632856+00	f	t	2025-11-25 03:40:23.801231+00	rotated	2025-11-25 03:40:23.621408+00
d6482905-0609-43ad-97cf-7a1e69d7fd8e	987fa969-961f-4afb-98aa-636c3448bd87	09e2c6c13b2c52d4d2f1e099c9e7a0713b2f651a1b6e7201aa31d48696f1dd77	92658f6d-912a-45de-9ad2-4bc180a2ea4d	8f34da01-4168-4d81-b5a2-7e1f77809991	27.64.96.160	PostmanRuntime/7.50.0	2025-11-18 11:49:16.260557+00	2025-12-18 11:49:16.260561+00	t	f	\N	\N	2025-11-18 11:49:16.260597+00
7c3e2cba-b843-4038-9c32-122646ddcd80	987fa969-961f-4afb-98aa-636c3448bd87	9243cd4e9ea42dca2880a63a5b5cde8bc83dcd9a5225ff90b1a13db39ada399e	22317ce1-a2cd-4f3e-910d-524939f2f360	c560f164-9a96-4704-b6b5-9a8a83ba8049	27.64.96.160	PostmanRuntime/7.50.0	2025-11-18 11:54:15.679593+00	2025-12-18 11:54:15.679605+00	t	f	\N	\N	2025-11-18 11:54:15.679656+00
f61bc002-a88b-4123-80f4-ae5424248163	987fa969-961f-4afb-98aa-636c3448bd87	5250da9863bca686a3f4abccbfd26239923dc8c7942976802937ed247b8c9960	07b09722-9aeb-4222-85eb-0bc618fca9f5	999bf7c6-ad04-4f77-85ad-e1a5e9ff1532	118.68.150.178	PostmanRuntime/7.49.1	2025-11-18 11:55:59.744024+00	2025-12-18 11:55:59.744031+00	t	f	\N	\N	2025-11-18 11:55:59.744059+00
fbd91d8f-b3f5-4da0-8ce4-5bbb8d8c5245	987fa969-961f-4afb-98aa-636c3448bd87	626f2f2557ff8e34ee821a8eed6be7a13bb05fe15d0080ba79ea63084d9198d8	13585e2b-2814-4008-9f40-6bd0d191d1b5	b79774fc-4382-4d2c-9c3b-97260c33a2db	42.114.92.40	PostmanRuntime/7.49.1	2025-11-18 15:40:16.058782+00	2025-12-18 15:40:16.058792+00	t	f	\N	\N	2025-11-18 15:40:16.058839+00
4644e8d6-abdb-48ef-b9fb-0f79af153a9a	987fa969-961f-4afb-98aa-636c3448bd87	6f771fab7bb6200d485ccc65c774580757daccd9ac87d9582e6a42f973ee2996	f085a7fe-d7ad-457f-b919-beb5885b2ba6	cdc7b655-d4c2-472a-bd06-f201725e5d2e	27.64.96.160	PostmanRuntime/7.49.1	2025-11-18 17:01:07.525702+00	2025-12-18 17:01:07.525713+00	t	f	\N	\N	2025-11-18 17:01:07.525768+00
c8d361f8-3494-401c-876f-9eb270280df4	987fa969-961f-4afb-98aa-636c3448bd87	1fa549ee0996a8bdf8a8fde48b368d56b5db22a11bea8b52de53f8ff69f265e5	f7c05932-6590-491d-b96b-311010bc087f	5d3905ca-f78c-4088-8c6d-cb11689bb58b	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 05:30:18.365774+00	2025-12-25 05:30:18.365776+00	f	t	2025-11-25 05:44:25.427517+00	rotated	2025-11-25 05:44:25.258397+00
9496201b-118e-41b4-9dd5-92618ee1d96c	c1d918d1-18d8-4837-a271-967d90f569a3	ba132fabccb8f26ef8e3edf279721adfc903795b83d28d4b366d9f14732833cb	51b3a7d8-2422-44d0-afc9-338bb593e631	68a5588b-1c7f-4a70-899b-0e78e4d017b6	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 17:17:26.663925+00	2025-12-18 17:17:26.663927+00	t	f	\N	\N	2025-11-18 17:17:26.663955+00
1d1b5179-38d7-4270-8389-084f3fa4f719	c1d918d1-18d8-4837-a271-967d90f569a3	f2666c2b04b1e08511bc8044828a0de0f5213dbcd3deea835395788ada3c006f	51b3a7d8-2422-44d0-afc9-338bb593e631	286447e3-a274-44ed-b80c-b2b480b1d104	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 17:03:14.337478+00	2025-12-18 17:03:14.33752+00	f	t	2025-11-18 17:17:26.663484+00	rotated	2025-11-18 17:17:26.464983+00
5a415df3-8342-422c-b3e3-780a2b523ff7	c1d918d1-18d8-4837-a271-967d90f569a3	0bf7213912d0ddcba1e3b24b32f21785df88e797e5be500360690cb712dbc0c3	03018612-5661-41d8-a465-6f22940bed51	45107913-63e7-4014-b5f4-3bee669978ea	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 17:17:32.699605+00	2025-12-18 17:17:32.699642+00	t	f	\N	\N	2025-11-18 17:17:32.699659+00
930a8164-a730-4dcf-9382-19d79251b029	c1d918d1-18d8-4837-a271-967d90f569a3	c1af31baeeb2c28c3f854bee8dea3741d3aafed68392cc3914c648e53801f267	6431e53b-745c-415e-bc81-258b814aac29	722da24d-28ce-42ad-ac0c-c94b7da8bf9f	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 17:34:29.390206+00	2025-12-18 17:34:29.390213+00	t	f	\N	\N	2025-11-18 17:34:29.390259+00
2ec08202-5069-46f7-878a-ac06fa0a1803	c1d918d1-18d8-4837-a271-967d90f569a3	f325726306ca635d14c86a0654013b1837e61cb0290af14ae8891efdf1ec3e9a	af755790-382a-443d-808e-f79885131e28	66a85177-a900-4d9e-9504-f03a74fe74e0	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 17:55:15.391158+00	2025-12-18 17:55:15.391165+00	t	f	\N	\N	2025-11-18 17:55:15.391241+00
5b470173-63c3-40fc-95b3-772f624795d0	c1d918d1-18d8-4837-a271-967d90f569a3	da1f8d9aa3d54b6e39279b7b7e616c729a4179f8f0fec71cb44eedbea53005d4	1e351c37-17f8-47a1-b2c8-35f2e15fd960	3f9b2706-e19c-4204-b875-aacad5039c63	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 18:03:43.753389+00	2025-12-18 18:03:43.753396+00	t	f	\N	\N	2025-11-18 18:03:43.75344+00
fd0e4587-dbee-485a-86e2-e123fadfc828	c1d918d1-18d8-4837-a271-967d90f569a3	09b1b73f36480e585c6ba83067b8c3066dc78a4bc2192284d1623452c06a3088	c17c96fd-77fb-4371-9e06-b50c318f837f	cee5bb7e-ecec-4386-80f9-62429ab2683d	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 18:04:59.886813+00	2025-12-18 18:04:59.886816+00	t	f	\N	\N	2025-11-18 18:04:59.886837+00
61a98405-383a-4705-ba74-0818f3140c8c	c1d918d1-18d8-4837-a271-967d90f569a3	494a129632d11ada26e1d698b62ee3e25d84191aa862ff2df6aa3fee4e32bce9	6f06d39e-35f7-411e-83cf-8a9a281d3d9d	14f466e4-70ed-42f9-bc31-b5643300191e	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 18:08:12.587871+00	2025-12-18 18:08:12.587878+00	t	f	\N	\N	2025-11-18 18:08:12.587919+00
8d0e868a-0c54-4cd9-b294-e952e09ac070	c1d918d1-18d8-4837-a271-967d90f569a3	f1c7a48c4b3a178225bcf3d2389956ef08aa00af5d96818fd2dd08fb12bc3dbe	88f93f1b-77d8-4935-9b0b-d7ef67f91a90	9c884158-8879-47ff-9d76-6b43d1a180cb	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 18:13:12.955348+00	2025-12-18 18:13:12.955356+00	t	f	\N	\N	2025-11-18 18:13:12.955395+00
8f67e7c7-800d-461b-80f1-0b2422c5a907	987fa969-961f-4afb-98aa-636c3448bd87	863a597190c5db7847d4958d4bd2bf6229c1c1127507bdc8bfd15020e2eeecd3	789a6e29-9ee4-4601-b144-88666b71ca24	d9c30f89-559a-4b33-8062-5fe87d4bd414	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 19:27:34.551478+00	2025-12-18 19:27:34.551486+00	t	f	\N	\N	2025-11-18 19:27:34.551533+00
ddf23a1b-0183-4757-8427-c4767e7b48d3	987fa969-961f-4afb-98aa-636c3448bd87	aa440a8f98b6b1a33545890685575a77299ecb2ec9c6bb88d374ce09828628b1	ebfef2e8-a6e7-40e7-8d81-21b600132149	36354c4c-defe-42ee-9929-7dd87a871212	42.114.92.40	PostmanRuntime/7.49.1	2025-11-18 19:29:39.393426+00	2025-12-18 19:29:39.393428+00	t	f	\N	\N	2025-11-18 19:29:39.393445+00
4800b2e8-694f-4f33-9213-306fcaae87f7	987fa969-961f-4afb-98aa-636c3448bd87	3edc0656479d8b6fab8a790c9ff09a35edeac0886b038dff20109cf4124c9f91	20d713a1-3ed0-4eb6-b40e-d5087ae78fb5	6a5fdbbb-b964-4754-95ae-7a62519e1dff	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 19:34:22.967101+00	2025-12-18 19:34:22.967112+00	t	f	\N	\N	2025-11-18 19:34:22.967164+00
1e3e4b08-db4e-411f-8fcd-ed19dc7a2c58	987fa969-961f-4afb-98aa-636c3448bd87	a36bff14253a651db6bc02f4e8a9ab8727d9a519f331f58e1c2169331b9f6cf6	7193792a-a5a2-486d-b037-42729b665648	a8df6e4b-de63-4e0b-8b86-e14201cfbeac	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 19:54:30.840732+00	2025-12-18 19:54:30.840738+00	t	f	\N	\N	2025-11-18 19:54:30.840805+00
6e342365-8c04-4d2e-a902-0e23f0820ad8	987fa969-961f-4afb-98aa-636c3448bd87	faa2f1b79faa60434bf7d6991cc90721ba5c5d9d33a5c42b92a59c2d49e153b0	1c5dba9c-5d92-424e-aba3-f82c67ae6551	4976865a-ebb9-4469-96ff-5379e584396c	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 13:16:19.559719+00	2025-12-25 13:16:19.559721+00	t	f	\N	\N	2025-11-25 13:16:19.559759+00
cbf4ff8e-1f32-4e82-925a-d28836e074ec	987fa969-961f-4afb-98aa-636c3448bd87	ba17671c3fafa0db645b5fca333db2bf748287afc1fac9c2461d28e044eb27ad	32aa67d1-ce73-4fcf-a9eb-aa3ae9657368	84306d65-5b70-4583-9b0f-7aead97d2a6f	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 19:54:58.740726+00	2025-12-18 19:54:58.740729+00	t	f	\N	\N	2025-11-18 19:54:58.740741+00
5637b293-2bc5-42c9-ba39-fdba1b515ded	987fa969-961f-4afb-98aa-636c3448bd87	357672152a9773578352ffe142dfc8c0df05741ee6bca3a64c70acb25f4dcc31	aa77e13a-75f4-4beb-929e-14fa444b15e8	53c7ac00-cce2-4cdf-b4d2-f55e8d1b8b0c	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 19:55:36.721837+00	2025-12-18 19:55:36.721839+00	t	f	\N	\N	2025-11-18 19:55:36.72185+00
ca683dae-2dad-4f2b-b518-75e13298ce09	987fa969-961f-4afb-98aa-636c3448bd87	61112f154271225dd7c5a1b0b9a224e7c03d0e6247bc5c8ea5324f0d2a94e8b6	692c2d0b-b9a5-4a3b-9afd-5a3312b8f311	ce3c4a3f-9c39-422b-958d-5bd3f9949331	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-18 19:58:04.963994+00	2025-12-18 19:58:04.964005+00	t	f	\N	\N	2025-11-18 19:58:04.964069+00
557a0a46-4203-46bc-8329-a4ea962f8c74	987fa969-961f-4afb-98aa-636c3448bd87	3d647e2e535070193cf378372f28982331e04c51f70cacadc8c64a938a9c828c	effd1efe-f588-4018-949b-c48a1919304f	a4cc5ec3-ccf2-4ba9-8099-7b616325921e	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 19:58:52.690266+00	2025-12-18 19:58:52.690268+00	t	f	\N	\N	2025-11-18 19:58:52.69028+00
bce94fe8-84f0-43ac-9d83-f21eba479ea9	987fa969-961f-4afb-98aa-636c3448bd87	dcf6e37b4c06ffe573cd0c5d8f6f318782e1dde2790102e8ab868d601916c2d0	56859bd8-2b91-43d3-9ee2-867f2b42406e	2face51f-0c0e-4d2e-99cd-f8af24d3b4f9	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 20:04:27.072091+00	2025-12-18 20:04:27.072094+00	t	f	\N	\N	2025-11-18 20:04:27.072126+00
85479814-51c3-41ee-bcf0-901ec4b33266	987fa969-961f-4afb-98aa-636c3448bd87	ca753337cb546d994c5e47dde0b29cdda8f80dd61ec518ea26a20e7fd4d73873	3302f1b1-4d59-49e6-b3ec-0b60850cc094	b6beef60-8609-46db-9b4f-0f74fe4aa174	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 20:06:26.447271+00	2025-12-18 20:06:26.447274+00	t	f	\N	\N	2025-11-18 20:06:26.447307+00
df5b9037-290a-4be5-8363-b16ad7cf525b	987fa969-961f-4afb-98aa-636c3448bd87	0555b1098230434dd5f0df817eb506a5c0bb613fbb4a8fafdf5ade92f474af89	d3240d52-dc7f-490f-9608-ffda2ce01b1a	cdcfa342-8391-4b93-9ad1-4a19defbacfb	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 20:07:16.90263+00	2025-12-18 20:07:16.902637+00	t	f	\N	\N	2025-11-18 20:07:16.902674+00
be6b480e-a219-4855-830b-4018c6f0029e	987fa969-961f-4afb-98aa-636c3448bd87	6dcbbf451fc7669cdf4ffb61407de69060f2d434d9d9936061a928319ab6cbb9	d22ff2a2-cae7-4399-9e17-79939656491a	b15fa50b-6871-42f3-9df9-265d7b59a9e9	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 20:14:51.071522+00	2025-12-18 20:14:51.071529+00	t	f	\N	\N	2025-11-18 20:14:51.071581+00
87893859-9de9-4f2f-8037-07900d786b58	987fa969-961f-4afb-98aa-636c3448bd87	32b2cf3776d7afac479a87a0ae5bfc72a47014117a3040705e4706461c779316	f146d330-4710-4a6b-8e72-1ae231e18908	734e75ac-6151-4f75-b933-618e05045cd3	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 20:15:47.961934+00	2025-12-18 20:15:47.961936+00	t	f	\N	\N	2025-11-18 20:15:47.96196+00
81760afc-7b0b-423f-b1f9-740a64c9da01	987fa969-961f-4afb-98aa-636c3448bd87	2da607d7af3dbfef91a2982f0faf83ca83e6dd08d27388bb313d9061c473d47b	5c557453-2f0c-4021-adea-161882393bdf	44ea35dc-f8ba-479c-85de-ee7d0e1de3b0	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 22:13:24.473486+00	2025-12-18 22:13:24.473496+00	t	f	\N	\N	2025-11-18 22:13:24.47357+00
d6e618e1-e579-4527-b9ac-c4836ac280e5	987fa969-961f-4afb-98aa-636c3448bd87	3f25b7e496f7174a6c3281b5b01f978f610afea30b3c80c6a7019789e3de089e	14765c04-a4c2-4ec6-befe-c153d5e34137	3e1554ce-cc92-42f8-97fc-fba88aa69531	42.114.92.40	PostmanRuntime/7.49.1	2025-11-18 22:19:25.411791+00	2025-12-18 22:19:25.411801+00	t	f	\N	\N	2025-11-18 22:19:25.411853+00
912b4203-b7a4-4e84-9257-ea442b137b65	987fa969-961f-4afb-98aa-636c3448bd87	78e4c2509ad665596e61048ba084927a2764c60174c2d0160544e63a2bfe01f5	7afdff35-6dab-429c-953c-9f278f4c26f6	8e47b45a-dc52-4418-963a-7a799673886d	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 22:24:48.909305+00	2025-12-18 22:24:48.909318+00	t	f	\N	\N	2025-11-18 22:24:48.909367+00
131e12e7-482a-4e61-90ec-c9505782723d	987fa969-961f-4afb-98aa-636c3448bd87	6ba40ab532f59df42118bf9f88627db3e8de054aeb2c3a2640bb9f7fe2473151	eb0f43f5-6187-477b-9f6d-d0e8c569f1e0	96483290-cecd-421c-a492-c33620773a8e	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 22:26:43.378514+00	2025-12-18 22:26:43.378517+00	t	f	\N	\N	2025-11-18 22:26:43.378557+00
745dc577-a49f-439c-b3e2-8c441ca5a789	cd23d611-1644-4d29-b7b3-100f9458018c	e40d48773b36343558dd8d9cfe5282b896a89375b1e56bf768e73f7cc0157ea9	f73e516d-deeb-4476-bf73-c26479bcabe1	121fbf9a-d976-42d4-99d7-00acb65179f6	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 15:16:07.41341+00	2025-12-22 15:16:07.413413+00	t	f	\N	\N	2025-11-22 15:16:07.413442+00
34f58a51-c707-4dfc-ae7b-c8a3d2be08eb	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	216b9d7a705b1b1c7c2a045e755b4a41727a690e5da5ecbec232b96d4296278e	7061d400-7c2a-4e41-87c8-aa9539b941f1	fdeeea5e-0a4d-4c2e-acf5-ec7961b027e0	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-18 22:32:25.392449+00	2025-12-18 22:32:25.392452+00	t	f	\N	\N	2025-11-18 22:32:25.392493+00
a28e34a0-6a8a-400d-ae5c-db23a31ab19f	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	09dadcdea96fe03e23b544c43987f095c6c83f7aff3d445fc44923120cdb5366	2d73d7ce-dedd-40f0-83ae-49831a2bb349	75dfdb63-a52d-4d71-894a-220e02a8209d	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-18 22:32:37.27293+00	2025-12-18 22:32:37.272938+00	t	f	\N	\N	2025-11-18 22:32:37.272962+00
843f5eab-a25c-4544-b2d6-e11dc88883c4	bb8259df-3cb8-487a-ab91-2ef95a68aa44	90694072c8e4a3945d8bae2de8a48446c43ef51c8902882678e0b8b01f7fb7ad	a0592882-dfa0-4ad6-bc31-b97f964836e1	59c9b081-91ce-4e4a-bf8f-6b826d9a0b70	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 04:11:31.108347+00	2025-12-24 04:11:31.108349+00	t	f	\N	\N	2025-11-24 04:11:31.108378+00
7b7f4708-530c-4934-9635-d0fdaf98d773	987fa969-961f-4afb-98aa-636c3448bd87	2a9b67b25eadf0c1a57ff97c245c89310743aef41f17ac80b3a01703bf92fb03	05ce7bca-1b02-4573-8026-9a88cb25beb9	b123a871-f1aa-42a6-b887-8f7e2dfb281a	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 22:43:15.444472+00	2025-12-18 22:43:15.444473+00	t	f	\N	\N	2025-11-18 22:43:15.444505+00
71a190d9-066c-4d19-b3fe-d3dcd684cfb9	987fa969-961f-4afb-98aa-636c3448bd87	e0eecfc59588504542cd5cdf20f664e591c1e030baa17635a14c9ee33f95f673	05ce7bca-1b02-4573-8026-9a88cb25beb9	2f7df5e6-61b9-47ee-a45b-88eb7b340d41	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 22:29:11.7692+00	2025-12-18 22:29:11.769206+00	f	t	2025-11-18 22:43:15.442069+00	rotated	2025-11-18 22:43:15.329115+00
9d4eb831-9c7c-48a0-a50e-d384fc9d7ddf	bb8259df-3cb8-487a-ab91-2ef95a68aa44	4c7066182cef25129118acc57ab62a06835d6f6f4e93b31b0f982cd5a03c093e	a0592882-dfa0-4ad6-bc31-b97f964836e1	b00e3959-3474-48fc-a93f-b094c5ecf0c6	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 03:57:30.370766+00	2025-12-24 03:57:30.370776+00	f	t	2025-11-24 04:11:31.10692+00	rotated	2025-11-24 04:11:30.91931+00
89f3fa3f-110a-4f9e-99ab-4dd32196c5c9	987fa969-961f-4afb-98aa-636c3448bd87	968dc15767ec7a601f75f855d4e38976d2772bea19a11e2b21dc6957de28ce2b	bcff6440-fd0b-4b62-bf04-9e6b1cdb0725	5133256b-e869-4cc5-a41c-160b93442743	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 22:47:51.865697+00	2025-12-18 22:47:51.8657+00	t	f	\N	\N	2025-11-18 22:47:51.86574+00
c1345499-e72c-4174-93a1-4747ced37970	987fa969-961f-4afb-98aa-636c3448bd87	7601f1b32de45c8094911cd501388719c281d03cbf35ff2762d2c49d8db6fffa	a62614a2-856b-4439-9a05-72bbfac7c339	e8e6f6df-4739-42d8-b8b4-30e2e5427ea9	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 03:40:23.803721+00	2025-12-25 03:40:23.803722+00	t	f	\N	\N	2025-11-25 03:40:23.803749+00
03a27ffd-e75d-4b00-82ad-293e0eac638f	987fa969-961f-4afb-98aa-636c3448bd87	47c4c81b997e387e12dc971303914aff781b5511e2ac2c2c38b5bcee175d4c60	ec815850-16a9-4540-9d67-64731b90e847	7b7a3614-26ec-4574-8866-b6237f425ce8	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-23 14:06:46.273111+00	2025-12-23 14:06:46.27312+00	t	f	\N	\N	2025-11-23 14:06:46.273198+00
292bd51c-9f10-4b3e-8161-cebf143a719d	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	bc116d1bcb007a680ac8d1212ae4eef1db9f1d76e34e37243d391cdca01aa827	67e1454c-b765-45f0-8b56-4e40122e777f	0f7f2b51-e08a-4db0-84e5-53665a5b1f13	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-23 14:08:49.105807+00	2025-12-23 14:08:49.105814+00	t	f	\N	\N	2025-11-23 14:08:49.105838+00
87559ac9-7df4-4ed6-8fda-aeb0d88985d9	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	0c20e58f89a912a98493d02093de6a9e8208ec302f221f08b65d84208498450f	02df0513-a26f-432c-9f3a-c3186fcb5c98	9ed04027-5b89-4f38-831b-4a73793b29da	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-23 14:08:59.054434+00	2025-12-23 14:08:59.054437+00	t	f	\N	\N	2025-11-23 14:08:59.054462+00
6c8f7f0f-68a2-4b91-b959-3a402a801887	987fa969-961f-4afb-98aa-636c3448bd87	26a859a86084ea8f4692e86fe39b15c9213696f338faa106afb180e30dd3e164	74b63a58-c055-4d0d-a6a5-d94ec85512b7	fc6bdadc-4aaa-4c23-9ddf-e88f9c9a660e	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 23:11:18.731076+00	2025-12-18 23:11:18.731078+00	t	f	\N	\N	2025-11-18 23:11:18.731121+00
03fdbf0a-682f-4e6a-9211-976e3a691aa9	987fa969-961f-4afb-98aa-636c3448bd87	2d78332185092510d313cbafe825c7ea75322e7ef24353e18ac1a60651ca062c	2989dba2-dbb0-4edd-a2af-9af54ecc776f	d5321511-f12f-46c1-8d5b-2f1f61d1e9ae	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-23 14:10:04.613981+00	2025-12-23 14:10:04.613986+00	t	f	\N	\N	2025-11-23 14:10:04.614031+00
90f7f77a-76a0-4e5d-a43c-85cb3dbb2f98	987fa969-961f-4afb-98aa-636c3448bd87	d26a0996d9e45a4c9bf585d2ebdadc73bcbbfa629ee26f3e8ef65cd4897d7bc9	f76d89d6-e278-4c56-9fa4-db81964f2627	e566b42e-4345-4a21-8c49-6cc0e82fe42e	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 23:15:39.709789+00	2025-12-18 23:15:39.709795+00	t	f	\N	\N	2025-11-18 23:15:39.709847+00
9031b76a-f3be-4f66-ab53-05e05a9663ff	987fa969-961f-4afb-98aa-636c3448bd87	979758523dbf4a97496ba643558b2114efe14e07fb4473b84f21ef197c94cc3d	8c062386-3bd3-4982-a086-bbc8638b15f3	91c5c9be-a2e6-4a75-a996-81cf0ba7fc2a	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 23:17:41.090912+00	2025-12-18 23:17:41.090918+00	t	f	\N	\N	2025-11-18 23:17:41.090975+00
d9794d30-6581-458c-bb1c-1c77170aa6c5	987fa969-961f-4afb-98aa-636c3448bd87	287bbfd0f9d3a024f0f8cb3cbda8b648e9dbe87eaac7d8f9137c643e400d84db	a15f65f5-2381-4388-b855-602c8b6d976c	1769f7e3-ce3d-4df5-9f29-bbacfb7ef727	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 23:18:18.119048+00	2025-12-18 23:18:18.11905+00	t	f	\N	\N	2025-11-18 23:18:18.119065+00
57fac246-2c0d-45db-9fb8-b685fbbf5d2f	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	52a729c1cddd951e5f797c7eaaa20197784af862a03d85142ea8dfc4c97c35f6	4195abef-1b26-44a2-ab86-222188791d1b	507b4d06-59b5-4cd1-837d-6b3e83c53f27	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-18 23:26:15.804134+00	2025-12-18 23:26:15.804135+00	t	f	\N	\N	2025-11-18 23:26:15.804161+00
44431890-8942-43ab-9368-6e351128e127	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	42235ad19bb0f3d309de185ecd77b86f3f7cbb8b7a795307ddbde2534639e62b	4195abef-1b26-44a2-ab86-222188791d1b	1d810fe0-45ca-4f68-b7c2-729536342c71	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-18 23:11:39.285429+00	2025-12-18 23:11:39.285441+00	f	t	2025-11-18 23:26:15.803812+00	rotated	2025-11-18 23:26:15.671038+00
2d3500f9-aa6c-4e66-9a89-460b012a111e	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	8936a09c9cb393811f5460abf37428bcfd2e0721cef747a1791b8a47b8a4ae39	f24bb751-a942-4472-ba0b-f75357253d1a	a4ceb08a-b1ca-46ed-96a1-402bf854872b	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 04:15:09.23791+00	2025-12-24 04:15:09.237917+00	t	f	\N	\N	2025-11-24 04:15:09.23794+00
e455363c-2037-4d13-9ebe-a0db13f70b3c	987fa969-961f-4afb-98aa-636c3448bd87	aa0fd0f3fa0bc22c31ba89acf8e1ceaf7eb36c5663e00a7eedd8776d53ce8dca	7bd3a719-3e00-42dc-ba06-32f0595273e5	090e0bd1-0699-45b9-abc4-523e196dd924	171.236.70.5	PostmanRuntime/7.49.1	2025-11-24 04:20:14.928179+00	2025-12-24 04:20:14.928199+00	t	f	\N	\N	2025-11-24 04:20:14.928264+00
ade9bea6-3cea-4232-82b3-fe860d085ee9	987fa969-961f-4afb-98aa-636c3448bd87	4a8b576454ae94fb827e1f429f5b99f8a85506aaa6282ad6cab76c34583b1c24	befb7714-a34b-4136-8f94-bf368e6e9d7d	019dcb32-7c63-4c52-b094-ba8c067f8068	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 23:28:19.368391+00	2025-12-18 23:28:19.368395+00	f	t	2025-11-18 23:30:09.345616+00	rotated	2025-11-18 23:30:09.213802+00
be2460c0-3919-448d-959f-a2d1d0f10c9d	c1d918d1-18d8-4837-a271-967d90f569a3	83d2de01dfb50b2c197b4d6396c10cbe37ebb21ae7a8c8521803cc829862d314	04bfac22-497b-4cf4-9d5d-4e8a43260dca	1f992487-6a4b-4784-a740-713d20a010f5	171.236.70.5	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-24 04:21:29.41174+00	2025-12-24 04:21:29.411749+00	t	f	\N	\N	2025-11-24 04:21:29.41179+00
86fdb64a-b2a7-48f5-9757-5e2fb4be1bf8	987fa969-961f-4afb-98aa-636c3448bd87	58d242c5fc7dcbfa7c45d107f1958b0ad63984b3ad95c8ec3c21545492ce81b6	befb7714-a34b-4136-8f94-bf368e6e9d7d	00764db3-9aa3-4bec-bbea-0ace6d04f4f4	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 23:30:09.345952+00	2025-12-18 23:30:09.345953+00	f	t	2025-11-18 23:30:09.934858+00	rotated	2025-11-18 23:30:09.816133+00
1056db43-6e3d-4831-95bc-0df6d836f2d5	987fa969-961f-4afb-98aa-636c3448bd87	576d232b09ace19fbb57181ee7a04fcfcf8b12fe2b6c9b1acf89ff9474e0accc	befb7714-a34b-4136-8f94-bf368e6e9d7d	8b03f5df-b6b1-454d-9ba6-6fbdb532169b	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 23:30:09.935225+00	2025-12-18 23:30:09.935226+00	f	t	2025-11-18 23:30:10.51268+00	rotated	2025-11-18 23:30:10.402545+00
836608fb-3463-4b19-b54d-8ca9c2ced57c	987fa969-961f-4afb-98aa-636c3448bd87	e29711404818b624464b91e3dda4e793732a386b122e7416dce05fa208dee5d3	befb7714-a34b-4136-8f94-bf368e6e9d7d	2fe05249-f93d-41f3-8906-9e764c1b7cb7	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 23:30:11.090175+00	2025-12-18 23:30:11.090176+00	t	f	\N	\N	2025-11-18 23:30:11.090186+00
97f11606-2035-46f3-8c8d-78ea75d72675	987fa969-961f-4afb-98aa-636c3448bd87	7ce1af58b3faec1d2ca44520fbae3dc6c83fe199c683ad4450b286c5f246366d	befb7714-a34b-4136-8f94-bf368e6e9d7d	31f2ebc4-cb82-45fe-a232-057161145b2d	42.114.92.40	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-18 23:30:10.512973+00	2025-12-18 23:30:10.512974+00	f	t	2025-11-18 23:30:11.089852+00	rotated	2025-11-18 23:30:10.973694+00
b5616820-a7e4-41a5-ba51-57e0c48bbd07	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	1b7d1f2f9464128f7ba6a6308e917bd9254e95dec0e706dc6dbac21e33b148dd	5c40af20-2d30-438f-83d9-6b9799daa9f5	94b0f859-d6c6-42a9-9fa1-a657578b7b3e	125.235.191.198	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-19 00:24:48.94959+00	2025-12-19 00:24:48.949607+00	t	f	\N	\N	2025-11-19 00:24:48.949636+00
24632970-f89e-4773-8bb9-4e75fe015978	987fa969-961f-4afb-98aa-636c3448bd87	431bcb1e45c4b40d262f6cd23078a0d7e4e90f549856ec16b1d3df54c88e85b7	7f383543-8f63-4abc-a14b-35fc934a9b8f	2b0614f7-3e3f-4c1f-ab9e-2f908db4d22b	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 00:49:42.09622+00	2025-12-19 00:49:42.096223+00	f	t	2025-11-19 01:04:14.068587+00	rotated	2025-11-19 01:04:13.907032+00
478ecb87-91a8-4abc-83d7-754ec22cbc03	987fa969-961f-4afb-98aa-636c3448bd87	003b9e243893d52a96c6706420d73162313c93813e84fa2157bd410387e5ff28	a23371a1-bf45-4805-b2e5-10838d79e944	8b8b775d-fc37-4855-bda7-f1b6f6ffde86	118.69.128.8	PostmanRuntime/7.49.1	2025-11-19 01:14:19.952894+00	2025-12-19 01:14:19.952897+00	t	f	\N	\N	2025-11-19 01:14:19.952932+00
7a46eb4d-2b92-4d23-900f-f7fdcbe63845	987fa969-961f-4afb-98aa-636c3448bd87	fb285326d0121edf28dc03dad433c649dbf98b1540a94f1470a0132ef602019a	7f383543-8f63-4abc-a14b-35fc934a9b8f	dade29f6-fdba-4ad3-a9e4-dd215bf490b0	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 01:18:18.600013+00	2025-12-19 01:18:18.600014+00	t	f	\N	\N	2025-11-19 01:18:18.600044+00
5fa6832a-694b-457e-998e-5826377a12bf	987fa969-961f-4afb-98aa-636c3448bd87	f6a29efdb114d5a2b498edc87850156350d56c6185d7a43b660058813b79c4df	7f383543-8f63-4abc-a14b-35fc934a9b8f	9491f5f3-7650-4b14-9acc-75f5a574016e	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 01:04:14.068873+00	2025-12-19 01:04:14.068874+00	f	t	2025-11-19 01:18:18.599749+00	rotated	2025-11-19 01:18:18.471902+00
176711c2-bca5-47cb-99aa-69bd7677645b	c1d918d1-18d8-4837-a271-967d90f569a3	57e86445458b030e935bb0dc7fe6f8ae8d61a99a41ae1c627f1475e6a0a97203	e9dfc2c1-73e1-4f1d-9557-7387cc7f65c4	af214883-facd-4138-a797-c12203dd1010	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 01:18:58.453556+00	2025-12-19 01:18:58.453559+00	t	f	\N	\N	2025-11-19 01:18:58.453578+00
fc611a2f-02b4-4cb5-9265-3c79ed8746c3	c1d918d1-18d8-4837-a271-967d90f569a3	fc2b82ca9ee2f27dc6728513a19c174585b393661d27ca72aeaf880ab35571b8	806a60ba-1f0e-4557-9daa-d1f335f3c368	cb5731ae-126a-48a7-9465-79ce7efa3439	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 01:21:20.930974+00	2025-12-19 01:21:20.930976+00	t	f	\N	\N	2025-11-19 01:21:20.93101+00
87476881-829a-450d-8ef4-6552eca18b82	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	1756d26332e83f5b06e6a3f03ef95fc8e8890b32e6cc4bcf32d3885c244533b5	cba5fd5c-7424-4c1e-833c-452b1b57b794	49dd4676-0bea-4f48-8f81-c5b6bba7a546	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 01:26:52.941379+00	2025-12-19 01:26:52.941382+00	t	f	\N	\N	2025-11-19 01:26:52.941439+00
a9fdc20b-49ac-49eb-bf19-4f7f52059c0f	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	1972878b229312b1b58bfac55964c92239828b6db9796a0e8b4a2ee71aa1d89f	4ac367f4-2e94-4eda-95df-5fce02c12a93	7ac7f333-033f-403a-aa80-26b9809248da	14.191.79.233	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-23 14:45:37.024653+00	2025-12-23 14:45:37.024682+00	t	f	\N	\N	2025-11-23 14:45:37.024734+00
f50d3143-b7a7-486a-85b7-84d702ef4e96	c1d918d1-18d8-4837-a271-967d90f569a3	d34311b64132e2b970d284adc1fb3716629d8fbe1c6f471f85c25e6c01dc5630	073a305a-8d7d-4a3a-9f90-6f4cb124cec5	fb22d762-9a84-4eb2-817d-0415ea06347b	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 01:34:45.27003+00	2025-12-19 01:34:45.270037+00	t	f	\N	\N	2025-11-19 01:34:45.270068+00
6bcbad97-a5ec-4178-a8a7-d810e481e72e	987fa969-961f-4afb-98aa-636c3448bd87	f25b6fa7d69640673413580effc746d5e68197ed0647cb5643e0b44953f96828	75148b8c-0ec7-448d-8cbb-9c9ca86722b6	bd56124b-75b2-4ffa-9f3e-5c7474a11c89	118.69.128.8	PostmanRuntime/7.49.1	2025-11-19 01:35:39.922446+00	2025-12-19 01:35:39.92245+00	t	f	\N	\N	2025-11-19 01:35:39.922466+00
b252794f-bf59-45cc-9bcb-14f80c39fdf8	cd23d611-1644-4d29-b7b3-100f9458018c	31d79ed4949376628d102fc703c68ec29f3bc476fa1be20e7c56b0a35438c6b5	afa87fdb-560a-43ef-9ac3-402c0b76c5a5	e3f655d3-8fa5-427f-8103-671f4a64e7e4	14.191.79.233	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-23 15:03:15.369143+00	2025-12-23 15:03:15.36916+00	t	f	\N	\N	2025-11-23 15:03:15.369193+00
e7e73423-1d28-4e3d-95eb-1b0afe706054	987fa969-961f-4afb-98aa-636c3448bd87	fd66ad070549eb7d8ba9f13571b2e9e4cca0c8cdb8c283df8a79e7037867e6e5	1af45457-5b3c-4586-8539-6eb18d06af7a	da700882-bb30-4d5a-bfcf-531bc2a8f67c	42.113.203.42	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 01:41:53.138807+00	2025-12-19 01:41:53.138808+00	t	f	\N	\N	2025-11-19 01:41:53.138845+00
a9312092-4f58-499c-9643-db7f1293f6ec	987fa969-961f-4afb-98aa-636c3448bd87	b8af9b2a6824b86368ad9f5ea3bcc9db91bc7682ae3c05f026345fe880a9cc9a	1af45457-5b3c-4586-8539-6eb18d06af7a	525a65d7-fab2-439c-af9d-08ae0c2041aa	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 01:27:51.019239+00	2025-12-19 01:27:51.019242+00	f	t	2025-11-19 01:41:53.138544+00	rotated	2025-11-19 01:41:53.014126+00
567ba6a3-7961-4688-9d6e-fbbe18699395	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	f869844887e65ab5fe949504bf7bbb1a05c723cce4c3a69361880d71c6e2f6c2	80d8ce95-c7d7-40cb-8f3c-7c38732251a4	b2cccf30-6ea1-4233-b0de-0d74975fdaa1	14.191.79.233	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-23 15:03:47.918459+00	2025-12-23 15:03:47.91847+00	t	f	\N	\N	2025-11-23 15:03:47.918496+00
5cd12d68-1103-4092-8dc2-775004f3e9fa	c1d918d1-18d8-4837-a271-967d90f569a3	71ffc422cc79a34842bbd6db149e2506168569b786f7b842102dd99970290264	d3250c6e-4498-4f07-a5e3-a8bf2b5397fc	e9e136fa-5a8b-4b8e-bcec-4ed0c7e5ea5a	27.74.132.237	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 01:50:48.490235+00	2025-12-19 01:50:48.490236+00	t	f	\N	\N	2025-11-19 01:50:48.490265+00
b52d4fb2-ee71-4119-a0cb-c76ce4241ab0	c1d918d1-18d8-4837-a271-967d90f569a3	4a66fbc511f232193c5423afa2b30d52f6b466c525e39bf22b9f40d13631c7e3	d3250c6e-4498-4f07-a5e3-a8bf2b5397fc	f6a26ca3-52ef-486d-b211-e89b31bd06c7	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 01:35:52.742007+00	2025-12-19 01:35:52.74201+00	f	t	2025-11-19 01:50:48.489972+00	rotated	2025-11-19 01:50:48.306942+00
72a8cba1-474d-4a74-b74a-8c7f030986a4	c1d918d1-18d8-4837-a271-967d90f569a3	d7c03bddadb94c12408bf93ca5a08c8e7d3f2fa0a15e13d7fc79f2cfcb8e77d3	5736880c-42aa-44ee-a687-76a96320313a	2d9acd51-9329-4d00-a7fe-4821f6506608	171.236.70.5	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-24 04:22:43.141707+00	2025-12-24 04:22:43.141722+00	t	f	\N	\N	2025-11-24 04:22:43.14177+00
6fce1793-62e8-4ed3-a7d0-f1fc4bfdd6d2	987fa969-961f-4afb-98aa-636c3448bd87	7ec669ba797e067eb145aa82d28855a69fea92faa2787eb90344846cb8272066	185145d8-ee5c-478b-b91b-d43a4f24cf07	c2235a6f-0601-4bd4-8acd-e5d61b7e35f6	27.74.132.237	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-19 01:56:01.6141+00	2025-12-19 01:56:01.614102+00	t	f	\N	\N	2025-11-19 01:56:01.61413+00
cdc46ef9-1a3b-4ab3-9b36-b6ec2693370e	987fa969-961f-4afb-98aa-636c3448bd87	166d506b05b0e9c72e6afd2cf013314adea4895e7511fee4967676188f2a15a6	d775d98e-e2fe-43cc-9ec1-11e19834a42d	1d22c8f1-78ae-4b99-bfe8-b99da3592569	42.113.203.42	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 01:56:17.145034+00	2025-12-19 01:56:17.145035+00	t	f	\N	\N	2025-11-19 01:56:17.145055+00
61681349-25b0-4b90-9e15-c6d99014e230	987fa969-961f-4afb-98aa-636c3448bd87	15dc190b0a41cd28115854154152d3d269e939d4c232988d303f77db96790207	d775d98e-e2fe-43cc-9ec1-11e19834a42d	5edf4576-c33a-4e1c-be97-ba817e672a9f	42.113.203.42	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 01:42:03.575456+00	2025-12-19 01:42:03.575458+00	f	t	2025-11-19 01:56:17.144785+00	rotated	2025-11-19 01:56:17.02401+00
fd42d9b7-6fc0-49b6-86a6-b88b1a7697ab	987fa969-961f-4afb-98aa-636c3448bd87	d77c1ef62728d6e95cc3a719499b2c20149f0d39625ba9d965de46732b9fd3ad	e16b0f29-55d1-440d-abdb-d16d8e5c7865	92d2188e-70f1-4d70-80ba-9117cb45e5c5	42.113.203.42	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 01:56:28.611328+00	2025-12-19 01:56:28.611332+00	t	f	\N	\N	2025-11-19 01:56:28.611346+00
d0046a47-2d8d-4341-aa40-c5735d967f3a	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	59d4d606c24ffc2a25baa8694a45f54198dab1e46ff5aa46b0892cd50b5ae8cf	65dea00e-4121-4b5f-8770-871b3d689a9b	9de96cc9-c383-44d0-ad5e-c2fffeabaa0b	27.74.132.237	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-19 01:59:15.065932+00	2025-12-19 01:59:15.065935+00	t	f	\N	\N	2025-11-19 01:59:15.065951+00
2b6b09e6-a19b-4bd4-8ee1-23139cc4fe6c	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	8546e08c797a36adc935059cea1d9c7d4239f874fe8c7c88b8196c3fa15242d4	b430c905-9fac-47ee-84fc-8173e778d1da	afcc1797-7e96-4e29-9bc1-309d5ff4185f	27.74.132.237	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-19 01:59:58.89226+00	2025-12-19 01:59:58.892267+00	t	f	\N	\N	2025-11-19 01:59:58.892283+00
6094e99c-6d2f-4d81-877b-9b382d182ae8	987fa969-961f-4afb-98aa-636c3448bd87	d34f27fb0778d51947f36f01042d883b2ad3932ab5761e2203749ddf0a4ff990	5a203273-70a2-4191-9907-017348369801	fb405b9e-5381-4108-ba38-2bf01a9b7de8	27.74.132.237	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-19 02:16:09.763485+00	2025-12-19 02:16:09.763486+00	t	f	\N	\N	2025-11-19 02:16:09.763522+00
3dbab47a-da90-4605-a9b7-301459227671	987fa969-961f-4afb-98aa-636c3448bd87	916a0f7c5c972d5d401f1cd3dd7bcc6946efeff013fce0d986b4bec10362193f	5a203273-70a2-4191-9907-017348369801	ba0dc9b8-04ed-4661-b1bc-27b7060dabca	27.74.132.237	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-19 02:02:06.092356+00	2025-12-19 02:02:06.09236+00	f	t	2025-11-19 02:16:09.76219+00	rotated	2025-11-19 02:16:09.589274+00
9bb73d42-f87a-44f6-be0f-71b3db81ee86	987fa969-961f-4afb-98aa-636c3448bd87	ccda75796be0d2c0be6c04d27949cfc935c77a41fc5bb201fb29c541412baeba	16c310d4-29ed-4472-b466-828cd049c5fd	bd6af7ad-d84e-442c-81f0-e79c799b16d6	27.74.132.237	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-19 02:27:46.247239+00	2025-12-19 02:27:46.247241+00	t	f	\N	\N	2025-11-19 02:27:46.247282+00
98ce2d4a-8aa9-40d2-ac81-c05b172b1de5	c1d918d1-18d8-4837-a271-967d90f569a3	7d35380e7568f100b61394d7852da8e49ddb00e7fd88fc1cb7322f1c795365d3	6c94ddc2-1432-4a57-9166-bbb82f696799	d1dcf9b0-359d-40bd-8d0a-4e933efdf29a	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 02:38:06.089457+00	2025-12-19 02:38:06.089463+00	t	f	\N	\N	2025-11-19 02:38:06.089507+00
2fde816b-04d7-4526-aa4f-f99462b14f3e	c1d918d1-18d8-4837-a271-967d90f569a3	a79844f3ffc5414eab7a6085e125cf5a37c5fc17d283e7913396398d954e40a2	0c300e77-44bb-4c17-ba35-58149b8de032	afc53cdd-fa99-48fc-94d2-a536abe04f4c	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 02:38:16.209233+00	2025-12-19 02:38:16.209235+00	t	f	\N	\N	2025-11-19 02:38:16.209246+00
e9c9d037-d8f4-4b60-839c-ab8ae8d01d19	c1d918d1-18d8-4837-a271-967d90f569a3	3b8f868b4846d687769575d41ffa981cb5c4008ae0def882567e628454391829	7bf40121-fe37-45fc-a1f4-b97998c486e5	49f3f360-8e4c-424c-bac7-4e1948066ab3	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 02:38:36.360342+00	2025-12-19 02:38:36.360345+00	t	f	\N	\N	2025-11-19 02:38:36.360365+00
3d46df6b-1d8e-4cd1-9b54-05209b17ffe9	c1d918d1-18d8-4837-a271-967d90f569a3	312fbef32587627a0ee003b2212ab686537667c6b1b1cffd5459a75fdf350fe6	be7b2af6-2b62-45bf-9ab1-aec73d7b8ead	56203c05-0fe2-4b43-81e2-cb518188f16a	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 02:59:43.838536+00	2025-12-19 02:59:43.838542+00	t	f	\N	\N	2025-11-19 02:59:43.838595+00
d0e34796-25fb-4c64-8311-ef091ec53bdb	c1d918d1-18d8-4837-a271-967d90f569a3	6ffe17d976a9c30b9c892463a91aa0596444d954ad050ea7d38a84b3dd0e5493	85ca743d-2210-4ba1-a3d4-f25e780a705c	adb13934-1e09-4d32-8dc7-e8a37ae14623	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:01:11.826402+00	2025-12-19 03:01:11.826408+00	t	f	\N	\N	2025-11-19 03:01:11.826454+00
74eba567-6b72-41e4-a94b-9a7e59d17da2	2a04b41b-422f-455e-85c3-4c036e692b3c	ccbf0388118043e2f99235a37cadfd6d7ff45e5b7a111acfba779ef08d799d4b	a21ffada-84d6-4405-87d8-64303715584e	280e2e64-a034-498b-9e16-35c555740624	118.69.128.8	PostmanRuntime/7.39.1	2025-11-19 03:04:16.527245+00	2025-12-19 03:04:16.527251+00	t	f	\N	\N	2025-11-19 03:04:16.52733+00
6a73d60c-3cff-4e94-8298-2a8e50c0f9af	bb8259df-3cb8-487a-ab91-2ef95a68aa44	86ac51ad4abab97dac6d9cb9d60edf4b770fb3bc9915cd9acce71dbc766242f3	6fda6ceb-06d0-49b8-82e1-b63b29bf1e79	28c86db1-ca9d-47a1-b875-9b467b18dff8	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-23 15:10:51.102584+00	2025-12-23 15:10:51.102588+00	t	f	\N	\N	2025-11-23 15:10:51.102622+00
ba91d479-bdc1-4063-9676-bfaa42617a84	c1d918d1-18d8-4837-a271-967d90f569a3	344605fa0d757b079f5831f606eb4f59c5ed14a5ff13bb6c8b848b340e117ecb	96f117a6-8fa8-4271-98e6-618ed7d241ae	cd74e559-8e58-40b9-8646-c959ad16830c	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:30:23.898218+00	2025-12-19 03:30:23.898219+00	t	f	\N	\N	2025-11-19 03:30:23.898243+00
200b01b5-cb3b-4d3c-b30d-f1a059b70813	c1d918d1-18d8-4837-a271-967d90f569a3	c0fc87fdb380a2137fceda797819a865a7949cbfb06ef9b94028b086657ee6fb	96f117a6-8fa8-4271-98e6-618ed7d241ae	60757768-6f1b-4ed1-862e-306380919a72	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:16:17.068352+00	2025-12-19 03:16:17.068356+00	f	t	2025-11-19 03:30:23.897932+00	rotated	2025-11-19 03:30:23.773233+00
2641482f-2923-48cf-8258-36533bc29f3b	987fa969-961f-4afb-98aa-636c3448bd87	73c57c8c17d9093f0efe7dcf2026adf01c83da91a4f6d2b98d2758da29811c22	3d0631a1-ba5c-45b9-b453-f4235e29c869	58c3750b-b805-46a6-a8ff-4cedb6fc62da	210.245.98.228	PostmanRuntime/7.49.1	2025-11-19 03:35:45.359034+00	2025-12-19 03:35:45.359037+00	t	f	\N	\N	2025-11-19 03:35:45.359077+00
388388f2-124e-40ac-99bb-aee3f6941e5a	c1d918d1-18d8-4837-a271-967d90f569a3	ec4caee1656ee7b3305a31e7fbc4179da7dcea9ff70d35f25c76067e3427e6a7	a0b7fdaa-64a5-4dd5-a243-78b00bdeff17	bdbbbba0-da64-4696-80a1-b99db6adc544	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:41:16.173513+00	2025-12-19 03:41:16.17352+00	t	f	\N	\N	2025-11-19 03:41:16.173564+00
2050b555-c3db-4194-8cfe-bef5509a7b99	c1d918d1-18d8-4837-a271-967d90f569a3	b98fce8137c420e0dce9db56571abbb4e3cee55913831ad33224cfaa4318ab0e	f0236b5a-375d-4eb3-84f7-9dc0fdbe750c	6fc95749-675f-4977-8eb8-09cffdda934d	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:41:33.441475+00	2025-12-19 03:41:33.441477+00	t	f	\N	\N	2025-11-19 03:41:33.441489+00
ec65da7d-b46d-4754-9ed0-a5eef83e39e3	2a04b41b-422f-455e-85c3-4c036e692b3c	2dfdc42cc7811052e35a304166b06afcac8a277f1fd230e286ec9a8a757474f5	a68c75b5-60d1-4de3-8e60-d6f1f0b6bb19	ae1571f7-5e3b-49e6-a1de-1bd9d9950967	118.69.128.8	PostmanRuntime/7.39.1	2025-11-19 03:48:06.310059+00	2025-12-19 03:48:06.310065+00	t	f	\N	\N	2025-11-19 03:48:06.310118+00
28dd5090-3804-4e5d-bfc7-ee934f0d9f66	c1d918d1-18d8-4837-a271-967d90f569a3	07a8addb502ab2fed7186e6e64c66ea029bf5414dfc12b56b502ac797259b18d	42b634ba-56f6-4e0b-9469-d446b9d00ea9	89bad953-0a27-4ea8-a01f-82727844b296	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:58:08.799513+00	2025-12-19 03:58:08.799514+00	t	f	\N	\N	2025-11-19 03:58:08.799548+00
e0e7ba6a-6f31-4690-92e0-01e870b5268d	c1d918d1-18d8-4837-a271-967d90f569a3	5e46df3273962a4da3e85c880b4db1fbd5602acb2bc32016475ba9dd2e9a51ff	42b634ba-56f6-4e0b-9469-d446b9d00ea9	2638c434-cbab-4dee-a4c6-30e7a181bec2	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:43:09.016432+00	2025-12-19 03:43:09.016442+00	f	t	2025-11-19 03:58:08.799215+00	rotated	2025-11-19 03:58:08.65911+00
4d59988e-a1c1-4ce8-b651-1ab63e043671	c1d918d1-18d8-4837-a271-967d90f569a3	4349ae6682513be4fccb4fe164aa4475812db914a8a1dbf057eca68c04c6c231	dc476ff1-f409-45cf-8e14-3b0e7df57425	8e1b4e94-af38-45d4-9563-23616d0e3b40	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:58:17.263378+00	2025-12-19 03:58:17.263394+00	t	f	\N	\N	2025-11-19 03:58:17.263417+00
1c3b14d3-7db1-41a0-9505-f8b96732dce1	c1d918d1-18d8-4837-a271-967d90f569a3	cd4c84c5dce3635ad27c158d225c3a2f5405e00432e048d3d45cb0db4c9fb643	0359e4d1-e14b-4979-bc44-2a069662ba7d	bf716e43-8874-4e45-856e-8783e6f9d229	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:59:21.742555+00	2025-12-19 03:59:21.742558+00	t	f	\N	\N	2025-11-19 03:59:21.742599+00
6f1cb82a-8caa-4bc1-b89e-5eb403c45472	c1d918d1-18d8-4837-a271-967d90f569a3	864bed3c75a865ae30fce4203186b04659650aa89d1542a27970a46694427f2d	0b4e4afe-1fee-4aef-8c0a-70566195d74c	2f210b75-cbf0-4199-a68e-96a959639af9	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 03:59:38.899142+00	2025-12-19 03:59:38.899145+00	t	f	\N	\N	2025-11-19 03:59:38.899182+00
82db9952-c752-421e-ac1d-ad708bf2156c	c1d918d1-18d8-4837-a271-967d90f569a3	def2b34c591e87c9bdd0e25f904d26ac5006942d60f6484572995dfbcb4c1954	ad90e12e-590f-410d-a7f5-10a4322ba04a	d72e9334-79a2-4dd3-b859-4be13b0e7276	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 04:05:24.264372+00	2025-12-19 04:05:24.264376+00	t	f	\N	\N	2025-11-19 04:05:24.264414+00
299f6b61-ccc7-4160-ac4b-aef2b073abfb	c1d918d1-18d8-4837-a271-967d90f569a3	2d9947baa3bdc42be9b9e168a9ecb909949cb6d56cf143e169097ce655a4afe5	9c8ecc0c-54f2-4ccf-92ee-45d59296ca9f	afc7b5b3-f648-4428-96e7-f3e70537c7e4	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 04:09:22.605614+00	2025-12-19 04:09:22.605623+00	t	f	\N	\N	2025-11-19 04:09:22.605675+00
54cdd0ba-54a1-43bb-b0bf-a90588576eb8	2a04b41b-422f-455e-85c3-4c036e692b3c	218b626b0770a71ca892f54260c6f53c78168b9b327930089aaa65fdfdf80bd9	c80043cd-d76e-4705-a369-998cf7731fc4	e0515d32-c064-4d11-93ec-e0687590c254	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 04:18:04.047738+00	2025-12-19 04:18:04.047739+00	t	f	\N	\N	2025-11-19 04:18:04.047781+00
a8bc7fca-4e55-476a-9ce7-af5385fbfdf2	2a04b41b-422f-455e-85c3-4c036e692b3c	068c05b16f42f14c7abb2f711156403819e436af2cd6bf89a9dc1f4b238af043	c80043cd-d76e-4705-a369-998cf7731fc4	47b26106-3b5b-46a5-a05c-c215ddcb48a8	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 04:03:59.732228+00	2025-12-19 04:03:59.732234+00	f	t	2025-11-19 04:18:04.047473+00	rotated	2025-11-19 04:18:03.912216+00
13486bdd-9845-4aa9-b4e1-ab600e6d7cb7	c1d918d1-18d8-4837-a271-967d90f569a3	84eecc4d0b40b1813673c9f8b7d56187abf716f2bc7ba937428b47c990971ca9	62fb79c2-7704-4e25-bc47-7df13f2fdfbd	9fa5c297-c96a-4398-802f-9859be9afeae	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 04:14:02.674768+00	2025-12-19 04:14:02.674783+00	f	t	2025-11-19 04:28:16.790336+00	rotated	2025-11-19 04:28:16.637128+00
8dda4b8e-6866-4902-8feb-7d9988b203f9	2a04b41b-422f-455e-85c3-4c036e692b3c	30c43d82f6d31553493f40fb13a8cd28c411b88a7c5d3b34a39306e0d4912cf3	5ac1e629-3f98-437f-9245-9c91664ce4d7	3eb3cf50-a0e1-4212-bfeb-ed18fa1d40a9	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 04:22:10.288264+00	2025-12-19 04:22:10.288266+00	t	f	\N	\N	2025-11-19 04:22:10.288372+00
bfc737b6-3b0e-44e4-876f-5c798f65b2e5	2a04b41b-422f-455e-85c3-4c036e692b3c	94b8298bcde104711dc672ea5db9bd1515d84821c51bf5cdd2c5210faaff6a6d	f3ec165d-8584-4bbe-8d9d-27aab84a8a19	13603b47-d964-4bca-bdec-97f71f4178ee	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 04:24:15.957357+00	2025-12-19 04:24:15.95736+00	t	f	\N	\N	2025-11-19 04:24:15.957389+00
eca92465-39a2-4aab-ba57-8ece0699e580	2a04b41b-422f-455e-85c3-4c036e692b3c	c89b35329ce747852efd493b2d8a3ecb95c3e73ba8576d5f74151aa11b876136	2c60b0fa-4b09-4a95-b4b4-7e6189f69cb6	ad0e3339-d9dc-4885-b298-e85b643163ee	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 04:26:36.080373+00	2025-12-19 04:26:36.080376+00	t	f	\N	\N	2025-11-19 04:26:36.080428+00
d19b26fa-cea4-45a0-978d-f7a153ffd36f	987fa969-961f-4afb-98aa-636c3448bd87	102bbaff368657f81c8edee065790e81c784b5c4982e2bddb10f0117003ed6c9	c70655ac-218c-4e8c-a949-5c3c3a5e4b9a	7871e5fd-18c1-47cf-ac82-787ed866cf52	210.245.98.228	PostmanRuntime/7.49.1	2025-11-19 04:27:19.821703+00	2025-12-19 04:27:19.821705+00	t	f	\N	\N	2025-11-19 04:27:19.821717+00
0090d619-49c9-4a70-9111-f246d0e09c0f	987fa969-961f-4afb-98aa-636c3448bd87	b536bdacb7e30abaf202771e7600ae857e7efe2ee69e739335d6c8462eb82790	020a5323-0d13-4769-8930-91deec13598b	db5084dd-1052-4607-9f8c-63ea5706328d	210.245.98.228	PostmanRuntime/7.49.1	2025-11-19 04:27:58.846887+00	2025-12-19 04:27:58.846899+00	t	f	\N	\N	2025-11-19 04:27:58.846927+00
15cfd73d-660a-40a2-bf3b-19e0296b003b	c1d918d1-18d8-4837-a271-967d90f569a3	c1deab12f04b4809ea0e28939042e01a46ed7df5f20005a252f4fe377ba14dfb	62fb79c2-7704-4e25-bc47-7df13f2fdfbd	a2562c8c-95f5-4596-aa8d-926bbb8506ff	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 04:28:16.790575+00	2025-12-19 04:28:16.790576+00	t	f	\N	\N	2025-11-19 04:28:16.790592+00
fded2b53-341f-4caf-aabd-ce626935c517	2a04b41b-422f-455e-85c3-4c036e692b3c	3891c90c3a3a6d022627aacd521e2401a864737ec4e9349862e69e0de59fe648	842831a0-1deb-4be5-b4b6-1d7ed59e5184	896a29fc-8f04-438e-a049-4cbbdbb13a7c	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 04:30:45.476191+00	2025-12-19 04:30:45.476193+00	t	f	\N	\N	2025-11-19 04:30:45.476233+00
aec245eb-3493-4890-971d-b45f4dfd49fc	c1d918d1-18d8-4837-a271-967d90f569a3	b7cc10f22e2033ff3250e4dbb5bf29d51c52d737163817cc56c5646416ef9766	7765f7e4-a563-48fa-8589-a660d2ffee7f	99da0e82-6cfc-4b29-ba99-3d1efe797643	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 05:28:01.462735+00	2025-12-19 05:28:01.462742+00	t	f	\N	\N	2025-11-19 05:28:01.462808+00
6d5298f4-5d6b-40a6-9a38-e9b28b5244bc	987fa969-961f-4afb-98aa-636c3448bd87	2ad5c07e189829ef61836d731aeb91d61278c8a26b021999cf12f934ac0b89b3	33cc3626-5d1d-4f3a-a588-8d55c2e61a91	8f125e09-c3f1-47e1-b871-8bf0062ca7a7	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:32:57.519139+00	2025-12-19 05:32:57.519142+00	t	f	\N	\N	2025-11-19 05:32:57.51919+00
968f5b00-f010-429e-b557-4d2ae2d73bcc	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	f14c314cf25fdeed3beb60040e00303c145a32e0cabfe41f8f439b8ac2d3a006	a9dfdcd2-8a18-44a2-b90e-f0dc85564deb	a5ca2d10-3e71-4b7d-a23f-67e04d3c60bf	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-23 15:12:50.015331+00	2025-12-23 15:12:50.015336+00	t	f	\N	\N	2025-11-23 15:12:50.015363+00
01816455-1246-427f-af86-1d5bc13a3486	987fa969-961f-4afb-98aa-636c3448bd87	b4dcf62b6bdbf24a08af02df08cb387287f51d5f51f5fa95fb0c3f3e5ef91248	7517420a-7943-4ffa-8a6d-bdd61502b82c	e98d55ec-4273-4ca2-bcc1-0662ecaa7b0d	113.161.234.220	PostmanRuntime/7.49.1	2025-11-19 05:41:59.647379+00	2025-12-19 05:41:59.647382+00	t	f	\N	\N	2025-11-19 05:41:59.647394+00
65212eb5-80c6-44ac-8ce0-f1ed328693ec	987fa969-961f-4afb-98aa-636c3448bd87	cee98de703730f0856fef1c17bfd8e5d3de469b555f9882498acad57e5bce3fa	e70b0f89-c7a2-4be0-abde-113049a3370a	78418535-08b1-4e7e-bb2a-b00784f34ead	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:48:40.377123+00	2025-12-19 05:48:40.377126+00	t	f	\N	\N	2025-11-19 05:48:40.377157+00
8002d80b-1c2d-4f54-9b90-564c4a463a8d	c1d918d1-18d8-4837-a271-967d90f569a3	cef98b6631038770a3c2753c04245e4dce37069fe14a44f3623b06ad87db2dca	2c93335e-bbf2-4b4c-9c39-4a1e414785a8	9a3af1ac-54a1-4823-a4bb-0994dc5ddd00	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 05:55:42.139232+00	2025-12-19 05:55:42.139233+00	t	f	\N	\N	2025-11-19 05:55:42.139244+00
e23db91f-5c45-418c-a4f1-5aedab8b7ecc	c1d918d1-18d8-4837-a271-967d90f569a3	1e5bea3c60e68360264d236efb3eeea703dc7b60c5e829790630c16a576196bb	2c93335e-bbf2-4b4c-9c39-4a1e414785a8	8b7aaea3-c509-4c93-a2d5-3a758733c925	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 05:41:37.631919+00	2025-12-19 05:41:37.631926+00	f	t	2025-11-19 05:55:42.139013+00	rotated	2025-11-19 05:55:41.985977+00
d216716e-c6f6-4869-9f5b-0356dde2e169	987fa969-961f-4afb-98aa-636c3448bd87	e969a8ec118531805bd2baafeed31336a6e86bd68489897904244148dfa7d3e4	8a39d4c8-8110-4ca7-8738-7c60fba68184	4bb40c3c-81a0-4e7b-905d-125b0d124071	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:54:40.306122+00	2025-12-19 05:54:40.306132+00	f	t	2025-11-19 05:55:47.404462+00	rotated	2025-11-19 05:55:47.283321+00
18e78101-90d8-4fe9-b1b9-e9ec26882775	987fa969-961f-4afb-98aa-636c3448bd87	735b19ba35a5f0a65535b41a74b25a1badcb67c8aeea82b0852cbb5bfac8c36b	8a39d4c8-8110-4ca7-8738-7c60fba68184	5a609d95-5cff-43cc-8735-f1bce7c29b95	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:55:47.404678+00	2025-12-19 05:55:47.404679+00	f	t	2025-11-19 05:55:49.001104+00	rotated	2025-11-19 05:55:48.885304+00
41e10f8c-0f2a-4fda-92b2-8b75ec30c4a6	987fa969-961f-4afb-98aa-636c3448bd87	48bf34a7298045fa219d0566a3bff5eccda17f95f6ff38b39f3264026f8da8c7	8a39d4c8-8110-4ca7-8738-7c60fba68184	9b9afc50-282b-416d-b77c-31ecf5d24a9d	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:55:49.001357+00	2025-12-19 05:55:49.001358+00	f	t	2025-11-19 05:55:50.648652+00	rotated	2025-11-19 05:55:50.500145+00
ce420e19-45bc-4b31-977d-f2ccef68a7f5	987fa969-961f-4afb-98aa-636c3448bd87	08d8928f2350b1eec9ae1d94158c6f9266d57fc2df127a2ef8df53d61a983840	8a39d4c8-8110-4ca7-8738-7c60fba68184	5526ef32-b27e-422b-95e0-e91532f61787	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:55:52.070655+00	2025-12-19 05:55:52.070656+00	t	f	\N	\N	2025-11-19 05:55:52.070668+00
4130fe38-b344-4e2e-831f-190a6e1196fd	987fa969-961f-4afb-98aa-636c3448bd87	35832365c0c4cc58d0303d2ed1816da358e4ce81f3f86ee496f9e711898abbb6	8a39d4c8-8110-4ca7-8738-7c60fba68184	e32ebdbe-484a-4062-853b-5920faf11de6	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:55:50.648894+00	2025-12-19 05:55:50.648895+00	f	t	2025-11-19 05:55:52.070166+00	rotated	2025-11-19 05:55:51.942481+00
5f936d05-285f-4423-99bc-155f880ac6ab	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	b034820f2e7c2fadd71f4de2299f6338cbef14ae95901fcf9f0903156319025a	0f3684d7-28bd-4b52-b164-d5b688f589b6	8584e8e9-aa70-4b02-aade-bfcdfb4d16e6	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:56:59.621007+00	2025-12-19 05:56:59.621009+00	t	f	\N	\N	2025-11-19 05:56:59.621032+00
4ecb72c8-4414-474c-89c0-d445d38084a2	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	7886c499cf2509a7b385ce6e8e17c111b2a82e241a3328459f0f51ffecc01053	78a2fa61-1915-4ef6-b421-5c490a36f6f4	00d1239b-a0d5-4f98-8a59-3a4ca88b2def	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:58:19.174382+00	2025-12-19 05:58:19.174385+00	t	f	\N	\N	2025-11-19 05:58:19.17441+00
2fac37d3-3df5-4070-8392-e44df56ebf94	987fa969-961f-4afb-98aa-636c3448bd87	3fc7ce4c953fe9bbc2bc612af8c0cad2ae1c7716d9c5e14ae5c03e70c166ad65	f743de53-0111-4f16-baf3-b46c344674d5	1c09144b-8424-434b-8704-34796fe91698	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 05:59:03.730353+00	2025-12-19 05:59:03.730356+00	t	f	\N	\N	2025-11-19 05:59:03.730367+00
e3689691-38b6-4cf2-9e30-1cd833bb0fd9	c1d918d1-18d8-4837-a271-967d90f569a3	4e8f19325488886c82b4fd651a8b1075b40a45af6d18cffa1687f6696f5fbfe4	e4c567a4-064a-41e0-9517-d04b00048b1b	a7e685bb-b4b4-4c73-b8d2-cdecf926c9fa	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 06:10:55.716784+00	2025-12-19 06:10:55.716785+00	f	t	2025-11-19 06:24:58.798161+00	rotated	2025-11-19 06:24:58.667616+00
2981fe4f-b3bd-45eb-bcb1-6c9dd8e65830	c1d918d1-18d8-4837-a271-967d90f569a3	c9b9db6c969340f3aee273dc5a88be9bd3934ba57d46ef4f4b383c0ee28b28e8	e4c567a4-064a-41e0-9517-d04b00048b1b	7776f636-e4fa-4ce7-bed6-20afeecb5175	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 05:56:39.720032+00	2025-12-19 05:56:39.720038+00	f	t	2025-11-19 06:10:55.71651+00	rotated	2025-11-19 06:10:55.545378+00
5530827e-b6d5-48ca-bd60-705a4b3f5be3	987fa969-961f-4afb-98aa-636c3448bd87	2d98e208864926828e4002b851dbdd86ec1a62bb273c4de6f90da94c36861596	ceae110a-5899-49f9-a3d3-072fe390b725	40d5c3ce-6825-4eb2-8492-588a091f3794	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-19 06:14:28.993902+00	2025-12-19 06:14:28.993908+00	t	f	\N	\N	2025-11-19 06:14:28.99394+00
64b5c27f-62af-4397-b6be-3c42618714f0	2a04b41b-422f-455e-85c3-4c036e692b3c	8b016c808dc147a4c80e6eace911be85f5344659e201fcdeccb099953f2e4bff	4dc74e5f-159e-4444-ad6a-baa9fd556674	31831cd3-b5f2-4e80-bf6e-8ea106c3d88b	104.28.227.234	PostmanRuntime/7.39.1	2025-11-19 06:22:28.863858+00	2025-12-19 06:22:28.863866+00	t	f	\N	\N	2025-11-19 06:22:28.863916+00
c15e2ead-72cd-4562-9ca9-7e38962c288b	c1d918d1-18d8-4837-a271-967d90f569a3	19e258e15ad81712ddbf172b0ffd035e6335da02e72c03a88bfd151b2c2416a6	e4c567a4-064a-41e0-9517-d04b00048b1b	3f9d33e5-35f7-4c89-b929-e1e93b290881	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 06:24:58.798431+00	2025-12-19 06:24:58.798432+00	t	f	\N	\N	2025-11-19 06:24:58.798473+00
d3d20bd4-423d-45c4-b353-3af0c200372b	987fa969-961f-4afb-98aa-636c3448bd87	407af87c28fa702dd99c59933e0591762db9fcb2a5f24914a6d83c4dbe45ebd8	55319af7-78ec-4c0c-ae09-30e15b3a8c32	a2c7911b-06c0-4b4b-865d-a94f17ae596e	118.69.128.8	PostmanRuntime/7.49.1	2025-11-19 06:28:56.04808+00	2025-12-19 06:28:56.048087+00	t	f	\N	\N	2025-11-19 06:28:56.048165+00
02e2e824-86e1-4790-be84-cbe0de7fb934	2a04b41b-422f-455e-85c3-4c036e692b3c	7ff3b07df9fdeaae0a4d449e12dd0ea3fba82e2976c213bbe501d38ef26051da	8aea2566-0dca-4f08-95b9-b06f067f1bcb	d378eec3-4459-4d20-9063-d7a0b831f38e	104.28.227.234	PostmanRuntime/7.39.1	2025-11-19 06:36:05.087367+00	2025-12-19 06:36:05.087374+00	t	f	\N	\N	2025-11-19 06:36:05.087421+00
14ca8deb-842e-4688-b568-f78472dd7d9b	2a04b41b-422f-455e-85c3-4c036e692b3c	6bb8b657855aa7c930e282613f957f2e84da6b2d1af581a9ba9f47c8f9aa4f08	036dcf9b-e7fd-46cd-adc0-c38f283c8269	c4ad02e3-30b0-407b-9c64-cde2b7f6d0ef	104.28.227.234	PostmanRuntime/7.39.1	2025-11-19 06:38:08.009727+00	2025-12-19 06:38:08.009734+00	t	f	\N	\N	2025-11-19 06:38:08.009792+00
d8d080b9-f289-47a0-806a-6ebecb2981d4	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	35755b4b0a67b8c59a401edf1ee3abeb6796523022bb91881cb71e822e19aea3	fd5ad4af-785c-477e-93c7-42408db53c31	0a7de79e-fb3e-4254-8e47-96d1df700101	14.191.79.233	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-23 15:14:48.894677+00	2025-12-23 15:14:48.894681+00	t	f	\N	\N	2025-11-23 15:14:48.894702+00
b7ec0314-98e1-4a92-b740-f49d265ea1ff	987fa969-961f-4afb-98aa-636c3448bd87	ce558beae1ee0e4e19bc05250ae2e21f08e7752b5129f82a06324adc053ae4e9	3dbaa9ec-3da1-4437-884f-25854870d5a9	0fc24062-a091-4e5c-b6f8-d503f656e167	118.69.128.8	PostmanRuntime/7.49.1	2025-11-19 06:40:34.103762+00	2025-12-19 06:40:34.103764+00	t	f	\N	\N	2025-11-19 06:40:34.103798+00
02f69aa9-8978-49e9-be0c-df2fbef415bd	c1d918d1-18d8-4837-a271-967d90f569a3	ac042f178219023bf9270867ca43683fb9df4356c4ae0c0ace29acefd8f52afd	848fdb1c-a89b-4462-9485-dd3acda0c9e7	6d6e62e3-3040-4b1f-b7bc-cbcf9875eb39	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 06:54:58.407197+00	2025-12-19 06:54:58.407198+00	t	f	\N	\N	2025-11-19 06:54:58.407234+00
462744fc-2ae9-4f8d-b2f9-ca1b937c2bdc	c1d918d1-18d8-4837-a271-967d90f569a3	b9969a56aeb6ebda167104997e2405fdfae041d9dddd2d72697a23e0708e376e	848fdb1c-a89b-4462-9485-dd3acda0c9e7	47875a02-58f4-492c-8ca5-fc4c591f5d75	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 06:40:19.975213+00	2025-12-19 06:40:19.975215+00	f	t	2025-11-19 06:54:58.406895+00	rotated	2025-11-19 06:54:58.253145+00
2f222798-74a1-4012-a81c-175de4fbbb7c	b46b4c47-31c6-4ad2-9829-0332963bb646	2974c668e6444b0378668213488f03728cda60e38e5c9964105ab35c0e479885	421587ef-37cf-47fd-9142-242585f764f6	95bbc9b4-c656-4197-bc2e-73b66d18877f	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:02:46.411513+00	2025-12-19 07:02:46.411514+00	t	f	\N	\N	2025-11-19 07:02:46.411541+00
bad10ffe-d407-4b27-b81b-6cb310fbbb3f	b46b4c47-31c6-4ad2-9829-0332963bb646	75263430d2ad1b617537c6bc7ccf48d4512da6e451bffcda0cfbc30f0d59e1ea	421587ef-37cf-47fd-9142-242585f764f6	8ca729a6-a25c-48f1-b4d5-ecd0c6f16c2e	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 06:48:40.464799+00	2025-12-19 06:48:40.464811+00	f	t	2025-11-19 07:02:46.411232+00	rotated	2025-11-19 07:02:46.270716+00
152e893c-7d6e-450b-917f-17618c632b59	987fa969-961f-4afb-98aa-636c3448bd87	96686c760c75c290c90e9dc864bb1b382c3d29b4ea7e0074c96a4e8f8d1fe9b2	6e0161b7-5fdc-420b-a63d-83974e00bcf8	06097fbf-f060-4a07-9846-8d30be2be529	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:04:10.60551+00	2025-12-19 07:04:10.605514+00	t	f	\N	\N	2025-11-19 07:04:10.605551+00
7b34dbc4-d272-4b0b-a9f0-05c5ec235dc1	987fa969-961f-4afb-98aa-636c3448bd87	605705c21af8faeb42e9b3956ee8bd3f01cb1efae11755f25ca33156282a8ecf	1530505f-1079-4451-8658-267d5e09faf2	650c7214-43e6-4d9c-b5d7-7475cb5c25c3	118.69.128.8	PostmanRuntime/7.49.1	2025-11-19 07:06:35.794568+00	2025-12-19 07:06:35.794577+00	t	f	\N	\N	2025-11-19 07:06:35.794648+00
6d265524-a2e9-4ff6-a217-3f7d1f608b2d	987fa969-961f-4afb-98aa-636c3448bd87	9fddded8cf6237b5cd611fb3e93c126cadd60f1578520f3096094b0d6043a8ed	70ade0f9-0246-49d4-95eb-230b8f7c6de7	a12e6826-8dee-457c-9da7-eaff93362c25	118.69.128.8	PostmanRuntime/7.49.1	2025-11-19 07:08:00.582203+00	2025-12-19 07:08:00.582206+00	t	f	\N	\N	2025-11-19 07:08:00.582263+00
e1e09a04-1e79-4988-b3b1-e3646399a938	c1d918d1-18d8-4837-a271-967d90f569a3	414963bfadbf88feef85c1dd1bdeef9adbb27cab1fb777de17e379140d125314	78c97cf0-6c9c-4a8a-8612-b6eb648808e0	b7a0c393-9175-456b-9c2f-9ae15b82cc0d	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:10:07.576274+00	2025-12-19 07:10:07.576277+00	t	f	\N	\N	2025-11-19 07:10:07.576345+00
d698ffaf-8dd8-478b-94b3-adcd680a52a0	c1d918d1-18d8-4837-a271-967d90f569a3	5052cdd8b04e1c5ec13976fcb44cef434f0e5137ae5a8a795fe66062a6579f54	6541d357-f7f1-4c04-b492-516301548877	e954998e-9463-44d8-b15b-6d0010b220d6	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:16:47.817096+00	2025-12-19 07:16:47.817104+00	t	f	\N	\N	2025-11-19 07:16:47.81716+00
620694ae-a3b9-4dcf-847c-1d8185d1eb1c	987fa969-961f-4afb-98aa-636c3448bd87	880cb2ce1efbf8916693cda9e3bd5ad7f1d65164a4e8da70e87cafd7887f425a	f627d583-0789-4270-9ce2-98fc8b37c237	ef904bad-e29d-43a6-ac14-d4328d6178ea	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:25:32.220991+00	2025-12-19 07:25:32.220998+00	t	f	\N	\N	2025-11-19 07:25:32.221057+00
dd141b8d-9212-42f0-9469-2307ee90593a	c1d918d1-18d8-4837-a271-967d90f569a3	280520a27bedc3c8af20c4f612f633af2a452329d5fcd413572b95198a07746e	f1b7241f-2535-4d1b-8358-644ccb2d6f3e	a1bb7478-2a4d-4b20-8a61-ec738a450685	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:31:59.367715+00	2025-12-19 07:31:59.367718+00	t	f	\N	\N	2025-11-19 07:31:59.367743+00
eaf23ab3-f7a8-49ef-85de-dca4e6d0a5b2	987fa969-961f-4afb-98aa-636c3448bd87	fc788402461ac48c1b045ded1eadaf37ecd4f56760584b08e60f9ed6317614c9	694413d7-b93d-47be-a6c4-bfa8551314f1	e542b427-f0d2-454f-9e47-43ae43468bec	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:42:01.112266+00	2025-12-19 07:42:01.112269+00	t	f	\N	\N	2025-11-19 07:42:01.11433+00
58082002-e1d6-4c56-b4b6-7be509dbb1bd	c1d918d1-18d8-4837-a271-967d90f569a3	c1d9a5e8ef1d7ed43955c7d9d104bf2a5cc8a675dde4f40ade92d0aae53464a4	b877c9f4-f4a4-446b-906e-59de6fbc1199	83c45cf8-b66e-4840-8429-e036a2dcb079	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:51:14.281602+00	2025-12-19 07:51:14.281604+00	t	f	\N	\N	2025-11-19 07:51:14.281644+00
3f49393c-18e3-4a6b-93d6-7c55ced3e328	c1d918d1-18d8-4837-a271-967d90f569a3	7e1219646f13859e3f820aa4716ab5603407589a4ef555df304bd026ca37e40a	b877c9f4-f4a4-446b-906e-59de6fbc1199	4d8fed4f-4675-4ba2-aebb-57a4ac44e615	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:36:33.858952+00	2025-12-19 07:36:33.858965+00	f	t	2025-11-19 07:51:14.281316+00	rotated	2025-11-19 07:51:14.118525+00
87a4db19-13af-4e9b-9597-50fec4852279	c1d918d1-18d8-4837-a271-967d90f569a3	8e6cb6806bb1a599ad2670059560cfbae53e5d51f731c43ab7a32154f5b7fd03	2ab7e138-7027-4e5e-996c-af8cc78424a0	2de49a63-0bfd-425a-8eea-279e8356c76d	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:51:19.074134+00	2025-12-19 07:51:19.074137+00	t	f	\N	\N	2025-11-19 07:51:19.074148+00
ce2b4943-7ff0-47e5-9f8a-71ae5524881c	987fa969-961f-4afb-98aa-636c3448bd87	ec40518a7f6f475972aba6cc0d846f83d088af430b3633d390716c075cfbc828	d99159cf-2c06-4aa3-b6f6-64014ba33ebd	8127bb56-177d-46e5-887f-970f3a0cce07	113.161.234.220	PostmanRuntime/7.49.1	2025-11-19 07:51:51.251623+00	2025-12-19 07:51:51.251626+00	t	f	\N	\N	2025-11-19 07:51:51.251641+00
ed4079ad-124e-4b51-b44e-316bc382ca0e	c1d918d1-18d8-4837-a271-967d90f569a3	2818d5eb96fa175d8c294a6e810d5f436caaa83420fce18a2e6cb5d4cdeff7a4	cc3797bf-a63e-4233-aba2-66ed2026e34b	6a406242-c785-4125-aa28-4b064efdcdfb	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 07:52:14.981458+00	2025-12-19 07:52:14.981461+00	t	f	\N	\N	2025-11-19 07:52:14.981484+00
4cf5ec7d-6b94-48fa-99b6-c4ded10f18ff	987fa969-961f-4afb-98aa-636c3448bd87	3219370e8a60ccced65912583d45205c36b55f847766974436fbec199701af9c	61974aac-df6e-457a-83f7-53d827a45215	35d6d0fd-42d6-423e-adde-e4e833a208b6	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 08:01:11.054457+00	2025-12-19 08:01:11.05446+00	t	f	\N	\N	2025-11-19 08:01:11.054486+00
a712488b-525a-4503-a0e6-16362e588d36	987fa969-961f-4afb-98aa-636c3448bd87	6e7c360e7dd33fee29440969aa79f92c9963c62465b417313fa935814fed76c7	0d6c5fba-c0b9-431f-8843-0fb4101669af	e3a02c62-b28a-4ff1-a56c-769e4a364cb4	42.113.203.183	PostmanRuntime/7.49.1	2025-11-19 08:04:22.589708+00	2025-12-19 08:04:22.589716+00	t	f	\N	\N	2025-11-19 08:04:22.589765+00
73aae563-0cd8-4fcb-8af8-96c79a3ba6bc	987fa969-961f-4afb-98aa-636c3448bd87	cb641364e4bab1ef2360619e4f1c5ae3188f919959b75514f590e2ac40ad78d7	9e2a89d2-fbf7-4277-983f-837253dbff77	cdd04bd5-faa2-41d8-946a-d842bdc0fa3b	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-19 08:18:55.444889+00	2025-12-19 08:18:55.444895+00	t	f	\N	\N	2025-11-19 08:18:55.444941+00
0fec0e75-abf2-44ce-a046-6ed42766f137	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	2575be9a833794d60185f36b1972fd841cc3a31fedfe56170fe6122d406f7a61	25074313-990c-4a4e-9985-a123a356a02f	27fc9a64-7787-4479-ba5a-3dd25bf07866	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-19 14:02:28.286137+00	2025-12-19 14:02:28.28614+00	t	f	\N	\N	2025-11-19 14:02:28.286184+00
f90c43a0-e95c-40db-bb64-4bb52115a142	987fa969-961f-4afb-98aa-636c3448bd87	334ae536d8b3c3aeb3ad256fc430f46b8a88d52b94bd2cec7fe6820ec03f18f2	8ccd3d66-9fe9-45dd-96df-d89cd0692a74	a10229da-1bdf-4332-b31c-238c715fec79	27.64.96.160	PostmanRuntime/7.49.1	2025-11-19 14:12:34.766844+00	2025-12-19 14:12:34.766851+00	t	f	\N	\N	2025-11-19 14:12:34.766901+00
42bfbc0f-1738-43b3-afb3-96a06317b096	987fa969-961f-4afb-98aa-636c3448bd87	6f6bfb398312d76f2105a6a4b8575575916cbdaa461ca9400cba0b9c3aaf2202	6a0bb73e-d321-45c1-9972-42c41f3b7a31	0029959f-a9f6-4c62-a54a-4d6a7f2374e1	27.64.96.160	PostmanRuntime/7.49.1	2025-11-19 14:13:00.016494+00	2025-12-19 14:13:00.016497+00	t	f	\N	\N	2025-11-19 14:13:00.016512+00
30103110-0c7f-46cc-b68d-21f1bc1d7a3f	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	c0cceba1cb7bbba8b63b54f6db26d2a7c2c33fe9eb7e4bac31a57cd21b2ed1d7	4522f8b5-4935-4fb8-836c-7d0f9291380a	7f91580f-d091-4c00-acc0-6e392dd941e7	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-19 14:23:24.416513+00	2025-12-19 14:23:24.41652+00	t	f	\N	\N	2025-11-19 14:23:24.416565+00
39586f55-e21d-4efd-9394-a672c1a670e7	987fa969-961f-4afb-98aa-636c3448bd87	60ed4822281f904c2eab51b8ac3fa6d2593826e6aee3d31ba59d481fee2045a0	bb1bf75a-8f38-42d0-a2ce-c40ba3430099	feb6aae4-2e17-4024-bd88-9b2b1efd4732	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 09:36:41.082865+00	2025-12-20 09:36:41.082869+00	t	f	\N	\N	2025-11-20 09:36:41.082918+00
ebd1e9ca-4e36-4a43-9e64-46b1dac3ed73	987fa969-961f-4afb-98aa-636c3448bd87	74c328d2ae76c48932b29fbf8bf027fa2aa2f2977278f0085ecf0e9aa5f55a17	fa348859-f972-4d42-bdd6-a1461b25ffb7	981a2317-9734-4104-8b43-6d927574e5ec	42.114.93.242	PostmanRuntime/7.49.1	2025-11-20 10:04:13.884175+00	2025-12-20 10:04:13.884183+00	t	f	\N	\N	2025-11-20 10:04:13.884239+00
c3c160c8-e290-49fc-b44b-f08b08176c70	987fa969-961f-4afb-98aa-636c3448bd87	f14dc8b928135a2f00efd76c2bae5cc3fdc8cf146cd02751eb7f98a76930a11d	c06d09e7-37b9-4f74-9bd6-1cd3a6619445	4252fb2e-377c-484c-91ed-f63deb0acd04	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 10:18:32.330269+00	2025-12-20 10:18:32.330276+00	t	f	\N	\N	2025-11-20 10:18:32.332386+00
0616a9c8-6ac5-47ca-b6e5-726c78272123	987fa969-961f-4afb-98aa-636c3448bd87	c47e9d4f50262c545b006ced014f06a1274dee0442e078557d0d1615aa5fe7fd	9016c133-dfc4-4a8a-b944-fa18aaef5576	d37e1037-1581-4846-869e-bc03245acce2	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 10:33:24.682717+00	2025-12-20 10:33:24.682718+00	t	f	\N	\N	2025-11-20 10:33:24.682764+00
f5885ce7-ba6f-4094-a55e-72bb024160a7	987fa969-961f-4afb-98aa-636c3448bd87	4864d178aaf7fc32993fb84e46d686351aa2b61e2e14a9c53782318e4f1d5efa	9016c133-dfc4-4a8a-b944-fa18aaef5576	5914fb90-1ff2-4a9a-a93e-91f73952631e	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 10:19:05.58789+00	2025-12-20 10:19:05.587893+00	f	t	2025-11-20 10:33:24.682443+00	rotated	2025-11-20 10:33:24.432578+00
763eccb1-16c0-4e24-8f15-bda6420ad1e3	987fa969-961f-4afb-98aa-636c3448bd87	cbbf6e73c689c0618d8d7039a964943a496de39ac56730654bf25d2e0b4b0336	9cdc71e7-aa8e-4144-9ab4-e89d6b419174	5854ee0a-b9f8-49be-a1bb-63a0d134a49c	42.114.93.242	PostmanRuntime/7.49.1	2025-11-20 10:50:19.128771+00	2025-12-20 10:50:19.128778+00	t	f	\N	\N	2025-11-20 10:50:19.128831+00
f38372b3-6c19-4bb2-8671-bd1c806483e1	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	40734022c4a894285e9859b5090d0d497b866db3f34b6dcd25b23b78ba85b0d3	d6a68eb5-978f-42dc-8313-872a1d96a704	e6bf72dd-d48e-4c0a-b8dd-b9e88a6c03eb	14.191.79.233	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-23 15:31:47.261747+00	2025-12-23 15:31:47.261769+00	t	f	\N	\N	2025-11-23 15:31:47.261781+00
054cba7c-5503-4fb3-b425-0cd9c6d0687c	987fa969-961f-4afb-98aa-636c3448bd87	de5e8341824d9ea0c5a90389c529d82d6b15e954009d3288fe2fcd45a958471c	0a945847-887d-493b-bb97-b027d6788c69	b7999787-029a-4778-b537-2c58300f37d7	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 11:07:33.0516+00	2025-12-20 11:07:33.051601+00	t	f	\N	\N	2025-11-20 11:07:33.051649+00
f26d30c3-bf1e-47f7-8193-8b1697495b6b	987fa969-961f-4afb-98aa-636c3448bd87	1cb197ab170f9e1e6d6311ddc077de97d87e5d144a0f4a70f244d7b684205366	0a945847-887d-493b-bb97-b027d6788c69	1979f555-4eba-4a9f-843d-707879a9a6b3	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 10:52:37.55782+00	2025-12-20 10:52:37.557822+00	f	t	2025-11-20 11:07:33.05132+00	rotated	2025-11-20 11:07:32.880132+00
f4f76df2-4cf6-455b-a479-93d3647a6964	987fa969-961f-4afb-98aa-636c3448bd87	911a3960ad27481011d577483ec5c0cf45df8c3a22f2a2c18e22e7a66e5c35c4	93daec3a-e747-466f-84eb-e21caec440ee	f9154493-a879-457e-a112-13d9f8bfb47b	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 11:07:39.803201+00	2025-12-20 11:07:39.803203+00	t	f	\N	\N	2025-11-20 11:07:39.803214+00
b2a2f3b1-480b-420e-9633-b806f459d312	987fa969-961f-4afb-98aa-636c3448bd87	4f0a7a29c53afc4c52fa5e93b6b123229f2211015f59c852e0c708483671d52f	11cd0e36-78a1-4138-a659-aff5f406a6c2	4d8eebdb-611a-4a91-9920-4031768b6b28	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 11:23:50.204936+00	2025-12-20 11:23:50.204939+00	t	f	\N	\N	2025-11-20 11:23:50.204985+00
c9cff5e5-3207-481f-85f4-25682609bb47	cd23d611-1644-4d29-b7b3-100f9458018c	9dad0c6e9e6a70ecb611dc576df282a8f98670548f2595a04a864c1aa0e8137c	2f08d252-9656-46c9-8a65-416e758b8dee	bf042ecc-1640-40bb-9a26-7d7b225620fd	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 04:26:00.335626+00	2025-12-24 04:26:00.335645+00	t	f	\N	\N	2025-11-24 04:26:00.335715+00
84ab260e-537e-471e-ba51-76244fa26e2f	987fa969-961f-4afb-98aa-636c3448bd87	60ec648952ba7d624f9e391af3dd0af8be9c8d7d83cd099e264fddd7eceec1ef	1017c439-018f-4349-bb59-54bbdb31a280	30db96c2-04d5-4521-9ebb-9bfbde406e30	27.64.96.160	PostmanRuntime/7.49.1	2025-11-20 11:47:10.057159+00	2025-12-20 11:47:10.057162+00	t	f	\N	\N	2025-11-20 11:47:10.057206+00
04137743-ecdd-4d80-8a44-931afe794167	c1d918d1-18d8-4837-a271-967d90f569a3	8673cc829bdb4f3fd54ccf88eb30ff4d6d8e7fa0f78adff711c744bfa5084183	296e5828-1dd6-4aee-b9aa-7fd3547dbc60	a68d4614-1d8c-41f6-84ce-7593af4b25ff	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 11:47:56.474389+00	2025-12-20 11:47:56.474395+00	t	f	\N	\N	2025-11-20 11:47:56.474445+00
c8ec23a0-b8ea-4abc-b978-042282590008	c1d918d1-18d8-4837-a271-967d90f569a3	532401805bd563d6b70e740c5ba0c4198cc2c53bdc0e5e780d298a679a634174	647270cd-8b74-451b-b9fc-ff000336ec6b	1ff2f322-94a2-49b7-b260-d7a1f8669c3d	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 11:48:54.690732+00	2025-12-20 11:48:54.690743+00	t	f	\N	\N	2025-11-20 11:48:54.690799+00
ff4ec6a6-2c34-4b38-a39e-338e36eb910f	987fa969-961f-4afb-98aa-636c3448bd87	fed17d749bc53288a5f772993a19004054977154566d9d6360526feedabd2d3c	01a33c92-8fb4-4a7c-8010-e75f08fc2385	8001d9e3-9021-495d-8294-f26ab05bbcb7	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 11:43:53.836132+00	2025-12-20 11:43:53.836136+00	f	t	2025-11-20 11:57:56.652225+00	rotated	2025-11-20 11:57:56.451018+00
d7a45c1d-a17b-41c4-a019-31b2e21804f0	cd23d611-1644-4d29-b7b3-100f9458018c	b5268a57e12a7b125b737a73b00233bf54b35bd6234bb5eaba4ae4b01cdd7450	89e481c0-2307-4c0f-a8ca-2a49a6c84b2e	1095961e-f29c-429b-abde-bf90ac927d0a	14.191.79.233	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-23 15:45:43.133888+00	2025-12-23 15:45:43.13389+00	t	f	\N	\N	2025-11-23 15:45:43.133921+00
bc4546c5-8379-4a18-ab43-681d77216fba	987fa969-961f-4afb-98aa-636c3448bd87	1718f0e8c1c98ef939e03502e857bfe90268a773975bdab6baca1dd5313fc98d	01a33c92-8fb4-4a7c-8010-e75f08fc2385	aef7b5df-16f9-4923-a3b2-0aa6358f1a3f	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 11:57:56.652576+00	2025-12-20 11:57:56.652578+00	t	f	\N	\N	2025-11-20 11:57:56.652634+00
f285dfd9-3383-48c1-b3d5-741e7f53703f	c1d918d1-18d8-4837-a271-967d90f569a3	fd936011a93a50fb41b2209fef07933791272df5f08f7ae54241a74c344d5488	811ef73c-6a30-4400-87cf-0bca6a6ca4b8	142ee3ca-6d85-4b37-80f0-5a1eb1811346	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 11:51:35.899006+00	2025-12-20 11:51:35.899012+00	f	t	2025-11-20 12:05:39.033238+00	rotated	2025-11-20 12:05:38.859149+00
1e2f0d64-185d-4f53-b146-4cee933ff8a0	987fa969-961f-4afb-98aa-636c3448bd87	dc89699a54d174f4d742ce11af81e32c2785594d9f84896d2f69e981779985d5	922f5b21-e1d7-46b2-bc39-9c0a6c748a31	e9a47aca-29e3-463e-a71d-d89d7f389b4e	42.114.93.242	PostmanRuntime/7.49.1	2025-11-20 12:08:43.217718+00	2025-12-20 12:08:43.217726+00	t	f	\N	\N	2025-11-20 12:08:43.217777+00
6696592c-3071-40b3-987f-bb61029b4052	c1d918d1-18d8-4837-a271-967d90f569a3	502dfc24603345067dc684d13b90b14b40a474aa5aa972845fbe0b1ff7aa0318	811ef73c-6a30-4400-87cf-0bca6a6ca4b8	56e9a536-28b3-4d6a-9642-0267b7a7767f	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 12:19:41.309837+00	2025-12-20 12:19:41.309838+00	t	f	\N	\N	2025-11-20 12:19:41.309881+00
c9c58b53-bf3e-4899-a1ae-242405907fd7	c1d918d1-18d8-4837-a271-967d90f569a3	333ded88f8effedc8256ec3982480939337e1927bda3251d46703f540628050d	811ef73c-6a30-4400-87cf-0bca6a6ca4b8	74ad3179-d741-49e2-ac56-f808b35fc1b9	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 12:05:39.033532+00	2025-12-20 12:05:39.033533+00	f	t	2025-11-20 12:19:41.309588+00	rotated	2025-11-20 12:19:41.127933+00
6f7efe83-d206-4efa-8979-74bca80f7f9d	987fa969-961f-4afb-98aa-636c3448bd87	814d84d6689731faf95dfc1865903dc66dc97e77bd16a3a8c3e1b37b622ede39	19fe6a70-76d4-401e-8159-d9b51040d0dc	69b1e993-7160-417d-9af8-0b6a4ad47e5b	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 12:23:43.068506+00	2025-12-20 12:23:43.068512+00	t	f	\N	\N	2025-11-20 12:23:43.068556+00
d0bae61b-72d3-49fc-8460-61b532897b99	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	443add608b4b6a2e0a1d64c9cc05485f3fcae5048f7ef666f6c364a82d85a0b0	3050b1c7-8ee5-4c62-b91c-0cd208acabc9	71538494-0007-442e-9658-0f4634f36481	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 12:31:11.727251+00	2025-12-20 12:31:11.727254+00	t	f	\N	\N	2025-11-20 12:31:11.728334+00
ba7bee2e-71dc-4911-b401-b06175225794	c1d918d1-18d8-4837-a271-967d90f569a3	05861532081b620d921aa833b327422563b2aff58bb3cd4143c5b89689770f08	a07abd99-9396-4ec3-bd2a-5e3dd13cdd7b	506b0b83-392c-474c-87ef-5c1174e60db6	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 12:35:40.737448+00	2025-12-20 12:35:40.737451+00	t	f	\N	\N	2025-11-20 12:35:40.737495+00
6d6f74dd-ff3c-4790-abb1-3c7c063a75f4	987fa969-961f-4afb-98aa-636c3448bd87	2d1872ed7a0a2ec34bd42f2369507ba769ee09f99ad181dda2b103d6ae4c7ce1	73905006-d20a-4ede-bad8-218145533062	faf8d49a-5aa0-41f3-befd-2e71366cf9cc	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 12:41:34.592084+00	2025-12-20 12:41:34.59209+00	t	f	\N	\N	2025-11-20 12:41:34.59213+00
098d32d5-8f07-451d-97e5-3a8963cfa5fa	987fa969-961f-4afb-98aa-636c3448bd87	4dbe4b2e97be0eaf578d8f009b698d9b74d009df2a9da594987f88dc00c61697	c016e0f5-aa03-4277-80c4-a6d0d0009116	f7d6f936-65cb-47b9-9bf8-813748dc415b	27.64.96.160	PostmanRuntime/7.49.1	2025-11-20 12:44:57.154053+00	2025-12-20 12:44:57.154055+00	t	f	\N	\N	2025-11-20 12:44:57.154075+00
55501faf-980f-46c8-b1a4-9bf303484ba9	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	1cb5a27ca930b88c79a6c1e753264d30fc703444e6b159384c74394699497cb8	0459af1f-9360-41d5-86b5-67ca6731a15a	ab4f6c3a-f66a-4e88-a6bb-8909b3a6812d	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 12:31:20.183645+00	2025-12-20 12:31:20.183647+00	f	t	2025-11-20 12:45:31.888239+00	rotated	2025-11-20 12:45:31.737533+00
55e0b8c6-dfef-4f7d-a27f-14063e78dde7	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	839193d315e0f20275dd77190d2eeac935a53c707763c5a2ad796e2ea1326ec5	63465d7f-3c21-416a-a0de-6807e8b854af	141bb62a-3455-4880-8533-cec8239994da	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 12:47:50.933958+00	2025-12-20 12:47:50.933966+00	t	f	\N	\N	2025-11-20 12:47:50.934022+00
26260359-37e2-4501-ad68-3fb1cb224fef	987fa969-961f-4afb-98aa-636c3448bd87	af73632848219b83cab04a51cea3a4ac8e6a4b3823aef82b48989f5e98f91917	2b7853a5-4893-4c52-9568-b92abba74df7	9128e941-cb67-44f2-8dc2-936121d36272	27.64.96.160	PostmanRuntime/7.49.1	2025-11-20 12:51:15.126684+00	2025-12-20 12:51:15.126705+00	t	f	\N	\N	2025-11-20 12:51:15.126733+00
cb435ec5-e80c-4dc9-930f-8e42315fdb3a	c1d918d1-18d8-4837-a271-967d90f569a3	2047df0564560427127a67e0496adbbfe5a89d8c7be3d054fcb12ac701ede637	49a622d8-2925-47d1-9bc0-e09c28cb17d0	b29a4972-6d5d-4a6a-badc-9146ff678697	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 12:51:46.785974+00	2025-12-20 12:51:46.785977+00	t	f	\N	\N	2025-11-20 12:51:46.785998+00
fc94d53b-d0fd-487c-8253-16ac8bd8135b	c1d918d1-18d8-4837-a271-967d90f569a3	0dd2da05a60e28bdcfabb00b4465e2bc1e651f1ed9871c37789745a5f68686f1	ed98a93d-929f-4a2e-ab1c-f5c016937384	df419d7e-feb9-4193-86f9-8bf119ae0b5b	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 12:52:16.920282+00	2025-12-20 12:52:16.920284+00	t	f	\N	\N	2025-11-20 12:52:16.920315+00
817210dc-2b64-4077-960a-d0daf332643d	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	805e0e1f9bc51c0f94ba614a373c1c86deb695affcd19029ec12c9acc4db9b1d	0459af1f-9360-41d5-86b5-67ca6731a15a	72da2ae0-b5be-4b4b-b4ad-caa13b825130	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 13:00:31.917257+00	2025-12-20 13:00:31.917258+00	t	f	\N	\N	2025-11-20 13:00:31.917279+00
9b2c0b0f-d99d-416d-8f3c-0628cd529191	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	03ef350c3cc862452db13b2521d9eb554e3e356bc8cf26c92ebc9d2bd12fb3ce	0459af1f-9360-41d5-86b5-67ca6731a15a	5e7cf966-c1f7-44be-ab37-5b56b22d2e39	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 12:45:31.88957+00	2025-12-20 12:45:31.889571+00	f	t	2025-11-20 13:00:31.916929+00	rotated	2025-11-20 13:00:31.7515+00
a4b668f8-9f83-4c53-8115-3e035f687f1b	987fa969-961f-4afb-98aa-636c3448bd87	154acd75d449457bb29bf766d2461ee8b9c234e7ccb129340ffdb1551e4c971a	2af21a25-903e-4abb-8ea0-1b51ab525cec	006c2624-161f-400b-b57f-946a2e05c6df	125.235.236.147	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 13:07:10.526271+00	2025-12-20 13:07:10.526277+00	t	f	\N	\N	2025-11-20 13:07:10.528351+00
eba4ea25-9991-4f9b-9dd1-7065e13dc275	c1d918d1-18d8-4837-a271-967d90f569a3	7046d9e0db1d862a9f6ab278241baaf298e31c098bdb4efbb5e2d471374d6b36	55ee2676-c136-4515-8f02-1d343bcb69b4	b4091351-d061-4fdf-a4fd-333f774616f4	27.64.96.160	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 13:09:49.310797+00	2025-12-20 13:09:49.310804+00	t	f	\N	\N	2025-11-20 13:09:49.310846+00
c56de70d-25ca-4b48-b981-686df2975e3f	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	4c0c27a7eb5b3199284f24087abf428aae6a1541d3baeb5316c15eb07326789e	d30377c3-9327-4faa-998d-d33c4ece044d	c95f05f9-a6b6-4850-9229-785b2434e47b	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 13:12:29.588632+00	2025-12-20 13:12:29.588638+00	t	f	\N	\N	2025-11-20 13:12:29.588673+00
3a1c4418-5bb9-4090-bd4c-82ac6df69054	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	328d84baf041654e0c6684dc664927e4d3988feac17c5fea6ed9c25ef04657d1	5be168b2-d73c-4c33-b878-c233d0b23f44	2088f000-9fe1-4b69-8a4f-bae23eb26b53	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 13:12:44.241539+00	2025-12-20 13:12:44.241542+00	t	f	\N	\N	2025-11-20 13:12:44.242053+00
3b083fc4-2f6c-4488-b760-133cae6d992f	987fa969-961f-4afb-98aa-636c3448bd87	87224bedfb34cfb950fc7aeb4577e7585431dbc0cbd7d0812773ef68b6a9ee32	a0eb21c9-71de-4c8b-bf84-c7c3a5f79742	a75418f6-6d76-4f57-be4d-97aea72eea8d	125.235.236.147	PostmanRuntime/7.49.1	2025-11-20 13:18:02.003436+00	2025-12-20 13:18:02.003443+00	t	f	\N	\N	2025-11-20 13:18:02.003509+00
632b7091-9700-401f-9fd0-76db0045872d	987fa969-961f-4afb-98aa-636c3448bd87	4a54aec8af6587f2de57f87c8d084ee19658fd712f64bac163f0536e9f773ce1	10af7b24-892f-4f5c-8175-2002bd599e44	61a39b38-67ca-45d1-a131-11b59b31a7e2	125.235.236.147	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 13:49:33.483284+00	2025-12-20 13:49:33.483303+00	t	f	\N	\N	2025-11-20 13:49:33.483352+00
fb79ea5a-c386-4194-91b1-29cd11092b1e	987fa969-961f-4afb-98aa-636c3448bd87	d31fdbd5b85c26dd511e104abc2be44f5ecfecb1bb55442f1e53fe6609c54491	d7bd4e84-63cd-4d4c-9d0c-14c4737941c3	052a190a-8ee5-4423-881b-386ea3c250bd	125.235.236.147	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 14:10:12.563708+00	2025-12-20 14:10:12.563713+00	t	f	\N	\N	2025-11-20 14:10:12.563765+00
0b30152b-a9a2-42c7-95a7-69c689aeb035	987fa969-961f-4afb-98aa-636c3448bd87	e7d4ec357d6730c4c0f375570949cdce010271ac1f4110ab7ad380f3efac22ea	db4f02b2-4456-45dc-9be7-12cfa4f0cc63	bb6cd6f3-0313-4a04-9b61-2f9ecd42aaee	125.235.236.147	PostmanRuntime/7.49.1	2025-11-20 14:12:08.35057+00	2025-12-20 14:12:08.350575+00	t	f	\N	\N	2025-11-20 14:12:08.350617+00
697deeeb-eb8a-4705-97e5-f1954c4529f3	987fa969-961f-4afb-98aa-636c3448bd87	707b6e1eccf7fd1e119b7ffc5a25ae00e0e51a7bc4588d7bbf3fa63512b89327	ccfad170-f587-416d-ba39-5989ae50db75	84a6289f-095c-4778-bbaf-91d206178e67	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 14:13:21.772551+00	2025-12-20 14:13:21.772554+00	t	f	\N	\N	2025-11-20 14:13:21.772564+00
9434eab9-2bd9-4c8b-8159-fe710d1c37c4	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	ffaf6d3e96f481a7df2d54967dc486bf351ba0e4221d2c8c147928ba2b96fb7d	78386292-29e5-4a47-a8ff-e06b8a7ce009	bc69abf2-88a4-4433-b2f0-370ae60e3b12	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-23 15:46:14.477843+00	2025-12-23 15:46:14.477845+00	t	f	\N	\N	2025-11-23 15:46:14.47786+00
6e9f3100-08e7-415b-abe3-e8ba0d156570	987fa969-961f-4afb-98aa-636c3448bd87	0f8b1e71646f63997e029ea2afbf2ee6b85d64b09472246f5d92c8f92961711c	0507f6e1-328c-46f8-9b29-3a4cd1b3ad12	44544368-602c-4a58-9972-c361d9f76e50	125.235.236.147	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-20 14:32:41.824275+00	2025-12-20 14:32:41.824282+00	t	f	\N	\N	2025-11-20 14:32:41.826367+00
1b6ab43d-6958-4611-a005-eb27e675ac1e	987fa969-961f-4afb-98aa-636c3448bd87	798840b2c6182ada4e17fe829cd6295fb873c58f6649196672f163071d28de66	0a5657d7-3b60-4a14-99d3-c6149ad5da5d	4c1f09b1-3f42-4165-a4f1-c551638c8348	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 14:36:46.882941+00	2025-12-20 14:36:46.882942+00	t	f	\N	\N	2025-11-20 14:36:46.882985+00
52006e31-26ef-42b6-9d83-c0ccc12f59c7	987fa969-961f-4afb-98aa-636c3448bd87	f8f00a4e982d564b155dfa89cf1973179392413970265c66ca070c7fddc2cb7e	0a5657d7-3b60-4a14-99d3-c6149ad5da5d	15919127-c1b0-4c46-88f5-a0222fb0fcb5	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 14:22:43.507261+00	2025-12-20 14:22:43.507269+00	f	t	2025-11-20 14:36:46.882617+00	rotated	2025-11-20 14:36:46.717157+00
4a3eeec7-2e3f-406f-a247-454710584fd9	987fa969-961f-4afb-98aa-636c3448bd87	c8da221c97971911ae8e087a718a928c459e59b3ba4f263fb023d7c356dd9728	7376087b-73fd-4d18-997c-a1be6788ffb5	bcf145a4-5eca-4846-822c-df05f788b633	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 15:27:19.65723+00	2025-12-20 15:27:19.657237+00	t	f	\N	\N	2025-11-20 15:27:19.657283+00
27b221d3-7945-4194-9b8f-eba867e11ad0	c1d918d1-18d8-4837-a271-967d90f569a3	e569c679da960ddb018357c89684ee768c7b2c6d28d488cf3f74f23837196243	832d5218-edd2-482c-850f-3397cf4ca544	951b7e42-c151-4b7a-be0b-4295a063f2ab	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 16:20:54.862076+00	2025-12-20 16:20:54.862079+00	f	t	2025-11-20 16:35:22.418896+00	rotated	2025-11-20 16:35:22.222849+00
c40917aa-fbf9-45f5-af26-eb7b3a1215b8	c1d918d1-18d8-4837-a271-967d90f569a3	8c8d4f688e8e22d507a772a19e5d335b3368d682a0e992a8e02634c37e83eace	832d5218-edd2-482c-850f-3397cf4ca544	4aa9f0ff-bdba-4fa0-b7a3-48d0cb52d4eb	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 16:49:46.246355+00	2025-12-20 16:49:46.246356+00	t	f	\N	\N	2025-11-20 16:49:46.246396+00
1c98fcf3-ff8e-421c-9213-bd626fb3ea81	c1d918d1-18d8-4837-a271-967d90f569a3	00dee1e551caf20c62f0e2f293810b9ba01583f0ccff1bb5543d0dc227d31e83	832d5218-edd2-482c-850f-3397cf4ca544	8453e624-3d3d-40da-b235-f3fa3c357aea	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 16:35:22.419206+00	2025-12-20 16:35:22.419207+00	f	t	2025-11-20 16:49:46.245925+00	rotated	2025-11-20 16:49:46.080976+00
538c22e1-415a-4064-9a9c-18897cfedd6d	c1d918d1-18d8-4837-a271-967d90f569a3	f78b7bcc4288092f0fce3434236ae471e60b078b163bd9d519ffa0c1ee6ca825	8fe87b64-1fde-4abb-bec3-2c1eeed94c3b	ed0b026c-edd2-4e3d-a754-42cd551da633	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 16:58:11.213887+00	2025-12-20 16:58:11.213895+00	t	f	\N	\N	2025-11-20 16:58:11.213954+00
5091ec7f-9328-4811-a9e3-8b00616052a9	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	b12f9a465ec8a1f39fa1db419bc0d5d209a55077adea90b4718adc3783ebe45d	c434528c-7dc4-4685-9134-fc60a4f316f4	28ea0c4f-8d4d-41d8-a570-8961961d7333	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-20 16:58:55.194015+00	2025-12-20 16:58:55.194017+00	t	f	\N	\N	2025-11-20 16:58:55.194062+00
ae4c8320-14e9-46fb-80b3-4b8a94e8cc69	987fa969-961f-4afb-98aa-636c3448bd87	c2343874b3b0745f01dc296d3d54ae55b261bea0801f7fb77112748e38cabf33	ba03a82a-901f-4f3f-936e-6beb9b0b844d	2a8c6240-ddb4-4746-a8af-d534a1e6dd1e	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 17:40:47.556425+00	2025-12-20 17:40:47.556427+00	t	f	\N	\N	2025-11-20 17:40:47.556467+00
48c34fb6-f0c5-4050-b626-3d57bdef7bc3	987fa969-961f-4afb-98aa-636c3448bd87	e881b74616bbb9cc889cbb82c19407e86326860637ba19715baf0a38d8c0f456	ba03a82a-901f-4f3f-936e-6beb9b0b844d	97c7bb34-5976-4b31-bdd8-53abe7b18cce	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 17:26:33.652052+00	2025-12-20 17:26:33.652057+00	f	t	2025-11-20 17:40:47.554402+00	rotated	2025-11-20 17:40:47.378482+00
24dcc35b-321d-4c8a-8e2f-17c35a93474b	987fa969-961f-4afb-98aa-636c3448bd87	46aa8a4bb9eee48665b0693703e229e3fd61d30616c029881325d08cc21982b2	8360bc40-0b52-457a-9a00-d9958933b0c3	1a211842-2325-4c2e-afca-95639a338d80	42.114.93.242	PostmanRuntime/7.49.1	2025-11-20 17:58:05.687115+00	2025-12-20 17:58:05.687121+00	t	f	\N	\N	2025-11-20 17:58:05.68717+00
677de2ce-7ecf-48e9-bea5-cbc5314c603f	987fa969-961f-4afb-98aa-636c3448bd87	db022af28ec02ad426dca73ea49aa8b2308ef1ba6e934180cbc9658afe78202c	0df713b2-1e2d-4a7f-a302-1f0908d76349	ce1a8498-6ba5-4577-a11b-bd53199ae676	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 18:02:09.528225+00	2025-12-20 18:02:09.528227+00	t	f	\N	\N	2025-11-20 18:02:09.528277+00
bea7da29-ec57-4a20-8cd2-d7da76b04908	987fa969-961f-4afb-98aa-636c3448bd87	12f983fac67ff9bd66ea8be2cbebfe2edcae073a84710eab22caa71770c8ac31	c8d6a85c-7571-41c1-bf0f-154255a99489	58936047-1b75-4332-9caf-a5319b3b8c10	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 18:04:10.554823+00	2025-12-20 18:04:10.554825+00	t	f	\N	\N	2025-11-20 18:04:10.554859+00
2b807ba6-810e-4cca-9a5a-168d09dac718	987fa969-961f-4afb-98aa-636c3448bd87	8d521bd2fdac0b0639ab3ec6527b25834d795c129200cc5dee79a2897f213cbb	ad930c61-cef9-4268-bb5c-c5a7fcc99c5b	79abab9f-4ec3-483b-a521-b94d557e5e49	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 18:05:19.334307+00	2025-12-20 18:05:19.33431+00	t	f	\N	\N	2025-11-20 18:05:19.334342+00
d4fbab24-d795-4b6f-94d4-94db6ad421b8	987fa969-961f-4afb-98aa-636c3448bd87	95f3343a2c1ccc4e5ddd45529cb84956ed40c6e27261cad117beed54decf9691	4b15fcb7-d894-4a25-86d6-76d50b6caa2f	160e8f1a-f4e5-4a6c-bb5a-34954d137206	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 18:07:54.323097+00	2025-12-20 18:07:54.323103+00	t	f	\N	\N	2025-11-20 18:07:54.323144+00
0d2c90a7-4761-4f3c-aa7d-fd40ca58d20a	987fa969-961f-4afb-98aa-636c3448bd87	cd9e3cda6e6c51321ede5f617223c79acd5f7410d9057ccef9cf644a1c28c16e	877944af-6f60-463c-9bba-de6ef2fef704	4e1d72ef-3c30-4fcb-9011-ef584ab38b3e	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 18:24:54.197482+00	2025-12-20 18:24:54.197488+00	t	f	\N	\N	2025-11-20 18:24:54.197541+00
35c1e1b8-9add-4f07-b1dd-c6c017d45e7f	987fa969-961f-4afb-98aa-636c3448bd87	28b4192b1215ac707858c2be65e56fb48e5ada2ec75d8be4e573a898377109fb	e526a6ec-161d-4bb8-bc43-bb1ef6a66106	e5d23775-ac85-4588-9c26-4eae348091c9	42.114.93.242	PostmanRuntime/7.49.1	2025-11-20 18:35:18.235948+00	2025-12-20 18:35:18.235954+00	t	f	\N	\N	2025-11-20 18:35:18.236006+00
3c51266f-b8d5-41d8-986a-4cb0269caac8	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	8d244697423cef523a6d64a9fac186915adbdbf52f637db8fd676cc0d7d48854	78386292-29e5-4a47-a8ff-e06b8a7ce009	da856cca-2e65-494d-a197-1880f97268bc	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-23 15:31:39.896725+00	2025-12-23 15:31:39.896925+00	f	t	2025-11-23 15:46:14.477355+00	rotated	2025-11-23 15:46:14.236901+00
0d2e45d0-f383-49b0-b9af-4bbbd2708e6c	987fa969-961f-4afb-98aa-636c3448bd87	533d1a6fac238cf3bee1c2a443e99b437653a6533dd0ef014674eedcf8cea84b	d0536810-fc73-4d9a-8bf6-e72b96ca5b51	ca7a09c1-c2dd-4401-857b-d19ded9f4fab	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 18:46:21.309022+00	2025-12-20 18:46:21.309028+00	f	t	2025-11-20 19:00:41.128864+00	rotated	2025-11-20 19:00:40.938735+00
159e44e7-8306-4ced-b3e2-4d8936e3ceda	987fa969-961f-4afb-98aa-636c3448bd87	d494d94d1497e16e9c923bdc03ac6e419a5ce31caf184356f70814de39644e0f	d0536810-fc73-4d9a-8bf6-e72b96ca5b51	f66f7a42-6932-4df3-a562-ab683b89cc98	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 19:15:13.770617+00	2025-12-20 19:15:13.770618+00	t	f	\N	\N	2025-11-20 19:15:13.770659+00
170fdd2f-d060-47dd-80e0-7489552dba65	987fa969-961f-4afb-98aa-636c3448bd87	0672fee874c6042e588f353d18c525973bcd2aa9060c0a20c78b53d43de76faa	d0536810-fc73-4d9a-8bf6-e72b96ca5b51	bc7d1dd6-f663-4885-a10b-472d65eb1378	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 19:00:41.129146+00	2025-12-20 19:00:41.129147+00	f	t	2025-11-20 19:15:13.766056+00	rotated	2025-11-20 19:15:13.590593+00
d0d4bcfa-782f-4b47-a5b4-85c98b0679bc	987fa969-961f-4afb-98aa-636c3448bd87	ffb7b54ca002f9e355c7736972e7788a75ecb4d3966dcc3cdc2a400e7d32008b	68f13a9a-6c49-4e13-a9b7-1ecd1f424b58	2b13500b-e86f-4101-b4a8-1376a5409771	42.114.93.242	PostmanRuntime/7.49.1	2025-11-20 19:43:22.073342+00	2025-12-20 19:43:22.073349+00	t	f	\N	\N	2025-11-20 19:43:22.073399+00
75b7fb81-9833-49fc-8f00-466c1a77ce6e	987fa969-961f-4afb-98aa-636c3448bd87	a16fba3825f3a90b201b1d4fdc3cd6695bc757c19cd61f0ee995a98b37448f67	c09ee925-a439-43f4-bd35-a37e34437c27	0128450f-0206-4377-bd82-e3ef72e218d7	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 19:31:01.376901+00	2025-12-20 19:31:01.376904+00	f	t	2025-11-20 19:45:03.974494+00	rotated	2025-11-20 19:45:03.819019+00
74bd1471-bcbf-487b-9e2e-b38075f5e010	987fa969-961f-4afb-98aa-636c3448bd87	a9897181503657e3843601379e2b07ed3b8e14cbef62ffd5ca41b9abbb0b73b2	c09ee925-a439-43f4-bd35-a37e34437c27	fe88fc94-8180-43be-aea0-a9629e07dd4d	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 19:59:08.057316+00	2025-12-20 19:59:08.057318+00	t	f	\N	\N	2025-11-20 19:59:08.057359+00
48ec0220-d8ba-4d9d-bde4-be8412e68f60	987fa969-961f-4afb-98aa-636c3448bd87	b4aa46b01d010f3df3338f3f8bf2f610c73bcb73667a092d5f645792ff56456f	c09ee925-a439-43f4-bd35-a37e34437c27	41dba5a7-6ba8-4d75-ace1-53976d90fcee	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 19:45:03.974765+00	2025-12-20 19:45:03.974766+00	f	t	2025-11-20 19:59:08.054991+00	rotated	2025-11-20 19:59:07.849878+00
d9827437-60cf-4fbb-9a9c-3d69c1fe536c	987fa969-961f-4afb-98aa-636c3448bd87	ec20cba87910974d98c43083c729234a175dcb03dcd4c7f61eda006e88e8412e	56f678aa-0e49-49c6-b659-9a8704498e21	c64a0a80-1fba-4464-bbc7-72e10f7f9b17	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 20:14:57.530024+00	2025-12-20 20:14:57.530051+00	f	t	2025-11-20 20:29:32.445765+00	rotated	2025-11-20 20:29:32.266513+00
5c8d0688-f3c6-4ab1-addd-327ec862d3e0	987fa969-961f-4afb-98aa-636c3448bd87	12e23a235f22521d4a577b45b0b59838752c81c95ab504945bc3a1fe25f57b93	56f678aa-0e49-49c6-b659-9a8704498e21	74dc49b0-c98f-429f-943a-2955f2f42e6f	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 20:29:32.447513+00	2025-12-20 20:29:32.447515+00	f	t	2025-11-20 20:43:47.082974+00	rotated	2025-11-20 20:43:46.940399+00
57752eff-25c2-452c-abfa-95cb194ca434	987fa969-961f-4afb-98aa-636c3448bd87	b46d0ef7b87de1f3162d10bd423846fe75573c2e0ec8483d97d42df332493dc2	56f678aa-0e49-49c6-b659-9a8704498e21	4fbdf318-1228-4c60-9866-af9b83f2c858	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 20:58:19.117722+00	2025-12-20 20:58:19.117723+00	t	f	\N	\N	2025-11-20 20:58:19.117762+00
d6b32446-0328-4a2d-84a3-2d01e8bc1e7b	987fa969-961f-4afb-98aa-636c3448bd87	4e8b4e2bb06e46cbe75aafb469db9b89c9955ed409b907d76b82b491e0087e72	56f678aa-0e49-49c6-b659-9a8704498e21	19985d26-abde-4524-9d79-816046bc4b37	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 20:43:47.08337+00	2025-12-20 20:43:47.083378+00	f	t	2025-11-20 20:58:19.117469+00	rotated	2025-11-20 20:58:18.922155+00
163e9e08-d30b-4518-baef-fa79317410e6	987fa969-961f-4afb-98aa-636c3448bd87	36786d216239c757619149c82d903e849b5f4ea987f83e8a7435ac3b4f02ae03	ea5bf372-5d0f-42e4-8bcb-6a31aee0a0a9	b3fc88ba-cfaa-47be-a122-37c5e9deef79	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 21:13:32.173718+00	2025-12-20 21:13:32.173721+00	t	f	\N	\N	2025-11-20 21:13:32.173757+00
542f98d0-170d-460d-94c3-28eca5bf9c49	987fa969-961f-4afb-98aa-636c3448bd87	d1750a4ceb6e948b11ed055764ad49f44a63d7bab32e4c34c68fdd7d96ba095b	4691f024-ddbe-4b03-b7f0-f8cef4740d96	af3b65ec-5799-4747-879f-431251ef764f	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 21:30:12.09687+00	2025-12-20 21:30:12.096876+00	f	t	2025-11-20 21:44:14.893708+00	rotated	2025-11-20 21:44:14.758605+00
3d64f02a-4d06-4410-adc5-4e1c192895ce	987fa969-961f-4afb-98aa-636c3448bd87	7afced2d2e0a731d858777b10e201bacb766848bcad459468b8c4f0895a40986	4691f024-ddbe-4b03-b7f0-f8cef4740d96	4eeb4102-67d7-45a3-9796-7ad68b27113a	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 21:44:14.893985+00	2025-12-20 21:44:14.893987+00	f	t	2025-11-20 21:58:19.424802+00	rotated	2025-11-20 21:58:19.210049+00
7a054cf4-c880-4166-b362-b68730f15ec0	987fa969-961f-4afb-98aa-636c3448bd87	432327629629136352b492c756ab20b4bacdefd77488d1fd61c468af0a552aec	4691f024-ddbe-4b03-b7f0-f8cef4740d96	ac88f3af-6403-42cc-bfe8-bb99ce9d8be4	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 22:12:22.310388+00	2025-12-20 22:12:22.310394+00	t	f	\N	\N	2025-11-20 22:12:22.31045+00
689048f3-b63e-4eb0-9a2f-2c0ddf063855	987fa969-961f-4afb-98aa-636c3448bd87	c944c4daa8de0b1824547aa722ef346ba7882caa290118f5ee540ebaf9d07f65	4691f024-ddbe-4b03-b7f0-f8cef4740d96	24cd926e-bbea-4251-85aa-03a48369382c	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 21:58:19.42507+00	2025-12-20 21:58:19.425076+00	f	t	2025-11-20 22:12:22.309098+00	rotated	2025-11-20 22:12:22.148965+00
a2e1d88d-8766-428b-87e0-ea333aad37ac	987fa969-961f-4afb-98aa-636c3448bd87	8459071f71e73fbee8c00bc3c2c5707cbd74786ec6abbd3dfdd8789b91386c08	64375fa3-782a-465d-8eac-859dcd7bb55a	49644f3b-19d1-4bc2-b4a5-265ca7d1c0c5	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 22:29:19.589673+00	2025-12-20 22:29:19.589683+00	f	t	2025-11-20 22:43:36.050609+00	rotated	2025-11-20 22:43:35.872282+00
72ddcecc-0891-46c2-9d93-1387201e4179	987fa969-961f-4afb-98aa-636c3448bd87	7e3fc15923c35c5e4d2c8871dbf1b0ea1303f79d463648bda894a9d5cbfca027	64375fa3-782a-465d-8eac-859dcd7bb55a	7c140584-1559-4fe7-8475-068061cd92fa	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 22:58:16.790376+00	2025-12-20 22:58:16.790377+00	t	f	\N	\N	2025-11-20 22:58:16.790425+00
f618eca8-7b67-4878-a6f3-91f9d7bee5b5	987fa969-961f-4afb-98aa-636c3448bd87	75afd3fb764314d91fea77b065a800cbc96915149d6b0e01c17d539f2e6f5f3d	64375fa3-782a-465d-8eac-859dcd7bb55a	2a89d02c-b07d-4750-b95d-5a9ef5e67874	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 22:43:36.050867+00	2025-12-20 22:43:36.050872+00	f	t	2025-11-20 22:58:16.78784+00	rotated	2025-11-20 22:58:16.642926+00
3e33b4e3-3204-49cc-874c-d9816b165341	987fa969-961f-4afb-98aa-636c3448bd87	d14a9e27d2f11e040431bc29cde2559385c7a18f3984d2af0f8eb7c559602a2a	49242e2b-6c13-4952-a08a-6ede12c35ec5	c544ed23-bf40-4986-8b54-460496e2df07	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 23:00:22.197014+00	2025-12-20 23:00:22.197016+00	t	f	\N	\N	2025-11-20 23:00:22.197038+00
e784dd41-7eaf-4464-8f8d-c270fe1a47ba	987fa969-961f-4afb-98aa-636c3448bd87	1bb495145f4f6b546e9e40c177479c6ae5562b1d220ce49398521c091dcb5410	40bd2551-6fae-4432-bb6a-2a5a7f4750b8	dcb0130c-ab40-45d1-99ee-9cee7664f366	42.114.93.242	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-20 23:31:43.36085+00	2025-12-20 23:31:43.360858+00	t	f	\N	\N	2025-11-20 23:31:43.360901+00
fcb98a1a-359d-4315-9f2e-ad3a274119a5	8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	6ae677f2ad247c35f024f152453e6359f5dfd66386780aec557a8b1ce8f3fd1b	8371b4cd-f949-4e13-918f-4843f173fde6	bd37081c-5f10-42cc-bc7d-a7ee58f72701	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-23 15:46:18.106621+00	2025-12-23 15:46:18.106624+00	t	f	\N	\N	2025-11-23 15:46:18.106637+00
9ee608a0-652b-45da-aa63-4d07cfb6a4c9	987fa969-961f-4afb-98aa-636c3448bd87	97e57642bb8e6a626a2ef8b2d1f08ebb530adca832b365de34c611684284e5f3	5de0db4d-52f8-47e4-9897-03c51e849cb9	5290f28f-82a9-4988-a7eb-6a6136fefc69	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-21 00:56:55.928835+00	2025-12-21 00:56:55.928838+00	t	f	\N	\N	2025-11-21 00:56:55.928865+00
888c6f02-716d-4409-b206-6479b97920f4	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	1b1aeda5bb6e3b598b28e267f39f78bc90ad6efeaaac9e7a6274c1809ad9bfe2	d5795af7-0503-478c-972d-034893a9f17b	3737f35c-ecd0-4262-b745-09339eff64bd	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 04:26:58.945787+00	2025-12-24 04:26:58.945794+00	t	f	\N	\N	2025-11-24 04:26:58.945817+00
12b57d05-5b32-4c46-bff1-36db64ab6b01	987fa969-961f-4afb-98aa-636c3448bd87	a9bad2c13e71203fb6726d4f129e5e35de5607b07d9f43fc2a21720d9ed80465	48d6b9e0-29c2-462c-b743-3dee2788dbfe	35f16494-a025-4f68-8e5e-25943d31dfee	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 04:17:07.612918+00	2025-12-25 04:17:07.612921+00	t	f	\N	\N	2025-11-25 04:17:07.613003+00
15200935-6da0-4feb-b7fa-24fc93136fd2	987fa969-961f-4afb-98aa-636c3448bd87	acd8a2ef32b0b6ad9302846cdf02d968e2d80ef30e4725019d4276273c6300e8	c04398dd-1748-48c7-b94a-c415132d40a9	6b872f63-d8f8-4252-b10b-1d9d81bbea2b	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-21 01:12:05.8071+00	2025-12-21 01:12:05.807102+00	t	f	\N	\N	2025-11-21 01:12:05.807114+00
55e29aba-cf56-4e67-98ff-89fda9b54756	987fa969-961f-4afb-98aa-636c3448bd87	10a03fd799fe70fe15f5f92e2b61d2432780c93fd06cf124be0c4a91880756e1	75a7f47a-2a6c-4fc6-a56e-5a92a9eb0f3e	6c746e65-636b-4380-b79c-e1c251ab7552	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-21 01:27:11.730834+00	2025-12-21 01:27:11.730836+00	t	f	\N	\N	2025-11-21 01:27:11.730868+00
6564d218-46ca-4d0f-b5f6-c1bc68b9ed2e	987fa969-961f-4afb-98aa-636c3448bd87	2c2e750ea78947d68bf4f47a2f6998e49d5d3ddbf37da603c2b45e6c84eac3ce	f7c05932-6590-491d-b96b-311010bc087f	302c91d7-b94f-40ea-9605-e5fa1640f055	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 05:44:25.427869+00	2025-12-25 05:44:25.42787+00	f	t	2025-11-25 05:58:28.976607+00	rotated	2025-11-25 05:58:28.815255+00
7db91cbc-0c93-45f4-a88c-b4bbeddbf886	cd23d611-1644-4d29-b7b3-100f9458018c	9ce4d98d8859d2bcbe8da845c29dca9205bb1474b3d31a85ff449c77416e1b6f	4c187cf3-cf53-4229-8f66-2696e29bd68c	8c47613c-bc8d-4919-98f8-3927e3cf846b	58.186.28.4	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-25 12:26:08.371965+00	2025-12-25 12:26:08.371967+00	t	f	\N	\N	2025-11-25 12:26:08.372028+00
484f9546-ba6e-485d-bea4-d24b1c5c8789	987fa969-961f-4afb-98aa-636c3448bd87	bc54dc79ec6072b32f35d27b6bd1ac18a801e53f2a8c912545f661a64d4822eb	b2e6e5b8-a6c9-4b00-98a5-d822fe87f5a5	2dbbb796-f944-48bb-a8c9-5d3578a67951	118.69.128.8	PostmanRuntime/7.49.1	2025-11-21 01:45:25.987675+00	2025-12-21 01:45:25.987685+00	t	f	\N	\N	2025-11-21 01:45:25.987733+00
4aab5c62-f352-4009-8adf-3c88aa35f4bb	c1d918d1-18d8-4837-a271-967d90f569a3	e181c1abca21aefdd2b53716afff38fda34d226c1e8792d41138527fc7aa6a6c	062a96d1-f3a0-4239-b8ab-3c9070b74dc2	4dacf070-1f80-425b-b568-1e7b78301fbd	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 01:45:56.514723+00	2025-12-21 01:45:56.514731+00	t	f	\N	\N	2025-11-21 01:45:56.514746+00
247f91c8-b9bd-4404-8b04-54a7d83b2f91	c1d918d1-18d8-4837-a271-967d90f569a3	12f7f6b683ccc13ddff734f642d5a718363e7994a76811b415d99dd24ab5b6c7	352e93eb-f470-4bea-90c8-3e70fa25c203	0cff2055-a1a3-430a-9348-82722644676d	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 01:46:49.54868+00	2025-12-21 01:46:49.548683+00	t	f	\N	\N	2025-11-21 01:46:49.548707+00
0f78011b-a3d7-4704-80b4-33a2411bd2b3	987fa969-961f-4afb-98aa-636c3448bd87	dd31a4b70a534b2e875a5f8f95ebd5588f3f3c123b086845e46f74ef0410cf51	04752576-9789-4c52-b313-3194eceef2ab	3d7702a4-8267-408b-864b-f37e10ef2839	171.233.121.196	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 13:22:00.903428+00	2025-12-25 13:22:00.90343+00	t	f	\N	\N	2025-11-25 13:22:00.903474+00
da3da09a-17b8-4e12-a260-769aa6f388b5	c1d918d1-18d8-4837-a271-967d90f569a3	49cacff9fea53f9502ea5e5163c6234b73c9b32749fd65038def375f373dabc2	a6be15e3-41d5-4dc6-99a8-5ed683ab9129	7904508d-f2e4-40b0-9b9c-d3519bbc8a8d	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 01:47:40.093062+00	2025-12-21 01:47:40.093064+00	t	f	\N	\N	2025-11-21 01:47:40.093074+00
6d6ce873-79ef-4d14-a1fa-e1c61bb1a246	c1d918d1-18d8-4837-a271-967d90f569a3	a600c85939d2acdd0dc251da2b34d42fe58fa6aa984751803ad4d03578227251	41dea9c4-1fd3-4c8d-a53a-5c23e32ce52c	092d96be-72cb-42db-ba86-fe96d78e5105	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 01:48:10.239854+00	2025-12-21 01:48:10.23986+00	t	f	\N	\N	2025-11-21 01:48:10.239875+00
350194eb-da1b-4fb9-ab44-05901a7876db	987fa969-961f-4afb-98aa-636c3448bd87	059659e6ce09587ec06122437f017964b1abece20509064e8793affcaedde07e	c035f1c7-f087-431a-bbb8-bd6eecaa34d8	e385db9d-f173-4a6b-80a5-1ae868d39391	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-21 01:34:10.090812+00	2025-12-21 01:34:10.090815+00	f	t	2025-11-21 01:48:35.792831+00	rotated	2025-11-21 01:48:35.663613+00
524c7faf-a0fe-4fad-b948-6334cd31c472	2a04b41b-422f-455e-85c3-4c036e692b3c	ebf0f4d9138e8a39938e363d950f10855d220a9c9366f7e33c4ac0048478db4d	b080c582-b374-490e-af00-9f8162dc5566	74fd3892-dd99-4dc7-9438-3d1d83dc40af	210.245.98.228	PostmanRuntime/7.39.1	2025-11-21 01:52:38.998743+00	2025-12-21 01:52:38.998756+00	t	f	\N	\N	2025-11-21 01:52:38.998803+00
2c219d73-33f7-44c4-89ce-57ac486908bd	c1d918d1-18d8-4837-a271-967d90f569a3	7e23708e44ef1acd7ac00bfd3b64c485eba757c95b005a5c1c1d3a68c7df9d98	86176a07-a881-4e6e-ae25-f58c1fed679e	4f142f22-9a2e-49f5-9571-27820e0a100a	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 01:53:55.897021+00	2025-12-21 01:53:55.897024+00	t	f	\N	\N	2025-11-21 01:53:55.897039+00
b44b7dfb-e437-4848-a6a3-3d70691ef5c8	987fa969-961f-4afb-98aa-636c3448bd87	36c3042b8a2e5aeb5f57d2337606437f67673fa741a5ca2ac45079be41c6bf98	c035f1c7-f087-431a-bbb8-bd6eecaa34d8	bb1d87b3-4f25-4b34-b492-702458305235	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-21 02:03:02.543097+00	2025-12-21 02:03:02.543099+00	t	f	\N	\N	2025-11-21 02:03:02.543148+00
9155d927-8565-4a29-8cf2-a485e33a2755	987fa969-961f-4afb-98aa-636c3448bd87	802ec093053e7ccb3456c789ba825d0f457b00a7433654293bc13133e07b3607	c035f1c7-f087-431a-bbb8-bd6eecaa34d8	cf9ca247-3f76-4da4-9f10-3ee63454ed35	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-21 01:48:35.793059+00	2025-12-21 01:48:35.79306+00	f	t	2025-11-21 02:03:02.542745+00	rotated	2025-11-21 02:03:02.35622+00
dab65631-e461-4b06-9c53-ded568b1ab37	c1d918d1-18d8-4837-a271-967d90f569a3	0ff7167156d7708f1c46728c7923019c3409f5f028ca6f0731f970c55df38968	9d6bb7a1-1675-4317-b4b2-d1a3f3a1a02c	21fd590d-73f9-4ff2-bc2a-90ced05aaea1	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 02:14:02.686688+00	2025-12-21 02:14:02.686705+00	t	f	\N	\N	2025-11-21 02:14:02.686731+00
09c17fb9-daf9-4c54-be5b-075b294fccf2	2a04b41b-422f-455e-85c3-4c036e692b3c	18038af68be17c1d91fb44280a2b4f58657e06c92a03ed6f10d4bc745684e3ca	dfb4d9ea-2dfa-4734-8cee-fef2eac45254	07c90ae3-8ba5-43c8-8f1b-60d5ca443fcf	118.69.128.8	PostmanRuntime/7.39.1	2025-11-21 02:14:40.111366+00	2025-12-21 02:14:40.111369+00	t	f	\N	\N	2025-11-21 02:14:40.111392+00
db9e860a-ccae-4567-93e8-7999437dac6d	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	b54f15b17edd00b414522a908ef9a44fe8a9c7cdeeed89a43c19fbe63ac7b1f7	e527f6d9-c373-4e09-9655-69a9782664b9	210ab2f3-b53d-48a9-bf6d-15820971ec02	171.255.185.136	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-21 02:16:20.341456+00	2025-12-21 02:16:20.341458+00	t	f	\N	\N	2025-11-21 02:16:20.341478+00
5e85cd86-79aa-4596-b582-afc6edb13604	2a04b41b-422f-455e-85c3-4c036e692b3c	22b0e0823971f1dc067f1fde238c8ef514426402b69a480f12545c0dc5a81c03	ec0aeae1-1ef9-4af2-b5c3-51fbe670e9c2	d30d6bc8-8066-42c3-95b4-e1dd2b2f32cb	210.245.98.228	PostmanRuntime/7.39.1	2025-11-21 02:17:11.309142+00	2025-12-21 02:17:11.309144+00	t	f	\N	\N	2025-11-21 02:17:11.311333+00
ff9785d5-63e0-4038-996f-94613c5cdc43	2a04b41b-422f-455e-85c3-4c036e692b3c	246d032bfc216c427cf69e573c7570e9d946d187d249fc7eb80b60958d9e88d0	0be05d1a-57a7-47cb-8782-9f2ea9fe645e	c0522bca-06bc-4eb6-bf46-0627980c869a	118.69.128.8	PostmanRuntime/7.39.1	2025-11-21 02:17:43.525179+00	2025-12-21 02:17:43.525182+00	t	f	\N	\N	2025-11-21 02:17:43.525208+00
fa43201f-0f77-42dc-bf58-ea18ad42d1ad	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	f387d58b6b149e28e084456a7eb15ad653e31c91de8bf38f9c87183c0960980d	be80a600-53ca-47fc-b9d7-66d45463f357	0a6974c7-5c73-4e41-a403-26768ad76f53	14.191.79.233	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-23 15:54:22.005538+00	2025-12-23 15:54:22.005541+00	t	f	\N	\N	2025-11-23 15:54:22.005579+00
5367a720-c61b-439d-a2d0-9907406bf856	2a04b41b-422f-455e-85c3-4c036e692b3c	98cf3493a23b35302f66851a771a12166d1e9b9b2afc47ab6421f6957930df6c	297a7858-6793-4c71-9eb3-241a4afc5d03	1b371c57-7d5f-49a9-8d27-0d008012aadf	113.161.234.220	PostmanRuntime/7.39.1	2025-11-21 02:21:38.367316+00	2025-12-21 02:21:38.367328+00	t	f	\N	\N	2025-11-21 02:21:38.367359+00
dd558027-1dc7-492f-82e3-9ec531d7c234	987fa969-961f-4afb-98aa-636c3448bd87	89df86bc3c71ef8b815ac55bb079e3e8a73d8f301c3d1f07f1f23b101e5326f6	9b4d2f97-2ae4-4562-87a0-f41dc86db685	d7f3ea82-d064-411e-81a2-f5653e49d024	118.69.128.8	PostmanRuntime/7.49.1	2025-11-21 02:22:27.499096+00	2025-12-21 02:22:27.499099+00	t	f	\N	\N	2025-11-21 02:22:27.499126+00
819829dc-bf48-4003-858a-49e00283a65c	2a04b41b-422f-455e-85c3-4c036e692b3c	9560387b595e3c4610c29bd874d5a89ad5041b1cc8df0b41c8900d176415e112	b338588a-396a-4cc1-8b0f-7a34886a9895	3c2ae49a-e6cb-47a2-81d2-8b1197cb17a7	118.69.128.8	PostmanRuntime/7.39.1	2025-11-21 02:26:12.857976+00	2025-12-21 02:26:12.857979+00	t	f	\N	\N	2025-11-21 02:26:12.858003+00
bb31fb15-3e70-4ee8-b9c2-df270174ce1c	2a04b41b-422f-455e-85c3-4c036e692b3c	38d9c976dcf5f05e907ec1cec89eeddb48af3c68b4888b7df811accec5bc87f8	f6a68bfd-c40a-4c27-8a71-140b53622ecd	ec483e5e-5fdf-4803-8d34-467cfa9ce2ea	118.69.128.8	PostmanRuntime/7.39.1	2025-11-21 02:27:45.670786+00	2025-12-21 02:27:45.670788+00	t	f	\N	\N	2025-11-21 02:27:45.670798+00
05db62a6-407d-44a8-8cc8-698c680e08e1	987fa969-961f-4afb-98aa-636c3448bd87	5a7bbf04af3786b099e5f23e985ba4a6dcbef62e21c437da0cfa105b7c7b3421	8e5b0727-698a-4f1e-842a-90ac088871fd	f0de960f-9a23-4847-9897-e7143995f952	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 02:30:06.205222+00	2025-12-21 02:30:06.205225+00	t	f	\N	\N	2025-11-21 02:30:06.205262+00
12cc45c3-8c71-47a1-b84a-16662d388ed6	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	4ff2e804353c2d9694ed275e9778d565c8817bf584a242846c9abc35da0d3ccc	61576779-34ae-4c5c-9e48-a55691a5859e	c6332444-86f0-453b-831e-1b02bf579c8f	171.255.185.136	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-21 02:30:08.480891+00	2025-12-21 02:30:08.480893+00	t	f	\N	\N	2025-11-21 02:30:08.480902+00
1e8f81a9-a507-4e85-b2b6-e746c13f4e3d	2a04b41b-422f-455e-85c3-4c036e692b3c	82a0265fbf1db97b3c0519f1223e4079e239d48ad77fe40f2469eaf67686cc27	0237d41c-570f-47c9-8d32-0f6c09ff5ff5	850e3c67-9edb-46ff-84ec-0d11f6536360	113.161.234.220	PostmanRuntime/7.39.1	2025-11-21 02:30:29.173393+00	2025-12-21 02:30:29.173395+00	t	f	\N	\N	2025-11-21 02:30:29.173405+00
34f5fedb-d282-4330-a67f-85e8837882e3	bb8259df-3cb8-487a-ab91-2ef95a68aa44	f1968b31ff8a651c2150d8c667d63ff957b6e84d1e9c1bb9ae39a7370ba5d188	6f97a7e8-20b5-4c78-8000-fa9f1f77a196	140c2f1a-f74d-446f-a2c4-46a30baf5d01	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 04:30:57.947044+00	2025-12-24 04:30:57.947068+00	t	f	\N	\N	2025-11-24 04:30:57.94716+00
4e231155-40ba-434a-932e-0f859a94acbf	987fa969-961f-4afb-98aa-636c3448bd87	289d9e3b4e6f49d0d2bc8bdcc7d33e469b217a7109eb92cc960e6cc3ddca5515	668d6940-b9a2-4faf-97d3-1145c2c0f9bc	b8f0bfd8-243a-4f8f-b0fc-78e587c65ef0	171.247.205.163	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 04:29:33.878922+00	2025-12-25 04:29:33.878932+00	t	f	\N	\N	2025-11-25 04:29:33.87899+00
7b4827e0-e699-4059-a69b-6227c12d1c89	2a04b41b-422f-455e-85c3-4c036e692b3c	06b2402027c739797aac85408eaaaeb04bd0d008d54cd793ceeaa294a7dabdc1	ddd285e0-8a1f-41ec-b957-13e6f0db19fe	69436b08-1b6c-4e97-afb3-e8233d920e54	113.161.234.220	PostmanRuntime/7.39.1	2025-11-21 02:57:08.120895+00	2025-12-21 02:57:08.120903+00	t	f	\N	\N	2025-11-21 02:57:08.121076+00
7d5d3e54-d976-4291-b383-ccaefa50af80	987fa969-961f-4afb-98aa-636c3448bd87	24cf663ea0559b49d087f69412dc1d1edb09e54daaa5a21987fab572de11a3dc	f7c05932-6590-491d-b96b-311010bc087f	ce6840fb-b122-43b6-a358-fb474b8ecc92	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 05:58:28.976945+00	2025-12-25 05:58:28.976946+00	f	t	2025-11-25 06:12:43.279942+00	rotated	2025-11-25 06:12:43.104311+00
f4e1e3be-861d-43a2-8b8a-54861252ead4	2a04b41b-422f-455e-85c3-4c036e692b3c	978fd451f7caf8b7e376e1966998bfb9793ab90c8ca9deb2d5cdb9595a0bda9b	510c65f5-9d7e-4236-8aa4-6a162376fb2e	81230b50-2bd2-4da2-b237-a7b055a24da2	113.161.234.220	PostmanRuntime/7.39.1	2025-11-21 03:15:43.666829+00	2025-12-21 03:15:43.666833+00	t	f	\N	\N	2025-11-21 03:15:43.666922+00
a74b8d3a-c603-42a5-8931-59a6452cd8b0	987fa969-961f-4afb-98aa-636c3448bd87	a9caf347c0a43e84ecf8c9518689c2de3b8f922bed681d8e1f8d9604fdd92fc8	d1535a6d-8149-45c6-8f65-c463995a9c96	75c3bfa7-01c8-461d-8be3-66a77545b42e	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 12:18:06.358756+00	2025-12-25 12:18:06.358758+00	f	t	2025-11-25 12:32:22.278464+00	rotated	2025-11-25 12:32:22.076307+00
be98b6e3-62f9-4366-a76e-cf6290b41e77	987fa969-961f-4afb-98aa-636c3448bd87	19d62f76179868c80b4b2a853ba40ab14e7e1a1b26a76313ecb77b7cee87cf0c	c5b3615e-88f9-4053-b169-0611de1e39cc	3c816576-f240-4c0b-a51f-3221eb95f8a3	113.180.136.66	PostmanRuntime/7.49.1	2025-11-25 12:35:05.164799+00	2025-12-25 12:35:05.164801+00	t	f	\N	\N	2025-11-25 12:35:05.164862+00
84f2c1ee-2616-4ab5-b922-5399920ba04d	987fa969-961f-4afb-98aa-636c3448bd87	b0be0b3dc87fbfc6cc5f0e6403a0ae9f88e959324ac2289e291c632de41c1351	20692016-e6dd-4043-9c3e-d64a653718ac	91fbc9d3-0ab9-43c8-975b-8d04ea51b3aa	210.245.98.228	PostmanRuntime/7.49.1	2025-11-21 03:38:32.018022+00	2025-12-21 03:38:32.018025+00	t	f	\N	\N	2025-11-21 03:38:32.018031+00
7ce94f80-8442-4804-aa24-fb9470d052f1	c1d918d1-18d8-4837-a271-967d90f569a3	38ca0f87cf9030ea5a8c89bbc87b0a3c193e79fdf87e364d46a89bb36296f3b4	aa61c568-4a70-464b-a954-690001c7ac97	b39aea16-16ca-43e6-b460-2cbaeb0ce396	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 03:38:52.812618+00	2025-12-21 03:38:52.812644+00	t	f	\N	\N	2025-11-21 03:38:52.812678+00
d4b8b962-9f4a-4af7-a8cd-3eaf6a41d77f	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	562be5f28e9b97cded7e436dc89bd9fcd34ba1db76f0bb5ccb2cb7a2a283d20f	6e6eddc4-0f07-4725-860d-43b18610d631	bf9bc753-b075-4922-9923-82e2e3bb8ef2	171.255.185.136	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-21 04:09:13.375986+00	2025-12-21 04:09:13.375995+00	t	f	\N	\N	2025-11-21 04:09:13.376019+00
77151d72-ba34-4373-ad93-f65df905bf7b	c1d918d1-18d8-4837-a271-967d90f569a3	686e8c086e1b98cdfc5293dde9352fd4978ba996d88bc3f593b89aa11e147a5c	5d6c7cbf-2b35-4801-9ba6-aed44936d9ef	ca42bd9b-5d63-43c8-b634-c53b2735a4e0	171.255.185.136	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-21 04:30:49.03321+00	2025-12-21 04:30:49.033212+00	t	f	\N	\N	2025-11-21 04:30:49.03323+00
134cd5c7-3e5c-4f53-8561-166956c020ec	c1d918d1-18d8-4837-a271-967d90f569a3	8ff19d5145a4326039e9b828927337efc1498a16b4692d61ab289b964bfd1c79	5d6c7cbf-2b35-4801-9ba6-aed44936d9ef	eb327b3f-8b63-427b-b6ff-f17c9cf930c5	171.255.185.136	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-21 04:16:40.450416+00	2025-12-21 04:16:40.450419+00	f	t	2025-11-21 04:30:49.032958+00	rotated	2025-11-21 04:30:48.886011+00
c29dfa5a-979e-4e84-9ab1-456645f7b6b1	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	8fb62fc2294617e6310779cb29b0ea98ad3b083930a7bbf2a16ff93367a5417d	54183024-6d7a-4ed7-8dad-55dde44e5ce5	6209eab9-532c-48b2-9a7a-04cccdeb4d94	171.255.185.136	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-21 04:34:09.934937+00	2025-12-21 04:34:09.934939+00	t	f	\N	\N	2025-11-21 04:34:09.93495+00
191418e2-351b-4d8d-9869-111eccacfdab	c1d918d1-18d8-4837-a271-967d90f569a3	c44879cd13bdb84e65585c918e8016564411f6fe52c3ca9b697ce795729e4d5e	d6859091-bbb2-4782-a0b0-fd94034661e5	1c5b36a5-b0b1-445e-b1db-3fb33f1b8263	171.255.185.136	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-21 04:34:35.94208+00	2025-12-21 04:34:35.942082+00	t	f	\N	\N	2025-11-21 04:34:35.942087+00
9a0ffa79-794f-452f-8bb6-13e10b618973	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	fdc20a0f45f3af2f44c6e882e1a48a604198ebf5ee744c932267780f4e01b7c0	f63c268b-7f6b-4f39-a8e6-f2644e284261	357f69b4-f240-4fc1-a75e-546797526b89	171.255.185.136	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-21 04:35:58.944465+00	2025-12-21 04:35:58.944495+00	t	f	\N	\N	2025-11-21 04:35:58.944545+00
2e14ac7b-d529-4545-abdf-27e6499d9592	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	6e175a154c2265e1b763ccc1a1487798a251900359e7a68b7eaeb000b6d757d0	39e9f2d1-0186-4db3-b539-f81db4a24a40	50857d06-0fd6-4f2c-abc5-ef4a0be8ac8b	27.65.21.42	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36	2025-11-21 05:12:07.52692+00	2025-12-21 05:12:07.526922+00	t	f	\N	\N	2025-11-21 05:12:07.526936+00
aa43a3a1-679d-474b-90bf-6cd27c09251b	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	861f8cb9e2a35edf58bd140b18d32c36c4b74b1c068718216500cc358952aee0	43a81433-9ca9-4bf9-8dae-faaf19be6535	fdc838a7-7181-44c5-867b-bbafbf285fac	171.253.250.170	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-21 08:11:10.661474+00	2025-12-21 08:11:10.661477+00	t	f	\N	\N	2025-11-21 08:11:10.66151+00
3b817546-06ab-4965-b2b0-8a51563c83d3	987fa969-961f-4afb-98aa-636c3448bd87	dade561741397ac064860d96107660e487c67b61dfbe6e8a9b2d46966349c4e1	dcb066f9-f137-4f99-8f4e-6707b637bd1f	94f235e4-412c-405d-8516-ae9cd0dec738	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 08:28:53.542414+00	2025-12-21 08:28:53.542423+00	t	f	\N	\N	2025-11-21 08:28:53.54244+00
6df184f3-1b0a-4356-b0a5-c1b69c072840	987fa969-961f-4afb-98aa-636c3448bd87	d2886e62e8df37277a5538191aa2f97a7f0d5d89d923c8502fd60406f75d32fa	dcb066f9-f137-4f99-8f4e-6707b637bd1f	e0caee72-cd6f-4536-878b-6c154a30c1e7	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 08:13:53.410807+00	2025-12-21 08:13:53.410809+00	f	t	2025-11-21 08:28:53.541094+00	rotated	2025-11-21 08:28:53.383494+00
3eea81c8-d210-4322-b6d2-0aad91dcc3af	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	ed5f9a5623287a3b0bcce008dd1594202c7d83066c63114139bc2199a5444036	99738e03-8bd3-4331-85d1-462577839926	99c03b16-5328-47a9-96be-6644a81fe886	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 03:15:48.073134+00	2025-12-24 03:15:48.073144+00	f	t	2025-11-24 03:29:51.532978+00	rotated	2025-11-24 03:29:51.329199+00
74b57070-cf0c-4baa-aa11-6ae4cf83854c	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	1071f2ced3bbf16251d837ef74184d3f6b47236aed3675b0f0291cdab230c4e3	97fb62bb-69fb-4427-b082-ef599513b2be	c8c0d1e0-6897-4be3-970d-cdc10a091023	171.253.250.170	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-21 08:57:43.502835+00	2025-12-21 08:57:43.502839+00	t	f	\N	\N	2025-11-21 08:57:43.502865+00
a1089230-6e93-4a16-85b1-80353a40f208	987fa969-961f-4afb-98aa-636c3448bd87	6e52cede8b88170d32444a850a5e7ba433960f955131463ea084c347a4c36097	013cd82d-202d-4f1c-86bd-28a94ab2957f	8f4e7459-610c-46ee-af87-a3e0efdee955	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 08:57:49.306898+00	2025-12-21 08:57:49.306899+00	t	f	\N	\N	2025-11-21 08:57:49.306904+00
00f65151-4e85-4d39-8f08-57ad35ff6bb5	987fa969-961f-4afb-98aa-636c3448bd87	ecc4b59546fe1dc5a387c7e060b994e00fe1acf4f5ab7a18472c996237f23bf3	013cd82d-202d-4f1c-86bd-28a94ab2957f	1ebd065d-b0c3-467a-9799-f1ea7f55df51	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 08:42:49.597542+00	2025-12-21 08:42:49.597545+00	f	t	2025-11-21 08:57:49.306689+00	rotated	2025-11-21 08:57:49.15223+00
0f7326a5-d329-44ec-b796-02367878f168	c1d918d1-18d8-4837-a271-967d90f569a3	e21f31af86eaa66e17e07d00598ad7cc9d219e8cbb00359ee923681273ef461a	a2f515ef-cb6f-4482-b9b2-93ba61a27ec9	868508f7-3ea4-40f8-ab13-ca1584c7292b	171.236.70.5	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-24 04:38:04.100718+00	2025-12-24 04:38:04.100721+00	t	f	\N	\N	2025-11-24 04:38:04.100757+00
f2657aca-7216-4ba8-acac-e404abe7076e	987fa969-961f-4afb-98aa-636c3448bd87	46411b054c70ccb56343bf2f3d97b08da2e1e1b2d7c96a6c1180c99a33618cca	07012d36-06ea-4119-86bb-693d78b5ffed	a5c6cf47-b8e9-429e-afdd-aa2ffd8d9bdc	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 09:18:56.056055+00	2025-12-21 09:18:56.056063+00	t	f	\N	\N	2025-11-21 09:18:56.056109+00
33df35f6-bd11-45c9-9714-54fc6503c9e9	987fa969-961f-4afb-98aa-636c3448bd87	96e23d176c06e71492a1fd53a1feadbe217ad4185876ca5de51fc0d2424b9b93	07012d36-06ea-4119-86bb-693d78b5ffed	c486c8a7-47f6-4363-9655-a84f81ee5f1b	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-21 09:04:25.897741+00	2025-12-21 09:04:25.897746+00	f	t	2025-11-21 09:18:56.055736+00	rotated	2025-11-21 09:18:55.887695+00
3cc2a3fe-2312-4c06-8779-1dae9cb95fff	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	58ba67bd8bbe63d271077f0b889e03dcb943c24005d0bff303c9378d9e5a40f9	4b0430e2-4b1c-44fe-8ef7-7b5ff4a7785e	cc969029-9f95-481e-9916-edd82c76dd65	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-21 11:45:41.099861+00	2025-12-21 11:45:41.099863+00	t	f	\N	\N	2025-11-21 11:45:41.099875+00
3ecaf6ce-066c-47e5-aba4-d39d12e0ebca	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	98e8eaab5e4239a4c8db469233a47e7e520ea43ccbe0e63fd3ee324f75e101c3	39fcec1d-b1d5-415e-9928-7b622e9522e9	40f2292b-192f-4a2c-8448-a1b257b3305e	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-21 15:24:56.298363+00	2025-12-21 15:24:56.298368+00	t	f	\N	\N	2025-11-21 15:24:56.298405+00
33b73a87-e15c-4ad0-ad95-d914a7cfcd22	2a04b41b-422f-455e-85c3-4c036e692b3c	58b7f409a0cb70d1b0a976dfb72d8b0fd4fe7ce424ed68d863ee59963e60ffab	60d98137-f872-47a5-8e19-5688db368886	0176d12a-d5df-454b-8df5-12b0b659be8a	171.233.114.75	PostmanRuntime/7.39.1	2025-11-25 13:29:13.716435+00	2025-12-25 13:29:13.716437+00	t	f	\N	\N	2025-11-25 13:29:13.716489+00
7f530dc2-9cbb-4abc-a7ab-51181f7f9955	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	62d2a0cc25544c402d01a58bcae66a80504bde59ff25c69099d6b280806ba57a	67c936e0-3d69-4fe0-b1b7-26d07aa38df6	497fcca1-2762-48a0-afaf-efdc3f7b0b61	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-21 15:30:37.226828+00	2025-12-21 15:30:37.226831+00	t	f	\N	\N	2025-11-21 15:30:37.226852+00
297551e3-b597-4f58-ab46-dcc1ecf8d3e0	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	09b7763aa7f063623260ac16bcb1d404c373da7318b47ae0cabd141b1196b3d3	6be344b8-862c-458e-9bb7-139fa09fae30	221fd3e7-d6cd-4445-8a58-225ba3a6de31	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-21 15:33:30.866116+00	2025-12-21 15:33:30.866119+00	t	f	\N	\N	2025-11-21 15:33:30.866136+00
45dce991-b1e9-4306-8c55-81218db3bf04	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	19e7dfa29c957427eff1a3e32b62224537cb08997b976261d9436311bb5e00de	801ba1ed-ac82-43f2-9424-fbb1b3afad7f	a4378698-9fb4-4103-93a0-f224c670f4d2	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-21 16:06:46.669383+00	2025-12-21 16:06:46.669392+00	t	f	\N	\N	2025-11-21 16:06:46.669418+00
99fdd69e-935c-4d2b-8cfd-f80117b0eadd	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	7d06237d41db70c78304d009532f97d7bc85201279c9f5ab16ee31fa01ebb06f	801ba1ed-ac82-43f2-9424-fbb1b3afad7f	338ecb86-422f-4bd8-a37c-5c7575937a10	42.112.80.39	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-21 15:52:32.033458+00	2025-12-21 15:52:32.033461+00	f	t	2025-11-21 16:06:46.667653+00	rotated	2025-11-21 16:06:46.513307+00
f95d0469-f62d-466d-acf8-2daaaf5dfe84	987fa969-961f-4afb-98aa-636c3448bd87	fe664d23beecbb1b4efb368a5fe62679d8cd5c3a97c39f53ddd72d69d98a413f	5c079ef7-3079-4bb7-8080-005a260bf7af	923bf9d2-01ad-4978-89e3-11b7352ea41e	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-22 02:41:01.314998+00	2025-12-22 02:41:01.315+00	t	f	\N	\N	2025-11-22 02:41:01.315028+00
7008554c-2d89-44c7-8133-2e25a175fa88	987fa969-961f-4afb-98aa-636c3448bd87	1cb2d6dba24dbab680651f76b76ec3b380c0f603898878867c040a2c416f30a7	2e66dfb2-0d2a-41e3-9643-3d384bf96832	fd5e0d20-9e2f-40ce-b49c-7f1a460a6224	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-22 03:11:20.771558+00	2025-12-22 03:11:20.771567+00	t	f	\N	\N	2025-11-22 03:11:20.771597+00
b0a4c4d1-fef0-4baf-a1f1-2e752f0308c0	987fa969-961f-4afb-98aa-636c3448bd87	1bdc18934325f51e3a331d7e605991fdfb09ff126dd516a73a0adc86d8442e1a	2e66dfb2-0d2a-41e3-9643-3d384bf96832	bc8c26f1-acc6-42b6-a48a-2605effda49d	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-22 02:56:43.923163+00	2025-12-22 02:56:43.923166+00	f	t	2025-11-22 03:11:20.770247+00	rotated	2025-11-22 03:11:20.619452+00
de40e5fc-0194-4ced-a8a7-deff7dc73158	987fa969-961f-4afb-98aa-636c3448bd87	0215eca634a269fbd4bbfae8df1ad9a95c389e5bccb668d2bc50a7828845cb67	7732eea8-d845-4a37-808e-7af3d9f2d6b1	c6e4e97f-19c3-4a7c-a0ca-58d32561c8b1	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-22 03:15:55.072958+00	2025-12-22 03:15:55.072961+00	t	f	\N	\N	2025-11-22 03:15:55.072984+00
f9d23ffe-2b0e-4bc3-b456-3e411cc21670	987fa969-961f-4afb-98aa-636c3448bd87	e25bddeb6211c3e07946de699aec5d617a5e140c14e0b75f09daabdc5af8c56b	b52d0ad9-7620-4411-ad85-1719cc22f4ba	6db0a84d-e6fd-490d-8613-c6a2fd3bb2e2	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-22 03:34:08.021504+00	2025-12-22 03:34:08.021507+00	t	f	\N	\N	2025-11-22 03:34:08.021527+00
78a8c263-5d64-41e0-a8c7-243860f00a8d	987fa969-961f-4afb-98aa-636c3448bd87	cc05f7455b48796f0bd782e95b05dcf9e622e85fcee63f04ba1e2a46f10b1d0b	ac45b8c7-8c0d-45db-9ec9-a9dc7ef1975f	7ed00265-94c9-4a0b-bb39-52fe5ae94d5c	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-22 03:45:40.071831+00	2025-12-22 03:45:40.071833+00	t	f	\N	\N	2025-11-22 03:45:40.071856+00
48971678-65de-4545-b4c6-bb35147aa176	987fa969-961f-4afb-98aa-636c3448bd87	d431880e0dd0793f3dc0bd80a31eddd1fe49b14626017d9ab0828e674fc33fdc	69a8b8e7-fe3e-449d-9946-2ca1a89ecb4c	494868b2-93cb-445c-a92f-ebd0f893076a	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-22 04:19:58.293449+00	2025-12-22 04:19:58.29345+00	t	f	\N	\N	2025-11-22 04:19:58.293466+00
04280f9b-40b6-41c2-a704-6515b3d89130	987fa969-961f-4afb-98aa-636c3448bd87	8644fafa35168a424242179c4a918400a8b81304e28c7afdc1b858c1496b9a4b	69a8b8e7-fe3e-449d-9946-2ca1a89ecb4c	e2fa268b-c97c-4c90-9ffc-b3a589148c27	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-22 04:04:59.041776+00	2025-12-22 04:04:59.041779+00	f	t	2025-11-22 04:19:58.29119+00	rotated	2025-11-22 04:19:58.145523+00
b480be0d-06c7-4be6-97c8-0da3ac42ab0c	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	d41c1e8a190540377c0c9bd32e3ab44ae5d11431f8521fbd53107d00972af807	17fa0a06-8d1c-4643-8e3d-558bacdef2df	b2957094-6089-46e7-a29d-82c5ae4cac6b	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 06:33:31.132516+00	2025-12-22 06:33:31.13253+00	t	f	\N	\N	2025-11-22 06:33:31.132571+00
7e276d3b-0b3a-461f-8b3f-9856e5d590d3	987fa969-961f-4afb-98aa-636c3448bd87	d4d2f5927de5bdb9dae0cc632cb3d252a8ece0bc6ecbdae32821187807158cc1	127e68d8-0337-4b71-b251-34943b61d782	645a1d47-6894-438e-954a-ef9ed1de5397	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 03:29:44.466699+00	2025-12-24 03:29:44.466701+00	t	f	\N	\N	2025-11-24 03:29:44.466715+00
26dc2159-0b72-4108-97f5-6b15a7901d97	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	248c400784d25d944077c114d073eeb2b13af3821dd35bf33ee946f204a9017f	99738e03-8bd3-4331-85d1-462577839926	d0981665-31c5-4071-93ef-6d74fcbfa952	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 03:29:51.535393+00	2025-12-24 03:29:51.535394+00	t	f	\N	\N	2025-11-24 03:29:51.535409+00
6c23a0ac-7704-4dc5-a9b4-a6d737f84837	987fa969-961f-4afb-98aa-636c3448bd87	a52fb1bbb494e7b9763a840f0c5f77ba965782c1920c181481cc87c03cb139bf	4baede59-678f-4fca-be89-1d994660f894	80e11df7-fa12-4cd3-96ed-e30ffd33f529	1.53.197.175	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 03:29:56.487535+00	2025-12-24 03:29:56.487537+00	t	f	\N	\N	2025-11-24 03:29:56.487551+00
3a323c0f-ab8f-4635-ac20-ef81a91a993e	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	86f3efff201de041bf97e8c85d9c793e05cee3ffa3ad9aff6b07ff351138427b	ffa6a86a-1243-43bf-afac-f9a81828686b	f9775bae-4116-4505-bdda-745e9cfa61f6	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 07:57:40.580506+00	2025-12-22 07:57:40.580511+00	t	f	\N	\N	2025-11-22 07:57:40.580544+00
3de421d8-36c4-4d49-967a-bc826aebd59a	bb8259df-3cb8-487a-ab91-2ef95a68aa44	5367e91f3ba05f0e481cfba042942cc6dcf889e0b6d104ba34de7973a8472c58	e52657c3-a9e0-4005-bf6e-6ab00da4f991	766f7004-8127-4b6d-8d96-0d9c240d2155	125.235.237.198	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-24 04:46:38.700818+00	2025-12-24 04:46:38.700831+00	t	f	\N	\N	2025-11-24 04:46:38.700916+00
c6101944-47c0-4ab9-9212-dcb96f8893ee	987fa969-961f-4afb-98aa-636c3448bd87	a3978c02ee33ddc6c5df0c8885998affb9d4c2f4590e9b10d794e9737fb63bb4	44ee8580-a50c-4c08-b28c-76082cfb0740	8307927d-c107-41a3-b955-080ef2d490f9	171.236.70.5	PostmanRuntime/7.49.1	2025-11-24 04:46:41.713792+00	2025-12-24 04:46:41.713795+00	t	f	\N	\N	2025-11-24 04:46:41.713808+00
0255fad2-a22f-405b-9d84-10db9d45d689	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	cf4161eb7f030d5fbc3c36ab5a0bd226c45a54b332b5007de44f328211e7fef3	3a6333d3-63b9-4cf3-91bb-19d45fbff2a9	8637d51b-c488-47cb-8a08-22f48d670aec	14.191.78.141	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-24 04:46:42.443543+00	2025-12-24 04:46:42.443546+00	t	f	\N	\N	2025-11-24 04:46:42.443565+00
e4312847-54ff-4218-989f-98e78e8f58c6	987fa969-961f-4afb-98aa-636c3448bd87	c7cf49923f979bd944236387515f34891a3be088ae8dd6fd9f8c164a54bfbff4	34aee667-da46-463b-8b99-650ae0f84afd	9f39c5d6-8bd0-4000-b22a-52b324be491d	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 04:46:05.324333+00	2025-12-25 04:46:05.324345+00	f	t	2025-11-25 05:00:17.734145+00	rotated	2025-11-25 05:00:17.564207+00
37661942-5c22-4328-8178-df9e48e46343	987fa969-961f-4afb-98aa-636c3448bd87	4a0e62382c5fdeff6e19afc27222d7c63476ef9ed6535007736f8b3669b629ff	f7c05932-6590-491d-b96b-311010bc087f	3949763b-fbcb-4efe-844b-7f4497184507	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 06:12:43.280393+00	2025-12-25 06:12:43.280395+00	t	f	\N	\N	2025-11-25 06:12:43.280455+00
b0d3d25c-b7bd-45b1-bd03-5874a8879202	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	98a4b973db0594602fb8e101eabb128b4e403008bf1f82256f6ab74bbf06dbe8	1282bc37-6e85-46b3-988e-773aa04a3160	d0fa7b11-bdfa-4872-b355-ddb68103b67e	58.186.28.4	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-25 12:39:20.466596+00	2025-12-25 12:39:20.466598+00	t	f	\N	\N	2025-11-25 12:39:20.466657+00
931b3525-c954-401b-9466-a839b1f7dd93	987fa969-961f-4afb-98aa-636c3448bd87	9b38368ce0e8839501ce120d6bb74e20d05490ff9434a9d783210e904d7863af	c8b56512-370b-4127-8142-ea71de8a8bfd	0a2064f6-b7d0-4caa-a06d-337bbc5886c3	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 13:32:24.224231+00	2025-12-25 13:32:24.224234+00	t	f	\N	\N	2025-11-25 13:32:24.224282+00
58ef8292-cfa6-4473-83de-ab87c2707e4d	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	142861aa3c604b4efa79de5052dc25297870974950f38cc6175b094ae54d7b98	5429aca2-dc22-44ed-909c-470ec04f7649	0a1217ea-ae9a-46c7-acc7-c7e401d5a95e	58.186.28.177	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-22 08:02:01.476022+00	2025-12-22 08:02:01.476027+00	t	f	\N	\N	2025-11-22 08:02:01.476077+00
daaf19ec-50bb-4ab4-998a-14a6581771a8	c1d918d1-18d8-4837-a271-967d90f569a3	b3712a683f1d465225402e6fb4450e119bd62d64a53aa0c0ff903fa0a916b63d	1bf25b4b-aec9-410d-89b1-225e0c3d26d1	6e2b5a51-640d-464b-8619-e18ac18b64a2	113.180.136.66	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 13:33:04.328147+00	2025-12-25 13:33:04.328149+00	t	f	\N	\N	2025-11-25 13:33:04.328172+00
4a2871c3-0a22-454b-8d2c-7c4687770006	987fa969-961f-4afb-98aa-636c3448bd87	2c7412a865fa953c4a68dd00fb0e2534c3eb0dac07d6dd632be050b2d235e2fc	d4f21981-5bff-466a-b0ea-6842eaf6937c	c31169cd-9cd4-4be7-8981-da696e40c2d5	171.233.121.196	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 13:42:51.011526+00	2025-12-25 13:42:51.011528+00	t	f	\N	\N	2025-11-25 13:42:51.011558+00
1ce1ee6f-f68f-4158-b3c4-0260a9a6e797	987fa969-961f-4afb-98aa-636c3448bd87	7a4c0536c4b742f31278ba7955f6b21da3887458ee580384fe198cd5aacbf946	06a2caa8-348f-4443-b8f3-18f55ed5ad93	ce48af4c-c410-40af-8f73-10eae0d14952	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 13:48:42.667611+00	2025-12-25 13:48:42.667613+00	t	f	\N	\N	2025-11-25 13:48:42.667655+00
4ddb0065-386a-4f40-b335-c65418429126	987fa969-961f-4afb-98aa-636c3448bd87	6c1143b5a8dbad0f1e2e19e5232a34cd292f1d88a931b7e87df27715fdb0e9e8	20c02667-092d-44bd-ac99-83bb9eea789b	7f0d1fe7-a69c-4f17-827c-50dc15341d3f	171.233.121.196	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 13:49:03.634205+00	2025-12-25 13:49:03.634207+00	t	f	\N	\N	2025-11-25 13:49:03.634228+00
d0b9329e-85be-4365-93b6-dc2fbf763dd6	987fa969-961f-4afb-98aa-636c3448bd87	36965bc2862c8e92614fc0c0e59d7e142321d9e9fd160d7f7b5f602cf04195d2	582f796b-a636-41fd-a0a3-9096c18b155d	9400623e-6c73-4b25-aec5-6446c37ed2a9	171.233.121.196	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 13:54:26.277568+00	2025-12-25 13:54:26.27757+00	t	f	\N	\N	2025-11-25 13:54:26.277635+00
de93cb7b-e31b-4198-901c-5a99e213ece3	2a04b41b-422f-455e-85c3-4c036e692b3c	9c968d56798f844295bfcb39341fe5409b3af3c348d0418fc701380f6ef2ad61	5254c6c5-e8ed-446e-988e-a14f552c0997	e91477f7-f2f0-4248-b897-5744ceae156d	171.233.114.75	PostmanRuntime/7.39.1	2025-11-25 13:56:50.129052+00	2025-12-25 13:56:50.129061+00	t	f	\N	\N	2025-11-25 13:56:50.129117+00
222dd970-2bc4-473a-be11-0148e0cb85e2	2a04b41b-422f-455e-85c3-4c036e692b3c	a5699eef3174f339ee20c68e0d9d0f1d4aa9a7999dbf3c61e73599961b87c484	cda49fa4-0d26-411e-8ded-6d96105fb1df	5401f507-2747-4b5b-9693-970f89607d01	171.233.114.75	PostmanRuntime/7.39.1	2025-11-25 13:58:18.827383+00	2025-12-25 13:58:18.827385+00	t	f	\N	\N	2025-11-25 13:58:18.827431+00
f59cf22c-c1a2-4323-9e61-5a3d0304f740	cd23d611-1644-4d29-b7b3-100f9458018c	1f29f054650309c915c2f4f576f2bb69696d86e29ab360c751b74ee1dbb45851	c76e998e-594e-4273-9673-d3e49b7eb1cb	d183363b-9926-4c45-b1d9-05ac2628d482	58.186.28.4	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-25 14:03:07.850487+00	2025-12-25 14:03:07.850496+00	t	f	\N	\N	2025-11-25 14:03:07.850566+00
912c5dcd-f968-4391-b989-de5b6e180961	987fa969-961f-4afb-98aa-636c3448bd87	70e4a7ed26fa254944a41da2bcf605f112c78b78b15a1757673a1f09680c25a5	2dec470b-8994-4d0c-b411-5e74dc75adeb	962d984d-4e18-484d-bcb1-6f646739578d	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 14:24:55.133727+00	2025-12-25 14:24:55.13373+00	t	f	\N	\N	2025-11-25 14:24:55.133794+00
55aae6fa-4bb8-4e77-b35e-9f77f402e21a	987fa969-961f-4afb-98aa-636c3448bd87	6d168151ef5e54e43ceb4d1f8f1dcccc6335faf2353320626b9475fa24a6c28d	fc4c83a4-54eb-4496-bfb7-7334ddbb0fff	ca48a90f-7784-4c94-855e-7517bb174a73	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 14:25:07.872412+00	2025-12-25 14:25:07.872415+00	t	f	\N	\N	2025-11-25 14:25:07.872427+00
77ae4641-7557-43c1-bf0a-e3b5857dc5b6	987fa969-961f-4afb-98aa-636c3448bd87	e822b10e2ec08ab5df88ae5d5ab2f52a947fa6541ef9a138ab7b90f43da98fb5	00e6e452-dcd1-4b2e-8b51-865131d8b6eb	8fc3b652-cd60-40bf-9765-5dbe221e8bc4	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-25 14:26:39.862744+00	2025-12-25 14:26:39.862747+00	t	f	\N	\N	2025-11-25 14:26:39.862784+00
d2fb7d78-cf84-4cc7-8bea-de3cbd6ce471	cd23d611-1644-4d29-b7b3-100f9458018c	792f2c79b847f3c648e37d10d8b525a0898f40d2ad30db5be49c01eee087772b	54c5c5f8-47f6-41a1-b81c-420c3856c5d4	f81b2318-9761-4041-96e7-05487e8c99ed	58.186.28.4	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-25 15:45:08.060586+00	2025-12-25 15:45:08.060588+00	t	f	\N	\N	2025-11-25 15:45:08.060634+00
be926992-da2b-475f-a165-fd355b9caec1	cd23d611-1644-4d29-b7b3-100f9458018c	4d5774a40087d04ec4c1f44fe420c7dfec2977d9f9522656e70005769246b0b1	54c5c5f8-47f6-41a1-b81c-420c3856c5d4	c323fc3b-02a2-4166-b59c-7c841d71142c	58.186.28.4	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-25 15:31:05.602274+00	2025-12-25 15:31:05.602276+00	f	t	2025-11-25 15:45:08.059254+00	rotated	2025-11-25 15:45:07.846475+00
55f353c9-9f26-4506-9a16-3f6a627ab64a	cd23d611-1644-4d29-b7b3-100f9458018c	d904182575904690c1d317e8b18b9381373608a024572542402102cd471838e7	996e912c-84b4-4047-9cfe-ed4c926aaf03	ca6f729e-d0ca-4f1b-acce-a1b21ddb62dc	58.186.28.4	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-25 16:42:35.596213+00	2025-12-25 16:42:35.596215+00	t	f	\N	\N	2025-11-25 16:42:35.596267+00
0a68ee6e-d9d7-424e-82f9-6e1d0a05bb65	987fa969-961f-4afb-98aa-636c3448bd87	1cec2d91ef234f623984cb895535dcde4baafac16c660186ec9821812b82a228	d630911d-0884-4c33-a6dd-2fefb66a1cf3	e401f456-d70d-409c-acbc-20bc864b6f59	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 18:39:49.894879+00	2025-12-25 18:39:49.89488+00	t	f	\N	\N	2025-11-25 18:39:49.894931+00
d2b88d92-f850-4e36-9e44-e5350d6a56d4	987fa969-961f-4afb-98aa-636c3448bd87	e1d68dafb0afe6a07fa1c1eba415c8143bb30cb923e9fa32cd91dc55a33871af	d630911d-0884-4c33-a6dd-2fefb66a1cf3	3c2aee97-19ef-4417-8fa2-8c861300ce3a	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 18:25:46.346662+00	2025-12-25 18:25:46.346665+00	f	t	2025-11-25 18:39:49.89461+00	rotated	2025-11-25 18:39:49.686936+00
a16c8d2f-a2bc-4bb6-9326-7dc29ba6b6ea	987fa969-961f-4afb-98aa-636c3448bd87	ef8a69522cca7c95ce4de1e4a72ef9569d5580161245f37cbc1adc6eb24a71ee	6f2103cc-b907-484f-87c1-8b40c097d969	b47f3634-0833-4d4c-96fa-d4a620791f92	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 19:00:57.340692+00	2025-12-25 19:00:57.340694+00	f	t	2025-11-25 19:15:00.992328+00	rotated	2025-11-25 19:15:00.771057+00
3fce5851-1b5e-4223-8278-152b836f48e7	987fa969-961f-4afb-98aa-636c3448bd87	a851517d6c6d623a8647cac942981a279fd2e5e13f9d6f40e666b2c68b836230	6f2103cc-b907-484f-87c1-8b40c097d969	d5ab6d35-a5a3-443d-b25f-ecde89366402	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 19:15:00.996392+00	2025-12-25 19:15:00.996394+00	f	t	2025-11-25 19:29:05.728231+00	rotated	2025-11-25 19:29:05.528087+00
fbf7866c-270a-4b06-8af5-7728a2e4c552	987fa969-961f-4afb-98aa-636c3448bd87	b01d46d18c446cd41c241ad0e438087c53c334c93360868ac632401eacd10d40	6f2103cc-b907-484f-87c1-8b40c097d969	a286d00e-43f5-4ec9-bfcc-9b4b749a2f36	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 19:29:05.728587+00	2025-12-25 19:29:05.728588+00	f	t	2025-11-25 19:43:10.686463+00	rotated	2025-11-25 19:43:10.429316+00
13332a4e-760b-4f14-972b-e8baea29e5a2	987fa969-961f-4afb-98aa-636c3448bd87	9e235459349380cb3f2f1f645caae1b1dd862442b773be51be3f6b97f7c5170d	6f2103cc-b907-484f-87c1-8b40c097d969	9dee6a34-242c-4627-b05d-c6180fb5333d	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 19:43:10.686784+00	2025-12-25 19:43:10.686785+00	f	t	2025-11-25 19:57:16.009359+00	rotated	2025-11-25 19:57:15.79502+00
3108870c-c63d-488a-902d-f210bbea4ed0	987fa969-961f-4afb-98aa-636c3448bd87	831c10504c3bd19275e220384ff4653ee31519e95f83ccd2ee1fbf7f085feed6	6f2103cc-b907-484f-87c1-8b40c097d969	a8e527be-edab-44ec-a702-a070a83afa3c	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 19:57:16.009636+00	2025-12-25 19:57:16.009637+00	f	t	2025-11-25 20:11:19.858973+00	rotated	2025-11-25 20:11:19.633151+00
e4cbf9d7-415c-416e-b0dd-d04ffcd99049	987fa969-961f-4afb-98aa-636c3448bd87	b1d2d6142ff6b85367e221acf5fff6c2d3078e5a0978503f3316e1af1e5327bb	6f2103cc-b907-484f-87c1-8b40c097d969	32f27e6c-a214-4df9-baee-67e97647f84c	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 20:11:19.859263+00	2025-12-25 20:11:19.859264+00	f	t	2025-11-25 20:25:24.450929+00	rotated	2025-11-25 20:25:24.188752+00
a493a015-4309-4f19-adc4-bd1eb2ebc3d2	987fa969-961f-4afb-98aa-636c3448bd87	d5bed7553fff3ba7f8ca2c940707ecc24f71f217adb789f05481bfe8aff4fc0d	6f2103cc-b907-484f-87c1-8b40c097d969	22369c28-8d1a-48a5-98a8-fb5380b47e39	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 20:25:24.451228+00	2025-12-25 20:25:24.451229+00	f	t	2025-11-25 20:31:40.760159+00	rotated	2025-11-25 20:31:40.56528+00
fa064dcf-55ff-4fa0-bea0-a8b7c5cce601	987fa969-961f-4afb-98aa-636c3448bd87	fc53a50d4ec9e4929a5c4cc704dfac4721c23d2aad8b1e1cb1481c10bc42d9bb	6f2103cc-b907-484f-87c1-8b40c097d969	01ce5065-31d5-4a67-99e1-3ccc291bf80e	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 20:31:40.764502+00	2025-12-25 20:31:40.764504+00	f	t	2025-11-25 20:31:41.53119+00	rotated	2025-11-25 20:31:41.339051+00
32b59a7e-7f42-4edd-a36e-cd59f48c17cb	987fa969-961f-4afb-98aa-636c3448bd87	5c3162b4687da8af28af7f04ef91643f73d0187f77efadbcb8255779e0c80211	6f2103cc-b907-484f-87c1-8b40c097d969	13ce5904-3ca5-42ad-99db-a3a88f4fbc07	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 20:31:41.532447+00	2025-12-25 20:31:41.532448+00	f	t	2025-11-25 20:31:42.320226+00	rotated	2025-11-25 20:31:42.116606+00
b99f796c-5d05-4ec7-ae78-8b5a6ce94913	987fa969-961f-4afb-98aa-636c3448bd87	820c7b6c9140e85b062aab0a1417bd7b1be87aa62bbd69ba9f5c179341584da9	6f2103cc-b907-484f-87c1-8b40c097d969	43cbd0f7-26bf-435c-bf76-8a48eeb0bd83	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 20:31:43.193917+00	2025-12-25 20:31:43.193918+00	t	f	\N	\N	2025-11-25 20:31:43.19393+00
3c333cde-2f46-47c2-947e-ceb9fc17c120	987fa969-961f-4afb-98aa-636c3448bd87	728666ec5511be474b12c799623939e31743cddb8e3ff743f29a4d08d22b3830	6f2103cc-b907-484f-87c1-8b40c097d969	721647bf-89ff-4f0e-b420-30b8c28e1f7a	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-25 20:31:42.323071+00	2025-12-25 20:31:42.323072+00	f	t	2025-11-25 20:31:43.193672+00	rotated	2025-11-25 20:31:42.989404+00
cf8276ff-e853-41e3-90c6-c9aa5031ad69	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	b9b27a8363081d52a0e2f507979ec7cbc861c33bf1ee46793a8b4b5d60daad24	e72a7212-1bf3-42b7-9503-f24b1ef055ec	43ac2030-7a5a-42d4-a5b6-01058f986a21	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 00:02:07.274384+00	2025-12-26 00:02:07.274386+00	t	f	\N	\N	2025-11-26 00:02:07.27443+00
422c9674-8d46-460d-97b2-39ca78a8df2a	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	7370abdccc1d870b76c31f5f29b184da6c1c869dbf95769fb6f487ec40af2e23	2e9781b8-5bd4-4774-8640-8a99fa677c8c	c7132a99-1fc8-449e-af94-4c0fb6301adb	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 00:02:22.298427+00	2025-12-26 00:02:22.298431+00	t	f	\N	\N	2025-11-26 00:02:22.298453+00
09fe4d12-aaf7-4998-8130-f828fb160d76	987fa969-961f-4afb-98aa-636c3448bd87	2d32aec54c37dd0571715291c5fed9c34c8f00ecb0c05a12e972a5eff53788df	97567b76-d55b-4fd2-8390-54db215301ef	c018b39f-bccd-4c27-ac49-0d7548d0e732	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 00:02:47.872029+00	2025-12-26 00:02:47.872032+00	t	f	\N	\N	2025-11-26 00:02:47.872063+00
b7e4540c-ff58-4fab-8068-e2a0dfab345e	987fa969-961f-4afb-98aa-636c3448bd87	4a209e513506f62627bb1c8daaa3875bce360c8c914f0fbfe8c92fc41f2d3680	77fc51f4-648b-4e3a-8104-9b3a6809e753	db947c5d-81a7-49ff-97d3-ba691dcd2138	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 00:07:24.681375+00	2025-12-26 00:07:24.681379+00	t	f	\N	\N	2025-11-26 00:07:24.681483+00
e45b277a-739e-4dca-9858-bc6f17ecaddb	987fa969-961f-4afb-98aa-636c3448bd87	8af71afd0c120fd5001b9808e2b727cd0da60a93300b0a7584a823d8e80e7f3a	d74a1e29-66a0-401a-89b9-2c32a2508bb9	0cc8f60b-9e6c-48e0-bfe9-56f6a37dae94	42.114.92.45	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 00:16:09.123836+00	2025-12-26 00:16:09.123847+00	t	f	\N	\N	2025-11-26 00:16:09.12392+00
ba92edd4-f953-431f-a305-ff121eacaef5	987fa969-961f-4afb-98aa-636c3448bd87	588cfe5ac70b2ff03ab5796e20844895721089c846ced746f9d329b9e52c7ca2	67d53a6b-8557-4866-a444-a09a6136c6de	66e42ada-1299-43f0-ab55-e40d1c686d92	125.235.236.195	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 00:18:19.941868+00	2025-12-26 00:18:19.94187+00	t	f	\N	\N	2025-11-26 00:18:19.941915+00
c93bba1e-6ccd-4222-8391-8de1b14d8556	987fa969-961f-4afb-98aa-636c3448bd87	f91d53f582fe9e0844bf8b88d133aab6b33e4cf9f467d360db703879b151e425	97555e43-e9f4-4559-bf77-c76f7c6dc2a5	f2e75548-9a1c-4e02-84fb-57773205483d	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 01:33:00.563345+00	2025-12-26 01:33:00.563348+00	t	f	\N	\N	2025-11-26 01:33:00.563405+00
48f95e2a-8862-48ce-81b5-fcf0e856abb0	987fa969-961f-4afb-98aa-636c3448bd87	b49561d6748b762a5b510638264af22c61da24d5b60ba4e93afdf629f0004499	b3f7841e-fd5a-42da-9fc9-008fdac6eb9f	5137fd9f-f0c4-4ffd-945a-25aeaea7f5ae	118.69.128.8	PostmanRuntime/7.49.1	2025-11-26 01:33:30.177279+00	2025-12-26 01:33:30.177281+00	t	f	\N	\N	2025-11-26 01:33:30.177349+00
b71f2c9b-c644-4544-87a3-0a4c52d41dec	987fa969-961f-4afb-98aa-636c3448bd87	a7462ad85bdd5fc75d8d600133ea1bb49aeb8410cef4c0cbe0f7dc4c6d4d1e5b	925bed06-ab8e-424d-b0e2-44d88fae76cb	d78b39c6-ec6f-4c6b-9e13-917af4c057ea	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 01:33:55.747344+00	2025-12-26 01:33:55.747346+00	t	f	\N	\N	2025-11-26 01:33:55.74737+00
91920f7d-c073-4b09-874d-00743044c18a	987fa969-961f-4afb-98aa-636c3448bd87	758cb6715ee3dd6467159529ea0f73116c84c80362efa59011a5eb2c4bad3e8d	7a70a2f6-3b1e-4684-8d19-e813edea7bb5	bf1d0136-6adb-4c12-a250-3439e142eb95	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 01:39:03.596098+00	2025-12-26 01:39:03.596099+00	t	f	\N	\N	2025-11-26 01:39:03.596155+00
1e5bc760-48aa-4813-8496-41db15dfb23b	cd23d611-1644-4d29-b7b3-100f9458018c	bbec024f258e62a300201ba6153dc49f765f15c9f938e9966cb3898a597c6954	7e11aa8e-3582-4a43-8850-18fc10bd8d13	d9c315eb-dd42-4cd5-846f-16fc6c0ed8cd	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 01:47:27.145645+00	2025-12-26 01:47:27.145646+00	t	f	\N	\N	2025-11-26 01:47:27.145693+00
d2a29769-3163-455f-ae59-41dbea6a91e6	cd23d611-1644-4d29-b7b3-100f9458018c	b23cb8fcf54496887f3bea347f1806b7b56fc79eeb773ec98edd97fe72c6d8e7	7e11aa8e-3582-4a43-8850-18fc10bd8d13	8c1464f0-6e20-4ada-a647-48616bacdfc1	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 01:33:24.011654+00	2025-12-26 01:33:24.011657+00	f	t	2025-11-26 01:47:27.145317+00	rotated	2025-11-26 01:47:26.910958+00
104b8fa4-3b83-495d-8e52-5ee1c4de6b74	c1d918d1-18d8-4837-a271-967d90f569a3	d9fb836d37fe6e9a29018ef88b93ed77116834c81bd28879246a66873a9caae6	7ee1e685-bd6c-4af8-8910-c10c56cc029d	57c7a10a-28be-4e1e-afb3-fd228191f676	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 01:52:03.504959+00	2025-12-26 01:52:03.504959+00	t	f	\N	\N	2025-11-26 01:52:03.504969+00
4a82a16f-3444-4ec2-a31f-9965bde4276f	c1d918d1-18d8-4837-a271-967d90f569a3	ef00baabea30eb605a45e1120e565c62c50370399dfac665e618074cb314bdc0	7ee1e685-bd6c-4af8-8910-c10c56cc029d	65b8bc09-0cd2-45b3-b5b2-d35ba7dca99b	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 01:37:42.51422+00	2025-12-26 01:37:42.514222+00	f	t	2025-11-26 01:52:03.504735+00	rotated	2025-11-26 01:52:03.311405+00
ca3e3bbb-6dcd-4c23-b98b-ce1a7c145958	987fa969-961f-4afb-98aa-636c3448bd87	4186252681801e37c79a463ea22cf2fc3a5b83aedde46b9841c400df0c8a073a	d0a7380d-894a-49a0-aab2-d17099f4ad8e	280a693a-24fa-47fb-97ce-50822e95b2be	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 01:54:36.769531+00	2025-12-26 01:54:36.769533+00	t	f	\N	\N	2025-11-26 01:54:36.769574+00
fdf966d5-b7e0-4659-a3ac-c3c6e965e1e0	987fa969-961f-4afb-98aa-636c3448bd87	f2227046bc3498cf7560dcdb0223231281701c1ebac6a6eded979bceb1ff973a	bd6bce5d-3706-42f9-92d2-875f323f6771	d1ffc006-9b5d-4b7c-b306-c829f4b236d2	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 01:56:20.439828+00	2025-12-26 01:56:20.43983+00	t	f	\N	\N	2025-11-26 01:56:20.439873+00
849eeb49-a29d-4c0d-8092-bb2aab4f8e9b	c1d918d1-18d8-4837-a271-967d90f569a3	989319526fd7d279402659a64f983676edb38c4c670c15501108e10152a3514a	14dc48c4-ceab-42aa-a68b-18b792a45ddb	bef00d43-c40c-4309-b542-69359716c6bb	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 02:05:03.726786+00	2025-12-26 02:05:03.726786+00	t	f	\N	\N	2025-11-26 02:05:03.726833+00
9f012961-a644-4f6b-9a43-df66d017bc44	c1d918d1-18d8-4837-a271-967d90f569a3	133ba9f6be64f471e0dd7446f4ab72be571c182a2fa99cd29d9ed5de97093e3c	14dc48c4-ceab-42aa-a68b-18b792a45ddb	76ae9bde-b2ef-4324-a018-cb86bc05aead	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 01:50:29.782407+00	2025-12-26 01:50:29.782409+00	f	t	2025-11-26 02:05:03.726496+00	rotated	2025-11-26 02:05:03.478389+00
e98ce8b7-855b-48eb-a8be-93354766ef69	987fa969-961f-4afb-98aa-636c3448bd87	fb2e43c8b7c38ba71b17b93ce094315dde2549982ebed0a33830289978c762c0	f3556c29-62be-48fc-8db0-33e5d1a24568	15280af8-2780-4937-835c-1e691a13caa1	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 01:56:25.362948+00	2025-12-26 01:56:25.36295+00	f	t	2025-11-26 02:10:29.770249+00	rotated	2025-11-26 02:10:29.565004+00
64407645-006b-4020-9d66-25f2be93984c	987fa969-961f-4afb-98aa-636c3448bd87	f190493d41428ebf98f4389f67378f3b57234de61564fce124bf8c328e4653d9	f3556c29-62be-48fc-8db0-33e5d1a24568	d1bd1fbd-8390-43e5-8db2-5bc25ee3037b	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 02:10:29.771594+00	2025-12-26 02:10:29.771595+00	f	t	2025-11-26 02:24:34.335244+00	rotated	2025-11-26 02:24:34.122789+00
c12d48e8-e276-41b7-9fe5-1c47b02fc808	c1d918d1-18d8-4837-a271-967d90f569a3	a0ad29b0d80f8adc1350efe471a2d0f1c5fc6f9a2daf6eb318d3c5fed022089d	e64c27f7-e2c2-4c29-aead-f73955c51084	c44f2c4d-657b-421b-8135-4442a3541dd4	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 02:24:43.18207+00	2025-12-26 02:24:43.182078+00	t	f	\N	\N	2025-11-26 02:24:43.182093+00
f7f04552-7bb7-46ec-847f-e00d3699a42d	cd23d611-1644-4d29-b7b3-100f9458018c	9e2a9b5c6cf7c94c83cb723d815e17f6a2468f4dd1cb43fecfb71960508373a6	5951ddf6-9a7c-4bee-95d1-7824a50ac21f	1a70fda0-c3e5-47be-8188-86cb5ec856b3	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 02:29:49.451332+00	2025-12-26 02:29:49.451335+00	t	f	\N	\N	2025-11-26 02:29:49.451363+00
ad2b068a-f1d0-4ce5-a84b-83e60c87c54e	987fa969-961f-4afb-98aa-636c3448bd87	aa3edc37128c91714156103909552e4d0a613d7db220896c6791362e81d84c06	79102e9d-7232-4f21-bf02-7ddb20fe3bbe	f36db8df-24c5-4076-bd71-9c2c0951a9fe	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 02:28:45.986902+00	2025-12-26 02:28:45.986905+00	f	t	2025-11-26 02:36:04.778244+00	rotated	2025-11-26 02:36:04.587041+00
33912023-52d7-4bf3-9619-e00d566fbb3e	987fa969-961f-4afb-98aa-636c3448bd87	fb5ff107da78d57fca71df0dc66f2ceb1b9390349ef924bcd12d8cca304cf13e	79102e9d-7232-4f21-bf02-7ddb20fe3bbe	f3b73d41-f500-4781-9bcd-dad810fb6080	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 02:36:05.539515+00	2025-12-26 02:36:05.539516+00	f	t	2025-11-26 02:36:06.294834+00	rotated	2025-11-26 02:36:06.111371+00
58cf06f9-dd2b-4c25-b1e1-cd232abb300c	987fa969-961f-4afb-98aa-636c3448bd87	d8492c358198e634f98c22dcec7aedc130292054d3fa9b86ffb8a21a023b1a6d	f3556c29-62be-48fc-8db0-33e5d1a24568	2f9fcadb-44e4-4fa8-9156-f1bbc610851a	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 02:24:34.33769+00	2025-12-26 02:24:34.337691+00	f	t	2025-11-26 02:39:00.056431+00	rotated	2025-11-26 02:38:59.860986+00
a2c9de09-2af6-409e-98d1-8cdaf504c0a3	987fa969-961f-4afb-98aa-636c3448bd87	58787df3e9a384aefd0401f1ab315934a53ce0ac6fda57d01e815b37a9a92325	79102e9d-7232-4f21-bf02-7ddb20fe3bbe	d3055fb9-f71a-4dbc-9036-a504ec861cad	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 02:36:04.779557+00	2025-12-26 02:36:04.779558+00	f	t	2025-11-26 02:36:05.53925+00	rotated	2025-11-26 02:36:05.352224+00
bb9e033d-b59f-4dad-bdf4-5cfb0ebfb510	987fa969-961f-4afb-98aa-636c3448bd87	a0349b2ba64e35f37cf4dc9bcab450a2985a8f4b01f9c04514bf4b23df6d9217	79102e9d-7232-4f21-bf02-7ddb20fe3bbe	ad15ef65-f52e-4186-8215-628a06b719d6	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 02:36:07.057628+00	2025-12-26 02:36:07.057629+00	t	f	\N	\N	2025-11-26 02:36:07.05764+00
9c29f3a9-2db5-4e74-8a1e-10d432b9d204	987fa969-961f-4afb-98aa-636c3448bd87	a7ce94160da1e3bbdb8d68700e78aca967da1ffb3feed2967008fb7920cdfae9	79102e9d-7232-4f21-bf02-7ddb20fe3bbe	b1309ea5-8b6d-44a9-a498-94c7c6546501	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 02:36:06.295074+00	2025-12-26 02:36:06.295075+00	f	t	2025-11-26 02:36:07.057403+00	rotated	2025-11-26 02:36:06.867519+00
5bb39916-6ef4-48da-aac2-090d7ea3f734	987fa969-961f-4afb-98aa-636c3448bd87	ef86fd045178b4ee08805be068bf5711a6fb19691b9d64371f724102f92ac3b0	0ae5bf43-0ea6-44da-9182-a00044b6bd25	19735eac-db4c-48fb-a1c3-a39261e34725	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 02:36:58.955036+00	2025-12-26 02:36:58.955038+00	t	f	\N	\N	2025-11-26 02:36:58.955056+00
3ed2b0a6-eeef-4d14-a942-41864c29814e	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	3ecbbae5978b12ff650c6773e3e103fb1da087f3252850985303f610894c07a6	a7b44832-bcdf-4df8-a193-ec2549de254a	258447f8-0c75-4f4d-9800-1a60f2065bbe	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 02:37:51.496615+00	2025-12-26 02:37:51.496617+00	t	f	\N	\N	2025-11-26 02:37:51.49665+00
22ab9dbb-1905-4339-a01e-22c63a533b88	cd23d611-1644-4d29-b7b3-100f9458018c	19231a764eecfa2e49b980a6cb1d2201b0178ba15987a318837eac416ed20301	90fd82e6-07e5-4e9c-b328-0a71f8ada678	2c2b67dc-94d6-48ed-a14e-e07374f84d8a	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 02:38:05.044227+00	2025-12-26 02:38:05.044229+00	t	f	\N	\N	2025-11-26 02:38:05.044241+00
2f790c3d-75f0-4d61-b5d7-ae31148ebb32	987fa969-961f-4afb-98aa-636c3448bd87	f59d50a490b85e7b137550e15d98f6df8a7780017d7f1da1203bf0fffeaa3cfd	f3556c29-62be-48fc-8db0-33e5d1a24568	ac79bcb4-a4e6-4de2-8dda-76bacc9ddd93	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 02:39:00.05668+00	2025-12-26 02:39:00.05668+00	t	f	\N	\N	2025-11-26 02:39:00.056712+00
47fa8cb7-672d-4076-adfc-0db284429cfc	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	b05dc8a0282614581151e711721cf052e836c67fc4b5aadcb0c1347f09aa9410	0420da28-73a4-4596-be70-bf813850266b	b623af97-9f18-46cc-aa57-b79db2812426	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 02:44:48.686544+00	2025-12-26 02:44:48.686546+00	t	f	\N	\N	2025-11-26 02:44:48.686598+00
51127ee2-9f02-4539-b138-d76c8d822d7e	987fa969-961f-4afb-98aa-636c3448bd87	2909333822e9523a6fe12f7cd2ea2a386fc824ba00f87643dafa7cbb490d08cd	9e22d2ce-a35f-4dc0-bac2-103d38f13c82	eba62657-cde0-4d35-a040-f9378ec4e1f5	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 02:54:13.149363+00	2025-12-26 02:54:13.149366+00	t	f	\N	\N	2025-11-26 02:54:13.149405+00
737b1f6a-3640-43bd-b643-b85f546bd2a2	cd23d611-1644-4d29-b7b3-100f9458018c	d760c479d8533d2798fa09bc0dedd49755b5d658d2eb7532dc5d317b746a74b2	7be92aea-9e16-4f33-9d9b-ea390ad87842	aaead230-080d-4de6-a29e-b0db350eac03	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 02:54:33.94581+00	2025-12-26 02:54:33.945812+00	t	f	\N	\N	2025-11-26 02:54:33.945823+00
562bbe51-8152-410f-9d47-f1d2c1f1df78	987fa969-961f-4afb-98aa-636c3448bd87	a0a2249f247e330c08c80e940fc14b5221810b168baa717e300108f0fd21bbc3	2c2a2063-dc56-4228-ba46-7d1e01b3fe9b	d61f8d56-744f-4d2b-9acc-3737ae38bfaa	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 02:55:41.807271+00	2025-12-26 02:55:41.807273+00	t	f	\N	\N	2025-11-26 02:55:41.80933+00
34c173e3-3b8e-458b-9738-10d9bd228db4	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	3ca41ecaa7583e3ddb31fd0ea5d95f4268e9003086ade3b02946b1dfe3198a88	8fef5631-84fb-478b-a210-cf31e184fadc	b1a58a20-5d39-42bb-b8c2-44c2627044ec	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 02:56:01.416127+00	2025-12-26 02:56:01.416129+00	t	f	\N	\N	2025-11-26 02:56:01.416141+00
bc8662b5-7e57-4a26-827c-3399ba7dd745	987fa969-961f-4afb-98aa-636c3448bd87	a8d41b94f9e976baa133fd5e7c4c4739a770c47e0575d9cf66ba73f72d1fbcc5	ac65fd24-e0fa-40e6-b07c-17b822b6895b	d9daf538-5b62-4b82-ae68-0edf25ab4d82	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 02:56:14.176178+00	2025-12-26 02:56:14.17618+00	t	f	\N	\N	2025-11-26 02:56:14.176194+00
61715af6-43cf-418e-858d-002ee88d94f5	cd23d611-1644-4d29-b7b3-100f9458018c	fd90305563886fb8112d4d142f7c0299e5407941f6dddafba2ad21fb441c6eb6	b0d1827e-8936-413b-b0f7-28f597e906da	c1b6ce7c-bd23-44f2-a92b-b5b15828c7d7	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 02:56:18.460176+00	2025-12-26 02:56:18.460178+00	t	f	\N	\N	2025-11-26 02:56:18.460192+00
68fa8e51-c00b-45c6-9d36-f28c324db212	cd23d611-1644-4d29-b7b3-100f9458018c	bc5bc8d9432d948c3fec0af80fffbd671ba24a9370e128da07a84312fa8b29b7	67c9d510-6c01-467e-bfe0-108238d7f852	158dae2c-f25f-4f2a-b6ba-7de5f4890a62	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 02:57:44.547072+00	2025-12-26 02:57:44.547088+00	f	t	2025-11-26 03:12:40.658202+00	rotated	2025-11-26 03:12:40.47671+00
020a2c7d-37da-4b41-8dd8-d8da2aaca07e	987fa969-961f-4afb-98aa-636c3448bd87	7bd49d607620f4a1489c0163be9e056467e77a202497f0286afcd4da2d2fa498	df1345cf-2e35-4e94-9f74-76faab554ca3	21c3bbe8-2db5-46d9-8263-04993680a360	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 03:21:44.431575+00	2025-12-26 03:21:44.431577+00	t	f	\N	\N	2025-11-26 03:21:44.431629+00
34140091-eab2-4761-8702-ca19cb878740	987fa969-961f-4afb-98aa-636c3448bd87	5ae24660cb2ff21c7bd5520fbd6fcf94db17bc4619830b07598c126819b9fda6	df1345cf-2e35-4e94-9f74-76faab554ca3	0dcf697f-b641-4203-ad26-18669658a6e5	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 03:07:40.05051+00	2025-12-26 03:07:40.050512+00	f	t	2025-11-26 03:21:44.431244+00	rotated	2025-11-26 03:21:44.235438+00
ac4c9518-4a69-4829-848b-ce4a5610aaa8	cd23d611-1644-4d29-b7b3-100f9458018c	c5816859c66fb162286c5b9d55e8e5897775cfeb653fced0f5ea3fe231408767	67c9d510-6c01-467e-bfe0-108238d7f852	9e5c2f71-a294-4377-ac70-67a3a6a34a5e	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 03:26:42.824244+00	2025-12-26 03:26:42.824245+00	t	f	\N	\N	2025-11-26 03:26:42.824324+00
a76af184-6cf8-411a-8c40-9ca4eb66452f	cd23d611-1644-4d29-b7b3-100f9458018c	a0e5f165e7dd677c5fe3750017458d355e0117ac18f7a643db95d593ab08536d	67c9d510-6c01-467e-bfe0-108238d7f852	a4d2e6c3-cf05-46ce-af7c-ddfb9ead463f	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 03:12:40.658547+00	2025-12-26 03:12:40.658551+00	f	t	2025-11-26 03:26:42.82395+00	rotated	2025-11-26 03:26:42.585369+00
4be6b8b8-d574-4b17-b22b-e8617b348d7f	987fa969-961f-4afb-98aa-636c3448bd87	43210f9e72ff24561c89bcfd313022d3b723617caf2ab468ee80c6dd419c9fe1	c7063095-0c55-4f8d-8a38-7bd87ed87367	5f5104da-e177-49b5-b707-49c808b0fc81	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 03:29:41.112028+00	2025-12-26 03:29:41.112031+00	t	f	\N	\N	2025-11-26 03:29:41.112091+00
21b9e024-586c-467a-bc05-19a5a6cfca85	987fa969-961f-4afb-98aa-636c3448bd87	2dace29addd84a1ec35efd2ce1e23c8f55449d5bdef1cf54c3e6ebab0089f6d1	3cc4828d-906b-43c8-8283-956c042a0c5b	04c65f25-151e-4bab-9955-a730cef7a81a	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 03:37:33.618352+00	2025-12-26 03:37:33.618354+00	t	f	\N	\N	2025-11-26 03:37:33.618411+00
dbad2903-ffc9-4984-9f39-eb9ac9fa7ed0	987fa969-961f-4afb-98aa-636c3448bd87	c5d1ed684de7136ec696e8ca4abea45e56c83cdba9ad385e3f0d2fa4b20fab15	709c0897-77ab-49ca-8630-874a5a83a5ab	89d42e3c-eb21-4fd9-ad88-bc7ebb9bd27f	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 04:01:40.012784+00	2025-12-26 04:01:40.012785+00	t	f	\N	\N	2025-11-26 04:01:40.01284+00
be0d1449-d136-47b0-bd45-251c14a314d4	987fa969-961f-4afb-98aa-636c3448bd87	bfdba00787a68a29b2891b3247f63befb60b048f3d1aa46f003199385d8f059b	709c0897-77ab-49ca-8630-874a5a83a5ab	dfecf89a-03ab-40e5-bab6-e83141ad341c	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 03:46:42.425181+00	2025-12-26 03:46:42.425183+00	f	t	2025-11-26 04:01:40.012472+00	rotated	2025-11-26 04:01:39.762732+00
a3705ea6-6c68-450e-9fe5-5032670484ff	c1d918d1-18d8-4837-a271-967d90f569a3	d9b0aa0dea4be7a763e3501c5c28669389ed125f6814baecf1b48794e194dce4	a40f8ce7-aebb-4be4-a327-949e213af8ec	857de350-44ad-44f1-be8e-dd7f7c12a436	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 04:02:44.166503+00	2025-12-26 04:02:44.166505+00	t	f	\N	\N	2025-11-26 04:02:44.166547+00
f67fa91e-45f2-4976-adae-e224f0d898e4	987fa969-961f-4afb-98aa-636c3448bd87	068644a853c30933b3f956436dcb79c785cbb67bcc1cc51db806c5a560410ef8	69a255ad-899f-4be1-8a03-fa5ed4f87455	54843567-72ba-402f-96dd-400c6420f528	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 04:03:22.406007+00	2025-12-26 04:03:22.406009+00	t	f	\N	\N	2025-11-26 04:03:22.40604+00
bbb728a7-07fa-4751-b856-0bfaaf7e9bfb	b46b4c47-31c6-4ad2-9829-0332963bb646	9d0d1717243a6eb3173987198a11aaec8e6dd8a114140858dc7b65a0931b3fa4	3eb38647-9f1a-4d4c-b513-16e6a87bc87f	bb5c2020-9827-4a31-a6d6-135c45cf6daf	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 04:04:56.025039+00	2025-12-26 04:04:56.025042+00	t	f	\N	\N	2025-11-26 04:04:56.025089+00
febe67b2-255d-4acb-aa43-685758065c5e	c1d918d1-18d8-4837-a271-967d90f569a3	e2d547653699cac6eabbef0bb999065daa392c061662844a4c1bb45dc2eeda9c	7c0a68a6-6b16-4d61-a31a-24d3963733f7	e14deacb-7863-4e96-9b0e-0a0eaf6578d0	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 04:02:54.873922+00	2025-12-26 04:02:54.873925+00	f	t	2025-11-26 04:16:56.505446+00	rotated	2025-11-26 04:16:56.311575+00
fd649ed7-f6b6-46a2-99e7-a7b4bf648de0	cd23d611-1644-4d29-b7b3-100f9458018c	d5ce6922d6cd20cb1197b28f1e932f20477fcdfcc3c39452592522ac650013ee	ef52ef4a-e45a-4970-8cfe-ed62afb85208	5a9475c2-1517-44d0-9eaf-84b34b635dce	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 04:20:13.252123+00	2025-12-26 04:20:13.252124+00	t	f	\N	\N	2025-11-26 04:20:13.252172+00
fb690732-1382-4ab3-a59b-297cbc45c956	987fa969-961f-4afb-98aa-636c3448bd87	de58087fe4d5edb03652bc4009fc2c7b683ac6630d0950880df0ad0c347da5a9	6e2c6d2d-690b-4f99-9070-a68920625132	a619238f-8544-4f7c-8e30-48fe00d470c8	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 04:20:33.02441+00	2025-12-26 04:20:33.024412+00	t	f	\N	\N	2025-11-26 04:20:33.024423+00
9985114a-9795-443a-8fbc-87a3504ae2e1	c1d918d1-18d8-4837-a271-967d90f569a3	c170739e969a11a162df76926a4db2ff99f45163de01f5a5d80e67ccb10cd7ff	b9c2107d-725e-474d-911f-4d07aabe8f98	e0bfeaf6-dc3e-47f3-a863-1bfcfd8014ff	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 04:22:07.913958+00	2025-12-26 04:22:07.913961+00	t	f	\N	\N	2025-11-26 04:22:07.91399+00
54b5729f-4978-4104-96fc-2041dfd87ab6	c1d918d1-18d8-4837-a271-967d90f569a3	0b57c4acb97664bf89e5a0b0c24c0f1db2f0c88cb06f73c78693349b365281f8	7c0a68a6-6b16-4d61-a31a-24d3963733f7	6f5a84b2-e8e9-4cb9-b8d9-8310336d86fe	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 04:31:26.841277+00	2025-12-26 04:31:26.841278+00	t	f	\N	\N	2025-11-26 04:31:26.841349+00
7d871ba7-0972-4b13-86b3-dad4fe989d19	c1d918d1-18d8-4837-a271-967d90f569a3	6417e3748d19b6b677865edcda9a60cc26700c45915d3a20d73c6c94d2c8ea63	7c0a68a6-6b16-4d61-a31a-24d3963733f7	67198b73-dbe6-4f5b-9227-1626f7e7f21a	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 04:16:56.505738+00	2025-12-26 04:16:56.505739+00	f	t	2025-11-26 04:31:26.840978+00	rotated	2025-11-26 04:31:26.631799+00
8c5e2930-9ccb-4b44-aaf6-dae6080600d7	cd23d611-1644-4d29-b7b3-100f9458018c	9f2d2df25890eb42aa0703bb43decc8dd20c65cb750ddb3b3b68ec793d533a61	d6d3ed76-7a62-4da6-97c6-26fe0c923841	b2dc17a7-8e49-41b8-b37e-626c7a7b8100	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 04:37:27.407611+00	2025-12-26 04:37:27.407613+00	t	f	\N	\N	2025-11-26 04:37:27.407655+00
1ee0ab8a-074b-477b-b479-2323eed180ac	c1d918d1-18d8-4837-a271-967d90f569a3	f6089d0bace7951aeef1d100e75583caeb31db44ebfc54668fb3649f0dcd2321	93a1d91c-1b8a-46ab-bdeb-afc34e1f8a1b	d23666c9-3172-42c4-b70e-03eb0da294ed	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 04:41:40.821425+00	2025-12-26 04:41:40.821427+00	t	f	\N	\N	2025-11-26 04:41:40.82148+00
dc0cc25a-fffb-4c17-8bd7-b169a3c95086	987fa969-961f-4afb-98aa-636c3448bd87	a2e83d9cf46c2ece6edfa55ae89cb92c464f92d9edae4341772c2ad14f1a3f06	c1e2bdde-d15b-4a23-aef5-291ebc8d89f5	ae28bbcd-912c-4a6e-9490-0ea5e89e1d4d	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 04:41:52.198219+00	2025-12-26 04:41:52.198221+00	t	f	\N	\N	2025-11-26 04:41:52.198236+00
7ef924a7-d0bd-4db8-8553-900c935b048c	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	41e13ed62a8bcd8397f6b82fc5cedba90c72b196a1e7a027359d9c818e208bca	f0a520e6-9eb2-4a94-bef8-91a333af26f4	96a138fc-2e04-475a-87f7-ce324d263124	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 04:41:56.681172+00	2025-12-26 04:41:56.681174+00	t	f	\N	\N	2025-11-26 04:41:56.681186+00
d914efd3-0ce7-41c4-a30a-b80903be704e	987fa969-961f-4afb-98aa-636c3448bd87	f0430bd0d2a7735e24734a344a17580d29c83d0b120f8440ea6d6464c3de2a0e	83a52b5b-039e-4bef-aeb6-eb980e90e9c7	7b428966-0b53-4f8a-a97b-f3ca93d008b4	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 05:20:12.204399+00	2025-12-26 05:20:12.204401+00	t	f	\N	\N	2025-11-26 05:20:12.20445+00
20d7c4a5-2da1-4f75-bb6e-fc63bc77a7b9	cd23d611-1644-4d29-b7b3-100f9458018c	fef482a3d4ceeddcece8d53f1cae70da7f14933326c3c0ea4f7f801f701b95b6	add92290-53f5-4788-b2c1-fbc534916f02	8a27fb22-5947-4cae-9fa2-fb6aec99dede	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 05:29:16.180599+00	2025-12-26 05:29:16.180601+00	t	f	\N	\N	2025-11-26 05:29:16.180654+00
de664dd2-231a-4314-ba63-3e2b547399e6	cd23d611-1644-4d29-b7b3-100f9458018c	12d15211ed73089a855975e9845ee2a657ec984ce30754f93b30644ebc9dbcbf	8d79fb75-abc6-48c7-8914-e7bb0b932b92	3c72a53a-7d52-45f4-ac25-499c18c5cc75	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 05:35:34.13357+00	2025-12-26 05:35:34.133571+00	t	f	\N	\N	2025-11-26 05:35:34.133619+00
32f7c59f-e28d-4d33-b9d8-5854a740bbb2	cd23d611-1644-4d29-b7b3-100f9458018c	f92fe13dbad960483301006a0e6ac4760fdfc12fed0ddeea465e70c33ed6ff97	74e2d01e-53d9-43a4-9498-5393c4f22590	df8748b1-7cb2-4d7e-8b59-a2b499e5a2a6	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 05:35:59.090606+00	2025-12-26 05:35:59.090608+00	f	t	2025-11-26 05:50:03.165808+00	rotated	2025-11-26 05:50:02.985986+00
89a7dbd1-708c-4023-bb43-020ca6891d50	987fa969-961f-4afb-98aa-636c3448bd87	95284dab0ed0245c605dc4ddeba228a8acc67b9c3a51788236b63573283841d3	7ca28898-8348-4901-90a4-17e395ab06a1	5b550fd2-f156-493f-8515-3edd393eda19	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 05:37:52.177931+00	2025-12-26 05:37:52.177934+00	f	t	2025-11-26 05:51:55.46089+00	rotated	2025-11-26 05:51:55.263338+00
441b06a8-d789-4352-8cbe-9e176eb2ac84	c1d918d1-18d8-4837-a271-967d90f569a3	ee318190ee1d4d5e9251020c8638d8cda3f5b7c5da1f99f10daf35f73fcd432d	a702983f-d918-477c-b37b-e882543a9598	168a11eb-6ac5-4703-9f75-df5707fe5446	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 05:39:22.065321+00	2025-12-26 05:39:22.065334+00	t	f	\N	\N	2025-11-26 05:39:22.06538+00
5522c029-331f-4283-a697-e6271ab36b1c	c1d918d1-18d8-4837-a271-967d90f569a3	b318daa46907e227811b03a656b5a9fe16833e365091d8331f1b271675ea6622	bbadc67b-2c86-4411-9b9c-c4e7b42f7020	1d7b6e80-1722-4916-b012-532e56a47dfe	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 05:44:15.633113+00	2025-12-26 05:44:15.633121+00	t	f	\N	\N	2025-11-26 05:44:15.63317+00
79b8ce07-6750-46b0-9f58-e3b652085821	987fa969-961f-4afb-98aa-636c3448bd87	95bf49f51569e3518d6ade8df61a7e5106508653b4b863ded823816558319b4b	ac89ceed-d740-40c4-8e12-559c823782b2	a3b12f52-c1b0-45e2-819b-7869a494b555	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 05:46:23.345659+00	2025-12-26 05:46:23.345661+00	t	f	\N	\N	2025-11-26 05:46:23.345723+00
ce1e94e6-10ec-4b11-bc66-24efed5d6278	cd23d611-1644-4d29-b7b3-100f9458018c	2f5f791142d5494ff487ed574da9810cb3ad8b1464b0ed1cb342d84a135c5ef1	74e2d01e-53d9-43a4-9498-5393c4f22590	27c7c627-7fd4-4d2d-90dc-513705367a32	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 05:50:03.166081+00	2025-12-26 05:50:03.166082+00	t	f	\N	\N	2025-11-26 05:50:03.166152+00
8cb3f316-9809-4913-a61f-553d7df2d067	987fa969-961f-4afb-98aa-636c3448bd87	dec8eb1e7876a8ceaf0bd56a0e7d24fbcfb4433407f76fe67fff08b2e35524a1	7ca28898-8348-4901-90a4-17e395ab06a1	6a8652a1-bde1-457f-ae39-77f47ce7c2da	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0	2025-11-26 05:51:55.461132+00	2025-12-26 05:51:55.461132+00	t	f	\N	\N	2025-11-26 05:51:55.461156+00
0795b208-18e5-4c5e-a534-8b94db26d6c5	c1d918d1-18d8-4837-a271-967d90f569a3	a6a538aa310d8f238e3888f8b19eb1550ebf1b77ebc392bb0306b112d711e488	c414ef78-2547-4822-978c-5eab06f23cc3	2ca3214d-8de0-4d48-b306-10385d3e2019	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 05:55:26.371414+00	2025-12-26 05:55:26.371415+00	t	f	\N	\N	2025-11-26 05:55:26.371468+00
cfe2ef79-90e4-4c0d-b63c-ae112a0dec62	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	1a0a91153cf698471dc673ebe27ac3c711e46fee8d386c01be448c0f89ba790d	1f2ff33f-d9e0-449c-a015-8ef209114ec4	0361016a-0922-477a-845d-6a1746a94bda	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 06:12:24.395778+00	2025-12-26 06:12:24.39578+00	t	f	\N	\N	2025-11-26 06:12:24.395817+00
b433047f-2468-4edc-8985-8ea42fefe4e5	cd23d611-1644-4d29-b7b3-100f9458018c	c6ded47c284bed2ebb847cc1e1ea059896dc5743bd1b10c34e2b229ad12c7305	9bee5cf8-282f-474d-969e-7f96cfe38085	1b8bafff-6f85-4923-b060-dbbb8630d1ef	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 06:12:40.639612+00	2025-12-26 06:12:40.639614+00	t	f	\N	\N	2025-11-26 06:12:40.639633+00
20f42ff4-b2cf-4802-b2b0-e382399f8e4c	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	dc1321d09e6036d45fb66e9ec5b57a775ecde408ce23fc3c51a244f8cbdb6624	59405bce-b672-462b-90af-c5c929f068e3	3542409b-505b-414e-801a-fe4dd01bf063	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 06:12:58.905569+00	2025-12-26 06:12:58.90558+00	t	f	\N	\N	2025-11-26 06:12:58.905624+00
a0da2f89-49f4-4481-b509-e01cd155c464	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	5e47455d39c8e7bdb198b32ed69f44c64f6eecce99d583dda48cdad1f2a2736a	ff691d1c-e100-4b05-a5c6-5ba25c2bb329	7fcf8831-ebb9-42a9-b61d-bce80a389d29	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 06:23:03.476093+00	2025-12-26 06:23:03.476095+00	t	f	\N	\N	2025-11-26 06:23:03.476133+00
0137176a-facf-4181-89d6-2d29906995cc	cd23d611-1644-4d29-b7b3-100f9458018c	6964357d04389123dee09badd7efde069237841acab0dd525f2b977671f74ded	51c42b28-091f-4120-a2b3-f75881654070	ea2e3f98-1b21-47ae-af63-da3c7a75feb6	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 06:38:51.982471+00	2025-12-26 06:38:51.982472+00	t	f	\N	\N	2025-11-26 06:38:51.982527+00
e63e318a-25ab-449f-a936-9c7e736d9d07	cd23d611-1644-4d29-b7b3-100f9458018c	630cac0bde0c83df2329dcbdb61544b02323b94de0dfe24afca391940e7c73b6	51c42b28-091f-4120-a2b3-f75881654070	2809a23b-6f94-409f-aa48-ae262d0c7374	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 06:24:49.511975+00	2025-12-26 06:24:49.511978+00	f	t	2025-11-26 06:38:51.982017+00	rotated	2025-11-26 06:38:51.75846+00
14ae237b-af55-4089-a005-59be45b41077	c1d918d1-18d8-4837-a271-967d90f569a3	798190f47ac58ac64acb2450b045523471928901faaeaef549685223871715ee	5f51bf00-0a64-4c87-bd24-b15625f34884	693daef9-cf15-4338-b069-09247b2ffe1f	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 06:53:25.31826+00	2025-12-26 06:53:25.318262+00	t	f	\N	\N	2025-11-26 06:53:25.31833+00
895efd84-8cf3-47c9-afdd-1a8e4033e624	cd23d611-1644-4d29-b7b3-100f9458018c	b2fdedbab6114793a695b19d8ea4db888d4836966f47c76d16d9b6ad7b4b5972	87757471-1cce-4298-aeb0-c74c33d010a0	f979670c-62f0-4931-9c49-014634fb8306	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 07:01:29.298446+00	2025-12-26 07:01:29.298449+00	t	f	\N	\N	2025-11-26 07:01:29.298472+00
b64e5593-3c2d-4592-9fd0-fcf1789af774	987fa969-961f-4afb-98aa-636c3448bd87	68950521c49a6f0579a6714fffbffb717a44db935d501ae2c01dd22e845b1eba	b06e7731-a197-434b-8617-dcb21480f3d4	15a597f2-c8e0-413c-8bfa-676b762bd2d7	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 06:59:16.014726+00	2025-12-26 06:59:16.014728+00	f	t	2025-11-26 07:13:45.035448+00	rotated	2025-11-26 07:13:44.829363+00
0dd3e9ab-dd0f-4ae5-b482-5ba33fcb447a	c1d918d1-18d8-4837-a271-967d90f569a3	76ccaf59efe920b8f807f470b9000ff49a445c829a0e06f88583a6fafa6c79e5	9bca969d-c48e-483f-b9d2-5ab1892618f4	6e741d00-a847-43f6-9aa3-c00b7f4ad7db	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 07:00:24.592865+00	2025-12-26 07:00:24.592867+00	f	t	2025-11-26 07:14:34.172587+00	rotated	2025-11-26 07:14:33.948269+00
649113c7-b452-4a81-aedf-e72e3ed97f26	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	af7289df68ed13edcc20858c3e430f5f0252a11887e63a1a07c1b23bafe9276f	8c9766bb-75c3-4916-ac06-acf60e061669	bd9f498f-a3fe-4170-8bc8-5098fbc7a4a6	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 07:21:43.982465+00	2025-12-26 07:21:43.982468+00	t	f	\N	\N	2025-11-26 07:21:43.982509+00
d0141817-a597-4e56-8759-b10b2a60d4e4	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	aa4e5286d5c32c4d790f9514af5a7af5c195fd75b3be6a51701b10a6e22a7cfc	3a1ef5b1-1a9d-4459-a870-d8f255c290d6	60a808ae-9b12-42cf-a7b3-a3c30897656a	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 07:22:23.985759+00	2025-12-26 07:22:23.985761+00	t	f	\N	\N	2025-11-26 07:22:23.985781+00
80e521ae-a6ea-48fb-9d1f-5fe5ae604068	c1d918d1-18d8-4837-a271-967d90f569a3	9bbc913ade93128bfcde1ea11be8e6de39342de65d4c3644482c2cb97fa94abc	9bca969d-c48e-483f-b9d2-5ab1892618f4	77c76f0c-843b-4813-9baa-3649d6c25c1e	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 07:28:36.250062+00	2025-12-26 07:28:36.250063+00	t	f	\N	\N	2025-11-26 07:28:36.250093+00
aa997d77-dc9f-4753-b374-1635f7991e13	c1d918d1-18d8-4837-a271-967d90f569a3	f29e220ec81ea183435ad28e45e2820d7f37abc7a8e67795ed1f0e4c8fb54ec4	9bca969d-c48e-483f-b9d2-5ab1892618f4	d782dcb6-4ea2-4ee9-9cd1-9a42fb50c75a	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 07:14:34.172824+00	2025-12-26 07:14:34.172825+00	f	t	2025-11-26 07:28:36.24974+00	rotated	2025-11-26 07:28:36.054989+00
d22afc3d-5a11-4b25-b24d-8f8fd1be0ca3	987fa969-961f-4afb-98aa-636c3448bd87	b6c8a9787be909436a7e27ac20416315902b9d777e93e4f57862f22ef456a01d	b06e7731-a197-434b-8617-dcb21480f3d4	4c3e427d-ad4a-4eb2-8946-4d5af74ec6f6	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 07:13:45.035749+00	2025-12-26 07:13:45.035749+00	f	t	2025-11-26 07:28:37.518347+00	rotated	2025-11-26 07:28:37.286373+00
d559d722-ad9f-4dac-8489-f731003a5f9b	987fa969-961f-4afb-98aa-636c3448bd87	696dc241ed72e10b38ed89423cbcb535697602154c6a312d0d2ec7b1daf3e1ec	b06e7731-a197-434b-8617-dcb21480f3d4	9d5f0650-3e92-431d-abf1-2a69bc53d634	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 07:28:37.518589+00	2025-12-26 07:28:37.51859+00	f	t	2025-11-26 07:42:43.203702+00	rotated	2025-11-26 07:42:43.005105+00
8c0d8d29-4821-4c03-b7b1-7dca785fb7da	987fa969-961f-4afb-98aa-636c3448bd87	40ea406289b92959a892026059c671cfc35f7ff0d25186434c13d9d1b86f8755	b06e7731-a197-434b-8617-dcb21480f3d4	a1a24169-06e9-4792-8b5b-cf050d4dc09a	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 07:56:48.519895+00	2025-12-26 07:56:48.519896+00	t	f	\N	\N	2025-11-26 07:56:48.51995+00
98f9d77c-d129-4421-a211-2df0b4a56ffa	987fa969-961f-4afb-98aa-636c3448bd87	dedfe43269096c36251651c870f3b233444f1800c6906987c4c5c20596907e3c	b06e7731-a197-434b-8617-dcb21480f3d4	bf222014-1a04-4423-96ee-fbfc03a9c36e	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 07:42:43.203976+00	2025-12-26 07:42:43.203976+00	f	t	2025-11-26 07:56:48.519591+00	rotated	2025-11-26 07:56:48.27165+00
b38dc886-6898-41c3-9b4a-802eb07803f1	c1d918d1-18d8-4837-a271-967d90f569a3	74cde9c593092a2f6a54372e7b05928b6d9b117216a27d35f471c9945f108a63	d8bab7a2-17bb-49b2-b268-860862e11e30	b2093aa3-8584-4858-b52a-da6e73629e9b	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 08:01:06.635154+00	2025-12-26 08:01:06.635154+00	t	f	\N	\N	2025-11-26 08:01:06.635176+00
06ecefdf-830d-4d27-b818-9d1bd05d6327	c1d918d1-18d8-4837-a271-967d90f569a3	0c8faa76bb63a7184106c94370373c6599ab7989bdfbca05c2c43d1aaba0747b	d8bab7a2-17bb-49b2-b268-860862e11e30	2c4e33ca-d69a-499f-91f5-b7b9079260f6	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 07:47:02.999367+00	2025-12-26 07:47:02.99937+00	f	t	2025-11-26 08:01:06.634897+00	rotated	2025-11-26 08:01:06.441059+00
ccf3e091-4381-41d2-bf08-9e3359f29dc7	4135dbcc-c6fb-4781-afb3-90ee621dd9f4	feb7a864dc5d21e8dbd4fba181ee3d5e6e00baefd69cebba356d6144e4ea4b4e	390f7314-4b8c-44d5-9d93-21a8d6c98d0a	ecb68227-8c2f-4d80-8f42-51d72c184abc	171.253.25.31	Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36	2025-11-26 08:29:26.606581+00	2025-12-26 08:29:26.606584+00	t	f	\N	\N	2025-11-26 08:29:26.606633+00
8e6768d6-4621-40e5-901f-f6272c311dd7	c1d918d1-18d8-4837-a271-967d90f569a3	0500f056c1492dd592656622efda28c0fafd73c69996d71803804b624a360478	bb360746-45be-4825-ae1c-6049eaca1801	145e7aab-8313-4348-9159-42bd200d2c96	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 08:30:24.967398+00	2025-12-26 08:30:24.967399+00	t	f	\N	\N	2025-11-26 08:30:24.967411+00
84381b07-28d4-4d72-8be5-3591a479a8b2	c1d918d1-18d8-4837-a271-967d90f569a3	aa9609f419bf2baa2b1e5ca0acb63974e09c194709ea1dd0a628e9d6703ba8f7	bb360746-45be-4825-ae1c-6049eaca1801	626efe56-9c13-4a51-af75-c39844ac5d80	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 08:16:22.587887+00	2025-12-26 08:16:22.5879+00	f	t	2025-11-26 08:30:24.967099+00	rotated	2025-11-26 08:30:24.789574+00
7008fdbe-2947-425f-9885-9d61067f2e26	c1d918d1-18d8-4837-a271-967d90f569a3	96a3d5529b8fb6f63329f12a4dcc1f5d2ae13e4e7707e6a3a86b4087d6133755	395ca9b3-ddca-478f-aa18-789754a68d40	228c1639-7385-4f34-b325-f50aa5348deb	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 08:44:00.268754+00	2025-12-26 08:44:00.268756+00	t	f	\N	\N	2025-11-26 08:44:00.268799+00
6c32e574-02f5-4dca-9a7f-5eb28a4ba1ad	c1d918d1-18d8-4837-a271-967d90f569a3	fd5f43de52720a079d4b22e1da943f18153388f7580941451abb8cdb1035a46b	9929e92c-4ecc-4e98-b552-512aef45f938	ad19cce8-bc17-48ec-873b-0cd08b0d7e00	210.245.98.228	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 09:00:25.654648+00	2025-12-26 09:00:25.65465+00	t	f	\N	\N	2025-11-26 09:00:25.654671+00
41ec1adb-2c16-4a49-aa2b-ed19bf75d9a7	c1d918d1-18d8-4837-a271-967d90f569a3	290659be69c4b57665f1932e27be50db803c445b8a9873b05fec133dd00cb57a	0f154c46-f973-43c9-b92e-cb3da46d2e0e	62003f6a-80cd-43fc-8e57-536ffa3635c3	113.161.234.220	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 09:01:08.775817+00	2025-12-26 09:01:08.775819+00	t	f	\N	\N	2025-11-26 09:01:08.775848+00
f0a181ff-6b46-4e00-8445-6d7103175be2	c1d918d1-18d8-4837-a271-967d90f569a3	e91c51ce33190682e9c75050ec83ea8beef606e332bae982a56ea18e3066a16c	c132e803-1bd1-4e2d-9c14-ff16888a93e8	87c5a6b3-2fcc-4af8-af80-2511618f41b3	118.69.128.8	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36	2025-11-26 09:04:01.676818+00	2025-12-26 09:04:01.67682+00	t	f	\N	\N	2025-11-26 09:04:01.676874+00
\.


--
-- TOC entry 3781 (class 0 OID 33052)
-- Dependencies: 227
-- Data for Name: role_privileges; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.role_privileges (role_id, privilege_id) FROM stdin;
df87d5fc-0380-4b85-812e-d433bf6ab91a	10fd436d-5d52-4ad0-84e0-238a1540e886
df87d5fc-0380-4b85-812e-d433bf6ab91a	33e1c04b-8c5e-4cca-9ddc-fa3a850ab4ed
df87d5fc-0380-4b85-812e-d433bf6ab91a	534f9f40-1f79-449f-97bc-eccd51b044d1
df87d5fc-0380-4b85-812e-d433bf6ab91a	6302e164-34d8-4aa9-9a27-2ea418ca57e5
df87d5fc-0380-4b85-812e-d433bf6ab91a	1b75216d-fd16-4dea-a329-82131d0542d0
df87d5fc-0380-4b85-812e-d433bf6ab91a	525da488-8586-4710-b584-4c5417be4361
df87d5fc-0380-4b85-812e-d433bf6ab91a	7e487309-ac5c-4223-abb3-a1cf1007d4ad
df87d5fc-0380-4b85-812e-d433bf6ab91a	76021b2a-b5ba-4db5-84ba-1b8d426d227b
df87d5fc-0380-4b85-812e-d433bf6ab91a	ae861974-9e7d-49da-af85-1f80c2614f2d
6369cadd-88f3-4879-9478-b11e3e53d1a7	77cb55f9-c0de-4887-9bbe-3192e0110b48
6369cadd-88f3-4879-9478-b11e3e53d1a7	76021b2a-b5ba-4db5-84ba-1b8d426d227b
6369cadd-88f3-4879-9478-b11e3e53d1a7	33e1c04b-8c5e-4cca-9ddc-fa3a850ab4ed
6369cadd-88f3-4879-9478-b11e3e53d1a7	525da488-8586-4710-b584-4c5417be4361
d24c97cb-ead8-447c-8318-4631fdc928a2	76021b2a-b5ba-4db5-84ba-1b8d426d227b
cc49e2f1-cdb2-42bd-9776-b641a22529bf	525da488-8586-4710-b584-4c5417be4361
cc49e2f1-cdb2-42bd-9776-b641a22529bf	475cddfe-0b9d-488d-aa16-93bc51f0a9ac
cc49e2f1-cdb2-42bd-9776-b641a22529bf	6e8df40a-8c61-4499-a323-a1484fc728b4
cc49e2f1-cdb2-42bd-9776-b641a22529bf	33e1c04b-8c5e-4cca-9ddc-fa3a850ab4ed
cc49e2f1-cdb2-42bd-9776-b641a22529bf	e4d4f092-7149-4d54-bdd9-c3469e2fadc0
cc49e2f1-cdb2-42bd-9776-b641a22529bf	26028ba2-9b3d-49d2-930a-50a4d3f7c6e1
cc49e2f1-cdb2-42bd-9776-b641a22529bf	afedd297-90a6-4301-a948-760abfff586d
d24c97cb-ead8-447c-8318-4631fdc928a2	85cd9809-2aa6-4164-ab59-b5bb84e77746
d24c97cb-ead8-447c-8318-4631fdc928a2	7d3a8dfd-68a8-435c-8653-555ac23197d3
d24c97cb-ead8-447c-8318-4631fdc928a2	26028ba2-9b3d-49d2-930a-50a4d3f7c6e1
d24c97cb-ead8-447c-8318-4631fdc928a2	8c419f65-6604-4b42-87ce-02d3852a80e3
d24c97cb-ead8-447c-8318-4631fdc928a2	61ecfee8-5e1f-455b-9f44-630fd4fe41f7
cc49e2f1-cdb2-42bd-9776-b641a22529bf	afa4572f-fe95-4822-af5f-58e1e5bc265d
cc49e2f1-cdb2-42bd-9776-b641a22529bf	b21b3404-ca22-4cd8-b358-537c2eea6540
cc49e2f1-cdb2-42bd-9776-b641a22529bf	37c5bff7-38fb-498e-b3a5-328b36b14b83
cc49e2f1-cdb2-42bd-9776-b641a22529bf	76021b2a-b5ba-4db5-84ba-1b8d426d227b
cc49e2f1-cdb2-42bd-9776-b641a22529bf	77379757-4023-4299-b90c-beecc8534924
cc49e2f1-cdb2-42bd-9776-b641a22529bf	8307e64f-a352-4824-b901-6e592aa900f6
cc49e2f1-cdb2-42bd-9776-b641a22529bf	3de0222f-006a-4bb5-b579-53113f15a455
cc49e2f1-cdb2-42bd-9776-b641a22529bf	2b601aaa-5463-47af-8858-f510a9d7d291
cc49e2f1-cdb2-42bd-9776-b641a22529bf	8c419f65-6604-4b42-87ce-02d3852a80e3
cc49e2f1-cdb2-42bd-9776-b641a22529bf	eb4aa561-e719-458c-83f2-d5f38519fec0
cc49e2f1-cdb2-42bd-9776-b641a22529bf	45bec9a1-53b3-486d-b414-e2f5dc97fa7a
cc49e2f1-cdb2-42bd-9776-b641a22529bf	04c9e7de-3536-43c9-b009-c608764d72d5
d24c97cb-ead8-447c-8318-4631fdc928a2	f21e0710-0c2f-472b-8904-b3abecca9aad
d24c97cb-ead8-447c-8318-4631fdc928a2	33e1c04b-8c5e-4cca-9ddc-fa3a850ab4ed
d24c97cb-ead8-447c-8318-4631fdc928a2	45bec9a1-53b3-486d-b414-e2f5dc97fa7a
d24c97cb-ead8-447c-8318-4631fdc928a2	011748ae-74a0-42e5-baa3-3dda8ac90ccc
d24c97cb-ead8-447c-8318-4631fdc928a2	183c05fc-cd78-403b-8f5a-dd026a1122d3
d24c97cb-ead8-447c-8318-4631fdc928a2	3de0222f-006a-4bb5-b579-53113f15a455
d24c97cb-ead8-447c-8318-4631fdc928a2	04c9e7de-3536-43c9-b009-c608764d72d5
d24c97cb-ead8-447c-8318-4631fdc928a2	1b75216d-fd16-4dea-a329-82131d0542d0
d24c97cb-ead8-447c-8318-4631fdc928a2	cd944cee-9a4b-4ef7-a952-c30d048a86ab
d24c97cb-ead8-447c-8318-4631fdc928a2	622c94fc-23ab-496a-a659-d07ed4c1d9d1
d24c97cb-ead8-447c-8318-4631fdc928a2	77cb55f9-c0de-4887-9bbe-3192e0110b48
d24c97cb-ead8-447c-8318-4631fdc928a2	faeaecd0-6dfd-46bf-b0cf-6862ea800890
d24c97cb-ead8-447c-8318-4631fdc928a2	21e34022-4e5f-4409-9a61-e73c8332859a
d24c97cb-ead8-447c-8318-4631fdc928a2	10fd436d-5d52-4ad0-84e0-238a1540e886
d24c97cb-ead8-447c-8318-4631fdc928a2	6302e164-34d8-4aa9-9a27-2ea418ca57e5
d24c97cb-ead8-447c-8318-4631fdc928a2	de3d2157-11a1-4a7e-9d78-34551a97238b
d24c97cb-ead8-447c-8318-4631fdc928a2	128531c7-903d-43e4-814d-895bd0bea3fe
d24c97cb-ead8-447c-8318-4631fdc928a2	37c5bff7-38fb-498e-b3a5-328b36b14b83
d24c97cb-ead8-447c-8318-4631fdc928a2	7e487309-ac5c-4223-abb3-a1cf1007d4ad
d24c97cb-ead8-447c-8318-4631fdc928a2	197480b6-56e5-451f-bc2d-d9a3908abe85
d24c97cb-ead8-447c-8318-4631fdc928a2	eb4aa561-e719-458c-83f2-d5f38519fec0
d24c97cb-ead8-447c-8318-4631fdc928a2	7b8123ce-4091-4d5b-9733-6ae53710040a
d24c97cb-ead8-447c-8318-4631fdc928a2	a7dc0f69-59e6-4228-b5f2-78fdbbe58707
d24c97cb-ead8-447c-8318-4631fdc928a2	db82b74c-5364-4818-a567-eafa8c98303c
d24c97cb-ead8-447c-8318-4631fdc928a2	77379757-4023-4299-b90c-beecc8534924
d24c97cb-ead8-447c-8318-4631fdc928a2	b21b3404-ca22-4cd8-b358-537c2eea6540
d24c97cb-ead8-447c-8318-4631fdc928a2	534f9f40-1f79-449f-97bc-eccd51b044d1
d24c97cb-ead8-447c-8318-4631fdc928a2	093c997a-e924-42e2-83d1-3f1afdfb5051
d24c97cb-ead8-447c-8318-4631fdc928a2	b21ac688-9834-4291-8174-440657f23927
d24c97cb-ead8-447c-8318-4631fdc928a2	2ef43e9d-0eac-49c7-bd70-78bde0e9d689
d24c97cb-ead8-447c-8318-4631fdc928a2	ae861974-9e7d-49da-af85-1f80c2614f2d
d24c97cb-ead8-447c-8318-4631fdc928a2	475cddfe-0b9d-488d-aa16-93bc51f0a9ac
d24c97cb-ead8-447c-8318-4631fdc928a2	8fb89f3a-7b6a-489f-80cc-737f1d16fb8b
d24c97cb-ead8-447c-8318-4631fdc928a2	dfd1216f-7c06-4e82-8839-cf4c0aac41f1
d24c97cb-ead8-447c-8318-4631fdc928a2	3eca6b24-ac69-49b8-b1f2-d39413b47098
d24c97cb-ead8-447c-8318-4631fdc928a2	bd2c5881-2153-4fa5-87ac-74c956251952
d24c97cb-ead8-447c-8318-4631fdc928a2	b0534608-9be9-4343-8bd7-f09b36df1d2a
d24c97cb-ead8-447c-8318-4631fdc928a2	4df6d823-e27b-4039-9c99-ef950664b418
d24c97cb-ead8-447c-8318-4631fdc928a2	396b577b-36af-42e4-8103-46717b6611d4
d24c97cb-ead8-447c-8318-4631fdc928a2	2792802f-4f5c-41c6-a91e-bffaae95fe4c
d24c97cb-ead8-447c-8318-4631fdc928a2	afa4572f-fe95-4822-af5f-58e1e5bc265d
d24c97cb-ead8-447c-8318-4631fdc928a2	2b601aaa-5463-47af-8858-f510a9d7d291
d24c97cb-ead8-447c-8318-4631fdc928a2	7dd0003f-a9bb-4f9a-8fef-6574b8dc18a3
d24c97cb-ead8-447c-8318-4631fdc928a2	d5ed06c2-bc5a-4c54-ac79-890689344d6f
d24c97cb-ead8-447c-8318-4631fdc928a2	525da488-8586-4710-b584-4c5417be4361
d24c97cb-ead8-447c-8318-4631fdc928a2	e200f22c-7498-4014-9cf5-709dfd83d4f5
d24c97cb-ead8-447c-8318-4631fdc928a2	afedd297-90a6-4301-a948-760abfff586d
d24c97cb-ead8-447c-8318-4631fdc928a2	6165fe2d-d3bf-43b9-af1a-71432ba65ff7
d24c97cb-ead8-447c-8318-4631fdc928a2	a995e224-4f27-402e-a0ce-d1cd93ee9673
d24c97cb-ead8-447c-8318-4631fdc928a2	71b0b31a-f254-4192-8f5c-bf6555db4ad0
d24c97cb-ead8-447c-8318-4631fdc928a2	3feb5a19-d45c-451f-8de3-88965a3ce576
d24c97cb-ead8-447c-8318-4631fdc928a2	6e8df40a-8c61-4499-a323-a1484fc728b4
d24c97cb-ead8-447c-8318-4631fdc928a2	8307e64f-a352-4824-b901-6e592aa900f6
d24c97cb-ead8-447c-8318-4631fdc928a2	8f48d2cb-cd76-45ec-af2d-73efa8dde299
d24c97cb-ead8-447c-8318-4631fdc928a2	95d8769a-eb52-4346-b175-1ecd4d235b48
d24c97cb-ead8-447c-8318-4631fdc928a2	e0f990cd-78d3-40a2-b753-21a381b12b60
d24c97cb-ead8-447c-8318-4631fdc928a2	e4d4f092-7149-4d54-bdd9-c3469e2fadc0
d24c97cb-ead8-447c-8318-4631fdc928a2	b0e0973d-c22d-44b8-8d16-3c5a087dbd15
d24c97cb-ead8-447c-8318-4631fdc928a2	d991316b-7baf-485a-803d-f76c7f85df32
d24c97cb-ead8-447c-8318-4631fdc928a2	c80718c9-f972-4eaa-80ec-6fc5e77f0c20
5d6c50ef-851b-4ea8-985b-2a94bea662c8	3de0222f-006a-4bb5-b579-53113f15a455
5d6c50ef-851b-4ea8-985b-2a94bea662c8	45bec9a1-53b3-486d-b414-e2f5dc97fa7a
5d6c50ef-851b-4ea8-985b-2a94bea662c8	a995e224-4f27-402e-a0ce-d1cd93ee9673
5d6c50ef-851b-4ea8-985b-2a94bea662c8	bd2c5881-2153-4fa5-87ac-74c956251952
5d6c50ef-851b-4ea8-985b-2a94bea662c8	04c9e7de-3536-43c9-b009-c608764d72d5
5d6c50ef-851b-4ea8-985b-2a94bea662c8	37c5bff7-38fb-498e-b3a5-328b36b14b83
5d6c50ef-851b-4ea8-985b-2a94bea662c8	8307e64f-a352-4824-b901-6e592aa900f6
5d6c50ef-851b-4ea8-985b-2a94bea662c8	afedd297-90a6-4301-a948-760abfff586d
5d6c50ef-851b-4ea8-985b-2a94bea662c8	eb4aa561-e719-458c-83f2-d5f38519fec0
5d6c50ef-851b-4ea8-985b-2a94bea662c8	e4d4f092-7149-4d54-bdd9-c3469e2fadc0
5d6c50ef-851b-4ea8-985b-2a94bea662c8	33e1c04b-8c5e-4cca-9ddc-fa3a850ab4ed
5d6c50ef-851b-4ea8-985b-2a94bea662c8	8c419f65-6604-4b42-87ce-02d3852a80e3
5d6c50ef-851b-4ea8-985b-2a94bea662c8	475cddfe-0b9d-488d-aa16-93bc51f0a9ac
5d6c50ef-851b-4ea8-985b-2a94bea662c8	d5ed06c2-bc5a-4c54-ac79-890689344d6f
5d6c50ef-851b-4ea8-985b-2a94bea662c8	093c997a-e924-42e2-83d1-3f1afdfb5051
5d6c50ef-851b-4ea8-985b-2a94bea662c8	26028ba2-9b3d-49d2-930a-50a4d3f7c6e1
5d6c50ef-851b-4ea8-985b-2a94bea662c8	77379757-4023-4299-b90c-beecc8534924
5d6c50ef-851b-4ea8-985b-2a94bea662c8	ae861974-9e7d-49da-af85-1f80c2614f2d
5d6c50ef-851b-4ea8-985b-2a94bea662c8	de3d2157-11a1-4a7e-9d78-34551a97238b
5d6c50ef-851b-4ea8-985b-2a94bea662c8	2ef43e9d-0eac-49c7-bd70-78bde0e9d689
5d6c50ef-851b-4ea8-985b-2a94bea662c8	b0e0973d-c22d-44b8-8d16-3c5a087dbd15
5d6c50ef-851b-4ea8-985b-2a94bea662c8	b21b3404-ca22-4cd8-b358-537c2eea6540
5d6c50ef-851b-4ea8-985b-2a94bea662c8	c80718c9-f972-4eaa-80ec-6fc5e77f0c20
5d6c50ef-851b-4ea8-985b-2a94bea662c8	2792802f-4f5c-41c6-a91e-bffaae95fe4c
5d6c50ef-851b-4ea8-985b-2a94bea662c8	95d8769a-eb52-4346-b175-1ecd4d235b48
5d6c50ef-851b-4ea8-985b-2a94bea662c8	76021b2a-b5ba-4db5-84ba-1b8d426d227b
5d6c50ef-851b-4ea8-985b-2a94bea662c8	622c94fc-23ab-496a-a659-d07ed4c1d9d1
5d6c50ef-851b-4ea8-985b-2a94bea662c8	3eca6b24-ac69-49b8-b1f2-d39413b47098
5d6c50ef-851b-4ea8-985b-2a94bea662c8	db82b74c-5364-4818-a567-eafa8c98303c
5d6c50ef-851b-4ea8-985b-2a94bea662c8	396b577b-36af-42e4-8103-46717b6611d4
5d6c50ef-851b-4ea8-985b-2a94bea662c8	b7cf08b2-86bf-4c20-9a2a-93e3f0634db1
5d6c50ef-851b-4ea8-985b-2a94bea662c8	128531c7-903d-43e4-814d-895bd0bea3fe
5d6c50ef-851b-4ea8-985b-2a94bea662c8	71b0b31a-f254-4192-8f5c-bf6555db4ad0
5d6c50ef-851b-4ea8-985b-2a94bea662c8	525da488-8586-4710-b584-4c5417be4361
5d6c50ef-851b-4ea8-985b-2a94bea662c8	011748ae-74a0-42e5-baa3-3dda8ac90ccc
5d6c50ef-851b-4ea8-985b-2a94bea662c8	dfd1216f-7c06-4e82-8839-cf4c0aac41f1
5d6c50ef-851b-4ea8-985b-2a94bea662c8	77cb55f9-c0de-4887-9bbe-3192e0110b48
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	95d8769a-eb52-4346-b175-1ecd4d235b48
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	d5ed06c2-bc5a-4c54-ac79-890689344d6f
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	bbe5f22c-bb3c-4722-b604-f28b2bd674a7
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	6e8df40a-8c61-4499-a323-a1484fc728b4
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	2ef43e9d-0eac-49c7-bd70-78bde0e9d689
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	26028ba2-9b3d-49d2-930a-50a4d3f7c6e1
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	525da488-8586-4710-b584-4c5417be4361
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	33e1c04b-8c5e-4cca-9ddc-fa3a850ab4ed
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	3eca6b24-ac69-49b8-b1f2-d39413b47098
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	475cddfe-0b9d-488d-aa16-93bc51f0a9ac
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	afedd297-90a6-4301-a948-760abfff586d
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	622c94fc-23ab-496a-a659-d07ed4c1d9d1
5d6c50ef-851b-4ea8-985b-2a94bea662c8	bbe5f22c-bb3c-4722-b604-f28b2bd674a7
5d6c50ef-851b-4ea8-985b-2a94bea662c8	b21ac688-9834-4291-8174-440657f23927
5d6c50ef-851b-4ea8-985b-2a94bea662c8	afa4572f-fe95-4822-af5f-58e1e5bc265d
5d6c50ef-851b-4ea8-985b-2a94bea662c8	6e8df40a-8c61-4499-a323-a1484fc728b4
5d6c50ef-851b-4ea8-985b-2a94bea662c8	2b601aaa-5463-47af-8858-f510a9d7d291
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	8c419f65-6604-4b42-87ce-02d3852a80e3
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	37c5bff7-38fb-498e-b3a5-328b36b14b83
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	b0e0973d-c22d-44b8-8d16-3c5a087dbd15
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	a995e224-4f27-402e-a0ce-d1cd93ee9673
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	b21b3404-ca22-4cd8-b358-537c2eea6540
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	e4d4f092-7149-4d54-bdd9-c3469e2fadc0
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	7d3a8dfd-68a8-435c-8653-555ac23197d3
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	76021b2a-b5ba-4db5-84ba-1b8d426d227b
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	dfd1216f-7c06-4e82-8839-cf4c0aac41f1
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	2792802f-4f5c-41c6-a91e-bffaae95fe4c
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	3de0222f-006a-4bb5-b579-53113f15a455
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	de3d2157-11a1-4a7e-9d78-34551a97238b
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	77379757-4023-4299-b90c-beecc8534924
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	afa4572f-fe95-4822-af5f-58e1e5bc265d
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	db82b74c-5364-4818-a567-eafa8c98303c
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	197480b6-56e5-451f-bc2d-d9a3908abe85
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	093c997a-e924-42e2-83d1-3f1afdfb5051
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	04c9e7de-3536-43c9-b009-c608764d72d5
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	71b0b31a-f254-4192-8f5c-bf6555db4ad0
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	bd2c5881-2153-4fa5-87ac-74c956251952
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	c80718c9-f972-4eaa-80ec-6fc5e77f0c20
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	eb4aa561-e719-458c-83f2-d5f38519fec0
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	2b601aaa-5463-47af-8858-f510a9d7d291
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	128531c7-903d-43e4-814d-895bd0bea3fe
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	011748ae-74a0-42e5-baa3-3dda8ac90ccc
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	b21ac688-9834-4291-8174-440657f23927
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	45bec9a1-53b3-486d-b414-e2f5dc97fa7a
d24c97cb-ead8-447c-8318-4631fdc928a2	bbe5f22c-bb3c-4722-b604-f28b2bd674a7
d24c97cb-ead8-447c-8318-4631fdc928a2	b7cf08b2-86bf-4c20-9a2a-93e3f0634db1
d24c97cb-ead8-447c-8318-4631fdc928a2	33aacb02-322e-43b7-8425-435aa44a6df3
d24c97cb-ead8-447c-8318-4631fdc928a2	c9604fc2-9c8a-4c0c-b973-1f48378bbcd4
5d6c50ef-851b-4ea8-985b-2a94bea662c8	7d3a8dfd-68a8-435c-8653-555ac23197d3
5d6c50ef-851b-4ea8-985b-2a94bea662c8	197480b6-56e5-451f-bc2d-d9a3908abe85
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	2b601aaa-5463-47af-8858-f510a9d7d291
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	45bec9a1-53b3-486d-b414-e2f5dc97fa7a
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	8307e64f-a352-4824-b901-6e592aa900f6
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	04c9e7de-3536-43c9-b009-c608764d72d5
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	8c419f65-6604-4b42-87ce-02d3852a80e3
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	afedd297-90a6-4301-a948-760abfff586d
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	e4d4f092-7149-4d54-bdd9-c3469e2fadc0
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	77379757-4023-4299-b90c-beecc8534924
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	eb4aa561-e719-458c-83f2-d5f38519fec0
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	26028ba2-9b3d-49d2-930a-50a4d3f7c6e1
\.


--
-- TOC entry 3782 (class 0 OID 33055)
-- Dependencies: 228
-- Data for Name: roles; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.roles (role_id, role_code, role_name, role_description, is_system_role, is_active, created_at, updated_at) FROM stdin;
df87d5fc-0380-4b85-812e-d433bf6ab91a	SERVICE	Service	As a system operations and maintenance technician, you have the authority to monitor, manage and ensure the performance of the system.	f	t	2025-10-26 05:10:10.585527+00	2025-11-07 03:31:01.18204+00
6369cadd-88f3-4879-9478-b11e3e53d1a7	NORMAL_USER	Normal User	As a patient, you only have the right to see your test results.	f	t	2025-11-07 03:32:15.996022+00	2025-11-07 03:34:38.204935+00
5d6c50ef-851b-4ea8-985b-2a94bea662c8	LAB_MANAGER	Lab Manager	Lab managers, lab users, service users, have the right to view and monitor the entire system.	t	t	2025-10-26 05:10:10.585527+00	2025-11-22 08:02:21.632768+00
e73c5b55-62ea-4ac7-972c-c461c2d52b2f	LAB_USER	Lab User	As a lab worker, perform specialized tasks such as creating and updating test orders, performing tests, adding comments, and managing test results.	f	t	2025-10-26 05:10:10.585527+00	2025-11-23 15:45:13.529284+00
cc49e2f1-cdb2-42bd-9776-b641a22529bf	LAB_TECH	Lab Technician	Is the person who works directly in the laboratory and operates the system to perform the testing process.	f	t	2025-10-26 05:10:10.585527+00	2025-11-24 04:27:15.504451+00
d24c97cb-ead8-447c-8318-4631fdc928a2	ADMIN	Administrator	Get access to all features in the system — user management, configuration, permissions, event logs, devices, and more.	t	t	2025-10-26 05:10:10.585527+00	2025-11-24 04:47:09.607322+00
c9fbda4c-eb80-48da-a780-89278fe65051	STAFF	Staff Lab		f	t	2025-11-24 04:47:16.360089+00	2025-11-24 04:47:16.3601+00
c9fcb488-6d1f-4d63-bed2-c3d2e8c3c98e	STAFFLAB	Staff Lab	None	f	t	2025-11-26 06:20:35.336301+00	2025-11-26 06:20:52.04144+00
\.


--
-- TOC entry 3783 (class 0 OID 33065)
-- Dependencies: 229
-- Data for Name: screen_actions; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.screen_actions (action_code, action_name, is_active, created_at, updated_at) FROM stdin;
VIEW	View	t	2025-11-01 13:36:07.791157+00	2025-11-01 13:36:07.791157+00
CREATE	Create	t	2025-11-01 13:36:07.791157+00	2025-11-01 13:36:07.791157+00
UPDATE	Update	t	2025-11-01 13:36:07.791157+00	2025-11-01 13:36:07.791157+00
DELETE	Delete	t	2025-11-01 13:36:07.791157+00	2025-11-01 13:36:07.791157+00
EXPORT	Export	t	2025-11-01 13:36:07.791157+00	2025-11-01 13:36:07.791157+00
IMPORT	Import	t	2025-11-01 13:36:07.791157+00	2025-11-01 13:36:07.791157+00
APPROVE	Approve	t	2025-11-01 13:36:07.791157+00	2025-11-01 13:36:07.791157+00
\.


--
-- TOC entry 3784 (class 0 OID 33071)
-- Dependencies: 230
-- Data for Name: screens; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.screens (screen_id, screen_code, path, base_path, title, icon, ordering, parent_code, is_menu, is_default, is_public, is_active, created_at, updated_at, component_name, component_key) FROM stdin;
cc72a106-63f5-498b-9380-855c0ff64884	FORGOT_SEND	/forgot-password	/forgot-password	Quên mật khẩu	mail	3	\N	f	f	t	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	ForgotSend	ForgotSend
691a1807-3d16-4d1c-b837-0aaf95e861f6	FORGOT_VERIFY	/forgot-password/verify	/forgot-password	Xác thực OTP	shield-check	4	\N	f	f	t	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	ForgotVerify	ForgotVerify
ab083da3-efb5-4baa-8b93-5070c7dfd88a	FORGOT_RESET	/forgot-password/reset	/forgot-password	Đặt lại mật khẩu	key	5	\N	f	f	t	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	ForgotReset	ForgotReset
53b7e3f3-987f-445b-9daf-fb99fd9d5b58	NOT_FOUND	/404	/404	Không tìm thấy	alert-circle	99	\N	f	f	t	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	NotFound	NotFound
20d331a2-8a9c-4ae1-86e4-2be0697f7d5e	USER_HOME	/user/home	/user	User Dashboard	user	10	\N	t	f	f	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	UserHome	UserHome
7c66ed4b-76f7-4617-a058-bdd609829946	ADMIN_USERS_LIST	/admin/users	/admin	Quản lý người dùng	users	20	\N	t	f	f	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	UsersList	UsersList
079787f7-bd41-4f97-afe4-da3805083f06	ADMIN_ROLES_LIST	/admin/roles	/admin	Quản lý vai trò	shield	21	\N	t	f	f	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	RolesList	RolesList
0f17109c-27d6-434b-a717-e7a5f62c2ba6	ADMIN_PRIVILEGES_LIST	/admin/privileges	/admin	Quản lý quyền hạn	lock	22	\N	t	f	f	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	PrivilegesList	PrivilegesList
72579e1e-934a-402e-86fe-8a50b2132788	LAB_MANAGER_HOME	/lab-manager/home	/lab-manager	Lab Manager Dashboard	briefcase	30	\N	t	f	f	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	LabManagerHome	LabManagerHome
f5d7a587-028f-4283-bf60-252f8092e816	LAB_TECH_HOME	/lab-tech/home	/lab-tech	Lab Tech Dashboard	flask-conical	31	\N	t	f	f	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	LabTechHome	LabTechHome
58d8c021-89f9-422c-b164-23a91840172d	LAB_USER_HOME	/lab-user/home	/lab-user	Lab User Dashboard	microscope	32	\N	t	f	f	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	LabUserHome	LabUserHome
96b972b2-22da-474e-9ab4-4233362e4759	SERVICE_HOME	/service/home	/service	Service Dashboard	wrench	40	\N	t	f	f	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	ServiceHome	ServiceHome
1a4617f8-c618-4f86-852f-e05778f3a518	LOGIN	/	/login	Đăng nhập	log-in	2	\N	f	t	t	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	Login	Login
7dd66b97-b412-4f46-b5e4-a8f0d8146be6	LANDING_PAGE	/home	/	Trang chủ	home	1	\N	t	f	t	t	2025-11-02 12:48:41.501336+00	2025-11-02 12:48:41.501336+00	LandingPage	LandingPage
65bb4df8-95bf-40af-9ff0-412ccc1bcf38	ADMIN_CREATE_USER	/admin/users/create	/admin/users	Tạo User	UserPlus	2	ADMIN_USERS_LIST	t	f	f	t	2025-11-03 14:58:36.365212+00	2025-11-03 14:58:36.365212+00	CreateUser	AdminCreateUser
56534673-1ddc-46c9-8699-9a76f122f19d	ADMIN_EDIT_USER	/admin/users/:id/edit	/admin	Chỉnh sửa người dùng	Edit3	20	ADMIN_USERS_LIST	t	f	f	t	2025-11-04 15:03:01.204472+00	2025-11-04 15:03:01.204472+00	EditUser	EditUser
67f680af-8c8c-4404-9bb8-81c290e0343e	PROFILE_ROOT	/profile	/profile	Profile	user	10	\N	f	f	f	t	2025-11-06 02:55:23.001674+00	2025-11-06 02:55:23.001674+00	ProfileLayout	ProfileLayout
980e91cf-9b85-4dcd-8f82-c50083f227f6	PROFILE_OVERVIEW	/profile	/profile	My profile	user	11	PROFILE_ROOT	f	f	f	t	2025-11-06 02:55:23.001674+00	2025-11-06 02:55:23.001674+00	Profile	Profile
b896c088-392c-45fe-baba-a4f6dc0bef6e	PROFILE_UPDATE	/profile/update	/profile	Update profile	user-pen	12	PROFILE_ROOT	f	f	f	t	2025-11-06 02:55:23.001674+00	2025-11-06 02:55:23.001674+00	UpdateProfile	UpdateProfile
62e7e1c8-a0e6-4e72-8962-5671229388e7	PROFILE_CHANGE_PASSWORD	/profile/security/change-password	/profile	Change password	lock	13	PROFILE_ROOT	f	f	f	t	2025-11-06 02:55:23.001674+00	2025-11-06 02:55:23.001674+00	ChangePassword	ChangePassword
0b136c74-253b-4f8b-9df8-43a90a3b1b23	PATIENT_LIST	/patients	/patients	Patient List	format-list-bulleted	42	PATIENTS	t	f	f	t	2025-11-11 15:58:38.133348+00	2025-11-11 15:58:38.133348+00	PatientList	PatientList
59d3fac0-b2dc-4d10-b8d2-0bcbce2f2990	PATIENT_DETAIL	/patients/:patientId	/patients	Patient Detail	account	45	PATIENTS	t	f	f	t	2025-11-11 15:58:38.133348+00	2025-11-11 15:58:38.133348+00	PatientDetail	PatientDetail
e462d048-d39d-4f1f-972e-7a29ef5a98fa	PATIENT_CREATE	/patients/new	/patients	Add Patient	account-plus	43	PATIENTS	t	f	f	t	2025-11-11 15:58:38.133348+00	2025-11-11 15:58:38.133348+00	PatientAdd	PatientAdd
bcb70224-04b4-4b91-bb34-c15f242143bf	PATIENT_EDIT	/patients/:patientId/edit	/patients	Edit Patient	account-edit	44	PATIENTS	t	f	f	t	2025-11-11 15:58:38.133348+00	2025-11-11 15:58:38.133348+00	PatientEdit	PatientEdit
39a54aba-d1f1-4e02-ba27-115bd28153e1	MEDICAL_RECORD_DETAIL	/patients/:patientId/medical-records/:recordId	/patients	Medical Record Detail	file-document	46	PATIENTS	t	f	f	t	2025-11-11 15:58:38.133348+00	2025-11-11 15:58:38.133348+00	MedicalRecordDetail	MedicalRecordDetail
27cf362a-29c3-4c63-a6e8-a4cda156a53c	ADMIN_LOGIN	/admin/login	/admin	Admin Login	log-in	10	LOGIN	f	f	t	t	2025-11-13 04:17:04.330355+00	2025-11-13 04:17:04.330355+00	AdminLogin	ADMIN_LOGIN
bdf59fdd-8400-4bd0-91b1-711141bb9b15	CHANGE_PASSWORD_FIRST_LOGIN	/change-password-first-login	/change-password-first-login	Change Password - First Login	KeyRound	6	\N	f	f	t	t	2025-11-12 16:22:49.967112+00	2025-11-12 16:22:49.967112+00	ChangePasswordFirstLogin	CHANGE_PASSWORD_FIRST_LOGIN
3b0d72a0-0392-4d02-a5b6-0c67d570223c	MEDICAL_RECORD_CREATE	/patients/medical-records/create	/patients/medical-records	Create Medical Record	note-plus	47	PATIENTS	f	f	f	t	2025-11-13 14:38:31.293296+00	2025-11-13 14:38:31.293296+00	MedicalRecordCreate	MEDICAL_RECORD_CREATE
78c7dcb1-bef6-4cd4-8782-2d549aac5c0d	MEDICAL_RECORD_EDIT	/patients/medical-records/edit/:id	/patients/medical-records	Edit Medical Record	note-edit	48	PATIENTS	f	f	f	t	2025-11-13 14:38:38.66834+00	2025-11-13 14:38:38.66834+00	MedicalRecordEdit	MEDICAL_RECORD_EDIT
2becf3ac-043f-42c1-ae5b-7f19cf4c8d49	PATIENTS	/patients	/patients	Patients	account-group	40	PATIENTS	t	f	f	t	2025-11-11 15:58:38.133348+00	2025-11-11 15:58:38.133348+00		
b440ca52-d1d0-49da-aa7e-0da8f21927b9	LAB_TEST_ORDER_CREATE	/test-order/create	/test-order	Tạo phiếu xét nghiệm	playlist-plus	51	TEST_ORDERS	t	f	f	t	2025-11-14 07:38:31.826327+00	2025-11-14 07:38:31.826327+00	TestOrderCreate	LAB_TEST_ORDER_CREATE
55bd1a46-45b3-457d-8715-d61c937e57a7	TEST_ORDER_LIST	/test-order	/test-order	Test Order List	format-list-bulleted	50	TEST_ORDERS	t	f	f	t	2025-11-14 07:53:36.197408+00	2025-11-14 07:53:36.197408+00	TestOrderList	TEST_ORDER_LIST
605fb7ec-4ea5-4e1c-93dc-40eb5d19338f	TEST_ORDER_EDIT	/test-order/edit/:id	/test-order	Edit Test Order	pencil	52	TEST_ORDERS	f	f	f	t	2025-11-14 07:54:51.186464+00	2025-11-14 07:54:51.186464+00	TestOrderEdit	TEST_ORDER_EDIT
e4021c05-4068-4439-90b2-aaca6cfc2690	TEST_ORDER_DETAIL	/test-order/:id	/test-order	Test Order Detail	file-document	53	TEST_ORDERS	f	f	f	t	2025-11-14 07:55:51.760534+00	2025-11-14 07:55:51.760534+00	TestOrderDetail	TEST_ORDER_DETAIL
1c9fb5a0-a39c-4f16-a8ad-b9fb1d034709	TEST_RESULT_LIST	/test-results	/test-results	Test Result List	format-list-bulleted	54		t	f	f	t	2025-11-20 13:27:32.184486+00	2025-11-20 13:27:32.184486+00	TestResultList	TEST_RESULT_LIST
bcc4b91a-590d-4041-ab0a-1b2e71596bc6	ALL_MEDICAL_RECORDS	/patients/all-medical-records	/patients	All Medical Records	file-medical	49	PATIENTS	t	f	f	t	2025-11-21 02:07:31.011997+00	2025-11-21 02:07:31.011997+00	AllMedicalRecords	pages/PATIENTS/AllMedicalRecords.jsx
ac3786fb-1e7b-4643-973a-1b336760949f	FORBIDDEN_403	/403	/403	Forbidden	ban	98	\N	f	f	t	t	2025-11-22 07:53:03.26862+00	2025-11-22 07:53:03.26862+00	Forbidden403	Forbidden403
\.


--
-- TOC entry 3785 (class 0 OID 33084)
-- Dependencies: 231
-- Data for Name: system_configurations; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.system_configurations (config_id, config_key, config_value, config_type, config_category, description, default_value, is_active, created_at) FROM stdin;
\.


--
-- TOC entry 3786 (class 0 OID 33093)
-- Dependencies: 232
-- Data for Name: user_roles; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.user_roles (user_id, role_id, assigned_at, assigned_by, expires_at, is_active) FROM stdin;
4135dbcc-c6fb-4781-afb3-90ee621dd9f4	d24c97cb-ead8-447c-8318-4631fdc928a2	2025-11-06 04:42:33.257651+00	\N	\N	t
2a04b41b-422f-455e-85c3-4c036e692b3c	cc49e2f1-cdb2-42bd-9776-b641a22529bf	2025-11-07 08:25:27.60056+00	\N	\N	t
987fa969-961f-4afb-98aa-636c3448bd87	5d6c50ef-851b-4ea8-985b-2a94bea662c8	2025-11-07 09:10:40.581509+00	\N	\N	t
bb8259df-3cb8-487a-ab91-2ef95a68aa44	d24c97cb-ead8-447c-8318-4631fdc928a2	2025-11-12 07:48:05.772958+00	\N	\N	t
8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	cc49e2f1-cdb2-42bd-9776-b641a22529bf	2025-11-14 02:47:36.060916+00	\N	\N	t
b46b4c47-31c6-4ad2-9829-0332963bb646	cc49e2f1-cdb2-42bd-9776-b641a22529bf	2025-11-14 06:24:40.689971+00	\N	\N	t
cd23d611-1644-4d29-b7b3-100f9458018c	cc49e2f1-cdb2-42bd-9776-b641a22529bf	2025-11-24 03:33:06.009366+00	\N	\N	t
c1d918d1-18d8-4837-a271-967d90f569a3	cc49e2f1-cdb2-42bd-9776-b641a22529bf	2025-11-24 04:14:07.520522+00	\N	\N	t
ef8716fc-d175-4c54-870d-1c9313405fd0	cc49e2f1-cdb2-42bd-9776-b641a22529bf	2025-11-26 02:45:05.404019+00	\N	\N	t
76f0e8e4-687f-4f7f-b2c4-b76fa8588ad6	5d6c50ef-851b-4ea8-985b-2a94bea662c8	2025-11-26 04:43:55.985422+00	\N	\N	t
\.


--
-- TOC entry 3787 (class 0 OID 33098)
-- Dependencies: 233
-- Data for Name: users; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.users (user_id, username, email, phone_number, full_name, identity_number, gender, date_of_birth, address, age_years, password_hash, password_algorithm, password_updated_at, password_expires_at, must_change_password, is_active, is_locked, locked_at, locked_until, locked_reason, failed_login_attempts, last_failed_login_at, last_successful_login_at, last_activity_at, last_login_user_agent, created_at, created_by, updated_at, updated_by) FROM stdin;
c1d918d1-18d8-4837-a271-967d90f569a3	ThanhNT	truongthanhj1999@gmail.com	0862844146	Nguyễn Trường Thạnh	098728738241	male	2003-08-08	78/2A, Phường Long Xuyên, Tỉnh An Giang	22	$argon2id$v=19$m=4096,t=3,p=1$QVbkqSKiS6wHWD1Lk3rh4w$lDDi9xj07OB83DzjLQd8+02wKD6Hg2aRxtu17q2Uqsk	ARGON2ID	2025-11-20 12:52:10.291457+00	\N	f	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-11-05 08:12:50.369847+00	\N	2025-11-24 04:14:07.524629+00	\N
987fa969-961f-4afb-98aa-636c3448bd87	PhatNT	phatnt261004@gmail.com	\N	Nguyễn Tấn Phát	\N	\N	\N	Phường Long Châu, Tỉnh Vĩnh Long	\N	$argon2id$v=19$m=4096,t=3,p=1$mFIKyj8QdiCKPr7m0BGRbg$vYPcSE1zV8sOFXsaY6804owwDOk/iVIcy9OapDeZ38w	ARGON2ID	2025-11-14 02:46:33.246555+00	\N	f	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-11-07 09:10:40.585257+00	\N	2025-11-26 00:02:30.248908+00	\N
cd23d611-1644-4d29-b7b3-100f9458018c	BaoNPG	nhathuydt3@gmail.com	\N	Nguyễn Phạm Gia Bảo	\N	male	2002-06-22	23/4A, Phường Trà Vinh, Tỉnh Vĩnh Long	23	$argon2id$v=19$m=4096,t=3,p=1$SJvUrfOLdMznQfc6nvdXSA$TG4APrDJIWwVo+8JFt9XrdzW1yW3E2JO4OVQaYayymE	ARGON2ID	2025-11-22 08:08:30.928637+00	\N	f	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-11-22 08:07:32.997131+00	\N	2025-11-26 02:38:00.619623+00	\N
ef8716fc-d175-4c54-870d-1c9313405fd0	HungNQ	hungfptedu@gmail.com	\N	Nguyễn Quốc Hưng	\N	\N	\N	Phường Trà Vinh, Tỉnh Vĩnh Long	\N	$argon2id$v=19$m=4096,t=3,p=1$oa7w+VwZKgV//QWBfiHEkg$BLD1brOC2vPYQOgDzL6qEJCkw/bF2xdrwQSe2Ph/1Iw	ARGON2ID	2025-11-11 11:10:42.897727+00	\N	f	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-11-07 16:53:07.127964+00	\N	2025-11-26 02:45:05.412709+00	\N
76f0e8e4-687f-4f7f-b2c4-b76fa8588ad6	AnTV	hungtranxpf@localhost.com	0123456799	Trần Vỹ An	012345678911	male	2004-03-15	Ấp Phú Hưng 1, Phường Ba Đình, Thành phố Hà Nội	21	$argon2id$v=19$m=4096,t=3,p=1$mnLaC9n9/AcdqNo950riwA$Cc5p0pvrZu59jRigf0AI9nMU2S+ec4Z2z7yTNAopWKo	ARGON2ID	2025-11-26 04:43:56.018257+00	\N	t	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-11-26 04:43:56.018221+00	\N	2025-11-26 06:19:01.804787+00	\N
4135dbcc-c6fb-4781-afb3-90ee621dd9f4	Hungtq	hungtranxpf@gmail.com	0336761915	Trần Quốc Hưng	093274364709	male	2004-02-17	80, Ấp Phú Hưng 1, Xã Bình Phú, Tỉnh Vĩnh Long	21	$argon2id$v=19$m=4096,t=3,p=1$SxBHnhyqNj/nJ2MjUKkPzw$uClgQfsbvKTTfS3F4uPPYgxN2DPpgK9BwaNTgwPpXTY	ARGON2ID	2025-11-26 07:22:07.197106+00	\N	f	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-10-30 05:30:14.956359+00	\N	2025-11-26 07:22:07.354251+00	\N
2a04b41b-422f-455e-85c3-4c036e692b3c	LocLM	leminhloc001@gmail.com	\N	Lê Minh Lộc	\N	\N	\N	90, Xã Tân Thuận, Tỉnh Cà Mau	\N	$argon2id$v=19$m=4096,t=3,p=1$QMU92CenjnMBLet0qUAQyA$paBn1TJSmVx5iQorSNIX60UCf3D8/lNnyQ2QczlRRSI	ARGON2ID	2025-11-07 08:25:27.60411+00	\N	f	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-11-07 08:25:27.604078+00	\N	2025-11-07 08:25:27.604086+00	\N
8152cf83-39bb-44cd-a1c2-0ca4095ff0bf	Tkace	teek210504@gmail.com	\N	tkace	\N	\N	\N	Thành phố Cần Thơ	\N	$argon2id$v=19$m=4096,t=3,p=1$D06LaHrttvS/MUcNCe3n3g$LyZlbuEIrDxG78+34OfYP70N3E3ooXtFc+BCItWz0gU	ARGON2ID	2025-11-14 01:55:33.64986+00	\N	f	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-11-14 01:54:33.527063+00	\N	2025-11-14 02:47:36.067602+00	\N
b46b4c47-31c6-4ad2-9829-0332963bb646	minhbao	baotmce170752@fpt.edu.vn	0904838748	Trần Minh Bảo	098132110991	male	2000-02-17	20A/4, Phường Hưng Phú, Thành phố Cần Thơ	25	$argon2id$v=19$m=4096,t=3,p=1$0J6qTVLHfV1ei+FudK/Www$sX3Fq48J4UPpsGlEGIo9FdE6BOcIN2PYHKoSPavwLzU	ARGON2ID	2025-11-14 06:25:54.979669+00	\N	f	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-11-05 03:48:26.235803+00	\N	2025-11-14 07:41:32.142731+00	\N
bb8259df-3cb8-487a-ab91-2ef95a68aa44	KhoaNPT	khoanptce181730@fpt.edu.vn	\N	Nguyễn Phạm Trường Khoa	\N	\N	\N	Phường Ninh Kiều, Thành phố Cần Thơ	\N	$argon2id$v=19$m=4096,t=3,p=1$QNEqi+j7F+D/OuEp3zKx4Q$hRSnqO1PwKR5hcsER1p6hyDQdwO1WUYhqNrYeimALtQ	ARGON2ID	2025-11-12 07:48:05.779353+00	\N	f	t	f	\N	\N	\N	0	\N	\N	\N	\N	2025-11-12 07:48:05.77935+00	\N	2025-11-21 11:47:32.379143+00	\N
\.


--
-- TOC entry 3788 (class 0 OID 33133)
-- Dependencies: 238
-- Data for Name: vn_commune; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.vn_commune (code, name, english_name, administrative_level, province_code, district_code, province_name, decree) FROM stdin;
00004	Phường Ba Đình		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00008	Phường Ngọc Hà	Lieu Giai Commune	Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00025	Phường Giảng Võ		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00070	Phường  Hoàn Kiếm		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00082	Phường Cửa Nam		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00091	Phường Phú Thượng		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00097	Phường Hồng Hà		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00103	Phường Tây Hồ		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00118	Phường Bồ Đề		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00127	Phường Việt Hưng		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00136	Phường Phúc Lợi		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00145	Phường Long Biên		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00160	Phường Nghĩa Đô		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00166	Phường Cầu Giấy		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00175	Phường Yên Hòa		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00190	Phường Ô Chợ Dừa		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00199	Phường Láng		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00226	Phường Văn Miếu - Quốc Tử Giám		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00229	Phường Kim Liên		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00235	Phường Đống Đa		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00256	Phường Hai Bà Trưng		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00283	Phường Vĩnh Tuy		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00292	Phường Bạch Mai		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00301	Phường Vĩnh Hưng		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00316	Phường Định Công		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00322	Phường Tương Mai		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00328	Phường Lĩnh Nam		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00331	Phường Hoàng Mai		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00337	Phường Hoàng Liệt		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00340	Phường Yên Sở		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00352	Phường Phương Liệt		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00364	Phường Khương Đình		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00367	Phường Thanh Xuân		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00376	Xã Sóc Sơn		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00382	Xã Kim Anh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00385	Xã Trung Giã		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00430	Xã Đa Phúc		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00433	Xã Nội Bài		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00454	Xã Đông Anh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00466	Xã Phúc Thịnh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00475	Xã Thư Lâm		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00493	Xã Thiên Lộc		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00508	Xã Vĩnh Thanh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00541	Xã Phù Đổng		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00562	Xã Thuận An		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00565	Xã Gia Lâm	Trau Quy Commune	Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00577	Xã Bát Tràng		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00592	Phường Từ Liêm		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00598	Phường Thượng Cát		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00602	Phường Đông Ngạc		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00611	Phường Xuân Đỉnh		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00613	Phường Tây Tựu		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00619	Phường Phú Diễn		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00622	Phường Xuân Phương		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00634	Phường Tây Mỗ		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00637	Phường Đại Mỗ		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00640	Xã Thanh Trì		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00643	Phường Thanh Liệt		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00664	Xã Đại Thanh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00679	Xã Ngọc Hồi		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
00685	Xã Nam Phù		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
04930	Xã Yên Xuân		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
08974	Xã Quang Minh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
08980	Xã Yên Lãng		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
08995	Xã Tiến Thắng		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09022	Xã Mê Linh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09552	Phường Kiến Hưng		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09556	Phường Hà Đông		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09562	Phường Yên Nghĩa		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09568	Phường Phú Lương		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09574	Phường Sơn Tây		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09604	Phường Tùng Thiện		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09616	Xã Đoài Phương		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09619	Xã Quảng Oai		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09634	Xã Cổ Đô		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09661	Xã Minh Châu		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09664	Xã Vật Lại		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09676	Xã Bất Bạt		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09694	Xã Suối Hai		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09700	Xã Ba Vì		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09706	Xã Yên Bài		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09715	Xã Phúc Thọ		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09739	Xã Phúc Lộc		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09772	Xã Hát Môn		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09784	Xã Đan Phượng		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09787	Xã Liên Minh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09817	Xã Ô Diên		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09832	Xã Hoài Đức		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09856	Xã Dương Hòa		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09871	Xã Sơn Đồng		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09877	Xã An Khánh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09886	Phường Dương Nội		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09895	Xã Quốc Oai		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09910	Xã Kiều Phú		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09931	Xã Hưng Đạo		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09952	Xã Phú Cát		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09955	Xã Thạch Thất		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09982	Xã Hạ Bằng		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
09988	Xã Hòa Lạc		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10003	Xã Tây Phương		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10015	Phường Chương Mỹ		Phường	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10030	Xã Phú Nghĩa		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10045	Xã Xuân Mai		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10072	Xã Quảng Bị		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10081	Xã Trần Phú		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10096	Xã Hòa Phú		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10114	Xã Thanh Oai		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10126	Xã Bình Minh		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10144	Xã Tam Hưng		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10180	Xã Dân Hòa		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10183	Xã Thường Tín		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10210	Xã Hồng Vân		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10231	Xã Thượng Phúc		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10237	Xã Chương Dương		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10273	Xã Phú Xuyên		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10279	Xã Phượng Dực		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10330	Xã Chuyên Mỹ		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10342	Xã Đại Xuyên		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10354	Xã Vân Đình		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10369	Xã Ứng Thiên		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10402	Xã Ứng Hòa		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10417	Xã Hòa Xá		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10441	Xã Mỹ Đức		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10459	Xã Phúc Sơn		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10465	Xã Hồng Sơn		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
10489	Xã Hương Sơn		Xã	01	\N	Thành phố Hà Nội	Số: 1656/NQ-UBTVQH15; Ngày: 16/06/2025
01273	Phường Thục Phán		Phường	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01279	Phường Nùng Trí Cao		Phường	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01288	Phường Tân Giang		Phường	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01290	Xã Bảo Lâm		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01294	Xã Lý Bôn		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01297	Xã Nam Quang		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01304	Xã Quảng Lâm	Thach Lam commune	Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01318	Xã Yên Thổ		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01321	Xã Bảo Lạc		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01324	Xã Cốc Pàng		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01327	Xã Cô Ba		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01336	Xã Khánh Xuân		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01339	Xã Xuân Trường		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01351	Xã Hưng Đạo		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01354	Xã Huy Giáp		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01360	Xã Sơn Lộ		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01363	Xã Thông Nông		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01366	Xã Cần Yên		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01387	Xã Thanh Long		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01392	Xã Trường Hà		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01393	Xã Lũng Nặm		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01414	Xã Tổng Cọt		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01438	Xã Hà Quảng		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01447	Xã Trà Lĩnh		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01456	Xã Quang Hán		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01465	Xã Quang Trung		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01477	Xã Trùng Khánh		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01489	Xã Đình Phong		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01501	Xã Đàm Thủy		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01525	Xã Đoài Dương		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01537	Xã Lý Quốc		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01552	Xã Quang Long		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01558	Xã Hạ Lang		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01561	Xã Vinh Quý		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01576	Xã Quảng Uyên		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01594	Xã Độc Lập		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01618	Xã Hạnh Phúc		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01636	Xã Bế Văn Đàn		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01648	Xã Phục Hòa		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01654	Xã Hòa An		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01660	Xã Nam Tuấn		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01699	Xã Nguyễn Huệ		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01708	Xã Bạch Đằng		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01726	Xã Nguyên Bình		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01729	Xã Tĩnh Túc		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01738	Xã Ca Thành		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01747	Xã Minh Tâm		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01768	Xã Phan Thanh		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01774	Xã Tam Kim		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01777	Xã Thành Công		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01786	Xã Đông Khê		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01789	Xã Canh Tân		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01792	Xã Kim Đồng		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01795	Xã Minh Khai		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01807	Xã Thạch An		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
01822	Xã Đức Long		Xã	04	\N	Tỉnh Cao Bằng	Số: 1657/NQ-UBTVQH15; Ngày: 16/06/2025
00691	Phường Hà Giang 2		Phường	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00694	Phường Hà Giang 1		Phường	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00700	Xã Ngọc Đường		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00706	Xã Phú Linh		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00715	Xã Lũng Cú		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00721	Xã Đồng Văn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00733	Xã Sà Phìn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00745	Xã Phố Bảng		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00763	Xã Lũng Phìn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00769	Xã Mèo Vạc		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00778	Xã Sơn Vĩ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00787	Xã Sủng Máng		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00802	Xã Khâu Vai		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00808	Xã Tát Ngà		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00817	Xã Niêm Sơn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00820	Xã Yên Minh		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00829	Xã Thắng Mố		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00832	Xã Bạch Đích		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00847	Xã Mậu Duệ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00859	Xã Ngọc Long		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00865	Xã Đường Thượng		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00871	Xã Du Già		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00874	Xã Quản Bạ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00883	Xã Cán Tỷ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00889	Xã Nghĩa Thuận		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00892	Xã Tùng Vài		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00901	Xã Lùng Tám		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00913	Xã Vị Xuyên		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00919	Xã Minh Tân		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00922	Xã Thuận Hoà		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00925	Xã Tùng Bá		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00928	Xã Thanh Thủy		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00937	Xã Lao Chải		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00952	Xã Cao Bồ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00958	Xã Thượng Sơn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00967	Xã Việt Lâm		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00970	Xã Linh Hồ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00976	Xã Bạch Ngọc		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00982	Xã Minh Sơn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00985	Xã Giáp Trung		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00991	Xã Bắc Mê		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
00994	Xã Minh Ngọc		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01006	Xã Yên Cường		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01012	Xã Đường Hồng		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01021	Xã Hoàng Su Phì		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01024	Xã Bản Máy		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01033	Xã Thàng Tín		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01051	Xã Tân Tiến		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01057	Xã Pờ Ly Ngài		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01075	Xã Nậm Dịch		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01084	Xã Hồ Thầu		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01090	Xã Thông Nguyên		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01096	Xã Pà Vầy Sủ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01108	Xã Xín Mần		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01117	Xã Trung Thịnh		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01141	Xã Nấm Dẩn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01144	Xã Quảng Nguyên		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01147	Xã Khuôn Lùng		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01153	Xã Bắc Quang		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01156	Xã Vĩnh Tuy		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01165	Xã Đồng Tâm		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01171	Xã Tân Quang		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01180	Xã Bằng Hành		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01192	Xã Liên Hiệp		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01201	Xã Hùng An		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01216	Xã Đồng Yên		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01225	Xã Tiên Nguyên		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01234	Xã Yên Thành		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01237	Xã Quang Bình		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01243	Xã Tân Trịnh		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01246	Xã Bằng Lang		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01255	Xã Xuân Giang		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
01261	Xã Tiên Yên		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02212	Phường Nông Tiến		Phường	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02215	Phường Minh Xuân		Phường	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02221	Xã Nà Hang		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02239	Xã Thượng Nông		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02245	Xã Côn Lôn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02248	Xã Yên Hoa		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02260	Xã Hồng Thái		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02266	Xã Lâm Bình		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02269	Xã Thượng Lâm		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02287	Xã Chiêm Hoá		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02296	Xã Bình An		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02302	Xã Minh Quang		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02305	Xã Trung Hà		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02308	Xã Tân Mỹ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02317	Xã Yên Lập		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02320	Xã Tân An		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02332	Xã Kiên Đài		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02350	Xã Kim Bình		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02353	Xã Hoà An		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02359	Xã Tri Phú		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02365	Xã Yên Nguyên		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02374	Xã Hàm Yên		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02380	Xã Bạch Xa		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02392	Xã Phù Lưu		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02398	Xã Yên Phú		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02404	Xã Bình Xa		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02407	Xã Thái Sơn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02419	Xã Thái Hoà		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02425	Xã Hùng Đức		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02434	Xã Lực Hành		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02437	Xã Kiến Thiết		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02449	Xã Xuân Vân		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02455	Xã Hùng Lợi		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02458	Xã Trung Sơn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02470	Xã Tân Long		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02473	Xã Yên Sơn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02494	Xã Thái Bình		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02509	Phường Mỹ Lâm		Phường	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02512	Phường An Tường		Phường	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02524	Phường Bình Thuận		Phường	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02530	Xã Nhữ Khê		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02536	Xã Sơn Dương		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02545	Xã Tân Trào		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02548	Xã Bình Ca		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02554	Xã Minh Thanh		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02572	Xã Đông Thọ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02578	Xã Tân Thanh		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02608	Xã Hồng Sơn		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02611	Xã Phú Lương		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02620	Xã Sơn Thuỷ		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
02623	Xã Trường Sinh		Xã	08	\N	Tỉnh Tuyên Quang	Số: 1684/NQ-UBTVQH15; Ngày: 16/06/2025
03127	Phường Điện Biên Phủ		Phường	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03151	Phường Mường Lay		Phường	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03158	Xã Sín Thầu		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03160	Xã Mường Nhé		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03162	Xã Nậm Kè	Nam Ke commune	Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03163	Xã Mường Toong		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03164	Xã Quảng Lâm	Quang Lam Commune	Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03166	Xã Mường Chà		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03169	Xã Nà Hỳ		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03172	Xã Na Sang		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03175	Xã Chà Tở		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03176	Xã Nà Bủng		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03181	Xã Mường Tùng		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03193	Xã Pa Ham		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03194	Xã Nậm Nèn		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03199	Xã Si Pa Phìn		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03202	Xã Mường Pồn		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03203	Xã Na Son		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03208	Xã Xa Dung		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03214	Xã Mường Luân		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03217	Xã Tủa Chùa		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03220	Xã Tủa Thàng		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03226	Xã Sín Chải		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03241	Xã Sính Phình		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03244	Xã Sáng Nhè		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03253	Xã Tuần Giáo		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03256	Xã Mường Ảng		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03260	Xã Pú Nhung		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03268	Xã Mường Mùn		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03283	Xã Chiềng Sinh		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03295	Xã Quài Tở		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03301	Xã Búng Lao		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03313	Xã Mường Lạn		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03316	Xã Nà Tấu		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03325	Xã Mường Phăng		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03328	Xã Thanh Nưa		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03334	Phường Mường Thanh		Phường	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03349	Xã Thanh Yên		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03352	Xã Thanh An		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03356	Xã Sam Mứn		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03358	Xã Núa Ngam		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03368	Xã Mường Nhà		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03370	Xã Pu Nhi		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03382	Xã Phình Giàng		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03385	Xã Tìa Dình		Xã	11	\N	Tỉnh Điện Biên	Số: 1661/NQ-UBTVQH15; Ngày: 16/06/2025
03388	Phường Đoàn Kết		Phường	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03390	Xã Bình Lư	Tam Đường town	Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03394	Xã Sin Suối Hồ		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03405	Xã Tả Lèng		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03408	Phường Tân Phong		Phường	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03424	Xã Bản Bo		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03430	Xã Khun Há		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03433	Xã Bum Tở		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03434	Xã Nậm Hàng		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03439	Xã Thu Lũm		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03442	Xã Pa Ủ		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03445	Xã Mường Tè		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03451	Xã Mù Cả		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03460	Xã Hua Bum		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03463	Xã Tà Tổng		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03466	Xã Bum Nưa		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03472	Xã Mường Mô		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03478	Xã Sìn Hồ		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03487	Xã Lê Lợi		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03503	Xã Pa Tần		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03508	Xã Hồng Thu		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03517	Xã Nậm Tăm		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03529	Xã Tủa Sín Chải		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03532	Xã Pu Sam Cáp		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03538	Xã Nậm Mạ		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03544	Xã Nậm Cuổi		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03549	Xã Phong Thổ	Phong Thổ town	Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03562	Xã Sì Lở Lầu		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03571	Xã Dào San		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03583	Xã Khổng Lào		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03595	Xã Than Uyên		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03598	Xã Tân Uyên		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03601	Xã Mường Khoa		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03613	Xã Nậm Sỏ		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03616	Xã Pắc Ta		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03618	Xã Mường Than		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03637	Xã Mường Kim		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03640	Xã Khoen On		Xã	12	\N	Tỉnh Lai Châu	Số: 1670/NQ-UBTVQH15; Ngày: 16/06/2025
03646	Phường Tô Hiệu		Phường	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03664	Phường Chiềng An		Phường	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03670	Phường Chiềng Cơi		Phường	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03679	Phường Chiềng Sinh		Phường	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03688	Xã Mường Chiên		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03694	Xã Mường Giôn		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03703	Xã Quỳnh Nhai		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03712	Xã Mường Sại		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03721	Xã Thuận Châu		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03724	Xã Bình Thuận		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03727	Xã Mường É		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03754	Xã Chiềng La		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03757	Xã Mường Khiêng		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03760	Xã Mường Bám		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03763	Xã Long Hẹ		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03781	Xã Co Mạ		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03784	Xã Nậm Lầu		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03799	Xã Muổi Nọi		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03808	Xã Mường La		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03814	Xã Chiềng Lao		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03820	Xã Ngọc Chiến		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03847	Xã Mường Bú		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03850	Xã Chiềng Hoa		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03856	Xã Bắc Yên		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03862	Xã Xím Vàng		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03868	Xã Tà Xùa		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03871	Xã Pắc Ngà		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03880	Xã Tạ Khoa		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03892	Xã Chiềng Sại		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03901	Xã Suối Tọ		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03907	Xã Mường Cơi		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03910	Xã Phù Yên		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03922	Xã Gia Phù		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03943	Xã Mường Bang		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03958	Xã Tường Hạ		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03961	Xã Kim Bon		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03970	Xã Tân Phong		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03979	Phường Mộc Sơn		Phường	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03980	Phường Mộc Châu		Phường	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03982	Phường Thảo Nguyên		Phường	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03985	Xã Chiềng Sơn		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
03997	Xã Tân Yên		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04000	Xã Đoàn Kết		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04006	Xã Song Khủa		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04018	Xã Tô Múa		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04033	Phường Vân Sơn		Phường	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04045	Xã Lóng Sập		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04048	Xã Vân Hồ		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04057	Xã Xuân Nha		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04075	Xã Yên Châu		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04078	Xã Chiềng Hặc		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04087	Xã Yên Sơn		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04096	Xã Lóng Phiêng		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04099	Xã Phiêng Khoài		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04105	Xã Mai Sơn		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04108	Xã Chiềng Sung		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04117	Xã Mường Chanh		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04123	Xã Chiềng Mung		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04132	Xã Chiềng Mai		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04136	Xã Tà Hộc		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04144	Xã Phiêng Cằm		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04159	Xã Phiêng Pằn		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04168	Xã Sông Mã		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04171	Xã Bó Sinh		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04183	Xã Mường Lầm		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04186	Xã Nậm Ty		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04195	Xã Chiềng Sơ		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04204	Xã Chiềng Khoong		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04210	Xã Huổi Một		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04219	Xã Mường Hung		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04222	Xã Chiềng Khương		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04228	Xã Púng Bánh		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04231	Xã Sốp Cộp		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04240	Xã Mường Lèo		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
04246	Xã Mường Lạn		Xã	14	\N	Tỉnh Sơn La	Số: 1681/NQ-UBTVQH15; Ngày: 16/06/2025
02647	Phường Lào Cai		Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02671	Phường Cam Đường	Nam Cuong Commune	Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02680	Xã Hợp Thành		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02683	Xã Bát Xát		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02686	Xã A Mú Sung		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02695	Xã Trịnh Tường		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02701	Xã Y Tý		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02707	Xã Dền Sáng		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02725	Xã Bản Xèo		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02728	Xã Mường Hum		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02746	Xã Cốc San		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02752	Xã Pha Long		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02761	Xã Mường Khương		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02782	Xã Cao Sơn		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02788	Xã Bản Lầu		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02809	Xã Si Ma Cai		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02824	Xã Sín Chéng		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02839	Xã Bắc Hà		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02842	Xã Tả Củ Tỷ		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02848	Xã Lùng Phình		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02869	Xã Bản Liền		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02890	Xã Bảo Nhai		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02896	Xã Cốc Lầu		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02902	Xã Phong Hải		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02905	Xã Bảo Thắng		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02908	Xã Tằng Loỏng		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02923	Xã Gia Phú		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02926	Xã Xuân Quang		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02947	Xã Bảo Yên		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02953	Xã Nghĩa Đô		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02962	Xã Xuân Hòa		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02968	Xã Thượng Hà		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02989	Xã Bảo Hà		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
02998	Xã Phúc Khánh		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03004	Xã Ngũ Chỉ Sơn		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03006	Phường Sa Pa		Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03013	Xã Tả Phìn		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03037	Xã Tả Van		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03043	Xã Mường Bo		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03046	Xã Bản Hồ		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03061	Xã Võ Lao		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03076	Xã Nậm Chày		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03082	Xã Văn Bàn		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03085	Xã Nậm Xé		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03091	Xã Chiềng Ken		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03103	Xã Khánh Yên		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03106	Xã Dương Quỳ		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
03121	Xã Minh Lương		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04252	Phường Yên Bái		Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04273	Phường Nam Cường		Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04279	Phường Văn Phú		Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04288	Phường Nghĩa Lộ		Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04303	Xã Lục Yên		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04309	Xã Lâm Thượng		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04336	Xã Tân Lĩnh		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04342	Xã Khánh Hòa		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04345	Xã Mường Lai		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04363	Xã Phúc Lợi		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04375	Xã Mậu A		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04381	Xã Lâm Giang		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04387	Xã Châu Quế		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04399	Xã Đông Cuông		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04402	Xã Phong Dụ Hạ		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04423	Xã Phong Dụ Thượng		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04429	Xã Tân Hợp		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04441	Xã Xuân Ái		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04450	Xã Mỏ Vàng		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04456	Xã Mù Cang Chải		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04462	Xã Nậm Có		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04465	Xã Khao Mang		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04474	Xã Lao Chải		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04489	Xã Chế Tạo		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04492	Xã Púng Luông		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04498	Xã Trấn Yên		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04531	Xã Quy Mông		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04537	Xã Lương Thịnh		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04543	Phường Âu Lâu		Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04564	Xã Việt Hồng		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04576	Xã Hưng Khánh		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04585	Xã Hạnh Phúc		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04603	Xã Tà Xi Láng		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04606	Xã Trạm Tấu		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04609	Xã Phình Hồ		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04630	Xã Tú Lệ		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04636	Xã Gia Hội		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04651	Xã Sơn Lương		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04660	Xã Liên Sơn		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04663	Phường Trung Tâm		Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04672	Xã Văn Chấn		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04681	Phường Cầu Thia		Phường	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04693	Xã Cát Thịnh		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04699	Xã Chấn Thịnh		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04705	Xã Thượng Bằng La		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04711	Xã Nghĩa Tâm		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04714	Xã Yên Bình		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04717	Xã Thác Bà		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04726	Xã Cảm Nhân		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04744	Xã Yên Thành		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
04750	Xã Bảo Ái		Xã	15	\N	Tỉnh Lào Cai	Số: 1673/NQ-UBTVQH15; Ngày: 16/06/2025
01840	Phường Đức Xuân		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01843	Phường Bắc Kạn		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01849	Xã Phong Quang		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01864	Xã Bằng Thành		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01879	Xã Cao Minh		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01882	Xã Nghiên Loan		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01894	Xã Phúc Lộc		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01906	Xã Ba Bể		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01912	Xã Chợ Rã		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01921	Xã Thượng Minh		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01933	Xã Đồng Phúc		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01936	Xã Nà Phặc		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01942	Xã Bằng Vân		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01954	Xã Ngân Sơn		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01957	Xã Thượng Quan		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01960	Xã Hiệp Lực		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01969	Xã Phủ Thông		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
01981	Xã Vĩnh Thông		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02008	Xã Cẩm Giàng		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02014	Xã Bạch Thông		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02020	Xã Chợ Đồn		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02026	Xã Nam Cường		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02038	Xã Quảng Bạch		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02044	Xã Yên Thịnh		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02071	Xã Nghĩa Tá		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02083	Xã Yên Phong		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02086	Xã Chợ Mới		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02101	Xã Thanh Mai		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02104	Xã Tân Kỳ		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02107	Xã Thanh Thịnh		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02116	Xã Yên Bình		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02143	Xã Văn Lang		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02152	Xã Cường Lợi		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02155	Xã Na Rì		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02176	Xã Trần Phú		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02185	Xã Côn Minh		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
02191	Xã Xuân Dương		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05443	Phường Phan Đình Phùng		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05455	Phường Quyết Thắng		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05467	Phường Gia Sàng		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05482	Phường Quan Triều		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05488	Xã Đại Phúc		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05500	Phường Tích Lương		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05503	Xã Tân Cương		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05518	Phường Sông Công		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05528	Phường Bách Quang		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05533	Phường Bá Xuyên		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05542	Xã Lam Vỹ		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05551	Xã Kim Phượng		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05563	Xã Phượng Tiến		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05569	Xã Định Hóa		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05581	Xã Trung Hội		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05587	Xã Bình Yên		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05602	Xã Phú Đình		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05605	Xã Bình Thành		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05611	Xã Phú Lương		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05620	Xã Yên Trạch		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05632	Xã Hợp Thành		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05641	Xã Vô Tranh		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05662	Xã Trại Cau		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05665	Xã Văn Lăng		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05674	Xã Quang Sơn		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05680	Xã Văn Hán		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05692	Xã Đồng Hỷ		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05707	Xã Nam Hòa		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05710	Phường Linh Sơn		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05716	Xã Võ Nhai		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05719	Xã Sảng Mộc		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05722	Xã Nghinh Tường		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05725	Xã Thần Sa		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05740	Xã La Hiên		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05746	Xã Tràng Xá		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05755	Xã Dân Tiến		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05773	Xã Phú Xuyên		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05776	Xã Đức Lương		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05788	Xã Phú Lạc		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05800	Xã Phú Thịnh		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05809	Xã An Khánh		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05818	Xã La Bằng		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05830	Xã Đại Từ		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05845	Xã Vạn Phú		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05851	Xã Quân Chu		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05857	Phường Phúc Thuận		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05860	Phường Phổ Yên		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05881	Xã Thành Công		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05890	Phường Vạn Xuân		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05899	Phường Trung Thành		Phường	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05908	Xã Phú Bình		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05917	Xã Tân Khánh		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05923	Xã Tân Thành		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05941	Xã Điềm Thụy		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05953	Xã Kha Sơn		Xã	19	\N	Tỉnh Thái Nguyên	Số: 1683/NQ-UBTVQH15; Ngày: 16/06/2025
05977	Phường Đông Kinh		Phường	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
05983	Phường Lương Văn Tri		Phường	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
05986	Phường Tam Thanh		Phường	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06001	Xã Đoàn Kết		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06004	Xã Quốc Khánh		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06019	Xã Tân Tiến		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06037	Xã Kháng Chiến		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06040	Xã Thất Khê		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06046	Xã Tràng Định		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06058	Xã Quốc Việt		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06073	Xã Hoa Thám		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06076	Xã Quý Hòa		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06079	Xã Hồng Phong		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06085	Xã Thiện Hòa		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06091	Xã Thiện Thuật		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06103	Xã Thiện Long		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06112	Xã Bình Gia		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06115	Xã Tân Văn		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06124	Xã Na Sầm		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06148	Xã Thụy Hùng		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06151	Xã Hội Hoan		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06154	Xã Văn Lãng		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06172	Xã Hoàng Văn Thụ		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06184	Xã Đồng Đăng		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06187	Phường Kỳ Lừa		Phường	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06196	Xã Ba Sơn		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06211	Xã Cao Lộc		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06220	Xã Công Sơn		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06253	Xã Văn Quan		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06280	Xã Điềm He		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06286	Xã Khánh Khê		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06298	Xã Yên Phúc		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06313	Xã Tri Lễ		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06316	Xã Tân Đoàn		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06325	xã Bắc Sơn		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06337	Xã Tân Tri		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06349	Xã Hưng Vũ		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06364	Xã Vũ Lễ		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06367	Xã Vũ Lăng		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06376	Xã Nhất Hòa		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06385	Xã Hữu Lũng		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06391	Xã Yên Bình		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06400	Xã Hữu Liên		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06415	Xã Vân Nham		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06427	Xã Cai Kinh		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06436	Xã Thiện Tân		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06445	Xã Tân Thành		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06457	Xã Tuấn Sơn		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06463	Xã Chi Lăng		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06475	Xã Bằng Mạc		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06481	Xã Chiến Thắng		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06496	Xã Nhân Lý		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06505	Xã Vạn Linh		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06517	Xã Quan Sơn		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06526	Xã Na Dương		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06529	Xã Lộc Bình		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06541	Xã Mẫu Sơn		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06565	Xã Khuất Xá		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06577	Xã Thống Nhất		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06601	Xã Lợi Bác		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06607	Xã Xuân Dương		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06613	Xã Đình Lập		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06616	Xã Thái Bình		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06625	Xã Kiên Mộc		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06637	Xã Châu Sơn		Xã	20	\N	Tỉnh Lạng Sơn	Số: 1672/NQ-UBTVQH15; Ngày: 16/06/2025
06652	Phường Hà Tu		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06658	Phường Cao Xanh		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06661	Phường Việt Hưng		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06673	Phường Bãi Cháy		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06676	Phường Hà Lầm		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06685	Phường Hồng Gai		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06688	Phường Hạ Long		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06706	Phường Tuần Châu		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06709	Phường Móng Cái 2		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06712	Phường Móng Cái 1		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06724	Xã Hải Sơn		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06733	Xã Hải Ninh		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06736	Phường Móng Cái 3		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06757	Xã Vĩnh Thực		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06760	Phường Mông Dương		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06778	Phường Quang Hanh		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06781	Phường Cửa Ông		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06793	Phường Cẩm Phả		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06799	Xã Hải Hòa		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06811	Phường Uông Bí		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06820	Phường Vàng Danh		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06832	Phường Yên Tử		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06838	Xã Bình Liêu		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06841	Xã Hoành Mô		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06856	Xã Lục Hồn		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06862	Xã Tiên Yên		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06874	Xã Điền Xá		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06877	Xã Đông Ngũ		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06886	Xã Hải Lạng		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06895	Xã Đầm Hà		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06913	Xã Quảng Tân		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06922	Xã Quảng Hà		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06931	Xã Quảng Đức		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06946	Xã Đường Hoa		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06967	Xã Cái Chiên		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06970	Xã Ba Chẽ		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06979	Xã Kỳ Thượng		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06985	Xã Lương Minh		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
06994	Đặc khu Vân Đồn		Đặc khu	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07030	Phường Hoành Bồ		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07054	Xã Quảng La		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07060	Xã Thống Nhất		Xã	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07069	Phường Mạo Khê		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07081	Phường Bình Khê		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07090	Phường An Sinh		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07093	Phường Đông Triều		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07114	Phường Hoàng Quế		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07132	Phường Quảng Yên		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07135	Phường Đông Mai		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07147	Phường Hiệp Hòa		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07168	Phường Hà An		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07180	Phường Liên Hòa		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07183	Phường Phong Cốc		Phường	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07192	Đặc khu Cô Tô		Đặc khu	22	\N	Tỉnh Quảng Ninh	Số: 1679/NQ-UBTVQH15; Ngày: 16/06/2025
07210	Phường Bắc Giang		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07228	Phường Đa Mai		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07246	Xã Xuân Lương		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07264	Xã Tam Tiến		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07282	Xã Đồng Kỳ		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07288	Xã Yên Thế		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07294	Xã Bố Hạ		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07306	Xã Nhã Nam		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07330	Xã Phúc Hòa		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07333	Xã Quang Trung		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07339	Xã Tân Yên		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07351	Xã Ngọc Thiện		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07375	Xã Lạng Giang		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07381	Xã Tiên Lục		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07399	Xã Kép		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07420	Xã Mỹ Thái		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07432	Xã Tân Dĩnh		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07444	Xã Lục Nam		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07450	Xã Đông Phú		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07462	Xã Bảo Đài		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07486	Xã Nghĩa Phương		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07489	Xã Trường Sơn		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07492	Xã Lục Sơn		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07498	Xã Bắc Lũng		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07519	Xã Cẩm Lý		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07525	Phường Chũ		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07531	Xã Tân Sơn		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07534	Xã Sa Lý		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07537	Xã Biên Sơn		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07543	Xã Sơn Hải		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07552	Xã Kiên Lao		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07573	Xã Biển Động		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07582	Xã Lục Ngạn		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07594	Xã Đèo Gia		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07603	Xã Nam Dương		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07612	Phường Phượng Sơn		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07615	Xã Sơn Động		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07616	Xã Tây Yên Tử		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07621	Xã Vân Sơn		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07627	Xã Đại Sơn		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07642	Xã Yên Định		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07654	Xã An Lạc		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07663	Xã Tuấn Đạo		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07672	Xã Dương Hưu		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07681	Phường Yên Dũng		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07682	Phường Tân An		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07696	Phường Tiền Phong		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07699	Phường Tân Tiến		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07735	Xã Đồng Việt		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07738	Phường Cảnh Thụy		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07774	Phường Tự Lạn		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07777	Phường Việt Yên		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07795	Phường Nếnh		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07798	Phường Vân Hà		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07822	Xã Hoàng Vân		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07840	Xã Hiệp Hoà		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07864	Xã Hợp Thịnh		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
07870	Xã Xuân Cẩm		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09169	Phường Vũ Ninh		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09187	Phường Kinh Bắc		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09190	Phường Võ Cường		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09193	Xã Yên Phong		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09202	Xã Tam Giang		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09205	Xã Yên Trung		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09208	Xã Tam Đa		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09238	Xã Văn Môn		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09247	Phường Quế Võ		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09253	Phường Nhân Hòa		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09265	Phường Phương Liễu		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09286	Phường Nam Sơn		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09292	Xã Phù Lãng		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09295	Phường Bồng Lai		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09301	Phường Đào Viên		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09313	Xã Chi Lăng		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09319	Xã Tiên Du		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09325	Phường Hạp Lĩnh		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09334	Xã Liên Bão		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09340	Xã Đại Đồng		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09343	Xã Tân Chi		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09349	Xã Phật Tích		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09367	Phường Từ Sơn		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09370	Phường Tam Sơn		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09379	Phường Phù Khê		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09385	Phường Đồng Nguyên		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09400	Phường Thuận Thành		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09409	Phường Mão Điền		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09427	Phường Trí Quả		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09430	Phường Trạm Lộ		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09433	Phường Song Liễu		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09445	Phường Ninh Xá		Phường	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09454	Xã Gia Bình		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09466	Xã Cao Đức		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09469	Xã Đại Lai		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09475	Xã Nhân Thắng		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09487	Xã Đông Cứu		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09496	Xã Lương Tài		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09499	Xã Trung Kênh		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09523	Xã Trung Chính		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
09529	Xã Lâm Thao		Xã	24	\N	Tỉnh Bắc Ninh	Số: 1658/NQ-UBTVQH15; Ngày: 16/06/2025
04792	Phường Tân Hòa		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04795	Phường Hòa Bình		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04828	Phường Thống Nhất		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04831	Xã Đà Bắc		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04846	Xã Đức Nhàn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04849	Xã Tân Pheo		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04873	Xã Quy Đức		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04876	Xã Cao Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04891	Xã Tiền Phong		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04894	Phường Kỳ Sơn		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04897	Xã Thịnh Minh		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04924	Xã Lương Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04960	Xã Liên Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04978	Xã Kim Bôi		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
04990	Xã Nật Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05014	Xã Mường Động		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05047	Xã Cao Dương		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05068	Xã Hợp Kim		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05086	Xã Dũng Tiến		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05089	Xã Cao Phong		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05092	Xã Thung Nai		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05116	Xã Mường Thàng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05128	Xã Tân Lạc		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05134	Xã Mường Hoa		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05152	Xã Vân Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05158	Xã Mường Bi		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05191	Xã Toàn Thắng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05200	Xã Mai Châu		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05206	Xã Tân Mai		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05212	Xã Pà Cò		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05245	Xã Bao La		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05251	Xã Mai Hạ		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05266	Xã Lạc Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05287	Xã Mường Vang		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05290	Xã Nhân Nghĩa		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05293	Xã Thượng Cốc		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05305	Xã Yên Phú		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05323	Xã Quyết Thắng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05329	Xã Ngọc Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05347	Xã Đại Đồng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05353	Xã Yên Thủy		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05362	Xã Lạc Lương		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05386	Xã Yên Trị		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05392	Xã Lạc Thủy		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05395	Xã An Nghĩa		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
05425	Xã An Bình		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07894	Phường Nông Trang		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07900	Phường Việt Trì		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07909	Phường Thanh Miếu		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07918	Phường Vân Phú		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07942	Phường Phú Thọ		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07948	Phường Âu Cơ		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07954	Phường Phong Châu		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07969	Xã Đoan Hùng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07996	Xã Bằng Luân		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
07999	Xã Chí Đám		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08023	Xã Tây Cốc		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08038	Xã Chân Mộng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08053	Xã Hạ Hòa		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08071	Xã Đan Thượng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08110	Xã Hiền Lương		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08113	Xã Yên Kỳ		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08134	Xã Văn Lang		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08143	Xã Vĩnh Chân		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08152	Xã Thanh Ba		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08173	Xã Quảng Yên		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08203	Xã Hoàng Cương		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08209	Xã Đông Thành		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08218	Xã Chí Tiên		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08227	Xã Liên Minh		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08230	Xã Phù Ninh		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08236	Xã Phú Mỹ		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08245	Xã Trạm Thản		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08254	Xã Dân Chủ		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08275	Xã Bình Phú		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08290	Xã Yên Lập		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08296	Xã Sơn Lương		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08305	Xã Xuân Viên		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08311	Xã Trung Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08323	Xã Thượng Long		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08338	Xã Minh Hòa		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08341	Xã Cẩm Khê		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08344	Xã Tiên Lương		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08377	Xã Vân Bán		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08398	Xã Phú Khê		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08416	Xã Hùng Việt		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08431	Xã Đồng Lương		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08434	Xã Tam Nông		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08443	Xã Hiền Quan		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08467	Xã Vạn Xuân		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08479	Xã Thọ Văn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08494	Xã Lâm Thao		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08500	Xã Xuân Lũng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08515	Xã Hy Cương		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08521	Xã Phùng Nguyên		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08527	Xã Bản Nguyên		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08542	Xã Thanh Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08545	Xã Thu Cúc		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08560	Xã Lai Đồng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08566	Xã Tân Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08584	Xã Võ Miếu		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08590	Xã Xuân Đài		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08593	Xã Minh Đài		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08611	Xã Văn Miếu		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08614	Xã Cự Đồng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08620	Xã Long Cốc		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08632	Xã Hương Cần		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08635	Xã Khả Cửu		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08656	Xã Yên Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08662	Xã Đào Xá		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08674	Xã Thanh Thủy		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08686	Xã Tu Vũ		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08707	Phường Vĩnh Yên		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08716	Phường Vĩnh Phúc		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08740	Phường Phúc Yên		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08746	Phường Xuân Hòa		Phường	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08761	Xã Lập Thạch		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08770	Xã Hợp Lý		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08773	Xã Yên Lãng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08782	Xã Hải Lựu		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08788	Xã Thái Hòa		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08812	Xã Liên Hòa		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08824	Xã Tam Sơn		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08842	Xã Tiên Lữ		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08848	Xã Sông Lô		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08866	Xã Sơn Đông		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08869	Xã Tam Dương		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08872	Xã Tam Dương Bắc		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08896	Xã Hoàng An		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08905	Xã Hội Thịnh		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08911	Xã Tam Đảo		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08914	Xã Đạo Trù		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08923	Xã Đại Đình		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08935	Xã Bình Nguyên		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08944	Xã Bình Tuyền		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08950	Xã Bình Xuyên		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
08971	Xã Xuân Lãng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09025	Xã Yên Lạc		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09040	Xã Tề Lỗ		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09043	Xã Tam Hồng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09052	Xã Nguyệt Đức		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09064	Xã Liên Châu		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09076	Xã Vĩnh Tường		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09079	Xã Vĩnh An		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09100	Xã Vĩnh Hưng		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09106	Xã Vĩnh Thành		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09112	Xã Thổ Tang		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
09154	Xã Vĩnh Phú		Xã	25	\N	Tỉnh Phú Thọ	Số: 1676/NQ-UBTVQH15; Ngày: 16/06/2025
10507	Phường Thành Đông		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10525	Phường Hải Dương		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10532	Phường Lê Thanh Nghị		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10537	Phường Tân Hưng		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10543	Phường Việt Hòa		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10546	Phường Chí Linh		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10549	Phường Chu Văn An		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10552	Phường Nguyễn Trãi		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10570	Phường Trần Hưng Đạo		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10573	Phường Trần Nhân Tông		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10603	Phường Lê Đại Hành		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10606	Xã Nam Sách		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10615	Xã Hợp Tiến		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10633	Xã Trần Phú		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10642	Xã Thái Tân		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10645	Xã An Phú		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10660	Phường Ái Quốc		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10675	Phường Kinh Môn		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10678	Phường Bắc An Phụ		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10705	Xã Nam An Phụ		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10714	Phường Nhị Chiểu		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10726	Phường Phạm Sư Mạnh		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10729	Phường Trần Liễu		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10744	Phường Nguyễn Đại Năng		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10750	Xã Phú Thái		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10756	Xã Lai Khê		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10792	Xã An Thành		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10804	Xã Kim Thành		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10813	Xã Thanh Hà		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10816	Xã Hà Bắc		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10837	Phường Nam Đồng		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10843	Xã Hà Nam		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10846	Xã Hà Tây		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10882	Xã Hà Đông		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10888	Xã Cẩm Giang		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10891	Phường Tứ Minh		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10903	Xã Cẩm Giàng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10909	Xã Tuệ Tĩnh		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10930	Xã Mao Điền		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10945	Xã Kẻ Sặt		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10966	Xã Bình Giang		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10972	Xã Đường An		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10993	Xã Thượng Hồng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
10999	Xã Gia Lộc		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11002	Phường Thạch Khôi		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11020	Xã Yết Kiêu		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11050	Xã Gia Phúc		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11065	Xã Trường Tân		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11074	Xã Tứ Kỳ		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11086	Xã Đại Sơn		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11113	Xã Tân Kỳ		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11131	Xã Chí Minh		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11140	Xã Lạc Phượng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11146	Xã Nguyên Giáp		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11164	Xã Vĩnh Lại		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11167	Xã Tân An		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11203	Xã Ninh Giang		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11218	Xã Hồng Châu		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11224	Xã Khúc Thừa Dụ		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11239	Xã Thanh Miện		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11242	Xã Nguyễn Lương Bằng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11254	Xã Bắc Thanh Miện		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11257	Xã Hải Hưng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11284	Xã Nam Thanh Miện		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11311	Phường Hồng Bàng		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11329	Phường Ngô Quyền		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11359	Phường Gia Viên		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11383	Phường Lê Chân		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11407	Phường An Biên		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11411	Phường Đông Hải		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11413	Phường Hải An		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11443	Phường Kiến An		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11446	Phường Phù Liễn		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11455	Phường Đồ Sơn		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11473	Phường Bạch Đằng		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11488	Phường Lưu Kiếm		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11503	Xã Việt Khê		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11506	Phường Lê Ích Mộc		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11533	Phường Hòa Bình		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11542	Phường Nam Triệu		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11557	Phường Thiên Hương		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11560	Phường Thủy Nguyên		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11581	Phường An Dương		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11593	Phường An Phong		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11602	Phường Hồng An		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11617	Phường An Hải		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11629	Xã An Lão		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11635	Xã An Trường		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11647	Xã An Quang		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11668	Xã An Khánh		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11674	Xã An Hưng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11680	Xã Kiến Thụy		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11689	Phường Hưng Đạo		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11692	Phường Dương Kinh		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11713	Xã Nghi Dương		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11725	Xã Kiến Minh		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11728	Xã Kiến Hưng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11737	Phường Nam Đồ Sơn		Phường	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11749	Xã Kiến Hải		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11755	Xã Tiên Lãng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11761	Xã Quyết Thắng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11779	Xã Tân Minh		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11791	Xã Tiên Minh		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11806	Xã Chấn Hưng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11809	Xã Hùng Thắng		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11824	Xã Vĩnh Bảo		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11836	Xã Vĩnh Thịnh		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11842	Xã Vĩnh Thuận		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11848	Xã Vĩnh Hòa		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11875	Xã Vĩnh Hải		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11887	Xã Vĩnh Am		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11911	Xã Nguyễn Bỉnh Khiêm		Xã	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11914	Đặc khu Cát Hải		Đặc khu	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11948	Đặc khu Bạch Long Vĩ		Đặc khu	31	\N	Thành phố Hải Phòng	Số: 1669/NQ-UBTVQH15; Ngày: 16/06/2025
11953	Phường Phố Hiến		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
11977	Xã Tân Hưng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
11980	Phường Hồng Châu		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
11983	Phường Sơn Nam		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
11992	Xã Lạc Đạo		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
11995	Xã Đại Đồng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12004	Xã Như Quỳnh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12019	Xã Văn Giang		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12025	Xã Phụng Công		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12031	Xã Nghĩa Trụ		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12049	Xã Mễ Sở		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12064	Xã Nguyễn Văn Linh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12070	Xã Hoàn Long		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12073	Xã Yên Mỹ		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12091	Xã Việt Yên		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12103	Phường Mỹ Hào		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12127	Phường Thượng Hồng		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12133	Phường Đường Hào		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12142	Xã Ân Thi		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12148	Xã Phạm Ngũ Lão		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12166	Xã Xuân Trúc		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12184	Xã Nguyễn Trãi		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12196	Xã Hồng Quang		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12205	Xã Khoái Châu		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12223	Xã Triệu Việt Vương		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12238	Xã Việt Tiến		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12247	Xã Châu Ninh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12271	Xã Chí Minh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12280	Xã Lương Bằng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12286	Xã Nghĩa Dân		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12313	Xã Đức Hợp		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12322	Xã Hiệp Cường		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12337	Xã Hoàng Hoa Thám		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12361	Xã Tiên Hoa		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12364	Xã Tiên Lữ		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12391	Xã Quang Hưng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12406	Xã Đoàn Đào		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12424	Xã Tiên Tiến		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12427	Xã Tống Trân		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12452	Phường Trần Hưng Đạo		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12454	Phường Trần Lãm		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12466	Phường Vũ Phúc		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12472	Xã Quỳnh Phụ		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12499	Xã A Sào		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12511	Xã Minh Thọ		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12517	Xã Ngọc Lâm		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12523	Xã Phụ Dực	An Bai town	Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12526	Xã Đồng Bằng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12532	Xã Nguyễn Du		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12577	Xã Quỳnh An		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12583	Xã Tân Tiến		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12586	Xã Hưng Hà		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12595	Xã Ngự Thiên		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12613	Xã Long Hưng	Hung Nhan town	Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12619	Xã Diên Hà		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12631	Xã Thần Khê		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12634	Xã Tiên La		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12676	Xã Lê Quý Đôn		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12685	Xã Hồng Minh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12688	Xã Đông Hưng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12694	Xã Bắc Đông Hưng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12700	Xã Bắc Tiên Hưng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12736	Xã Đông Tiên Hưng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12745	Xã Bắc Đông Quan		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12754	Xã Tiên Hưng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12763	Xã Nam Tiên Hưng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12775	Xã Nam Đông Hưng		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12793	Xã Đông Quan		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12817	Phường Trà Lý		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12826	Xã Thái Thụy		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12850	Xã Tây Thụy Anh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12859	Xã Bắc Thụy Anh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12862	Xã Đông Thụy Anh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12865	Xã Thụy Anh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12904	Xã Nam Thụy Anh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12916	Xã Bắc Thái Ninh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12919	Xã Tây Thái Ninh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12922	Xã Thái Ninh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12943	Xã Đông Thái Ninh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12961	Xã Nam Thái Ninh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12970	Xã Tiền Hải		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
12988	Xã Đông Tiền Hải		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13003	Xã Đồng Châu		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13021	Xã Ái Quốc		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13039	Xã Tây Tiền Hải		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13057	Xã Nam Cường		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13063	Xã Nam Tiền Hải		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13066	Xã Hưng Phú		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13075	Xã Kiến Xương		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13093	Xã Trà Giang		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13096	Xã Bình Nguyên		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13120	Xã Lê Lợi		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13132	Xã Quang Lịch		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13141	Xã Vũ Quý		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13159	Xã Hồng Vũ		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13183	Xã Bình Thanh		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13186	Xã Bình Định		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13192	Xã Vũ Thư		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13219	Xã Vạn Xuân		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13222	Xã Thư Trì		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13225	Phường Thái Bình		Phường	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13246	Xã Tân Thuận		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13264	Xã Thư Vũ		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13279	Xã Vũ Tiên		Xã	33	\N	Tỉnh Hưng Yên	Số: 1666/NQ-UBTVQH15; Ngày: 16/06/2025
13285	Phường Phủ Lý		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13291	Phường Phù Vân		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13318	Phường Châu Sơn		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13324	Phường Duy Tiên		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13330	Phường Duy Tân		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13336	Phường Duy Hà		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13348	Phường Đồng Văn		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13363	Phường Tiên Sơn		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13366	Phường Hà Nam		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13384	Phường Kim Bảng		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13393	Phường Lê Hồ		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13396	Phường Nguyễn Uý		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13402	Phường Kim Thanh		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13420	Phường Tam Chúc		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13435	Phường Lý Thường Kiệt		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13444	Phường Liêm Tuyền		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13456	Xã Liêm Hà		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13474	Xã Tân Thanh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13483	Xã Thanh Bình		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13489	Xã Thanh Lâm		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13495	Xã Thanh Liêm		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13501	Xã Bình Mỹ		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13504	Xã Bình Lục		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13531	Xã Bình Giang		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13540	Xã Bình An		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13558	Xã Bình Sơn		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13573	Xã Lý Nhân		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13579	Xã Bắc Lý		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13591	Xã Nam Xang		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13594	Xã Trần Thương		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13597	Xã Vĩnh Trụ		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13609	Xã Nhân Hà		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13627	Xã Nam Lý		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13669	Phường Nam Định		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13684	Phường Thiên Trường		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13693	Phường Đông A		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13699	Phường Thành Nam		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13708	Phường Mỹ Lộc		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13741	Xã Vụ Bản		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13750	Xã Minh Tân		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13753	Xã Hiển Khánh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13777	Phường Trường Thi		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13786	Xã Liên Minh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13795	Xã Ý Yên		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13807	Xã Tân Minh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13822	Xã Phong Doanh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13834	Xã Vũ Dương		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13864	Xã Vạn Thắng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13870	Xã Yên Cường		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13879	Xã Yên Đồng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13891	Xã Nghĩa Hưng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13894	Xã Rạng Đông		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13900	Xã Đồng Thịnh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13918	Xã Nghĩa Sơn		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13927	Xã Hồng Phong		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13939	Xã Quỹ Nhất		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13957	Xã Nghĩa Lâm		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13966	Xã Nam Trực		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13972	Phường Vị Khê		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13984	Phường Hồng Quang		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
13987	Xã Nam Hồng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14005	Xã Nam Ninh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14011	Xã Nam Minh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14014	Xã Nam Đồng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14026	Xã Cổ Lễ		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14038	Xã Ninh Giang		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14053	Xã Trực Ninh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14056	Xã Cát Thành	Cat Thanh town	Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14062	Xã Quang Hưng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14071	Xã Minh Thái		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14077	Xã Ninh Cường		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14089	Xã Xuân Trường		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14095	Xã Xuân Hồng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14104	Xã Xuân Giang		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14122	Xã Xuân Hưng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14161	Xã Giao Minh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14167	Xã Giao Thuỷ		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14179	Xã Giao Hưng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14182	Xã Giao Hoà		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14194	Xã Giao Bình		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14203	Xã Giao Phúc		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14212	Xã Giao Ninh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14215	Xã Hải Hậu		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14218	Xã Hải Tiến		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14221	Xã Hải Thịnh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14236	Xã Hải Anh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14248	Xã Hải Hưng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14281	Xã Hải An		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14287	Xã Hải Quang		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14308	Xã Hải Xuân		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14329	Phường Hoa Lư		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14359	Phường Nam Hoa Lư		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14362	Phường Tam Điệp		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14365	Phường Trung Sơn		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14371	Phường Yên Sơn		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14389	Xã Gia Lâm		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14401	Xã Gia Tường		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14404	Xã Cúc Phương		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14407	Xã Phú Sơn		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14428	Xã Nho Quan		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14434	Xã Thanh Sơn		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14452	Xã Quỳnh Lưu		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14458	Xã Phú Long		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14464	Xã Gia Viễn		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14482	Xã Gia Hưng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14488	Xã Gia Vân		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14494	Xã Gia Trấn		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14500	Xã Đại Hoàng		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14524	Xã Gia Phong		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14533	Phường Tây Hoa Lư		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14560	Xã Yên Khánh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14563	Xã Khánh Thiện		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14566	Phường Đông Hoa Lư		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14608	Xã Khánh Trung		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14611	Xã Khánh Nhạc		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14614	Xã Khánh Hội		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14620	Xã Phát Diệm		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14623	Xã Bình Minh		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14638	Xã Kim Sơn		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14647	Xã Quang Thiện		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14653	Xã Chất Bình		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14674	Xã Lai Thành		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14677	Xã Định Hóa		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14698	Xã Kim Đông		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14701	Xã Yên Mô		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14725	Phường Yên Thắng		Phường	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14728	Xã Yên Từ		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14743	Xã Yên Mạc		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14746	Xã Đồng Thái		Xã	37	\N	Tỉnh Ninh Bình	Số: 1674/NQ-UBTVQH15; Ngày: 16/06/2025
14758	Phường Hàm Rồng		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14797	Phường Hạc Thành		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14812	Phường Bỉm Sơn		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14818	Phường Quang Trung		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14845	Xã Mường Lát		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14848	Xã Tam Chung		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14854	Xã Mường Lý		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14857	Xã Trung Lý		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14860	Xã Quang Chiểu		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14863	Xã Pù Nhi		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14864	Xã Nhi Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14866	Xã Mường Chanh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14869	Xã Hồi Xuân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14872	Xã Trung Thành		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14875	Xã Trung Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14878	Xã Phú Lệ		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14890	Xã Phú Xuân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14896	Xã Hiền Kiệt		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14902	Xã Nam Xuân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14908	Xã Thiên Phủ		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14923	Xã Bá Thước		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14932	Xã Điền Quang		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14950	Xã Điền Lư		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14953	Xã Quý Lương		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14956	Xã Pù Luông		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14959	Xã Cổ Lũng		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14974	Xã Văn Nho		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
14980	Xã Thiết Ống		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15001	Xã Trung Hạ		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15007	Xã Tam Thanh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15010	Xã Sơn Thủy		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15013	Xã Na Mèo		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15016	Xã Quan Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15019	Xã Tam Lư		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15022	Xã Sơn Điện		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15025	Xã Mường Mìn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15031	Xã Yên Khương		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15034	Xã Yên Thắng		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15043	Xã Giao An		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15049	Xã Văn Phú		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15055	Xã Linh Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15058	Xã Đồng Lương		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15061	Xã Ngọc Lặc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15085	Xã Thạch Lập		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15091	Xã Ngọc Liên		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15106	Xã Nguyệt Ấn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15112	Xã Kiên Thọ		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15124	Xã Minh Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15127	Xã Cẩm Thủy		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15142	Xã Cẩm Thạch		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15148	Xã Cẩm Tú		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15163	Xã Cẩm Vân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15178	Xã Cẩm Tân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15187	Xã Kim Tân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15190	Xã Vân Du		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15199	Xã Thạch Quảng		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15211	Xã Thạch Bình		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15229	Xã Thành Vinh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15250	Xã Ngọc Trạo		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15271	Xã Hà Trung		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15274	Xã Hà Long		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15286	Xã Hoạt Giang		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15298	Xã Lĩnh Toại		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15316	Xã Tống Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15349	Xã Vĩnh Lộc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15361	Xã Tây Đô		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15382	Xã Biện Thượng		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15409	Xã Yên Phú		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15412	Xã Quý Lộc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15421	Xã Yên Trường		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15442	Xã Yên Ninh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15448	Xã Định Hòa		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15457	Xã Định Tân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15469	Xã Yên Định		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15499	Xã Thọ Xuân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15505	Xã Thọ Long		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15520	Xã Xuân Hòa		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15544	Xã Lam Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15553	Xã Sao Vàng		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15568	Xã Thọ Lập		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15574	Xã Xuân Tín		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15592	Xã Xuân Lập		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15607	Xã Bát Mọt		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15610	Xã Yên Nhân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15622	Xã Vạn Xuân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15628	Xã Lương Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15634	Xã Luận Thành		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15643	Xã Thắng Lộc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15646	Xã Thường Xuân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15658	Xã Xuân Chinh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15661	Xã Tân Thành		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15664	Xã Triệu Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15667	Xã Thọ Bình		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15682	Xã Hợp Tiến		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15715	Xã Tân Ninh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15724	Xã Đồng Tiến		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15754	Xã Thọ Ngọc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15763	Xã Thọ Phú		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15766	Xã An Nông		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15772	Xã Thiệu Hóa		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15778	Xã Thiệu Tiến		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15796	Xã Thiệu Quang		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15820	Xã Thiệu Toán		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15835	Xã Thiệu Trung		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15853	Phường Đông Tiến		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15865	Xã Hoằng Hóa		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15880	Xã Hoằng Giang		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15889	Xã Hoằng Phú		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15910	Xã Hoằng Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15925	Phường Nguyệt Viên		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15961	Xã Hoằng Lộc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15976	Xã Hoằng Châu		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
15991	Xã Hoằng Tiến		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16000	Xã Hoằng Thanh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16012	Xã Hậu Lộc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16021	Xã Triệu Lộc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16033	Xã Đông Thành		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16072	Xã Hoa Lộc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16078	Xã Vạn Lộc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16093	Xã Nga Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16108	Xã Tân Tiến		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16114	Xã Nga Thắng		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16138	Xã Hồ Vương		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16144	Xã Nga An		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16171	Xã Ba Đình		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16174	Xã Như Xuân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16177	Xã Xuân Bình		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16186	Xã Hóa Quỳ		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16213	Xã Thanh Phong		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16222	Xã Thanh Quân		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16225	Xã Thượng Ninh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16228	Xã Như Thanh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16234	Xã Xuân Du		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16249	Xã Mậu Lâm		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16258	Xã Xuân Thái		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16264	Xã Yên Thọ		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16273	Xã Thanh Kỳ		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16279	Xã Nông Cống		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16297	Xã Trung Chính		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16309	Xã Thắng Lợi		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16342	Xã Thăng Bình		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16348	Xã Trường Văn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16363	Xã Tượng Lĩnh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16369	Xã Công Chính		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16378	Phường Đông Sơn		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16417	Phường Đông Quang		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16438	Xã Lưu Vệ		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16480	Xã Quảng Yên		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16489	Xã Quảng Chính		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16498	Xã Quảng Ngọc		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16516	Phường Nam Sầm Sơn		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16522	Phường Quảng Phú		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16531	Phường Sầm Sơn		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16540	Xã Quảng Ninh		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16543	Xã Quảng Bình		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16549	Xã Tiên Trang		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16561	Phường Tĩnh Gia		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16576	Phường Ngọc Sơn		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16591	Xã Các Sơn		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16594	Phường Tân Dân		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16597	Phường Hải Lĩnh		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16609	Phường Đào Duy Từ		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16624	Phường Trúc Lâm		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16636	Xã Trường Lâm		Xã	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16645	Phường Hải Bình		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16654	Phường Nghi Sơn		Phường	38	\N	Tỉnh Thanh Hóa	Số: 1686/NQ-UBTVQH15; Ngày: 16/06/2025
16681	Phường Thành Vinh		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16690	Phường Trường Vinh		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16702	Phường Vinh Phú		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16708	Phường Vinh Lộc		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16732	Phường Cửa Lò		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16738	Xã Quế Phong		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16744	Xã Thông Thụ		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16750	Xã Tiền Phong		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16756	Xã Tri Lễ		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16774	Xã Mường Quàng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16777	Xã Quỳ Châu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16792	Xã Châu Tiến		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16801	Xã Hùng Chân		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16804	Xã Châu Bình		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16813	Xã Mường Xén		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16816	Xã Mỹ Lý		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16819	Xã Bắc Lý		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16822	Xã Keng Đu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16828	Xã Huồi Tụ		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16831	Xã Mường Lống		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16834	Xã Na Loi		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16837	Xã Nậm Cắn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16849	Xã Hữu Kiệm		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16855	Xã Chiêu Lưu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16858	Xã Mường Típ		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16870	Xã Na Ngoi		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16876	Xã Tương Dương		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16882	Xã Nhôn Mai		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16885	Xã Hữu Khuông		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16903	Xã Nga My		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16906	Xã Lượng Minh		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16909	Xã Yên Hòa		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16912	Xã Yên Na		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16933	Xã Tam Quang		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16936	Xã Tam Thái		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16939	Phường Thái Hòa		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16941	Xã Nghĩa Đàn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16951	Xã Nghĩa Lâm		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16969	Xã Nghĩa Thọ		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16972	Xã Nghĩa Hưng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
16975	Xã Nghĩa Mai		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17011	Phường Tây Hiếu		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17017	Xã Đông Hiếu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17029	Xã Nghĩa Lộc		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17032	Xã Nghĩa Khánh		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17035	Xã Quỳ Hợp		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17044	Xã Châu Hồng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17056	Xã Châu Lộc		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17059	Xã Tam Hợp		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17071	Xã Minh Hợp		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17077	Xã Mường Ham		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17089	Xã Mường Chọng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17110	Phường Hoàng Mai	Hoang Mai town	Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17125	Phường Quỳnh Mai		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17128	Phường Tân Mai		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17143	Xã Quỳnh Văn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17149	Xã Quỳnh Tam		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17170	Xã Quỳnh Sơn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17176	Xã Quỳnh Anh		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17179	Xã Quỳnh Lưu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17212	Xã Quỳnh Phú		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17224	Xã Quỳnh Thắng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17230	Xã Bình Chuẩn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17239	Xã Mậu Thạch		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17242	Xã Cam Phục		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17248	Xã Châu Khê		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17254	Xã Con Cuông		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17263	Xã Môn Sơn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17266	Xã Tân Kỳ		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17272	Xã Tân Phú		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17278	Xã Giai Xuân		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17284	Xã Nghĩa Đồng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17287	Xã Tiên Đồng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17305	Xã Tân An		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17326	Xã Nghĩa Hành		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17329	Xã Anh Sơn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17335	Xã Thành Bình Thọ		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17344	Xã Nhân Hòa		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17357	Xã Vĩnh Tường		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17365	Xã Anh Sơn Đông		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17380	Xã Yên Xuân		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17395	Xã Hùng Châu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17416	Xã Đức Châu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17419	Xã Hải Châu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17443	Xã Quảng Châu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17464	Xã Diễn Châu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17476	Xã Minh Châu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17479	Xã An Châu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17488	Xã Tân Châu		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17506	Xã Yên Thành		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17515	Xã Bình Minh		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17521	Xã Quang Đồng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17524	Xã Giai Lạc		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17530	Xã Đông Thành		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17560	Xã Vân Du		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17569	Xã Quan Thành		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17605	Xã Hợp Minh		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17611	Xã Vân Tụ		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17623	Xã Bạch Ngọc		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17641	Xã Lương Sơn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17662	Xã Đô Lương		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17677	Xã Văn Hiến		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17689	Xã Thuần Trung		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17707	Xã Bạch Hà		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17713	Xã Đại Đồng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17722	Xã Hạnh Lâm		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17728	Xã Cát Ngạn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17743	Xã Tam Đồng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17759	Xã Sơn Lâm		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17770	Xã Hoa Quân		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17779	Xã Xuân Lâm		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17791	Xã Kim Bảng		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17818	Xã Bích Hào		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17827	Xã Nghi Lộc		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17833	Xã Hải Lộc		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17842	Xã Thần Lĩnh		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17854	Xã Văn Kiều		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17857	Xã Phúc Lộc		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17866	Xã Trung Lộc		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17878	Xã Đông Lộc		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17920	Phường Vinh Hưng		Phường	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17935	Xã Nam Đàn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17944	Xã Đại Huệ		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17950	Xã Vạn An		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17971	Xã Kim Liên		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
17989	Xã Thiên Nhẫn		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
18001	Xã Hưng Nguyên		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
18007	Xã Yên Trung		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
18028	Xã Hưng Nguyên Nam		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
18040	Xã Lam Thành		Xã	40	\N	Tỉnh Nghệ An	Số: 1678/NQ-UBTVQH15; Ngày: 16/06/2025
18073	Phường Thành Sen		Phường	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18100	Phường Trần Phú		Phường	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18115	Phường Bắc Hồng Lĩnh		Phường	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18118	Phường Nam Hồng Lĩnh		Phường	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18133	Xã Hương Sơn		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18160	Xã Sơn Hồng		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18163	Xã Sơn Tiến		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18172	Xã Sơn Tây		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18184	Xã Sơn Giang		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18196	Xã Sơn Kim 1		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18199	Xã Sơn Kim 2		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18202	Xã Tứ Mỹ		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18223	Xã Kim Hoa		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18229	Xã Đức Thọ		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18244	Xã Đức Minh		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18262	Xã Đức Quang		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18277	Xã Đức Thịnh		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18304	Xã Đức Đồng		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18313	Xã Vũ Quang		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18322	Xã Mai Hoa		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18328	Xã Thượng Đức		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18352	Xã Nghi Xuân		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18364	Xã Đan Hải		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18373	Xã Tiên Điền		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18394	Xã Cổ Đạm		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18406	Xã Can Lộc		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18409	Xã Hồng Lộc		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18418	Xã Tùng Lộc		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18436	Xã Trường Lưu		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18466	Xã Gia Hanh		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18481	Xã Xuân Lộc		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18484	Xã Đồng Lộc		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18496	Xã Hương Khê		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18502	Xã Hà Linh		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18523	Xã Hương Bình		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18532	Xã Hương Phố		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18544	Xã Hương Xuân		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18547	Xã Phúc Trạch		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18550	Xã Hương Đô		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18562	Xã Thạch Hà		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18568	Xã Lộc Hà		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18583	Xã Mai Phụ		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18586	Xã Đông Kinh		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18601	Xã Việt Xuyên		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18604	Xã Thạch Khê		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18619	Xã Đồng Tiến		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18628	Xã Thạch Lạc		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18634	Xã Toàn Lưu		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18652	Phường Hà Huy Tập		Phường	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18667	Xã Thạch Xuân		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18673	Xã Cẩm Xuyên		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18676	Xã Thiên Cầm		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18682	Xã Yên Hòa		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18685	Xã Cẩm Bình		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18736	Xã Cẩm Hưng		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18739	Xã Cẩm Duệ		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18742	Xã Cẩm Trung		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18748	Xã Cẩm Lạc		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18754	Phường Sông Trí		Phường	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18766	Xã Kỳ Xuân		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18775	Xã Kỳ Anh		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18781	Phường Hải Ninh		Phường	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18787	Xã Kỳ Văn		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18790	Xã Kỳ Khang		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18814	Xã Kỳ Hoa		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18823	Phường Vũng Áng		Phường	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18832	Phường Hoành Sơn		Phường	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18838	Xã Kỳ Lạc		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18844	Xã Kỳ Thượng		Xã	42	\N	Tỉnh Hà Tĩnh	Số: 1665/NQ-UBTVQH15; Ngày: 16/06/2025
18859	Phường Đồng Thuận		Phường	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18871	Phường Đồng Sơn		Phường	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18880	Phường Đồng Hới		Phường	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18901	Xã Minh Hóa		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18904	Xã Dân Hóa		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18919	Xã Tân Thành		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18922	Xã Kim Điền		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18943	Xã Kim Phú		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18949	Xã Đồng Lê		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18952	Xã Tuyên Sơn		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18958	Xã Tuyên Lâm		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18985	Xã Tuyên Phú		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18991	Xã Tuyên Bình		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
18997	Xã Tuyên Hóa		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19009	Phường Ba Đồn		Phường	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19021	Xã Phú Trạch		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19030	Xã Trung Thuần		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19033	Xã Hòa Trạch		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19051	Xã Tân Gianh		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19057	Xã Quảng Trạch		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19066	Phường Bắc Gianh		Phường	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19075	Xã Nam Ba Đồn		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19093	Xã Nam Gianh		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19111	Xã Hoàn Lão		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19126	Xã Bắc Trạch		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19138	Xã Phong Nha		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19141	Xã Bố Trạch		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19147	Xã Thượng Trạch		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19159	Xã Đông Trạch		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19198	Xã Nam Trạch		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19204	Xã Trường Sơn		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19207	Xã Quảng Ninh		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19225	Xã Ninh Châu		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19237	Xã Trường Ninh		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19246	Xã Lệ Ninh		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19249	Xã Lệ Thủy		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19255	Xã Cam Hồng		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19288	Xã Sen Ngư		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19291	Xã Tân Mỹ		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19309	Xã Trường Phú		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19318	Xã Kim Ngân		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19333	Phường Đông Hà		Phường	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19351	Phường Nam Đông Hà		Phường	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19360	Phường Quảng Trị		Phường	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19363	Xã Vĩnh Linh		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19366	Xã Bến Quan		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19372	Xã Vĩnh Hoàng		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19405	Xã Vĩnh Thủy		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19414	Xã Cửa Tùng		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19429	Xã Khe Sanh		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19432	Xã Lao Bảo		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19435	Xã Hướng Lập		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19441	Xã Hướng Phùng		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19462	Xã Tân Lập		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19483	Xã A Dơi		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19489	Xã Lìa		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19495	Xã Gio Linh		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19496	Xã Cửa Việt	Cua Viet town	Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19501	Xã Bến Hải		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19537	Xã Cồn Tiên		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19555	Xã Hướng Hiệp		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19564	Xã Đakrông		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19567	Xã Ba Lòng		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19588	Xã Tà Rụt		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19594	Xã La Lay		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19597	Xã Cam Lộ		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19603	Xã Hiếu Giang		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19624	Xã Triệu Phong		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19639	Xã Nam Cửa Việt		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19645	Xã Triệu Bình		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19654	Xã Triệu Cơ		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19669	Xã Ái Tử		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19681	Xã Diên Sanh		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19699	Xã Vĩnh Định		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19702	Xã Hải Lăng		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19735	Xã Nam Hải Lăng		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19741	Xã Mỹ Thủy		Xã	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19742	Đặc khu Cồn Cỏ		Đặc khu	44	\N	Tỉnh Quảng Trị	Số: 1680/NQ-UBTVQH15; Ngày: 16/06/2025
19753	Phường Phú Xuân		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19774	Phường Kim Long		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19777	Phường Vỹ Dạ		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19789	Phường Thuận Hóa		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19804	Phường Hương An		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19813	Phường Thủy Xuân		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19815	Phường An Cựu		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19819	Phường Phong Điền		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19828	Phường Phong Phú		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19831	Phường Phong Dinh		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19858	Phường Phong Thái		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19867	Xã Quảng Điền		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19873	Phường Phong Quảng		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19885	Xã Đan Điền		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19900	Phường Thuận An		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19909	Phường Dương Nỗ		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19918	Xã Phú Hồ		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19930	Phường Mỹ Thượng		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19942	Xã Phú Vang		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19945	Xã Phú Vinh		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19960	Phường Phú Bài		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19969	Phường Thanh Thủy		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19975	Phường Hương Thủy		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
19996	Phường Hương Trà		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20014	Phường Hóa Châu		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20017	Phường Kim Trà		Phường	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20035	Xã Bình Điền		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20044	Xã A Lưới 2		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20050	Xã A Lưới 5		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20056	Xã A Lưới 1		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20071	Xã A Lưới 3		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20101	Xã A Lưới 4		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20107	Xã Phú Lộc		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20122	Xã Vinh Lộc		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20131	Xã Hưng Lộc		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20137	Xã Chân Mây - Lăng Cô		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20140	Xã Lộc An		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20161	Xã Khe Tre		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20179	Xã Nam Đông		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20182	Xã Long Quảng		Xã	46	\N	Thành phố Huế	Số: 1675/NQ-UBTVQH15; Ngày: 16/06/2025
20194	Phường Hải Vân	Hoa Hiep Bac Commune	Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20197	Phường Liên Chiểu	Hoa Khanh Bac Commune	Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20200	Phường Hòa Khánh		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20209	Phường Thanh Khê		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20242	Phường Hải Châu		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20257	Phường Hòa Cường	Hoa Cuong Bac Commune	Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20260	Phường Cẩm Lệ		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20263	Phường Sơn Trà		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20275	Phường An Hải		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20285	Phường Ngũ Hành Sơn	Khue My Commune	Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20305	Phường An Khê		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20308	Xã Bà Nà		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20314	Phường Hòa Xuân		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20320	Xã Hòa Vang		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20332	Xã Hòa Tiến		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20333	Đặc khu Hoàng Sa		Đặc khu	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20335	Phường Bàn Thạch		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20341	Phường Tam Kỳ		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20350	Phường Hương Trà		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20356	Phường Quảng Phú		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20364	Xã Chiên Đàn		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20380	Xã Tây Hồ		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20392	Xã Phú Ninh		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20401	Phường Hội An Tây		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20410	Phường Hội An		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20413	Phường Hội An Đông		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20434	Xã Tân Hiệp		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20443	Xã Hùng Sơn		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20455	Xã Tây Giang		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20458	Xã Avương		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20467	Xã Đông Giang		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20476	Xã Sông Kôn		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20485	Xã Sông Vàng		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20494	Xã Bến Hiên		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20500	Xã Đại Lộc		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20506	Xã Thượng Đức		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20515	Xã Hà Nha		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20539	Xã Vu Gia		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20542	Xã Phú Thuận		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20551	Phường Điện Bàn		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20557	Phường Điện Bàn Bắc		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20569	Xã Điện Bàn Tây		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20575	Phường An Thắng		Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20579	Phường Điện Bàn Đông	Dien Nam Trung commune	Phường	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20587	Xã Gò Nổi		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20599	Xã Nam Phước		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20611	Xã Thu Bồn		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20623	Xã Duy Xuyên		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20635	Xã Duy Nghĩa		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20641	Xã Quế Sơn		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20650	Xã Xuân Phú		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20656	Xã Nông Sơn		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20662	Xã Quế Sơn Trung		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20669	Xã Quế Phước		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20695	Xã Thạnh Mỹ		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20698	Xã La Êê		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20704	Xã La Dêê		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20707	Xã Nam Giang		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20710	Xã Bến Giằng		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20716	Xã Đắc Pring		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20722	Xã Khâm Đức		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20728	Xã Phước Hiệp		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20734	Xã Phước Năng		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20740	Xã Phước Chánh		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20752	Xã Phước Thành		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20767	Xã Việt An		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20770	Xã Phước Trà		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20779	Xã Hiệp Đức		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20791	Xã Thăng Bình		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20794	Xã Thăng An		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20818	Xã Đồng Dương		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20827	Xã Thăng Phú		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20836	Xã Thăng Trường		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20848	Xã Thăng Điền		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20854	Xã Tiên Phước		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20857	Xã Sơn Cẩm Hà		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20875	Xã Lãnh Ngọc		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20878	Xã Thạnh Bình		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20900	Xã Trà My		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20908	Xã Trà Liên		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20920	Xã Trà Đốc		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20923	Xã Trà Tân		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20929	Xã Trà Giáp		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20938	Xã Trà Leng		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20941	Xã Trà Tập		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20944	Xã Nam Trà My		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20950	Xã Trà Linh		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20959	Xã Trà Vân		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20965	Xã Núi Thành		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20971	Xã Tam Xuân		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20977	Xã Đức Phú		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20984	Xã Tam Anh	Tam Anh Nam commune	Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
20992	Xã Tam Hải		Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
21004	Xã Tam Mỹ	Tam My Tay commune	Xã	48	\N	Thành phố Đà Nẵng	Số: 1659/NQ-UBTVQH15; Ngày: 16/06/2025
21025	Phường Cẩm Thành		Phường	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21028	Phường Nghĩa Lộ		Phường	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21034	Xã An Phú		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21040	Xã Bình Sơn		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21061	Xã Vạn Tường		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21085	Xã Bình Minh		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21100	Xã Bình Chương		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21109	Xã Đông Sơn		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21115	Xã Trà Bồng		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21124	Xã Thanh Bồng		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21127	Xã Đông Trà Bồng		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21136	Xã Cà Đam		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21154	Xã Tây Trà		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21157	Xã Tây Trà Bồng		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21172	Phường Trương Quang Trọng		Phường	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21181	Xã Thọ Phong		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21196	Xã Trường Giang		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21205	Xã Ba Gia		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21211	Xã Tịnh Khê		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21220	Xã Sơn Tịnh		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21235	Xã Tư Nghĩa		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21238	Xã Vệ Giang		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21244	Xã Trà Giang		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21250	Xã Nghĩa Giang		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21289	Xã Sơn Hà		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21292	Xã Sơn Hạ		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21307	Xã Sơn Linh		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21319	Xã Sơn Thủy		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21325	Xã Sơn Kỳ		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21334	Xã Sơn Tây Thượng		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21340	Xã Sơn Tây		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21343	Xã Sơn Tây Hạ		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21349	Xã Sơn Mai		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21361	Xã Minh Long		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21364	Xã Nghĩa Hành		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21370	Xã Phước Giang		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21385	Xã Đình Cương		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21388	Xã Thiện Tín		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21400	Xã Mộ Đức		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21409	Xã Long Phụng		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21421	Xã Mỏ Cày		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21433	Xã Lân Phong		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21439	Phường Đức Phổ		Phường	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21451	Phường Trà Câu		Phường	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21457	Xã Nguyễn Nghiêm		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21472	Xã Khánh Cường		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21478	Phường Sa Huỳnh		Phường	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21484	Xã Ba Tơ		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21490	Xã Ba Vinh		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21496	Xã Ba Động		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21499	Xã Ba Dinh		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21520	Xã Đặng Thùy Trâm		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21523	Xã Ba Tô		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21529	Xã Ba Vì		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21538	Xã Ba Xa		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21548	Đặc khu Lý Sơn		Đặc khu	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23284	Phường Đăk Cấm		Phường	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23293	Phường Kon Tum		Phường	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23302	Phường Đăk Bla		Phường	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23317	Xã Ngọk Bay		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23326	Xã Ia Chim		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23332	Xã Đăk Rơ Wa		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23341	Xã Đăk Pék		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23344	Xã Đăk Plô		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23356	Xã Xốp		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23365	Xã Ngọc Linh		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23368	Xã Đăk Long		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23374	Xã Đăk Môn		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23377	Xã Bờ Y		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23383	Xã Dục Nông		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23392	Xã Sa Loong		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23401	Xã Đăk Tô		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23416	Xã Đăk Sao		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23419	Xã Đăk Tờ Kan		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23425	Xã Tu Mơ Rông		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23428	Xã Ngọk Tụ		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23430	Xã Kon Đào	Dak Tram commune	Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23446	Xã Măng Ri		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23455	Xã Măng Bút		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23473	Xã Măng Đen		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23476	Xã Kon Plông		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23479	Xã Đăk Rve		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23485	Xã Đăk Kôi		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23497	Xã Kon Braih		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23500	Xã Đăk Hà		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23504	Xã Đăk Pxi		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23510	Xã Đăk Ui		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23512	Xã Đăk Mar		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23515	Xã Ngọk Réo		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23527	Xã Sa Thầy		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23530	Xã Rờ Kơi		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23534	Xã Sa Bình	Ho Moong commune	Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23535	Xã Ia Đal		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23536	Xã Mô Rai		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23538	Xã Ia Tơi		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
23548	Xã Ya Ly		Xã	51	\N	Tỉnh Quảng Ngãi	Số: 1677/NQ-UBTVQH15; Ngày: 16/06/2025
21553	Phường Quy Nhơn Bắc		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21583	Phường Quy Nhơn		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21589	Phường Quy Nhơn Tây		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21592	Phường Quy Nhơn Nam		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21601	Phường Quy Nhơn Đông		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21607	Xã Nhơn Châu		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21609	Xã An Lão		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21616	Xã An Vinh		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21622	Xã An Toàn		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21628	Xã An Hòa		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21637	Phường Tam Quan		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21640	Phường Bồng Sơn		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21655	Phường Hoài Nhơn Bắc		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21661	Phường Hoài Nhơn Tây		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21664	Phường Hoài Nhơn		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21670	Phường Hoài Nhơn Đông		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21673	Phường Hoài Nhơn Nam		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21688	Xã Hoài Ân		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21697	Xã Ân Hảo		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21703	Xã Vạn Đức		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21715	Xã Ân Tường		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21727	Xã Kim Sơn		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21730	Xã Phù Mỹ		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21733	Xã Bình Dương		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21739	Xã Phù Mỹ Bắc		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21751	Xã Phù Mỹ Đông		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21757	Xã Phù Mỹ Tây		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21769	Xã An Lương		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21775	Xã Phù Mỹ Nam		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21786	Xã Vĩnh Thạnh	Vinh Thanh commune	Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21787	Xã Vĩnh Sơn		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21796	Xã Vĩnh Thịnh		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21805	Xã Vĩnh Quang		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21808	Xã Tây Sơn		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21817	Xã Bình Hiệp		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21820	Xã Bình Khê		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21829	Xã Bình An		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21835	Xã Bình Phú		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21853	Xã Phù Cát		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21859	Xã Đề Gi		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21868	Xã Hội Sơn		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21871	Xã Hòa Hội		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21880	Xã Cát Tiến		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21892	Xã Xuân An		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21901	Xã Ngô Mây		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21907	Phường Bình Định		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21910	Phường An Nhơn		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21925	Phường An Nhơn Bắc		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21934	Phường An Nhơn Đông		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21940	Xã An Nhơn Tây		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21943	Phường An Nhơn Nam		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21952	Xã Tuy Phước		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21964	Xã Tuy Phước Bắc		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21970	Xã Tuy Phước Đông		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21985	Xã Tuy Phước Tây		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21994	Xã Vân Canh		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
21997	Xã Canh Liên		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
22006	Xã Canh Vinh		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23563	Phường Diên Hồng		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23575	Phường Pleiku		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23584	Phường Thống Nhất		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23586	Phường Hội Phú		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23590	Xã Biển Hồ		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23602	Phường An Phú		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23611	Xã Gào		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23614	Phường An Bình		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23617	Phường An Khê		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23629	Xã Cửu An		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23638	Xã Kbang		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23644	Xã Đak Rong		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23647	Xã Sơn Lang		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23650	Xã Krong		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23668	Xã Tơ Tung		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23674	Xã Kông Bơ La		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23677	Xã Đak Đoa		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23683	Xã Đak Sơmei		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23701	Xã Kon Gang		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23710	Xã Ia Băng		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23714	Xã KDang	Hnol commune	Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23722	Xã Chư Păh		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23728	Xã Ia Khươl		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23734	Xã Ia Ly		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23749	Xã Ia Phí		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23764	Xã Ia Grai		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23767	Xã Ia Hrung		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23776	Xã Ia Krái		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23782	Xã Ia O		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23788	Xã Ia Chia		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23794	Xã Mang Yang		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23798	Xã Ayun		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23799	Xã Hra		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23812	Xã Lơ Pang		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23818	Xã Kon Chiêng		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23824	Xã Kông Chro		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23830	Xã Chư Krey		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23833	Xã Ya Ma		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23839	Xã SRó		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23842	Xã Đăk Song		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23851	Xã Chơ Long		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23857	Xã Đức Cơ		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23866	Xã Ia Krêl		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23869	Xã Ia Dơk		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23872	Xã Ia Dom		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23881	Xã Ia Pnôn		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23884	Xã Ia Nan		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23887	Xã Chư Prông		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23896	Xã Bàu Cạn		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23908	Xã Ia Tôr		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23911	Xã Ia Boòng		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23917	Xã Ia Púch		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23926	Xã Ia Pia		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23935	Xã Ia Lâu		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23938	Xã Ia Mơ		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23941	Xã Chư Sê		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23942	Xã Chư Pưh		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23947	Xã Bờ Ngoong		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23954	Xã Al Bá		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23971	Xã Ia Hrú		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23977	Xã Ia Ko		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23986	Xã Ia Le		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
23995	Xã Đak Pơ		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24007	Xã Ya Hội		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24013	Xã Pờ Tó		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24022	Xã Ia Pa		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24028	Xã Ia Tul		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24043	Xã Phú Thiện		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24044	Phường Ayun Pa		Phường	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24049	Xã Chư A Thai	Ia Ake Commune	Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24061	Xã Ia Hiao		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24065	Xã Ia Rbol		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24073	Xã Ia Sao		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24076	Xã Phú Túc		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24100	Xã Ia Dreh		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24109	Xã Uar		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
24112	Xã Ia Rsai		Xã	52	\N	Tỉnh Gia Lai	Số: 1664/NQ-UBTVQH15; Ngày: 16/06/2025
22333	Phường Bắc Nha Trang		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22366	Phường Nha Trang		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22390	Phường Tây Nha Trang		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22402	Phường Nam Nha Trang		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22411	Phường Bắc Cam Ranh		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22420	Phường Cam Ranh		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22423	Phường Ba Ngòi		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22432	Phường Cam Linh		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22435	Xã Cam Hiệp		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22453	Xã Cam Lâm		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22465	Xã Cam An		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22480	Xã Nam Cam Ranh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22489	Xã Vạn Ninh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22498	Xã Tu Bông		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22504	Xã Đại Lãnh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22516	Xã Vạn Thắng		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22525	Xã Vạn Hưng		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22528	Phường Ninh Hòa		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22546	Xã Bắc Ninh Hòa		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22552	Xã Tây Ninh Hòa		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22558	Xã Hòa Trí		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22561	Phường Đông Ninh Hòa		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22576	Xã Tân Định		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22591	Phường Hòa Thắng		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22597	Xã Nam Ninh Hòa		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22609	Xã Khánh Vĩnh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22612	Xã Trung Khánh Vĩnh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22615	Xã Bắc Khánh Vĩnh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22624	Xã Tây Khánh Vĩnh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22648	Xã Nam Khánh Vĩnh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22651	Xã Diên Khánh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22657	Xã Diên Điền		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22660	Xã Diên Lâm		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22672	Xã Diên Thọ		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22678	Xã Diên Lạc		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22702	Xã Suối Hiệp		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22708	Xã Suối Dầu		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22714	Xã Khánh Sơn		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22720	Xã Tây Khánh Sơn		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22732	Xã Đông Khánh Sơn		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22736	Đặc khu Trường Sa		Đặc khu	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22738	Phường Đô Vinh		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22741	Phường Bảo An		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22759	Phường Phan Rang		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22780	Phường Đông Hải		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22786	Xã Bác Ái Tây		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22795	Xã Bác Ái		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22801	Xã Bác Ái Đông		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22810	Xã Ninh Sơn		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22813	Xã Lâm Sơn		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22822	Xã Mỹ Sơn		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22828	Xã Anh Dũng		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22834	Phường Ninh Chử		Phường	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22840	Xã Công Hải		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22846	Xã Vĩnh Hải		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22849	Xã Thuận Bắc		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22852	Xã Ninh Hải		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22861	Xã Xuân Hải		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22870	Xã Ninh Phước		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22873	Xã Phước Hậu		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22888	Xã Phước Dinh		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22891	Xã Phước Hữu		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22897	Xã Thuận Nam		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22900	Xã Phước Hà		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22909	Xã Cà Ná		Xã	56	\N	Tỉnh Khánh Hòa	Số: 1667/NQ-UBTVQH15; Ngày: 16/06/2025
22015	Phường Tuy Hòa		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22045	Phường Bình Kiến		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22051	Phường Sông Cầu		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22057	Xã Xuân Lộc		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22060	Xã Xuân Cảnh		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22075	Xã Xuân Thọ		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22076	Phường Xuân Đài		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22081	Xã Đồng Xuân		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22090	Xã Xuân Lãnh		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22096	Xã Phú Mỡ		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22111	Xã Xuân Phước		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22114	Xã Tuy An Bắc		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22120	Xã Tuy An Đông		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22132	Xã Tuy An Tây		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22147	Xã Ô Loan		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22153	Xã Tuy An Nam		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22165	Xã Sơn Hòa		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22171	Xã Tây Sơn		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22177	Xã Vân Hòa		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22192	Xã Suối Trai		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22207	Xã Sông Hinh		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22222	Xã Đức Bình		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22225	Xã Ea Bá		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22237	Xã Ea Ly		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22240	Phường Phú Yên		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24529	Xã Vụ Bổn		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22250	Xã Sơn Thành	Son Thanh Dong commune	Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22255	Xã Tây Hòa		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22258	Phường Đông Hòa		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22261	Phường Hòa Hiệp		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22276	Xã Hòa Thịnh		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22285	Xã Hòa Mỹ		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22291	Xã Hòa Xuân		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22303	Xã Phú Hòa 2		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22319	Xã Phú Hòa 1		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24121	Phường Tân Lập		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24133	Phường Buôn Ma Thuột		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24154	Phường Thành Nhất		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24163	Phường Tân An		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24169	Phường Ea Kao		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24175	Xã Hòa Phú		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24181	Xã Ea Drăng		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24184	Xã Ea H’Leo		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24187	Xã Ea Hiao		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24193	Xã Ea Wy		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24208	Xã Ea Khăl		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24211	Xã Ea Súp		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24214	Xã Ia Lốp		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24217	Xã Ea Rốk		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24221	Xã Ia Rvê	Ia RVe commune	Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24229	Xã Ea Bung		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24235	Xã Buôn Đôn		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24241	Xã Ea Wer		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24250	Xã Ea Nuôl		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24259	Xã Quảng Phú		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24265	Xã Ea Kiết		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24277	Xã Ea Tul		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24280	Xã Cư M’gar		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24286	Xã Ea M’Droh		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24301	Xã Cuôr Đăng		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24305	Phường Buôn Hồ		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24310	Xã Krông Búk		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24313	Xã Cư Pơng		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24316	Xã Pơng Drang		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24328	Xã Ea Drông		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24340	Phường Cư Bao		Phường	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24343	Xã Krông Năng		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24346	Xã Dliê Ya		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24352	Xã Tam Giang		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24364	Xã Phú Xuân		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24373	Xã Ea Kar		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24376	Xã Ea Knốp		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24400	Xã Ea Păl	Ea Păl commune	Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24403	Xã Ea Ô		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24406	Xã Cư Yang		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24412	Xã M’Drắk		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24415	Xã Cư Prao		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24433	Xã Ea Riêng		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24436	Xã Cư M’ta		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24444	Xã Krông Á		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24445	Xã Ea Trang		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24448	Xã Krông Bông		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24454	Xã Dang Kang		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24472	Xã Hòa Sơn		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24478	Xã Cư Pui		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24484	Xã Yang Mao		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24490	Xã Krông Pắc		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24496	Xã Ea Kly		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24502	Xã Ea Phê		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24505	Xã Ea Knuếc		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24526	Xã Tân Tiến		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24538	Xã Krông Ana		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24540	Xã Ea Ning		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24544	Xã Ea Ktur		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24559	Xã Ea Na		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24561	Xã Dray Bhăng	Dray Bhang Commune	Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24568	Xã Dur Kmăl		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24580	Xã Liên Sơn Lắk		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24595	Xã Đắk Liêng		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24598	Xã Đắk Phơi		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24604	Xã Krông Nô		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
24607	Xã Nam Ka		Xã	66	\N	Tỉnh Đắk Lắk	Số: 1660/NQ-UBTVQH15; Ngày: 16/06/2025
22918	Phường Mũi Né		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22924	Phường Phú Thuỷ		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22933	Phường Hàm Thắng		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22945	Phường Phan Thiết		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22954	Phường Tiến Thành		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22960	Phường Bình Thuận		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22963	Xã Tuyên Quang		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22969	Xã Liên Hương		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22972	Xã Phan Rí Cửa		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22978	Xã Tuy Phong		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
22981	Xã Vĩnh Hảo		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23005	Xã Bắc Bình		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23008	Xã Phan Sơn		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23020	Xã Hải Ninh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23023	Xã Sông Lũy		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23032	Xã Lương Sơn		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23041	Xã Hồng Thái		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23053	Xã Hòa Thắng		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23059	Xã Hàm Thuận		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23065	Xã La Dạ		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23074	Xã Đông Giang		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23086	Xã Hồng Sơn		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23089	Xã Hàm Thuận Bắc		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23095	Xã Hàm Liêm		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23110	Xã Hàm Thuận Nam		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23122	Xã Hàm Thạnh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23128	Xã Hàm Kiệm		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23134	Xã Tân Lập		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23143	Xã Tân Thành		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23149	Xã Tánh Linh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23152	Xã Bắc Ruộng		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23158	Xã Nghị Đức		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23173	Xã Đồng Kho		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23188	Xã Suối Kiết		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23191	Xã Đức Linh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23194	Xã Hoài Đức		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23200	Xã Nam Thành		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23227	Xã Trà Tân		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23230	Xã Tân Minh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23231	Phường Phước Hội		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23235	Phường La Gi		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23236	Xã Hàm Tân		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23246	Xã Tân Hải	Tan Tien commune	Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23266	Xã Sơn Mỹ		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
23272	Đặc khu Phú Quý		Đặc khu	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24611	Phường Bắc Gia Nghĩa	Nghĩa Đức precinct	Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24615	Phường Nam Gia Nghĩa	Nghia Tan precinct	Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24616	Xã Quảng Sơn		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24617	Phường Đông Gia Nghĩa	Nghia Trung precinct	Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24620	Xã Quảng Hòa		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24631	Xã Quảng Khê		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24637	Xã Tà Đùng		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24640	Xã Cư Jút		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24646	Xã Đắk Wil		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24649	Xã Nam Dong		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24664	Xã Đức Lập		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24670	Xã Đắk Mil		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24678	Xã Đắk Sắk		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24682	Xã Thuận An		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24688	Xã Krông Nô		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24697	Xã Nam Đà		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24703	Xã Nâm Nung		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24712	Xã Quảng Phú		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24717	Xã Đức An		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24718	Xã Đắk Song		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24722	Xã Thuận Hạnh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24730	Xã Trường Xuân		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24733	Xã Kiến Đức		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24736	Xã Quảng Trực		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24739	Xã Tuy Đức		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24748	Xã Quảng Tân		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24751	Xã Nhân Cơ		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24760	Xã Quảng Tín		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24778	Phường Lâm Viên - Đà Lạt		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24781	Phường Xuân Hương - Đà Lạt		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24787	Phường Cam Ly - Đà Lạt		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24805	Phường Xuân Trường - Đà Lạt		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24820	Phường 2 Bảo Lộc		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24823	Phường 1 Bảo Lộc		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24829	Phường B’Lao		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24841	Phường 3 Bảo Lộc		Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24846	Phường Lang Biang - Đà Lạt	Lac Duong Commune	Phường	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24848	Xã Lạc Dương	Da Nhim	Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24853	Xã Đam Rông 4		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24868	Xã Nam Ban Lâm Hà		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24871	Xã Đinh Văn Lâm Hà		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24875	Xã Đam Rông 3		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24877	Xã Đam Rông 2		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24883	Xã Nam Hà Lâm Hà		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24886	Xã Đam Rông 1		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24895	Xã Phú Sơn Lâm Hà		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24907	Xã Phúc Thọ Lâm Hà		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24916	Xã Tân Hà Lâm Hà		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24931	Xã Đơn Dương		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24934	Xã D’Ran		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24943	Xã Ka Đô		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24955	Xã Quảng Lập		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24958	Xã Đức Trọng		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24967	Xã Hiệp Thạnh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24976	Xã Tân Hội		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24985	Xã Ninh Gia		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24988	Xã Tà Năng		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
24991	Xã Tà Hine		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25000	Xã Di Linh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25007	Xã Đinh Trang Thượng		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25015	Xã Gia Hiệp		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25018	Xã Bảo Thuận		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25036	Xã Hòa Ninh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25042	Xã Hòa Bắc		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25051	Xã Sơn Điền		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25054	Xã Bảo Lâm 1		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25057	Xã Bảo Lâm 5		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25063	Xã Bảo Lâm 4		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25084	Xã Bảo Lâm 2		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25093	Xã Bảo Lâm 3		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25099	Xã Đạ Huoai		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25105	Xã Đạ Huoai 2		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25114	Xã Đạ Huoai 3		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25126	Xã Đạ Tẻh		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25135	Xã Đạ Tẻh 3		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25138	Xã Đạ Tẻh 2		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25159	Xã Cát Tiên		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25162	Xã Cát Tiên 3		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25180	Xã Cát Tiên 2		Xã	68	\N	Tỉnh Lâm Đồng	Số: 1671/NQ-UBTVQH15; Ngày: 16/06/2025
25195	Phường Bình Phước		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25210	Phường Đồng Xoài		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25217	Phường Phước Long		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25220	Phường Phước Bình		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25222	Xã Bù Gia Mập		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25225	Xã Đăk Ơ		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25231	Xã Đa Kia		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25246	Xã Bình Tân		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25252	Xã Phú Riềng		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25255	Xã Long Hà		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25261	Xã Phú Trung		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25267	Xã Phú Nghĩa		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25270	Xã Lộc Ninh		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25279	Xã Lộc Tấn		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25280	Xã Lộc Thạnh	Loc Thanh commune	Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25292	Xã Lộc Quang		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25294	Xã Lộc Thành		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25303	Xã Lộc Hưng		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25308	Xã Thiện Hưng	Thanh Binh town	Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25309	Xã Hưng Phước		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25318	Xã Tân Tiến		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25326	Phường Bình Long		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25333	Phường An Lộc		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25345	Xã Tân Hưng		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25349	Xã Minh Đức		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25351	Xã Tân Quan		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25357	Xã Tân Khai		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25363	Xã Đồng Phú		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25378	Xã Tân Lợi		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25387	Xã Thuận Lợi		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25390	Xã Đồng Tâm		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25396	Xã Bù Đăng		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25399	Xã Đak Nhau		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25402	Xã Thọ Sơn		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25405	Xã Bom Bo		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25417	Xã Nghĩa Trung		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25420	Xã Phước Sơn		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25432	Phường Chơn Thành		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25441	Phường Minh Hưng		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25450	Xã Nha Bích		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25993	Phường Trảng Dài		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26005	Phường Hố Nai		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26017	Phường Tam Hiệp		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26020	Phường Long Bình		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26041	Phường Trấn Biên		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26068	Phường Biên Hòa		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26080	Phường Long Khánh		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26089	Phường Bình Lộc		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26098	Phường Bảo Vinh		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26104	Phường Xuân Lập		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26113	Phường Hàng Gòn		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26116	Xã Tân Phú		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26119	Xã Đak Lua		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26122	Xã Nam Cát Tiên		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26134	Xã Tà Lài		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26158	Xã Phú Lâm		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26170	Xã Trị An		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26173	Xã Phú Lý		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26179	Xã Tân An		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26188	Phường Tân Triều		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26206	Xã Định Quán		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26209	Xã Thanh Sơn		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26215	Xã Phú Vinh		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26221	Xã Phú Hòa		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26227	Xã La Ngà		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26248	Xã Trảng Bom		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26254	Xã Bàu Hàm		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26278	Xã Bình Minh		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26281	Xã Hưng Thịnh		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26296	Xã An Viễn		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26299	Xã Thống Nhất		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26311	Xã Gia Kiệm		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26326	Xã Dầu Giây		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26332	Xã Xuân Quế		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26341	Xã Cẩm Mỹ		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26347	Xã Xuân Đường		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26359	Xã Xuân Đông		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26362	Xã Sông Ray		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26368	Xã Long Thành		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26374	Phường Tam Phước		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26377	Phường Phước Tân		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26380	Phường Long Hưng		Phường	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26383	Xã An Phước		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26389	Xã Bình An		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26413	Xã Long Phước		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26422	Xã Phước Thái		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26425	Xã Xuân Lộc		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26428	Xã Xuân Bắc		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26434	Xã Xuân Thành		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26446	Xã Xuân Hòa		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26458	Xã Xuân Phú		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26461	Xã Xuân Định		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26485	Xã Nhơn Trạch		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26491	Xã Đại Phước		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
26503	Xã Phước An		Xã	75	\N	Tỉnh Đồng Nai	Số: 1662/NQ-UBTVQH15; Ngày: 16/06/2025
25747	Phường Thủ Dầu Một		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25750	Phường Phú Lợi		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25760	Phường Bình Dương		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25768	Phường Phú An		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25771	Phường Chánh Hiệp		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25777	Xã Dầu Tiếng		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25780	Xã Minh Thạnh		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25792	Xã Long Hòa		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25807	Xã Thanh An		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25813	Phường Bến Cát		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25819	Xã Trừ Văn Thố		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25822	Xã Bàu Bàng		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25837	Phường Chánh Phú Hòa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25840	Phường Long Nguyên		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25843	Phường Tây Nam		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25846	Phường Thới Hòa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25849	Phường Hòa Lợi		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25858	Xã Phú Giáo		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25864	Xã Phước Thành		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25867	Xã An Long		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25882	Xã Phước Hòa		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25888	Phường Tân Uyên		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25891	Phường Tân Khánh		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25906	Xã Bắc Tân Uyên		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25909	Xã Thường Tân		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25912	Phường Vĩnh Tân		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25915	Phường Bình Cơ		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25920	Phường Tân Hiệp	Tan Hiep Commune	Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25942	Phường Dĩ An		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25945	Phường Tân Đông Hiệp		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25951	Phường Đông Hòa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25966	Phường Lái Thiêu		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25969	Phường Thuận Giao		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25975	Phường An Phú		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25978	Phường Thuận An		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25987	Phường Bình Hòa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26506	Phường Vũng Tàu		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26526	Phường Tam Thắng	Ninh An Nguyên Commune	Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26536	Phường Rạch Dừa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26542	Phường Phước Thắng		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26545	Xã Long Sơn		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26560	Phường Bà Rịa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26566	Phường Long Hương		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26572	Phường Tam Long		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26575	Xã Ngãi Giao		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26584	Xã Xuân Sơn		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26590	Xã Bình Giã		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26596	Xã Châu Đức		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26608	Xã Kim Long		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26617	Xã Nghĩa Thành		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26620	Xã Hồ Tràm		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26632	Xã Xuyên Mộc		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26638	Xã Bàu Lâm		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26641	Xã Hòa Hội		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26647	Xã Hòa Hiệp		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26656	Xã Bình Châu		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26659	Xã Long Điền		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26662	Xã Long Hải		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26680	Xã Đất Đỏ		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26686	Xã Phước Hải		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26704	Phường Phú Mỹ		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26710	Phường Tân Hải		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26713	Phường Tân Phước		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26725	Phường Tân Thành		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26728	Xã Châu Pha		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26732	Đặc khu Côn Đảo		Đặc khu	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26737	Phường Tân Định		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26740	Phường Sài Gòn		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26743	Phường Bến Thành		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26758	Phường Cầu Ông Lãnh		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26767	Phường An Phú Đông		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26773	Phường Thới An		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26782	Phường Tân Thới Hiệp		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26785	Phường Trung Mỹ Tây		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26791	Phường Đông Hưng Thuận		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26800	Phường Linh Xuân		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26803	Phường Tam Bình		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26809	Phường Hiệp Bình		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26824	Phường Thủ Đức		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26833	Phường Long Bình		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26842	Phường Tăng Nhơn Phú		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26848	Phường Phước Long		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26857	Phường Long Phước		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26860	Phường Long Trường		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26876	Phường An Nhơn		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26878	Phường An Hội Đông		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26882	Phường An Hội Tây		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26884	Phường Gò Vấp		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26890	Phường Hạnh Thông		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26898	Phường Thông Tây Hội		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26905	Phường Bình Lợi Trung		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26911	Phường Bình Quới		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26929	Phường Bình Thạnh		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26944	Phường Gia Định		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26956	Phường Thạnh Mỹ Tây		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26968	Phường Tân Sơn Nhất		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26977	Phường Tân Sơn Hòa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26983	Phường Bảy Hiền		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
26995	Phường Tân Hòa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27004	Phường Tân Bình		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27007	Phường Tân Sơn		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27013	Phường Tây Thạnh		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27019	Phường Tân Sơn Nhì		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27022	Phường Phú Thọ Hòa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27028	Phường Phú Thạnh		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27031	Phường Tân Phú		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27043	Phường Đức Nhuận		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27058	Phường Cầu Kiệu		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27073	Phường Phú Nhuận		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27094	Phường An Khánh		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27097	Phường Bình Trưng		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27112	Phường Cát Lái		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27139	Phường Xuân Hòa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27142	Phường Nhiêu Lộc		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27154	Phường Bàn Cờ		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27163	Phường Hòa Hưng		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27169	Phường Diên Hồng		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27190	Phường Vườn Lài		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27211	Phường Hòa Bình		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27226	Phường Phú Thọ		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27232	Phường Bình Thới		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27238	Phường Minh Phụng		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27259	Phường Xóm Chiếu		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27265	Phường Khánh Hội		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27286	Phường Vĩnh Hội		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27301	Phường Chợ Quán		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27316	Phường An Đông		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27343	Phường Chợ Lớn		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27349	Phường Phú Lâm		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27364	Phường Bình Phú		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27367	Phường Bình Tây		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27373	Phường Bình Tiên		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27418	Phường Chánh Hưng		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27424	Phường Bình Đông		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27427	Phường Phú Định		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27439	Phường Bình Hưng Hòa		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27442	Phường Bình Tân		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27448	Phường Bình Trị Đông		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27457	Phường Tân Tạo		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27460	Phường An Lạc		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27475	Phường Tân Hưng		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27478	Phường Tân Thuận		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27484	Phường Phú Thuận		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27487	Phường Tân Mỹ		Phường	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27496	Xã Tân An Hội		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27508	Xã An Nhơn Tây		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27511	Xã Nhuận Đức		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27526	Xã Thái Mỹ		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27541	Xã Phú Hòa Đông		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27544	Xã Bình Mỹ		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27553	Xã Củ Chi		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27559	Xã Hóc Môn		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27568	Xã Đông Thạnh		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27577	Xã Xuân Thới Sơn		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27592	Xã Bà Điểm		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27595	Xã Tân Nhựt		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27601	Xã Vĩnh Lộc		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27604	Xã Tân Vĩnh Lộc		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27610	Xã Bình Lợi		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27619	Xã Bình Hưng		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27628	Xã Hưng Long		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27637	Xã Bình Chánh		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27655	Xã Nhà Bè		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27658	Xã Hiệp Phước		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27664	Xã Cần Giờ		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27667	Xã Bình Khánh		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27673	Xã An Thới Đông		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
27676	Xã Thạnh An		Xã	79	\N	Thành phố Hồ Chí Minh	Số: 1685/NQ-UBTVQH15; Ngày: 16/06/2025
25459	Phường Tân Ninh		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25480	Phường Bình Minh		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25486	Xã Tân Biên		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25489	Xã Tân Lập		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25498	Xã Thạnh Bình		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25510	Xã Trà Vong		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25516	Xã Tân Châu		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25522	Xã Tân Đông		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25525	Xã Tân Hội		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25531	Xã Tân Hòa		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25534	Xã Tân Thành		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25549	Xã Tân Phú		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25552	Xã Dương Minh Châu		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25567	Phường Ninh Thạnh		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25573	Xã Cầu Khởi		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25579	Xã Lộc Ninh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25585	Xã Châu Thành		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25588	Xã Hảo Đước		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25591	Xã Phước Vinh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25606	Xã Hòa Hội		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25621	Xã Ninh Điền		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25630	Phường Long Hoa		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25633	Phường Thanh Điền		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25645	Phường Hòa Thành		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25654	Phường Gò Dầu		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25657	Xã Thạnh Đức		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25663	Xã Phước Thạnh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25666	Xã Truông Mít		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25672	Phường Gia Lộc		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25681	Xã Bến Cầu		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25684	Xã Long Chữ		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25702	Xã Long Thuận		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25708	Phường Trảng Bàng		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25711	Xã Hưng Thuận		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25729	Xã Phước Chỉ		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
25732	Phường An Tịnh		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27694	Phường Long An		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27712	Phường Tân An		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27715	Phường Khánh Hậu		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27721	Xã Tân Hưng		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27727	Xã Hưng Điền		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27736	Xã Vĩnh Thạnh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27748	Xã Vĩnh Châu		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27757	Xã Vĩnh Hưng		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27763	Xã Khánh Hưng		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27775	Xã Tuyên Bình		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27787	Phường Kiến Tường		Phường	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27793	Xã Bình Hiệp		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27811	Xã Bình Hòa		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27817	Xã Tuyên Thạnh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27823	Xã Mộc Hóa		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27826	Xã Tân Thạnh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27838	Xã Nhơn Hòa Lập		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27841	Xã Hậu Thạnh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27856	Xã Nhơn Ninh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27865	Xã Thạnh Hóa		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27868	Xã Bình Thành		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27877	Xã Thạnh Phước		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27889	Xã Tân Tây		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27898	Xã Đông Thành		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27907	Xã Mỹ Quý		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27925	Xã Đức Huệ		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27931	Xã Hậu Nghĩa		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27937	Xã Đức Hòa		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27943	Xã An Ninh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27952	Xã Hiệp Hòa		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27964	Xã Đức Lập		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27976	Xã Mỹ Hạnh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27979	Xã Hòa Khánh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27991	Xã Bến Lức		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
27994	Xã Thạnh Lợi		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28003	Xã Lương Hòa		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28015	Xã Bình Đức		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28018	Xã Mỹ Yên		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28036	Xã Thủ Thừa		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28051	Xã Mỹ Thạnh		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28066	Xã Mỹ An		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28072	Xã Tân Long		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28075	Xã Tân Trụ		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28087	Xã Nhựt Tảo		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28093	Xã Vàm Cỏ		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28108	Xã Cần Đước		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28114	Xã Rạch Kiến		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28126	Xã Long Cang		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28132	Xã Mỹ Lệ		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28138	Xã Tân Lân		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28144	Xã Long Hựu		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28159	Xã Cần Giuộc		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28165	Xã Phước Lý		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28177	Xã Mỹ Lộc		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28201	Xã Phước Vĩnh Tây		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28207	Xã Tân Tập		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28210	Xã Tầm Vu		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28222	Xã Vĩnh Công		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28225	Xã Thuận Mỹ		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28243	Xã An Lục Long		Xã	80	\N	Tỉnh Tây Ninh	Số: 1682/NQ-UBTVQH15; Ngày: 16/06/2025
28249	Phường Đạo Thạnh		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28261	Phường Mỹ Tho		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28270	Phường Thới Sơn		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28273	Phường Mỹ Phong		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28285	Phường Trung An		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28297	Phường Long Thuận		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28306	Phường Gò Công		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28315	Phường Bình Xuân		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28321	Xã Tân Phước 1		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28327	Xã Tân Phước 2		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28336	Xã Hưng Thạnh		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28345	Xã Tân Phước 3		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28360	Xã Cái Bè		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28366	Xã Hậu Mỹ		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28378	Xã Mỹ Thiện		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28393	Xã Hội Cư		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28405	Xã Mỹ Đức Tây		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28414	Xã Mỹ Lợi		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28426	Xã Thanh Hưng		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28429	Xã An Hữu		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28435	Phường Mỹ Phước Tây		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28436	Phường Thanh Hòa		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28439	Phường Cai Lậy		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28444	Xã Thạnh Phú		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28456	Xã Mỹ Thành		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28468	Xã Tân Phú		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28471	Xã Bình Phú		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28477	Phường Nhị Quý		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28501	Xã Hiệp Đức		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28504	Xã Long Tiên		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28516	Xã Ngũ Hiệp		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28519	Xã Châu Thành		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28525	Xã Tân Hương		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28537	Xã Long Hưng		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28543	Xã Long Định		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28564	Xã Bình Trưng		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28576	Xã Vĩnh Kim		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28582	Xã Kim Sơn		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28594	Xã Chợ Gạo		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28603	Xã Mỹ Tịnh An		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28615	Xã Lương Hòa Lạc		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28627	Xã Tân Thuận Bình		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28633	Xã An Thạnh Thủy		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28648	Xã Bình Ninh		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28651	Xã Vĩnh Bình		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28660	Xã Đồng Sơn		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28663	Xã Phú Thành		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28678	Xã Vĩnh Hựu		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28687	Xã Long Bình		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28693	Xã Tân Thới		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28696	Xã Tân Phú Đông		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28702	Xã Tân Hòa		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28720	Xã Gia Thuận		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28723	Xã Tân Đông		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28729	Phường Sơn Qui		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28738	Xã Tân Điền		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28747	Xã Gò Công Đông		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29869	Phường Cao Lãnh		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29884	Phường Mỹ Ngãi		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29888	Phường Mỹ Trà	My Phu Commune	Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29905	Phường Sa Đéc		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29926	Xã Tân Hồng		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29929	Xã Tân Hộ Cơ		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29938	Xã Tân Thành		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29944	Xã An Phước		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29954	Phường An Bình		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29955	Phường Hồng Ngự		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29971	Xã Thường Phước		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29978	Phường Thường Lạc		Phường	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29983	Xã Long Khánh		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
29992	Xã Long Phú Thuận		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30001	Xã Tràm Chim		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30010	Xã Tam Nông		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30019	Xã An Hòa		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30025	Xã Phú Cường		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30028	Xã An Long		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30034	Xã Phú Thọ		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30037	Xã Tháp Mười		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30043	Xã Phương Thịnh		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30046	Xã Trường Xuân		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30055	Xã Mỹ Quí		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30061	Xã Đốc Binh Kiều		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30073	Xã Thanh Mỹ		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30076	Xã Mỹ Thọ		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30085	Xã Ba Sao		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30088	Xã Phong Mỹ		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30112	Xã Mỹ Hiệp		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30118	Xã Bình Hàng Trung		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30130	Xã Thanh Bình		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30154	Xã Tân Long		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30157	Xã Tân Thạnh		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30163	Xã Bình Thành		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30169	Xã Lấp Vò		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30178	Xã Mỹ An Hưng		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30184	Xã Tân Khánh Trung		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30208	Xã Hòa Long		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30214	Xã Tân Dương		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30226	Xã Lai Vung		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30235	Xã Phong Hòa		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30244	Xã Phú Hựu		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30253	Xã Tân Nhuận Đông		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
30259	Xã Tân Phú Trung		Xã	82	\N	Tỉnh Đồng Tháp	Số: 1663/NQ-UBTVQH15; Ngày: 16/06/2025
28756	Phường Phú Khương		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28777	Phường An Hội		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28783	Phường Sơn Đông		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28789	Phường Bến Tre		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28807	Xã Giao Long		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28810	Xã Phú Túc		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28840	Xã Tân Phú		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28858	Phường Phú Tân		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28861	Xã Tiên Thủy		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28870	Xã Chợ Lách		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28879	Xã Phú Phụng		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28894	Xã Vĩnh Thành		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28901	Xã Hưng Khánh Trung		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28903	Xã Mỏ Cày		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28915	Xã Phước Mỹ Trung		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28921	Xã Tân Thành Bình		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28945	Xã Đồng Khởi		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28948	Xã Nhuận Phú Tân		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28957	Xã An Định		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28969	Xã Thành Thới		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28981	Xã Hương Mỹ		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28984	Xã Giồng Trôm		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28987	Xã Lương Hòa		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28993	Xã Lương Phú		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
28996	Xã Châu Hòa		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29020	Xã Phước Long		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29029	Xã Tân Hào		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29044	Xã Hưng Nhượng		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29050	Xã Bình Đại		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29062	Xã Phú Thuận		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29077	Xã Lộc Thuận		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29083	Xã Châu Hưng		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29089	Xã Thạnh Trị		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29104	Xã Thạnh Phước		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29107	Xã Thới Thuận		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29110	Xã Ba Tri		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29122	Xã Mỹ Chánh Hòa		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29125	Xã Bảo Thạnh		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29137	Xã Tân Xuân		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29143	Xã An Ngãi Trung		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29158	Xã An Hiệp		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29167	Xã Tân Thủy		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29182	Xã Thạnh Phú		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29191	Xã Quới Điền		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29194	Xã Đại Điền		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29221	Xã Thạnh Hải		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29224	Xã An Qui		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29227	Xã Thạnh Phong		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29242	Phường Trà Vinh		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29254	Phường Nguyệt Hóa		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29263	Phường Long Đức		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29266	Xã Càng Long		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29275	Xã An Trường		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29278	Xã Tân An		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29287	Xã Bình Phú		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29302	Xã Nhị Long		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29308	Xã Cầu Kè		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29317	Xã An Phú Tân		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29329	Xã Phong Thạnh		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29335	Xã Tam Ngãi		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29341	Xã Tiểu Cần		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29362	Xã Hùng Hòa		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29365	Xã Tập Ngãi		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29371	Xã Tân Hòa		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29374	Xã Châu Thành		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29386	Xã Song Lộc		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29398	Phường Hòa Thuận		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29407	Xã Hưng Mỹ		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29410	Xã Hòa Minh		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29413	Xã Long Hòa		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29416	Xã Cầu Ngang		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29419	Xã Mỹ Long		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29431	Xã Vinh Kim		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29446	Xã Nhị Trường		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29455	Xã Hiệp Mỹ		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29461	Xã Trà Cú		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29467	Xã Tập Sơn		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29476	Xã Lưu Nghiệp Anh		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29489	Xã Hàm Giang		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29491	Xã Đại An		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29497	Xã Đôn Châu		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29506	Xã Long Hiệp		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29512	Phường Duyên Hải		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29513	Xã Long Thành		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29516	Phường Trường Long Hòa		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29518	Xã Long Hữu		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29530	Xã Ngũ Lạc		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29533	Xã Long Vĩnh		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29536	Xã Đông Hải		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29551	Phường Long Châu		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29557	Phường Phước Hậu		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29566	Phường Tân Ngãi		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29584	Xã An Bình		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29590	Phường Thanh Đức		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29593	Phường Tân Hạnh		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29602	Xã Long Hồ		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29611	Xã Phú Quới		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29623	Xã Nhơn Phú		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29638	Xã Bình Phước		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29641	Xã Cái Nhum		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29653	Xã Tân Long Hội		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29659	Xã Trung Thành		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29668	Xã Quới An		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29677	Xã Quới Thiện		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29683	Xã Trung Hiệp		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29698	Xã Trung Ngãi		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29701	Xã Hiếu Phụng		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29713	Xã Hiếu Thành		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29719	Xã Tam Bình		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29728	Xã Cái Ngang		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29734	Xã Hòa Hiệp		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29740	Xã Song Phú		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29767	Xã Ngãi Tứ		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29770	Phường Cái Vồn		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29771	Phường Bình Minh		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29785	Xã Tân Lược		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29788	Xã Mỹ Thuận		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29800	Xã Tân Quới		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29812	Phường Đông Thành		Phường	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29821	Xã Trà Ôn		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29830	Xã Hòa Bình		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29836	Xã Trà Côn		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29845	Xã Vĩnh Xuân		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
29857	Xã Lục Sĩ Thành		Xã	86	\N	Tỉnh Vĩnh Long	Số: 1687/NQ-UBTVQH15; Ngày: 16/06/2025
30292	Phường Bình Đức		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30301	Phường Mỹ Thới		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30307	Phường Long Xuyên	My Hoa Ward	Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30313	Xã Mỹ Hòa Hưng		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30316	Phường Châu Đốc		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30325	Phường Vĩnh Tế		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30337	Xã An Phú		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30341	Xã Khánh Bình		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30346	Xã Nhơn Hội		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30352	Xã Phú Hữu		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30367	Xã Vĩnh Hậu		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30376	Phường Tân Châu		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30377	Phường Long Phú		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30385	Xã Vĩnh Xương		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30388	Xã Tân An		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30403	Xã Châu Phong		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30406	Xã Phú Tân		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30409	Xã Chợ Vàm		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30421	Xã Phú Lâm		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30430	Xã Hòa Lạc		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30436	Xã Phú An		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30445	Xã Bình Thạnh Đông		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30463	Xã Châu Phú		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30469	Xã Mỹ Đức		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30478	Xã Vĩnh Thạnh Trung		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30481	Xã Thạnh Mỹ Tây		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30487	Xã Bình Mỹ		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30502	Phường Thới Sơn		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30505	Phường Chi Lăng		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30520	Phường Tịnh Biên		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30526	Xã An Cư		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30538	Xã Núi Cấm		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30544	Xã Tri Tôn		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30547	Xã Ba Chúc		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30568	Xã Vĩnh Gia		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30577	Xã Ô Lâm		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30580	Xã Cô Tô		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30589	Xã An Châu		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30595	Xã Cần Đăng		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30604	Xã Vĩnh An		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30607	Xã Bình Hòa		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30619	Xã Vĩnh Hanh		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30628	Xã Chợ Mới		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30631	Xã Long Điền		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30643	Xã Cù Lao Giêng		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30658	Xã Nhơn Mỹ		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30664	Xã Long Kiến		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30673	Xã Hội An		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30682	Xã Thoại Sơn		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30685	Xã Phú Hòa		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30688	Xã Óc Eo		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30691	Xã Tây Phú		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30697	Xã Vĩnh Trạch		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30709	Xã Định Mỹ		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30742	Phường Rạch Giá		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30760	Phường Vĩnh Thông		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30766	Phường Tô Châu		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30769	Phường Hà Tiên		Phường	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30781	Xã Tiên Hải		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30787	Xã Kiên Lương		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30790	Xã Hòa Điền		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30793	Xã Vĩnh Điều		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30796	Xã Giang Thành		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30811	Xã Sơn Hải		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30814	Xã Hòn Nghệ		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30817	Xã Hòn Đất		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30823	Xã Bình Sơn		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30826	Xã Bình Giang		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30835	Xã Sơn Kiên		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30838	Xã Mỹ Thuận		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30850	Xã Tân Hiệp		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30856	Xã Tân Hội		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30874	Xã Thạnh Đông		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30880	Xã Châu Thành		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30886	Xã Thạnh Lộc		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30898	Xã Bình An		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30904	Xã Giồng Riềng		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30910	Xã Thạnh Hưng		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30928	Xã Ngọc Chúc		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30934	Xã Hòa Hưng		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30943	Xã Long Thạnh		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30949	Xã Hòa Thuận		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30952	Xã Gò Quao		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30958	Xã Định Hòa		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30970	Xã Vĩnh Hòa Hưng		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30982	Xã Vĩnh Tuy		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30985	Xã An Biên		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
30988	Xã Tây Yên		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31006	Xã Đông Thái		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31012	Xã Vĩnh Hòa		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31018	Xã An Minh		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31024	Xã Đông Hòa		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31027	Xã U Minh Thượng		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31031	Xã Tân Thạnh	Tan Thanh commune	Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31036	Xã Đông Hưng		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31042	Xã Vân Khánh		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31051	Xã Vĩnh Phong		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31064	Xã Vĩnh Bình		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31069	Xã Vĩnh Thuận		Xã	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31078	Đặc khu Phú Quốc		Đặc khu	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31105	Đặc khu Thổ Châu		Đặc khu	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31108	Đặc khu Kiên Hải		Đặc khu	91	\N	Tỉnh An Giang	Số: 1654/NQ-UBTVQH15; Ngày: 16/06/2025
31120	Phường Cái Khế		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31135	Phường Ninh Kiều		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31147	Phường Tân An		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31150	Phường An Bình		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31153	Phường Ô Môn		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31157	Phường Thới Long		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31162	Phường Phước Thới		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31168	Phường Bình Thủy		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31174	Phường Thới An Đông		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31183	Phường Long Tuyền		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31186	Phường Cái Răng		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31201	Phường Hưng Phú		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31207	Phường Thốt Nốt		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31213	Phường Tân Lộc		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31217	Phường Trung Nhứt		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31228	Phường Thuận Hưng		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31231	Xã Thạnh An		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31232	Xã Vĩnh Thạnh		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31237	Xã Vĩnh Trinh		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31246	Xã Thạnh Quới		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31249	Xã Thạnh Phú		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31255	Xã Trung Hưng		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31258	Xã Thới Lai		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31261	Xã Cờ Đỏ		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31264	Xã Thới Hưng		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31273	Xã Đông Hiệp		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31282	Xã Đông Thuận		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31288	Xã Trường Thành		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31294	Xã Trường Xuân		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31299	Xã Phong Điền		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31309	Xã Trường Long		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31315	Xã Nhơn Ái		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31321	Phường Vị Thanh		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31333	Phường Vị Tân		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31338	Xã Hỏa Lựu	Tân Tiến Commune	Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31340	Phường Ngã Bảy	Nga Bay precinct	Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31342	Xã Tân Hòa		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31348	Xã Trường Long Tây		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31360	Xã Thạnh Xuân		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31366	Xã Châu Thành		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31369	Xã Đông Phước		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31378	Xã Phú Hữu		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31393	Xã Hòa An		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31396	Xã Hiệp Hưng		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31399	Xã Tân Bình		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31408	Xã Thạnh Hòa		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31411	Phường Đại Thành		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31420	Xã Phụng Hiệp		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31426	Xã Phương Bình		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31432	Xã Tân Phước Hưng		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31441	Xã Vị Thủy		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31453	Xã Vĩnh Thuận Đông		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31459	Xã  Vĩnh Tường		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31465	Xã Vị Thanh 1		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31471	Phường Long Mỹ		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31473	Phường Long Bình		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31480	Phường Long Phú 1		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31489	Xã Vĩnh Viễn		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31492	Xã Lương Tâm		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31495	Xã Xà Phiên		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31507	Phường Sóc Trăng		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31510	Phường Phú Lợi		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31528	Xã Kế Sách		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31531	Xã An Lạc Thôn		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31537	Xã Phong Nẫm		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31540	Xã Thới An Hội		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31552	Xã Nhơn Mỹ		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31561	Xã Đại Hải		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31567	Xã Mỹ Tú		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31569	Xã Phú Tâm		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31570	Xã Hồ Đắc Kiện		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31579	Xã Long Hưng		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31582	Xã Thuận Hòa		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31591	Xã Mỹ Hương		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31594	Xã An Ninh		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31603	Xã Mỹ Phước		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31615	Xã An Thạnh		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31633	Xã Cù Lao Dung		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31639	Xã Long Phú		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31645	Xã Đại Ngãi		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31654	Xã Trường Khánh		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31666	Xã Tân Thạnh		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31673	Xã Trần Đề		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31675	Xã Liêu Tú		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31679	Xã Lịch Hội Thượng		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31684	Phường Mỹ Xuyên		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31687	Xã Tài Văn		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31699	Xã Thạnh Thới An		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31708	Xã Nhu Gia		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31717	Xã Hòa Tú		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31723	Xã Ngọc Tố		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31726	Xã Gia Hòa		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31732	Phường Ngã Năm		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31741	Xã Tân Long		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31753	Phường Mỹ Quới		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31756	Xã Phú Lộc		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31759	Xã Lâm Tân		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31777	Xã Vĩnh Lợi		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31783	Phường Vĩnh Châu		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31789	Phường Khánh Hòa		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31795	Xã Vĩnh Hải		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31804	Phường Vĩnh Phước		Phường	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31810	Xã Lai Hòa		Xã	92	\N	Thành phố Cần Thơ	Số: 1668/NQ-UBTVQH15; Ngày: 16/06/2025
31825	Phường Bạc Liêu		Phường	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31834	Phường Vĩnh Trạch		Phường	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31840	Phường Hiệp Thành		Phường	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31843	Xã Hồng Dân		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31849	Xã Ninh Quới		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31858	Xã Vĩnh Lộc		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31864	Xã Ninh Thạnh Lợi		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31867	Xã Phước Long		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31876	Xã Vĩnh Phước		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31882	Xã Vĩnh Thanh		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31885	Xã Phong Hiệp		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31891	Xã Hòa Bình		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31894	Xã Châu Thới		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31900	Xã Vĩnh Lợi		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31906	Xã Hưng Hội		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31918	Xã Vĩnh Mỹ		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31927	Xã Vĩnh Hậu		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31942	Phường Giá Rai		Phường	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31951	Phường Láng Tròn		Phường	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31957	Xã Phong Thạnh		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31972	Xã Gành Hào		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31975	Xã Đông Hải		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31985	Xã Long Điền		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31988	Xã An Trạch		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
31993	Xã Định Thành		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32002	Phường An Xuyên		Phường	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32014	Phường Lý Văn Lâm		Phường	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32025	Phường Tân Thành		Phường	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32041	Phường Hòa Thành		Phường	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32044	Xã Nguyễn Phích		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32047	Xã U Minh		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32059	Xã Khánh An		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32062	Xã Khánh Lâm		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32065	Xã Thới Bình		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32069	Xã Biển Bạch	Tan Bang commune	Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32071	Xã Trí Phải		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32083	Xã Tân Lộc		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32092	Xã Hồ Thị Kỷ		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32095	Xã Trần Văn Thời		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32098	Xã Sông Đốc		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32104	Xã Đá Bạc		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32110	Xã Khánh Bình		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32119	Xã Khánh Hưng		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32128	Xã Cái Nước		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32134	Xã Lương Thế Trân		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32137	Xã Tân Hưng		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32140	Xã Hưng Mỹ		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32152	Xã Đầm Dơi		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32155	Xã Tạ An Khương		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32161	Xã Trần Phán		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32167	Xã Tân Thuận		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32182	Xã Quách Phẩm		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32185	Xã Thanh Tùng		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32188	Xã Tân Tiến		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32191	Xã Năm Căn		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32201	Xã Đất Mới	Lam Hai commune	Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32206	Xã Tam Giang		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32212	Xã Cái Đôi Vàm		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32214	Xã Phú Mỹ	Phu Thuan Commune	Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32218	Xã Phú Tân		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32227	Xã Nguyễn Việt Khái		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32236	Xã Tân Ân		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32244	Xã Phan Ngọc Hiển		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
32248	Xã Đất Mũi		Xã	96	\N	Tỉnh Cà Mau	Số: 1655/NQ-UBTVQH15; Ngày: 16/06/2025
\.


--
-- TOC entry 3789 (class 0 OID 33138)
-- Dependencies: 239
-- Data for Name: vn_province; Type: TABLE DATA; Schema: iamservice_db; Owner: -
--

COPY iamservice_db.vn_province (code, name, english_name, decree) FROM stdin;
01	Thành phố Hà Nội	\N	\N
04	Tỉnh Cao Bằng	\N	\N
08	Tỉnh Tuyên Quang	\N	\N
11	Tỉnh Điện Biên	\N	\N
12	Tỉnh Lai Châu	\N	\N
14	Tỉnh Sơn La	\N	\N
15	Tỉnh Lào Cai	\N	\N
19	Tỉnh Thái Nguyên	\N	\N
20	Tỉnh Lạng Sơn	\N	\N
22	Tỉnh Quảng Ninh	\N	\N
24	Tỉnh Bắc Ninh	\N	\N
25	Tỉnh Phú Thọ	\N	\N
31	Thành phố Hải Phòng	\N	\N
33	Tỉnh Hưng Yên	\N	\N
37	Tỉnh Ninh Bình	\N	\N
38	Tỉnh Thanh Hóa	\N	\N
40	Tỉnh Nghệ An	\N	\N
42	Tỉnh Hà Tĩnh	\N	\N
44	Tỉnh Quảng Trị	\N	\N
46	Thành phố Huế	\N	\N
48	Thành phố Đà Nẵng	\N	\N
51	Tỉnh Quảng Ngãi	\N	\N
52	Tỉnh Gia Lai	\N	\N
56	Tỉnh Khánh Hòa	\N	\N
66	Tỉnh Đắk Lắk	\N	\N
68	Tỉnh Lâm Đồng	\N	\N
75	Tỉnh Đồng Nai	\N	\N
79	Thành phố Hồ Chí Minh	\N	\N
80	Tỉnh Tây Ninh	\N	\N
82	Tỉnh Đồng Tháp	\N	\N
86	Tỉnh Vĩnh Long	\N	\N
91	Tỉnh An Giang	\N	\N
92	Thành phố Cần Thơ	\N	\N
96	Tỉnh Cà Mau	\N	\N
\.


--
-- TOC entry 3554 (class 2606 OID 33144)
-- Name: flyway_schema_history flyway_schema_history_pk; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.flyway_schema_history
    ADD CONSTRAINT flyway_schema_history_pk PRIMARY KEY (installed_rank);


--
-- TOC entry 3559 (class 2606 OID 33146)
-- Name: login_history login_history_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.login_history
    ADD CONSTRAINT login_history_pkey PRIMARY KEY (history_id, attempted_at);


--
-- TOC entry 3562 (class 2606 OID 33148)
-- Name: login_history_default login_history_default_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.login_history_default
    ADD CONSTRAINT login_history_default_pkey PRIMARY KEY (history_id, attempted_at);


--
-- TOC entry 3566 (class 2606 OID 33150)
-- Name: outbox_events outbox_events_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.outbox_events
    ADD CONSTRAINT outbox_events_pkey PRIMARY KEY (event_id);


--
-- TOC entry 3569 (class 2606 OID 33152)
-- Name: outbox_messages outbox_messages_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.outbox_messages
    ADD CONSTRAINT outbox_messages_pkey PRIMARY KEY (id);


--
-- TOC entry 3573 (class 2606 OID 33154)
-- Name: privilege_screen privilege_screen_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.privilege_screen
    ADD CONSTRAINT privilege_screen_pkey PRIMARY KEY (privilege_id, screen_id, action_code);


--
-- TOC entry 3576 (class 2606 OID 33156)
-- Name: privileges privileges_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.privileges
    ADD CONSTRAINT privileges_pkey PRIMARY KEY (privilege_id);


--
-- TOC entry 3579 (class 2606 OID 33158)
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (token_id);


--
-- TOC entry 3581 (class 2606 OID 33160)
-- Name: role_privileges role_privileges_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.role_privileges
    ADD CONSTRAINT role_privileges_pkey PRIMARY KEY (role_id, privilege_id);


--
-- TOC entry 3584 (class 2606 OID 33162)
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (role_id);


--
-- TOC entry 3586 (class 2606 OID 33164)
-- Name: screen_actions screen_actions_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.screen_actions
    ADD CONSTRAINT screen_actions_pkey PRIMARY KEY (action_code);


--
-- TOC entry 3590 (class 2606 OID 33166)
-- Name: screens screens_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.screens
    ADD CONSTRAINT screens_pkey PRIMARY KEY (screen_id);


--
-- TOC entry 3595 (class 2606 OID 33168)
-- Name: system_configurations system_configurations_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.system_configurations
    ADD CONSTRAINT system_configurations_pkey PRIMARY KEY (config_id);


--
-- TOC entry 3597 (class 2606 OID 33170)
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);


--
-- TOC entry 3603 (class 2606 OID 33172)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- TOC entry 3605 (class 2606 OID 33174)
-- Name: users users_username_key; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- TOC entry 3609 (class 2606 OID 33176)
-- Name: vn_commune vn_commune_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.vn_commune
    ADD CONSTRAINT vn_commune_pkey PRIMARY KEY (code);


--
-- TOC entry 3611 (class 2606 OID 33178)
-- Name: vn_province vn_province_pkey; Type: CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.vn_province
    ADD CONSTRAINT vn_province_pkey PRIMARY KEY (code);


--
-- TOC entry 3555 (class 1259 OID 33179)
-- Name: flyway_schema_history_s_idx; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX flyway_schema_history_s_idx ON iamservice_db.flyway_schema_history USING btree (success);


--
-- TOC entry 3567 (class 1259 OID 33180)
-- Name: idx_outbox_messages_status_created; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_outbox_messages_status_created ON iamservice_db.outbox_messages USING btree (status, created_at);


--
-- TOC entry 3564 (class 1259 OID 33181)
-- Name: idx_outbox_unsent; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_outbox_unsent ON iamservice_db.outbox_events USING btree (sent) WHERE (sent = false);


--
-- TOC entry 3574 (class 1259 OID 33182)
-- Name: idx_privileges_code; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE UNIQUE INDEX idx_privileges_code ON iamservice_db.privileges USING btree (privilege_code);


--
-- TOC entry 3570 (class 1259 OID 33183)
-- Name: idx_ps_privilege; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_ps_privilege ON iamservice_db.privilege_screen USING btree (privilege_id) WHERE (is_active = true);


--
-- TOC entry 3571 (class 1259 OID 33184)
-- Name: idx_ps_screen; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_ps_screen ON iamservice_db.privilege_screen USING btree (screen_id, action_code) WHERE (is_active = true);


--
-- TOC entry 3577 (class 1259 OID 33185)
-- Name: idx_refresh_user_active; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_refresh_user_active ON iamservice_db.refresh_tokens USING btree (user_id) WHERE ((is_active = true) AND (is_revoked = false));


--
-- TOC entry 3582 (class 1259 OID 33186)
-- Name: idx_roles_code; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE UNIQUE INDEX idx_roles_code ON iamservice_db.roles USING btree (role_code);


--
-- TOC entry 3587 (class 1259 OID 33187)
-- Name: idx_screens_base_path; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_screens_base_path ON iamservice_db.screens USING btree (base_path);


--
-- TOC entry 3588 (class 1259 OID 33188)
-- Name: idx_screens_parent_code; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_screens_parent_code ON iamservice_db.screens USING btree (parent_code);


--
-- TOC entry 3593 (class 1259 OID 33189)
-- Name: idx_sysconfig_key; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE UNIQUE INDEX idx_sysconfig_key ON iamservice_db.system_configurations USING btree (config_key);


--
-- TOC entry 3598 (class 1259 OID 33190)
-- Name: idx_users_email_ci; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE UNIQUE INDEX idx_users_email_ci ON iamservice_db.users USING btree (lower((email)::text));


--
-- TOC entry 3599 (class 1259 OID 33191)
-- Name: idx_users_failed_attempts; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_users_failed_attempts ON iamservice_db.users USING btree (failed_login_attempts);


--
-- TOC entry 3600 (class 1259 OID 33192)
-- Name: idx_users_is_locked; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_users_is_locked ON iamservice_db.users USING btree (is_locked, updated_at DESC);


--
-- TOC entry 3601 (class 1259 OID 33193)
-- Name: idx_users_username_ci; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE UNIQUE INDEX idx_users_username_ci ON iamservice_db.users USING btree (lower((username)::text));


--
-- TOC entry 3606 (class 1259 OID 33194)
-- Name: idx_vn_commune_name; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_vn_commune_name ON iamservice_db.vn_commune USING btree (lower((name)::text));


--
-- TOC entry 3607 (class 1259 OID 33195)
-- Name: idx_vn_commune_province; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX idx_vn_commune_province ON iamservice_db.vn_commune USING btree (province_code);


--
-- TOC entry 3556 (class 1259 OID 33196)
-- Name: login_hist_ip_idx; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX login_hist_ip_idx ON ONLY iamservice_db.login_history USING btree (ip_address, attempted_at DESC);


--
-- TOC entry 3557 (class 1259 OID 33197)
-- Name: login_hist_user_idx; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX login_hist_user_idx ON ONLY iamservice_db.login_history USING btree (user_id, attempted_at DESC);


--
-- TOC entry 3560 (class 1259 OID 33198)
-- Name: login_history_default_ip_address_attempted_at_idx; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX login_history_default_ip_address_attempted_at_idx ON iamservice_db.login_history_default USING btree (ip_address, attempted_at DESC);


--
-- TOC entry 3563 (class 1259 OID 33199)
-- Name: login_history_default_user_id_attempted_at_idx; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE INDEX login_history_default_user_id_attempted_at_idx ON iamservice_db.login_history_default USING btree (user_id, attempted_at DESC);


--
-- TOC entry 3591 (class 1259 OID 33200)
-- Name: ux_screens_code; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE UNIQUE INDEX ux_screens_code ON iamservice_db.screens USING btree (screen_code);


--
-- TOC entry 3592 (class 1259 OID 33201)
-- Name: ux_screens_default_true; Type: INDEX; Schema: iamservice_db; Owner: -
--

CREATE UNIQUE INDEX ux_screens_default_true ON iamservice_db.screens USING btree (is_default) WHERE (is_default = true);


--
-- TOC entry 3612 (class 0 OID 0)
-- Name: login_history_default_ip_address_attempted_at_idx; Type: INDEX ATTACH; Schema: iamservice_db; Owner: -
--

ALTER INDEX iamservice_db.login_hist_ip_idx ATTACH PARTITION iamservice_db.login_history_default_ip_address_attempted_at_idx;


--
-- TOC entry 3613 (class 0 OID 0)
-- Name: login_history_default_pkey; Type: INDEX ATTACH; Schema: iamservice_db; Owner: -
--

ALTER INDEX iamservice_db.login_history_pkey ATTACH PARTITION iamservice_db.login_history_default_pkey;


--
-- TOC entry 3614 (class 0 OID 0)
-- Name: login_history_default_user_id_attempted_at_idx; Type: INDEX ATTACH; Schema: iamservice_db; Owner: -
--

ALTER INDEX iamservice_db.login_hist_user_idx ATTACH PARTITION iamservice_db.login_history_default_user_id_attempted_at_idx;


--
-- TOC entry 3626 (class 2620 OID 33202)
-- Name: users trg_update_age_years; Type: TRIGGER; Schema: iamservice_db; Owner: -
--

CREATE TRIGGER trg_update_age_years BEFORE INSERT OR UPDATE OF date_of_birth ON iamservice_db.users FOR EACH ROW EXECUTE FUNCTION iamservice_db.update_age_years();


--
-- TOC entry 3615 (class 2606 OID 33203)
-- Name: login_history login_history_refresh_token_id_fkey; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE iamservice_db.login_history
    ADD CONSTRAINT login_history_refresh_token_id_fkey FOREIGN KEY (refresh_token_id) REFERENCES iamservice_db.refresh_tokens(token_id);


--
-- TOC entry 3616 (class 2606 OID 33211)
-- Name: login_history login_history_user_id_fkey; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE iamservice_db.login_history
    ADD CONSTRAINT login_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES iamservice_db.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 3617 (class 2606 OID 33219)
-- Name: privilege_screen ps_action_fk; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.privilege_screen
    ADD CONSTRAINT ps_action_fk FOREIGN KEY (action_code) REFERENCES iamservice_db.screen_actions(action_code) ON DELETE RESTRICT;


--
-- TOC entry 3618 (class 2606 OID 33224)
-- Name: privilege_screen ps_privilege_fk; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.privilege_screen
    ADD CONSTRAINT ps_privilege_fk FOREIGN KEY (privilege_id) REFERENCES iamservice_db.privileges(privilege_id) ON DELETE CASCADE;


--
-- TOC entry 3619 (class 2606 OID 33229)
-- Name: privilege_screen ps_screen_fk; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.privilege_screen
    ADD CONSTRAINT ps_screen_fk FOREIGN KEY (screen_id) REFERENCES iamservice_db.screens(screen_id) ON DELETE CASCADE;


--
-- TOC entry 3620 (class 2606 OID 33234)
-- Name: refresh_tokens refresh_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.refresh_tokens
    ADD CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES iamservice_db.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 3621 (class 2606 OID 33239)
-- Name: role_privileges role_privileges_privilege_id_fkey; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.role_privileges
    ADD CONSTRAINT role_privileges_privilege_id_fkey FOREIGN KEY (privilege_id) REFERENCES iamservice_db.privileges(privilege_id) ON DELETE CASCADE;


--
-- TOC entry 3622 (class 2606 OID 33244)
-- Name: role_privileges role_privileges_role_id_fkey; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.role_privileges
    ADD CONSTRAINT role_privileges_role_id_fkey FOREIGN KEY (role_id) REFERENCES iamservice_db.roles(role_id) ON DELETE CASCADE;


--
-- TOC entry 3623 (class 2606 OID 33249)
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES iamservice_db.roles(role_id) ON DELETE CASCADE;


--
-- TOC entry 3624 (class 2606 OID 33254)
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES iamservice_db.users(user_id) ON DELETE CASCADE;


--
-- TOC entry 3625 (class 2606 OID 33259)
-- Name: vn_commune vn_commune_province_code_fkey; Type: FK CONSTRAINT; Schema: iamservice_db; Owner: -
--

ALTER TABLE ONLY iamservice_db.vn_commune
    ADD CONSTRAINT vn_commune_province_code_fkey FOREIGN KEY (province_code) REFERENCES iamservice_db.vn_province(code) ON DELETE CASCADE;


-- Completed on 2025-11-27 08:57:26 +07

--
-- PostgreSQL database dump complete
--

\unrestrict hc3Zkm6RTK3Igp8s8cZmSL6t7BgPrS2Ay1fTQ1nMFmVTN9KObicVEcsdE3lKwZb

