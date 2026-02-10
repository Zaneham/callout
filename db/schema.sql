-- Callout CAD — SQLite Schema
--
-- WAL mode for concurrent read/write safety.
-- Append-only event log: nothing is ever deleted, only superseded.

PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS events (
    id          TEXT PRIMARY KEY,
    timestamp   REAL NOT NULL,
    author      TEXT NOT NULL,
    authority   INTEGER NOT NULL,  -- 0=dispatcher, 1=IC, 2=crew, 3=field
    payload     TEXT NOT NULL,     -- JSON-encoded event_payload
    synced      INTEGER DEFAULT 0, -- 0=local only, 1=synced to server
    created_at  REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS incidents (
    id          TEXT PRIMARY KEY,
    status      TEXT NOT NULL,
    severity    INTEGER NOT NULL,
    lat         REAL NOT NULL,
    lng         REAL NOT NULL,
    description TEXT,
    created_at  REAL NOT NULL,
    updated_at  REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS units (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    status      TEXT NOT NULL,
    incident_id TEXT,
    lat         REAL,
    lng         REAL,
    updated_at  REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
CREATE INDEX IF NOT EXISTS idx_events_synced ON events(synced);
CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);
CREATE INDEX IF NOT EXISTS idx_units_status ON units(status);

-- Configurable event/incident types (fire, medical, traffic, etc.)
CREATE TABLE IF NOT EXISTS event_types (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    icon        TEXT,
    color       TEXT,
    sort_order  INTEGER DEFAULT 0,
    active      INTEGER DEFAULT 1
);

-- Roles (map to authority levels 0-3)
CREATE TABLE IF NOT EXISTS roles (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    authority   INTEGER NOT NULL,
    description TEXT,
    sort_order  INTEGER DEFAULT 0,
    active      INTEGER DEFAULT 1
);

-- Users table (login credentials + role assignment)
CREATE TABLE IF NOT EXISTS users (
    id          TEXT PRIMARY KEY,
    username    TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role_id     TEXT NOT NULL REFERENCES roles(id),
    active      INTEGER DEFAULT 1,
    created_at  REAL NOT NULL,
    updated_at  REAL NOT NULL
);

-- What UI panels each role can see
CREATE TABLE IF NOT EXISTS role_permissions (
    id          TEXT PRIMARY KEY,
    role_id     TEXT NOT NULL REFERENCES roles(id),
    panel       TEXT NOT NULL,
    can_view    INTEGER DEFAULT 1,
    can_edit    INTEGER DEFAULT 0,
    UNIQUE(role_id, panel)
);

-- Layout config: which panels appear and where for each role
CREATE TABLE IF NOT EXISTS role_view_panels (
    id          TEXT PRIMARY KEY,
    role_id     TEXT NOT NULL REFERENCES roles(id),
    panel       TEXT NOT NULL,
    position    TEXT NOT NULL,
    sort_order  INTEGER DEFAULT 0,
    config_json TEXT,
    UNIQUE(role_id, panel)
);

-- SOPs: markdown content with optional links
CREATE TABLE IF NOT EXISTS sops (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    content     TEXT NOT NULL,
    links_json  TEXT,
    active      INTEGER DEFAULT 1,
    created_at  REAL NOT NULL,
    updated_at  REAL NOT NULL
);

-- Which SOPs show for which roles + event types
CREATE TABLE IF NOT EXISTS sop_mappings (
    id          TEXT PRIMARY KEY,
    sop_id      TEXT NOT NULL REFERENCES sops(id),
    role_id     TEXT,
    event_type_id TEXT,
    sort_order  INTEGER DEFAULT 0,
    UNIQUE(sop_id, role_id, event_type_id)
);

-- Sessions for authentication
CREATE TABLE IF NOT EXISTS sessions (
    token       TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES users(id),
    created_at  REAL NOT NULL,
    expires_at  REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role_id);

-- Seed default roles matching ICS authority hierarchy
INSERT OR IGNORE INTO roles (id, name, authority, description, sort_order, active)
VALUES
    ('role-dispatcher', 'Dispatcher', 0, 'Communications center dispatcher', 0, 1),
    ('role-ic', 'Incident Commander', 1, 'On-scene incident commander', 1, 1),
    ('role-crew-leader', 'Crew Leader', 2, 'Crew or team leader', 2, 1),
    ('role-field-unit', 'Field Unit', 3, 'Field officer or responder', 3, 1);

-- Seed default permissions for each role
INSERT OR IGNORE INTO role_permissions (id, role_id, panel, can_view, can_edit) VALUES
    ('perm-d-map',       'role-dispatcher',  'map',       1, 1),
    ('perm-d-incidents', 'role-dispatcher',  'incidents', 1, 1),
    ('perm-d-units',     'role-dispatcher',  'units',     1, 1),
    ('perm-d-dispatch',  'role-dispatcher',  'dispatch',  1, 1),
    ('perm-d-notes',     'role-dispatcher',  'notes',     1, 1),
    ('perm-d-sops',      'role-dispatcher',  'sops',      1, 0),
    ('perm-d-admin',     'role-dispatcher',  'admin',     1, 1),
    ('perm-ic-map',       'role-ic',  'map',       1, 1),
    ('perm-ic-incidents', 'role-ic',  'incidents', 1, 1),
    ('perm-ic-units',     'role-ic',  'units',     1, 1),
    ('perm-ic-dispatch',  'role-ic',  'dispatch',  1, 1),
    ('perm-ic-notes',     'role-ic',  'notes',     1, 1),
    ('perm-ic-sops',      'role-ic',  'sops',      1, 0),
    ('perm-cl-map',       'role-crew-leader',  'map',       1, 0),
    ('perm-cl-incidents', 'role-crew-leader',  'incidents', 1, 0),
    ('perm-cl-units',     'role-crew-leader',  'units',     1, 0),
    ('perm-cl-dispatch',  'role-crew-leader',  'dispatch',  1, 1),
    ('perm-cl-notes',     'role-crew-leader',  'notes',     1, 1),
    ('perm-cl-sops',      'role-crew-leader',  'sops',      1, 0),
    ('perm-fu-map',       'role-field-unit',  'map',       1, 0),
    ('perm-fu-incidents', 'role-field-unit',  'incidents', 1, 0),
    ('perm-fu-units',     'role-field-unit',  'units',     1, 0),
    ('perm-fu-notes',     'role-field-unit',  'notes',     1, 1),
    ('perm-fu-sops',      'role-field-unit',  'sops',      1, 0);

-- Seed default view panel layouts
INSERT OR IGNORE INTO role_view_panels (id, role_id, panel, position, sort_order) VALUES
    ('vp-d-map',       'role-dispatcher', 'map',       'main',    0),
    ('vp-d-incidents', 'role-dispatcher', 'incidents', 'sidebar', 0),
    ('vp-d-units',     'role-dispatcher', 'units',     'sidebar', 1),
    ('vp-d-sops',      'role-dispatcher', 'sops',      'sidebar', 2),
    ('vp-ic-map',       'role-ic', 'map',       'main',    0),
    ('vp-ic-incidents', 'role-ic', 'incidents', 'sidebar', 0),
    ('vp-ic-units',     'role-ic', 'units',     'sidebar', 1),
    ('vp-ic-sops',      'role-ic', 'sops',      'sidebar', 2),
    ('vp-cl-map',       'role-crew-leader', 'map',       'main',    0),
    ('vp-cl-incidents', 'role-crew-leader', 'incidents', 'sidebar', 0),
    ('vp-cl-sops',      'role-crew-leader', 'sops',      'sidebar', 1),
    ('vp-fu-map',       'role-field-unit', 'map',       'main',    0),
    ('vp-fu-incidents', 'role-field-unit', 'incidents', 'sidebar', 0),
    ('vp-fu-sops',      'role-field-unit', 'sops',      'sidebar', 1);
