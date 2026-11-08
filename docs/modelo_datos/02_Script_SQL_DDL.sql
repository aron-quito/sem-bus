-- ============================================================
--  BC (Bus Conectado) — Tacna, Perú
--  Script DDL PostgreSQL 15+
--  Generado por: Analista BD / Equipo BC
--  Versión: 1.0.0
--  Fecha: 2026-11-08
-- ============================================================
-- NOTA: Requiere extensión pgcrypto (gen_random_uuid) y postgis (opcional, Fase 2)
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
--  0. EXTENSIONES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "citext";     -- VARCHAR case-insensitive (email/dni)

-- ─────────────────────────────────────────────────────────────────────────────
--  1. TIPOS ENUMERADOS (ENUM)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TYPE user_role       AS ENUM ('ADULT','STUDENT','CONADIS','DRIVER','ADMIN');
CREATE TYPE sv_status       AS ENUM ('PENDING','ACTIVE','EXPIRED','REJECTED');
CREATE TYPE tx_type         AS ENUM ('RECHARGE_CREDIT','TRIP_DEBIT','REFUND_CREDIT','ADJUSTMENT');
CREATE TYPE recharge_gw     AS ENUM ('YAPE','CARD','CASH_AGENT');
CREATE TYPE recharge_status AS ENUM ('PENDING','COMPLETED','FAILED','REFUNDED');
CREATE TYPE device_type     AS ENUM ('POS','TABLET');
CREATE TYPE pairing_status  AS ENUM ('PENDING','ACTIVE','REVOKED');
CREATE TYPE bus_pairing_st  AS ENUM ('UNPAIRED','PAIRED','REVOKED');
CREATE TYPE direction_type  AS ENUM ('UP','DOWN');
CREATE TYPE shift_status    AS ENUM ('ACTIVE','PAUSED','COMPLETED');
CREATE TYPE fare_type       AS ENUM ('ADULT','STUDENT','CONADIS');
CREATE TYPE trip_status     AS ENUM ('ACTIVE','COMPLETED','ABANDONED');
CREATE TYPE ticket_category AS ENUM ('BUG','SUGGESTION','PAYMENT_ISSUE','SAFETY','OTHER');
CREATE TYPE ticket_status   AS ENUM ('OPEN','IN_REVIEW','RESOLVED','CLOSED');

