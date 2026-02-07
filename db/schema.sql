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