-- ─────────────────────────────────────────────────────────────────────────────
--  2. TABLA: users
--     Pasajeros, conductores y administradores del sistema BC
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE users (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    phone               VARCHAR(15) UNIQUE NOT NULL,       -- +51XXXXXXXXX
    name                VARCHAR(100),
    role                user_role   NOT NULL DEFAULT 'ADULT',
    current_device_id   VARCHAR(200),                      -- fingerprint del dispositivo activo
    otp_hash            VARCHAR(255),                      -- bcrypt del OTP vigente
    otp_expires_at      TIMESTAMPTZ,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_phone      ON users(phone);
CREATE INDEX idx_users_role       ON users(role);
CREATE INDEX idx_users_device     ON users(current_device_id);

COMMENT ON TABLE  users                  IS 'Todos los usuarios del sistema: pasajeros, conductores y administradores.';
COMMENT ON COLUMN users.phone            IS 'Número de celular peruano en formato E.164 (+51XXXXXXXXX). Identificador primario de autenticación.';
COMMENT ON COLUMN users.current_device_id IS 'Fingerprint del dispositivo con sesión activa. Sesión única tipo Yape.';
COMMENT ON COLUMN users.otp_hash         IS 'Hash bcrypt del código OTP de 6 dígitos vigente. NULL si no hay OTP pendiente.';

-- ─────────────────────────────────────────────────────────────────────────────
--  3. TABLA: user_sessions
--     Sesiones JWT activas. Solo 1 por usuario (Yape-style).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE user_sessions (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id   VARCHAR(200) NOT NULL,                -- mismo fingerprint que users.current_device_id
    device_name VARCHAR(100),                         -- "iPhone 16 de Aron"
    jwt_jti     VARCHAR(255) UNIQUE NOT NULL,          -- JWT ID único para revocación
    ip_address  INET,
    is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at  TIMESTAMPTZ
);

CREATE INDEX idx_sessions_user_id   ON user_sessions(user_id);
CREATE INDEX idx_sessions_jwt_jti   ON user_sessions(jwt_jti);
CREATE INDEX idx_sessions_active    ON user_sessions(user_id, is_active) WHERE is_active = TRUE;

COMMENT ON TABLE user_sessions IS 'Sesiones JWT activas. Al iniciar sesión en un nuevo dispositivo, se revocan todas las sesiones previas del usuario.';

-- ─────────────────────────────────────────────────────────────────────────────
--  4. TABLA: student_verifications
--     Verificación SUNEDU para tarifa universitaria (S/. 0.70 / 7 puntos)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE student_verifications (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID        UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    dni                     VARCHAR(8)  NOT NULL,
    university              VARCHAR(150),
    university_code         VARCHAR(20),               -- código SUNEDU de la institución
    career                  VARCHAR(100),
    academic_cycle          VARCHAR(20),               -- e.g. "2026-II"
    photo_url               VARCHAR(500),              -- URL del carnet/constancia uploadada
    status                  sv_status   NOT NULL DEFAULT 'PENDING',
    sunedu_verified_at      TIMESTAMPTZ,               -- timestamp de validación API SUNEDU
    expires_at              TIMESTAMPTZ,               -- fin del período académico
    extension_grace_days    INTEGER     NOT NULL DEFAULT 30, -- prórroga configurada globalmente
    rejection_reason        TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sv_user_id ON student_verifications(user_id);
CREATE INDEX idx_sv_status  ON student_verifications(status);
CREATE INDEX idx_sv_expires ON student_verifications(expires_at);

COMMENT ON TABLE student_verifications IS 'Verificación de matrícula universitaria vigente para acceder a tarifa universitaria (S/. 0.70).';
COMMENT ON COLUMN student_verifications.extension_grace_days IS 'Días de gracia post-vencimiento configurables por el Admin. Parámetro global sincronizado desde app_config.';

-- ─────────────────────────────────────────────────────────────────────────────
--  5. TABLA: wallets
--     Monedero de Puntos BC (prepago cerrado, NO billetera SBS)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE wallets (
    id                  UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID    UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    points_balance      INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0),  -- NO saldo negativo
    last_transaction_id UUID,                                                     -- FK circular, se agrega luego
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wallets_user_id ON wallets(user_id);

COMMENT ON TABLE wallets IS 'Saldo en Puntos BC del usuario. Regla de oro: points_balance nunca puede ser negativo (CHECK constraint). No es billetera electrónica regulada por SBS.';
COMMENT ON COLUMN wallets.points_balance IS '1 PEN = 10 Puntos BC. Adulto: 15 pts (S/1.50). Universitario: 7 pts (S/0.70). CONADIS: 0 pts.';

-- ─────────────────────────────────────────────────────────────────────────────
--  6. TABLA: ledger_transactions
--     Libro mayor inmutable de movimientos de puntos
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE ledger_transactions (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id       UUID        NOT NULL REFERENCES wallets(id),
    user_id         UUID        NOT NULL REFERENCES users(id),
    type            tx_type     NOT NULL,
    amount_points   INTEGER     NOT NULL,              -- positivo = crédito, negativo = débito
    amount_pen      NUMERIC(10,2),                     -- equivalente en soles (referencial)
    reference_id    UUID,                              -- FK a recharges o trips (polimórfico)
    reference_type  VARCHAR(20) CHECK (reference_type IN ('RECHARGE','TRIP','ADJUSTMENT','REFUND')),
    balance_before  INTEGER     NOT NULL,
    balance_after   INTEGER     NOT NULL,
    description     VARCHAR(255),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para auditoría y consultas de historial
CREATE INDEX idx_ledger_wallet_id  ON ledger_transactions(wallet_id);
CREATE INDEX idx_ledger_user_id    ON ledger_transactions(user_id);
CREATE INDEX idx_ledger_type       ON ledger_transactions(type);
CREATE INDEX idx_ledger_created_at ON ledger_transactions(created_at DESC);
CREATE INDEX idx_ledger_ref        ON ledger_transactions(reference_id) WHERE reference_id IS NOT NULL;

COMMENT ON TABLE ledger_transactions IS 'Libro mayor append-only de todos los movimientos de puntos. Nunca se borra ni modifica un registro. Para reversión se crea una nueva entrada REFUND_CREDIT.';

-- FK circular wallet -> ledger
ALTER TABLE wallets ADD CONSTRAINT fk_wallet_last_tx
    FOREIGN KEY (last_transaction_id) REFERENCES ledger_transactions(id) DEFERRABLE INITIALLY DEFERRED;

-- ─────────────────────────────────────────────────────────────────────────────
--  7. TABLA: fare_config
--     Tarifas configurables por el Administrador (no hardcoded)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE fare_config (
    id                        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    fare_type                 fare_type   UNIQUE NOT NULL,
    amount_pen                NUMERIC(10,2) NOT NULL,
    points_cost               INTEGER     NOT NULL,
    student_cooldown_seconds  INTEGER     DEFAULT 120,   -- anti-fraude cooldown tarifa universitaria
    effective_from            TIMESTAMPTZ DEFAULT NOW(),
    updated_by                UUID        REFERENCES users(id),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed de tarifas iniciales
INSERT INTO fare_config (fare_type, amount_pen, points_cost, student_cooldown_seconds) VALUES
    ('ADULT',   1.50, 15, NULL),
    ('STUDENT', 0.70,  7, 120),
    ('CONADIS', 0.00,  0, NULL);

COMMENT ON TABLE fare_config IS 'Tarifas vigentes configurables por el Admin. No hardcoded. Histórico implícito via effective_from.';

-- ─────────────────────────────────────────────────────────────────────────────
--  8. TABLA: app_config
--     Parámetros globales del sistema (key-value store)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE app_config (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    key         VARCHAR(100) UNIQUE NOT NULL,
    value       TEXT        NOT NULL,
    description VARCHAR(255),
    updated_by  UUID        REFERENCES users(id),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed de parámetros iniciales
INSERT INTO app_config (key, value, description) VALUES
    ('sunedu_grace_days',         '30',  'Días de gracia post-vencimiento de matrícula universitaria'),
    ('qr_nonce_ttl_seconds',      '30',  'TTL máximo del nonce QR dinámico del POS en segundos (auto-refresco cada 30s si nadie escanea)'),
    ('qr_refresh_ms',             '500', 'Milisegundos para regenerar QR tras un cobro exitoso'),
    ('gps_pos_telemetry_seconds',  '5',   'Intervalo de telemetría GPS del POS del bus al backend (3-5s)'),
    ('gps_app_heartbeat_seconds', '45',  'Intervalo de ping GPS de la APP DEL PASAJERO al backend (segundo plano, ahorro batería)'),
    ('geofence_radius_m',         '150', 'Radio en metros para confirmar descenso del pasajero'),
    ('geofence_readings_required','2',   'Lecturas GPS consecutivas fuera del radio para confirmar bajada'),
    ('yape_webhook_timeout_s',    '5',   'Segundos de espera del webhook Yape antes de botón manual'),
    ('session_max_age_hours',     '720', 'Duración máxima de una sesión JWT en horas (30 días)'),
    ('max_companion_trips',       '5',   'Máximo de pasajes acompañantes por transacción');

COMMENT ON TABLE app_config IS 'Parámetros globales del sistema configurables por el Admin via backoffice. Cambios en caliente sin re-deploy.';

-- ─────────────────────────────────────────────────────────────────────────────
--  9. TABLA: recharges
--     Recargas de saldo (Yape, tarjeta, agente en efectivo)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE recharges (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID            NOT NULL REFERENCES users(id),
    wallet_id       UUID            NOT NULL REFERENCES wallets(id),
    amount_pen      NUMERIC(10,2)   NOT NULL CHECK (amount_pen > 0),
    points_credited INTEGER         NOT NULL CHECK (points_credited > 0 AND points_credited = ROUND(amount_pen * 10)),
    gateway         recharge_gw     NOT NULL,
    gateway_tx_id   VARCHAR(255)    UNIQUE,            -- ID único del gateway (idempotencia)
    status          recharge_status NOT NULL DEFAULT 'PENDING',
    metadata        JSONB,                             -- datos adicionales del gateway
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    completed_at    TIMESTAMPTZ
);

CREATE INDEX idx_recharges_user_id      ON recharges(user_id);
CREATE INDEX idx_recharges_wallet_id    ON recharges(wallet_id);
CREATE INDEX idx_recharges_gateway_txid ON recharges(gateway_tx_id) WHERE gateway_tx_id IS NOT NULL;
CREATE INDEX idx_recharges_status       ON recharges(status);
CREATE INDEX idx_recharges_created_at   ON recharges(created_at DESC);

COMMENT ON TABLE recharges IS 'Órdenes de recarga de Puntos BC. gateway_tx_id garantiza idempotencia de webhooks.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. TABLA: routes
--     Rutas de bus con geometría Up/Down (GeoJSON LineString)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE routes (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100) NOT NULL,
    line_number     VARCHAR(10)  UNIQUE NOT NULL,   -- e.g. "R1", "502"
    description     TEXT,
    geometry_up     JSONB,                          -- GeoJSON LineString sentido subida
    geometry_down   JSONB,                          -- GeoJSON LineString sentido bajada
    color_hex       VARCHAR(7)   DEFAULT '#1976D2', -- color en mapa para pasajeros
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_routes_line_number ON routes(line_number);
CREATE INDEX idx_routes_active      ON routes(is_active) WHERE is_active = TRUE;

COMMENT ON TABLE routes IS 'Rutas urbanas de bus con geometría bidireccional. geometry_up/down son GeoJSON LineString.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. TABLA: stops
--     Paraderos de cada ruta con secuencia y geofencing
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE stops (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    route_id            UUID            NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
    name                VARCHAR(100)    NOT NULL,
    lat                 NUMERIC(10,8)   NOT NULL,
    lng                 NUMERIC(11,8)   NOT NULL,
    sequence_up         INTEGER,                        -- orden en sentido subida
    sequence_down       INTEGER,                        -- orden en sentido bajada
    geofence_radius_m   INTEGER         NOT NULL DEFAULT 50,
    is_terminal         BOOLEAN         NOT NULL DEFAULT FALSE, -- cabecera terminal (invierte dirección)
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_stops_route_id  ON stops(route_id);
CREATE INDEX idx_stops_coords    ON stops(lat, lng);
CREATE INDEX idx_stops_terminal  ON stops(route_id, is_terminal) WHERE is_terminal = TRUE;

COMMENT ON TABLE stops IS 'Paraderos de cada ruta con coordenadas GPS, secuencia de paso y radio de geofencing para detectar abordaje/descenso.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. TABLA: buses
--     Flota de buses con telemetría GPS en tiempo real
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE buses (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    plate                   VARCHAR(10)     UNIQUE NOT NULL,       -- placa vehicular
    route_id                UUID            REFERENCES routes(id),
    pos_device_serial       VARCHAR(100)    UNIQUE,                -- serial del POS (con GPS)
    tablet_device_serial    VARCHAR(100)    UNIQUE,                -- serial de la tablet del chofer
    gps_lat                 NUMERIC(10,8),                         -- última latitud conocida
    gps_lng                 NUMERIC(11,8),                         -- última longitud conocida
    gps_heading             NUMERIC(5,2),                          -- dirección en grados (0-360)
    gps_speed               NUMERIC(5,2),                          -- velocidad en km/h
    last_telemetry_at       TIMESTAMPTZ,                           -- último ping GPS
    current_direction       direction_type,                        -- UP o DOWN (ida/vuelta)
    is_visible_public       BOOLEAN         NOT NULL DEFAULT TRUE,  -- visible en mapa de pasajeros
    pause_reason            VARCHAR(255),                           -- "Llanta pinchada", etc.
    pairing_status          bus_pairing_st  NOT NULL DEFAULT 'UNPAIRED',
    is_active               BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_buses_route_id       ON buses(route_id);
CREATE INDEX idx_buses_visible        ON buses(is_visible_public) WHERE is_visible_public = TRUE;
CREATE INDEX idx_buses_active         ON buses(is_active) WHERE is_active = TRUE;
CREATE INDEX idx_buses_telemetry      ON buses(last_telemetry_at DESC);

COMMENT ON TABLE buses IS 'Flota de buses con telemetría GPS en tiempo real. is_visible_public controla visibilidad en mapa de pasajeros (Admin puede pausar por incidencias). GPS reside en el POS (12V/24V), no en la tablet.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. TABLA: drivers
--     Conductores del sistema
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE drivers (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            VARCHAR(100) NOT NULL,
    license_number  VARCHAR(20)  UNIQUE NOT NULL,  -- brevete MTPE
    pin_hash        VARCHAR(255) NOT NULL,          -- PIN de 6 dígitos (bcrypt)
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_drivers_user_id ON drivers(user_id);
CREATE INDEX idx_drivers_active  ON drivers(is_active) WHERE is_active = TRUE;

COMMENT ON TABLE drivers IS 'Perfil extendido del conductor. Autenticación por PIN desde la tablet al iniciar turno.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. TABLA: shifts
--     Turnos de conducción con nonce QR dinámico
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE shifts (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id               UUID            NOT NULL REFERENCES drivers(id),
    bus_id                  UUID            NOT NULL REFERENCES buses(id),
    route_id                UUID            NOT NULL REFERENCES routes(id),
    direction               direction_type  NOT NULL,          -- UP o DOWN al iniciar
    qr_nonce                VARCHAR(255)    UNIQUE NOT NULL,   -- UUID nonce del QR dinámico vigente
    started_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    ended_at                TIMESTAMPTZ,
    initial_odometer_km     NUMERIC(8,2),
    total_app_revenue_pen   NUMERIC(10,2)   NOT NULL DEFAULT 0.00,
    total_yape_revenue_pen  NUMERIC(10,2)   NOT NULL DEFAULT 0.00,
    total_conadis_count     INTEGER         NOT NULL DEFAULT 0,
    total_trips             INTEGER         NOT NULL DEFAULT 0,
    status                  shift_status    NOT NULL DEFAULT 'ACTIVE',
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shifts_driver_id  ON shifts(driver_id);
CREATE INDEX idx_shifts_bus_id     ON shifts(bus_id);
CREATE INDEX idx_shifts_status     ON shifts(status) WHERE status = 'ACTIVE';
CREATE INDEX idx_shifts_qr_nonce   ON shifts(qr_nonce);

COMMENT ON TABLE shifts IS 'Turno de conducción. qr_nonce es el UUID que el POS incluye en el QR dinámico y se regenera en <500ms tras cada cobro exitoso. El Bus invierte dirección automáticamente al alcanzar un paradero terminal.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 15. TABLA: trips
--     Viajes individuales de pasajeros (abordaje → descenso)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE trips (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id),
    shift_id        UUID        NOT NULL REFERENCES shifts(id),
    bus_id          UUID        NOT NULL REFERENCES buses(id),
    fare_type       fare_type   NOT NULL,
    points_debited  INTEGER     NOT NULL DEFAULT 0,
    boarded_stop_id UUID        REFERENCES stops(id),
    alighted_stop_id UUID       REFERENCES stops(id),
    boarded_lat     NUMERIC(10,8),
    boarded_lng     NUMERIC(11,8),
    alighted_lat    NUMERIC(10,8),
    alighted_lng    NUMERIC(11,8),
    status          trip_status NOT NULL DEFAULT 'ACTIVE',
    qr_nonce_used   VARCHAR(255),                        -- nonce del QR escaneado (anti-replay)
    companion_count INTEGER     NOT NULL DEFAULT 0,       -- pasajeros acompañantes (CU-01.B)
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at        TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_trips_user_id    ON trips(user_id);
CREATE INDEX idx_trips_shift_id   ON trips(shift_id);
CREATE INDEX idx_trips_bus_id     ON trips(bus_id);
CREATE INDEX idx_trips_status     ON trips(status) WHERE status = 'ACTIVE';
CREATE INDEX idx_trips_created_at ON trips(created_at DESC);
CREATE INDEX idx_trips_qr_nonce   ON trips(qr_nonce_used) WHERE qr_nonce_used IS NOT NULL;

COMMENT ON TABLE trips IS 'Registro de cada viaje. qr_nonce_used previene replay attacks (nonce de un solo uso). companion_count incluye acompañantes pagados en la misma transacción.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 16. TABLA: hardware_pairings
--     Vinculación segura POS/Tablet con buses (mTLS + token QR de un solo uso)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE hardware_pairings (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    bus_id              UUID            NOT NULL REFERENCES buses(id),
    device_type         device_type     NOT NULL,
    device_serial       VARCHAR(100)    NOT NULL,
    mac_address         VARCHAR(17),                        -- formato AA:BB:CC:DD:EE:FF
    pairing_token_hash  VARCHAR(255),                       -- hash del token QR de un solo uso
    certificate_pem     TEXT,                               -- certificado mTLS del dispositivo
    status              pairing_status  NOT NULL DEFAULT 'PENDING',
    paired_at           TIMESTAMPTZ,
    revoked_at          TIMESTAMPTZ,
    revoked_by_admin_id UUID            REFERENCES users(id),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    UNIQUE (bus_id, device_type, status)                    -- un POS activo por bus
);

CREATE INDEX idx_pairings_bus_id      ON hardware_pairings(bus_id);
CREATE INDEX idx_pairings_device_type ON hardware_pairings(device_type);
CREATE INDEX idx_pairings_status      ON hardware_pairings(status);

COMMENT ON TABLE hardware_pairings IS 'Vinculación mTLS entre hardware (POS/Tablet) y buses. El Admin genera un token QR de un solo uso. El POS lo escanea para completar el handshake. Revocación inmediata disponible.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 17. TABLA: support_tickets
--     Tickets de soporte, sugerencias y reportes de pasajeros
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE support_tickets (
    id                      UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID            REFERENCES users(id),          -- nullable (invitado)
    trip_id                 UUID            REFERENCES trips(id),           -- nullable (referencia opcional)
    category                ticket_category NOT NULL,
    subject                 VARCHAR(255)    NOT NULL,
    description             TEXT            NOT NULL,
    attachment_url          VARCHAR(500),
    status                  ticket_status   NOT NULL DEFAULT 'OPEN',
    resolution_notes        TEXT,
    assigned_to_admin_id    UUID            REFERENCES users(id),
    created_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    resolved_at             TIMESTAMPTZ
);

CREATE INDEX idx_tickets_user_id  ON support_tickets(user_id);
CREATE INDEX idx_tickets_status   ON support_tickets(status);
CREATE INDEX idx_tickets_category ON support_tickets(category);
CREATE INDEX idx_tickets_created  ON support_tickets(created_at DESC);

COMMENT ON TABLE support_tickets IS 'Sistema de tickets CU-09. user_id nullable permite reportes anónimos. trip_id opcinal para vincular un problema a un viaje específico.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 18. TABLA: webhook_idempotency
--     Deduplicación de webhooks bancarios (Yape, etc.)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE webhook_idempotency (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    gateway             VARCHAR(50) NOT NULL,              -- 'YAPE', 'VISA', etc.
    gateway_tx_id       VARCHAR(255) NOT NULL,
    processed_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_snapshot   JSONB,                             -- snapshot del payload para auditoría
    UNIQUE (gateway, gateway_tx_id)
);

CREATE INDEX idx_webhook_gateway_txid ON webhook_idempotency(gateway, gateway_tx_id);

COMMENT ON TABLE webhook_idempotency IS 'Tabla de idempotencia para webhooks bancarios. Antes de procesar cualquier webhook, se verifica si (gateway, gateway_tx_id) ya existe. Si existe, se retorna 200 sin reprocesar.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 19. FUNCIONES Y TRIGGERS
-- ─────────────────────────────────────────────────────────────────────────────

-- 19.1 Trigger: updated_at automático
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Aplicar a todas las tablas con updated_at
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY['users','user_sessions','student_verifications',
                                'routes','buses','drivers','fare_config','app_config','support_tickets']
    LOOP
        EXECUTE format('
            CREATE TRIGGER trg_%s_updated_at
            BEFORE UPDATE ON %s
            FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at()', tbl, tbl);
    END LOOP;
END;
$$;

-- 19.2 Función: débito atómico de puntos con lock pesimista (anti-double-spend)
CREATE OR REPLACE FUNCTION fn_debit_wallet(
    p_wallet_id     UUID,
    p_user_id       UUID,
    p_points        INTEGER,
    p_amount_pen    NUMERIC,
    p_reference_id  UUID,
    p_reference_type VARCHAR,
    p_description   VARCHAR
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_wallet        wallets%ROWTYPE;
    v_tx_id         UUID;
BEGIN
    -- Lock pesimista: previene double-spend concurrente
    SELECT * INTO v_wallet FROM wallets WHERE id = p_wallet_id FOR UPDATE;

    IF v_wallet.points_balance < p_points THEN
        RAISE EXCEPTION 'INSUFFICIENT_BALANCE: saldo % < requerido %',
            v_wallet.points_balance, p_points;
    END IF;

    -- Descontar saldo
    UPDATE wallets
    SET points_balance = points_balance - p_points,
        updated_at     = NOW()
    WHERE id = p_wallet_id;

    -- Registrar en ledger
    INSERT INTO ledger_transactions (
        wallet_id, user_id, type, amount_points, amount_pen,
        reference_id, reference_type, balance_before, balance_after, description
    ) VALUES (
        p_wallet_id, p_user_id, 'TRIP_DEBIT', -p_points, -p_amount_pen,
        p_reference_id, p_reference_type, v_wallet.points_balance,
        v_wallet.points_balance - p_points, p_description
    ) RETURNING id INTO v_tx_id;

    -- Actualizar last_transaction_id en wallet
    UPDATE wallets SET last_transaction_id = v_tx_id WHERE id = p_wallet_id;

    RETURN v_tx_id;
END;
$$;

COMMENT ON FUNCTION fn_debit_wallet IS 'Débito atómico de puntos con SELECT...FOR UPDATE (lock pesimista). Previene double-spend en transacciones concurrentes.';

-- 19.3 Función: crédito atómico de puntos (recarga)
CREATE OR REPLACE FUNCTION fn_credit_wallet(
    p_wallet_id      UUID,
    p_user_id        UUID,
    p_points         INTEGER,
    p_amount_pen     NUMERIC,
    p_reference_id   UUID,
    p_reference_type VARCHAR,
    p_description    VARCHAR
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_balance_before INTEGER;
    v_tx_id          UUID;
BEGIN
    SELECT points_balance INTO v_balance_before FROM wallets WHERE id = p_wallet_id FOR UPDATE;

    UPDATE wallets
    SET points_balance = points_balance + p_points,
        updated_at     = NOW()
    WHERE id = p_wallet_id;

    INSERT INTO ledger_transactions (
        wallet_id, user_id, type, amount_points, amount_pen,
        reference_id, reference_type, balance_before, balance_after, description
    ) VALUES (
        p_wallet_id, p_user_id, 'RECHARGE_CREDIT', p_points, p_amount_pen,
        p_reference_id, p_reference_type, v_balance_before,
        v_balance_before + p_points, p_description
    ) RETURNING id INTO v_tx_id;

    UPDATE wallets SET last_transaction_id = v_tx_id WHERE id = p_wallet_id;

    RETURN v_tx_id;
END;
$$;

-- 19.4 Función: invalidar sesiones anteriores al crear nueva (sesión única Yape-style)
CREATE OR REPLACE FUNCTION fn_revoke_previous_sessions(
    p_user_id   UUID,
    p_new_jti   VARCHAR
) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE user_sessions
    SET is_active  = FALSE,
        revoked_at = NOW()
    WHERE user_id  = p_user_id
      AND is_active = TRUE
      AND jwt_jti  <> p_new_jti;
END;
$$;

COMMENT ON FUNCTION fn_revoke_previous_sessions IS 'Al autenticar en un nuevo dispositivo, invalida todas las sesiones activas previas del usuario. Implementa la restricción de 1 sesión activa por usuario (como Yape).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 20. VISTAS ÚTILES
-- ─────────────────────────────────────────────────────────────────────────────

-- Vista: saldo actual por usuario (para backoffice)
CREATE OR REPLACE VIEW v_user_wallet_summary AS
SELECT
    u.id            AS user_id,
    u.phone,
    u.name,
    u.role,
    w.points_balance,
    ROUND(w.points_balance::NUMERIC / 10, 2) AS balance_pen,
    w.updated_at    AS wallet_updated_at
FROM users u
JOIN wallets w ON w.user_id = u.id;

COMMENT ON VIEW v_user_wallet_summary IS 'Vista de saldo actual por usuario. balance_pen = points_balance / 10.';

-- Vista: buses activos con telemetría en tiempo real (para mapa)
CREATE OR REPLACE VIEW v_buses_realtime AS
SELECT
    b.id,
    b.plate,
    r.name          AS route_name,
    r.line_number,
    r.color_hex,
    b.gps_lat,
    b.gps_lng,
    b.gps_heading,
    b.gps_speed,
    b.current_direction,
    b.last_telemetry_at,
    b.is_visible_public,
    b.pause_reason,
    s.id            AS active_shift_id,
    d.name          AS driver_name
FROM buses b
LEFT JOIN routes r  ON r.id  = b.route_id
LEFT JOIN shifts s  ON s.bus_id = b.id AND s.status = 'ACTIVE'
LEFT JOIN drivers d ON d.id  = s.driver_id
WHERE b.is_active = TRUE;

COMMENT ON VIEW v_buses_realtime IS 'Vista de telemetría en tiempo real para el mapa de pasajeros. Incluye is_visible_public para filtrar buses pausados.';

-- Vista: historial de gastos y recargas por usuario (CU-08)
CREATE OR REPLACE VIEW v_user_transaction_history AS
SELECT
    lt.user_id,
    lt.created_at,
    lt.type,
    lt.amount_points,
    lt.amount_pen,
    lt.balance_before,
    lt.balance_after,
    lt.description,
    lt.reference_type,
    -- Enriquecer con datos del viaje o recarga
    CASE lt.reference_type
        WHEN 'TRIP'    THEN t.fare_type::TEXT
        WHEN 'RECHARGE' THEN r.gateway::TEXT
        ELSE NULL
    END AS reference_detail
FROM ledger_transactions lt
LEFT JOIN trips    t ON t.id = lt.reference_id AND lt.reference_type = 'TRIP'
LEFT JOIN recharges r ON r.id = lt.reference_id AND lt.reference_type = 'RECHARGE'
ORDER BY lt.created_at DESC;

COMMENT ON VIEW v_user_transaction_history IS 'Historial unificado de gastos (débitos de viajes) y recargas por usuario. Usado en CU-08.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 21. ÍNDICES COMPUESTOS ADICIONALES (Performance)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE INDEX idx_trips_user_status      ON trips(user_id, status);
CREATE INDEX idx_trips_bus_active       ON trips(bus_id, status) WHERE status = 'ACTIVE';
CREATE INDEX idx_ledger_user_created    ON ledger_transactions(user_id, created_at DESC);
CREATE INDEX idx_shifts_bus_active      ON shifts(bus_id, status) WHERE status = 'ACTIVE';
CREATE INDEX idx_sv_user_status         ON student_verifications(user_id, status);

-- ─────────────────────────────────────────────────────────────────────────────
-- 22. ROW LEVEL SECURITY (RLS) — Base
-- ─────────────────────────────────────────────────────────────────────────────
-- Habilitar RLS en tablas sensibles (política detallada en capa de aplicación)
ALTER TABLE users               ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallets             ENABLE ROW LEVEL SECURITY;
ALTER TABLE ledger_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips               ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets     ENABLE ROW LEVEL SECURITY;

-- Política de acceso: cada usuario solo ve sus propios datos
-- (implementar con JWT claim app.current_user_id en la capa de aplicación)
-- Ejemplo para wallets:
-- CREATE POLICY wallet_owner ON wallets
--     USING (user_id = current_setting('app.current_user_id')::UUID);

COMMENT ON TABLE wallets IS 'RLS habilitado. Los usuarios solo pueden consultar su propio monedero via políticas de fila.';

-- ─────────────────────────────────────────────────────────────────────────────
-- FIN DEL SCRIPT DDL BC v1.0.0
-- ─────────────────────────────────────────────────────────────────────────────

