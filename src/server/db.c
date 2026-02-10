#include "db.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static sqlite3 *s_db = NULL;

static const char *SCHEMA_SQL =
    "PRAGMA journal_mode=WAL;"
    "PRAGMA foreign_keys=ON;"
    "CREATE TABLE IF NOT EXISTS events ("
    "    id          TEXT PRIMARY KEY,"
    "    timestamp   REAL NOT NULL,"
    "    author      TEXT NOT NULL,"
    "    authority   INTEGER NOT NULL,"
    "    payload     TEXT NOT NULL,"
    "    synced      INTEGER DEFAULT 0,"
    "    created_at  REAL NOT NULL"
    ");"
    "CREATE TABLE IF NOT EXISTS incidents ("
    "    id          TEXT PRIMARY KEY,"
    "    status      TEXT NOT NULL,"
    "    severity    INTEGER NOT NULL,"
    "    lat         REAL NOT NULL,"
    "    lng         REAL NOT NULL,"
    "    description TEXT,"
    "    created_at  REAL NOT NULL,"
    "    updated_at  REAL NOT NULL"
    ");"
    "CREATE TABLE IF NOT EXISTS units ("
    "    id          TEXT PRIMARY KEY,"
    "    name        TEXT NOT NULL,"
    "    status      TEXT NOT NULL,"
    "    incident_id TEXT,"
    "    lat         REAL,"
    "    lng         REAL,"
    "    updated_at  REAL NOT NULL"
    ");"
    "CREATE TABLE IF NOT EXISTS event_types ("
    "    id          TEXT PRIMARY KEY,"
    "    name        TEXT NOT NULL,"
    "    icon        TEXT,"
    "    color       TEXT,"
    "    sort_order  INTEGER DEFAULT 0,"
    "    active      INTEGER DEFAULT 1"
    ");"
    "CREATE TABLE IF NOT EXISTS roles ("
    "    id          TEXT PRIMARY KEY,"
    "    name        TEXT NOT NULL UNIQUE,"
    "    authority   INTEGER NOT NULL,"
    "    description TEXT,"
    "    sort_order  INTEGER DEFAULT 0,"
    "    active      INTEGER DEFAULT 1"
    ");"
    "CREATE TABLE IF NOT EXISTS users ("
    "    id          TEXT PRIMARY KEY,"
    "    username    TEXT NOT NULL UNIQUE,"
    "    password_hash TEXT NOT NULL,"
    "    display_name TEXT NOT NULL,"
    "    role_id     TEXT NOT NULL REFERENCES roles(id),"
    "    active      INTEGER DEFAULT 1,"
    "    created_at  REAL NOT NULL,"
    "    updated_at  REAL NOT NULL"
    ");"
    "CREATE TABLE IF NOT EXISTS role_permissions ("
    "    id          TEXT PRIMARY KEY,"
    "    role_id     TEXT NOT NULL REFERENCES roles(id),"
    "    panel       TEXT NOT NULL,"
    "    can_view    INTEGER DEFAULT 1,"
    "    can_edit    INTEGER DEFAULT 0,"
    "    UNIQUE(role_id, panel)"
    ");"
    "CREATE TABLE IF NOT EXISTS role_view_panels ("
    "    id          TEXT PRIMARY KEY,"
    "    role_id     TEXT NOT NULL REFERENCES roles(id),"
    "    panel       TEXT NOT NULL,"
    "    position    TEXT NOT NULL,"
    "    sort_order  INTEGER DEFAULT 0,"
    "    config_json TEXT,"
    "    UNIQUE(role_id, panel)"
    ");"
    "CREATE TABLE IF NOT EXISTS sops ("
    "    id          TEXT PRIMARY KEY,"
    "    title       TEXT NOT NULL,"
    "    content     TEXT NOT NULL,"
    "    links_json  TEXT,"
    "    active      INTEGER DEFAULT 1,"
    "    created_at  REAL NOT NULL,"
    "    updated_at  REAL NOT NULL"
    ");"
    "CREATE TABLE IF NOT EXISTS sop_mappings ("
    "    id          TEXT PRIMARY KEY,"
    "    sop_id      TEXT NOT NULL REFERENCES sops(id),"
    "    role_id     TEXT,"
    "    event_type_id TEXT,"
    "    sort_order  INTEGER DEFAULT 0,"
    "    UNIQUE(sop_id, role_id, event_type_id)"
    ");"
    "CREATE TABLE IF NOT EXISTS sessions ("
    "    token       TEXT PRIMARY KEY,"
    "    user_id     TEXT NOT NULL REFERENCES users(id),"
    "    created_at  REAL NOT NULL,"
    "    expires_at  REAL NOT NULL"
    ");"
    "CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);"
    "CREATE INDEX IF NOT EXISTS idx_events_synced ON events(synced);"
    "CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);"
    "CREATE INDEX IF NOT EXISTS idx_units_status ON units(status);"
    "CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);"
    "CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at);"
    "CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);"
    "CREATE INDEX IF NOT EXISTS idx_users_role ON users(role_id);";

static const char *SEED_SQL =
    "INSERT OR IGNORE INTO roles (id, name, authority, description, sort_order, active) VALUES"
    " ('role-dispatcher', 'Dispatcher', 0, 'Communications center dispatcher', 0, 1),"
    " ('role-ic', 'Incident Commander', 1, 'On-scene incident commander', 1, 1),"
    " ('role-crew-leader', 'Crew Leader', 2, 'Crew or team leader', 2, 1),"
    " ('role-field-unit', 'Field Unit', 3, 'Field officer or responder', 3, 1);"
    "INSERT OR IGNORE INTO role_permissions (id, role_id, panel, can_view, can_edit) VALUES"
    " ('perm-d-map',       'role-dispatcher', 'map',       1, 1),"
    " ('perm-d-incidents', 'role-dispatcher', 'incidents', 1, 1),"
    " ('perm-d-units',     'role-dispatcher', 'units',     1, 1),"
    " ('perm-d-dispatch',  'role-dispatcher', 'dispatch',  1, 1),"
    " ('perm-d-notes',     'role-dispatcher', 'notes',     1, 1),"
    " ('perm-d-sops',      'role-dispatcher', 'sops',      1, 0),"
    " ('perm-d-admin',     'role-dispatcher', 'admin',     1, 1),"
    " ('perm-ic-map',       'role-ic', 'map',       1, 1),"
    " ('perm-ic-incidents', 'role-ic', 'incidents', 1, 1),"
    " ('perm-ic-units',     'role-ic', 'units',     1, 1),"
    " ('perm-ic-dispatch',  'role-ic', 'dispatch',  1, 1),"
    " ('perm-ic-notes',     'role-ic', 'notes',     1, 1),"
    " ('perm-ic-sops',      'role-ic', 'sops',      1, 0),"
    " ('perm-cl-map',       'role-crew-leader', 'map',       1, 0),"
    " ('perm-cl-incidents', 'role-crew-leader', 'incidents', 1, 0),"
    " ('perm-cl-units',     'role-crew-leader', 'units',     1, 0),"
    " ('perm-cl-dispatch',  'role-crew-leader', 'dispatch',  1, 1),"
    " ('perm-cl-notes',     'role-crew-leader', 'notes',     1, 1),"
    " ('perm-cl-sops',      'role-crew-leader', 'sops',      1, 0),"
    " ('perm-fu-map',       'role-field-unit', 'map',       1, 0),"
    " ('perm-fu-incidents', 'role-field-unit', 'incidents', 1, 0),"
    " ('perm-fu-units',     'role-field-unit', 'units',     1, 0),"
    " ('perm-fu-notes',     'role-field-unit', 'notes',     1, 1),"
    " ('perm-fu-sops',      'role-field-unit', 'sops',      1, 0);"
    "INSERT OR IGNORE INTO role_view_panels (id, role_id, panel, position, sort_order) VALUES"
    " ('vp-d-map',       'role-dispatcher', 'map',       'main',    0),"
    " ('vp-d-incidents', 'role-dispatcher', 'incidents', 'sidebar', 0),"
    " ('vp-d-units',     'role-dispatcher', 'units',     'sidebar', 1),"
    " ('vp-d-sops',      'role-dispatcher', 'sops',      'sidebar', 2),"
    " ('vp-ic-map',       'role-ic', 'map',       'main',    0),"
    " ('vp-ic-incidents', 'role-ic', 'incidents', 'sidebar', 0),"
    " ('vp-ic-units',     'role-ic', 'units',     'sidebar', 1),"
    " ('vp-ic-sops',      'role-ic', 'sops',      'sidebar', 2),"
    " ('vp-cl-map',       'role-crew-leader', 'map',       'main',    0),"
    " ('vp-cl-incidents', 'role-crew-leader', 'incidents', 'sidebar', 0),"
    " ('vp-cl-sops',      'role-crew-leader', 'sops',      'sidebar', 1),"
    " ('vp-fu-map',       'role-field-unit', 'map',       'main',    0),"
    " ('vp-fu-incidents', 'role-field-unit', 'incidents', 'sidebar', 0),"
    " ('vp-fu-sops',      'role-field-unit', 'sops',      'sidebar', 1);";

int db_open(const char *path) {
    int rc = sqlite3_open(path, &s_db);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "db: failed to open %s: %s\n", path, sqlite3_errmsg(s_db));
        return -1;
    }

    char *err_msg = NULL;
    rc = sqlite3_exec(s_db, SCHEMA_SQL, NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "db: schema error: %s\n", err_msg);
        sqlite3_free(err_msg);
        return -1;
    }

    rc = sqlite3_exec(s_db, SEED_SQL, NULL, NULL, &err_msg);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "db: seed data error: %s\n", err_msg);
        sqlite3_free(err_msg);
        return -1;
    }

    fprintf(stdout, "db: opened %s (WAL mode)\n", path);
    return 0;
}

void db_close(void) {
    if (s_db != NULL) {
        sqlite3_close(s_db);
        s_db = NULL;
    }
}

sqlite3 *db_handle(void) {
    return s_db;
}

int db_insert_event(const char *id, double timestamp, const char *author,
                    int authority, const char *payload_json, int synced) {
    const char *sql =
        "INSERT INTO events (id, timestamp, author, authority, payload, synced, created_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "db: prepare error: %s\n", sqlite3_errmsg(s_db));
        return -1;
    }

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 2, timestamp);
    sqlite3_bind_text(stmt, 3, author, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 4, authority);
    sqlite3_bind_text(stmt, 5, payload_json, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 6, synced);
    sqlite3_bind_double(stmt, 7, timestamp);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        fprintf(stderr, "db: insert event error: %s\n", sqlite3_errmsg(s_db));
        return -1;
    }
    return 0;
}

static int json_escape_append(char **buf, size_t *size, size_t *used,
                               const char *s, size_t slen) {
    size_t needed = *used + slen * 6 + 4;
    if (needed >= *size) {
        size_t new_size = needed + 4096;
        char *new_buf = realloc(*buf, new_size);
        if (new_buf == NULL) return -1;
        *buf = new_buf;
        *size = new_size;
    }
    char *p = *buf + *used;
    *p++ = '"';
    for (size_t i = 0; i < slen; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
            case '"':  *p++ = '\\'; *p++ = '"';  break;
            case '\\': *p++ = '\\'; *p++ = '\\'; break;
            case '\n': *p++ = '\\'; *p++ = 'n';  break;
            case '\r': *p++ = '\\'; *p++ = 'r';  break;
            case '\t': *p++ = '\\'; *p++ = 't';  break;
            default:
                if (c < 0x20) {
                    p += sprintf(p, "\\u%04x", c);
                } else {
                    *p++ = (char)c;
                }
                break;
        }
    }
    *p++ = '"';
    *used = (size_t)(p - *buf);
    return 0;
}

static char *stmt_to_json_array(sqlite3_stmt *stmt) {
    size_t buf_size = 4096;
    size_t buf_used = 0;
    char *buf = malloc(buf_size);
    if (buf == NULL) {
        sqlite3_finalize(stmt);
        return NULL;
    }

    buf[buf_used++] = '[';
    int first = 1;
    int col_count = sqlite3_column_count(stmt);
    int rc;

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (buf_used + 4 >= buf_size) {
            buf_size *= 2;
            char *new_buf = realloc(buf, buf_size);
            if (new_buf == NULL) {
                free(buf);
                sqlite3_finalize(stmt);
                return NULL;
            }
            buf = new_buf;
        }

        if (!first) buf[buf_used++] = ',';
        first = 0;
        buf[buf_used++] = '{';

        for (int i = 0; i < col_count; i++) {
            if (i > 0) buf[buf_used++] = ',';

            const char *name = sqlite3_column_name(stmt, i);
            int type = sqlite3_column_type(stmt, i);

            size_t needed = strlen(name) + 256;
            if (buf_used + needed >= buf_size) {
                buf_size = buf_used + needed + 4096;
                char *new_buf = realloc(buf, buf_size);
                if (new_buf == NULL) {
                    free(buf);
                    sqlite3_finalize(stmt);
                    return NULL;
                }
                buf = new_buf;
            }

            buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used,
                                         "\"%s\":", name);

            switch (type) {
                case SQLITE_INTEGER:
                    buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used,
                                                 "%lld", sqlite3_column_int64(stmt, i));
                    break;
                case SQLITE_FLOAT:
                    buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used,
                                                 "%f", sqlite3_column_double(stmt, i));
                    break;
                case SQLITE_TEXT: {
                    const char *text = (const char *)sqlite3_column_text(stmt, i);
                    size_t text_len = text ? strlen(text) : 0;
                    if (json_escape_append(&buf, &buf_size, &buf_used,
                                            text ? text : "", text_len) != 0) {
                        free(buf);
                        sqlite3_finalize(stmt);
                        return NULL;
                    }
                    break;
                }
                case SQLITE_NULL:
                    buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used,
                                                 "null");
                    break;
                default:
                    buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used,
                                                 "null");
                    break;
            }
        }

        if (buf_used + 2 >= buf_size) {
            buf_size = buf_used + 256;
            char *new_buf = realloc(buf, buf_size);
            if (new_buf == NULL) {
                free(buf);
                sqlite3_finalize(stmt);
                return NULL;
            }
            buf = new_buf;
        }
        buf[buf_used++] = '}';
    }

    if (buf_used + 2 >= buf_size) {
        char *new_buf = realloc(buf, buf_used + 2);
        if (new_buf == NULL) {
            free(buf);
            sqlite3_finalize(stmt);
            return NULL;
        }
        buf = new_buf;
    }
    buf[buf_used++] = ']';
    buf[buf_used] = '\0';

    sqlite3_finalize(stmt);
    return buf;
}

static char *stmt_to_json_object(sqlite3_stmt *stmt) {
    int rc = sqlite3_step(stmt);
    if (rc != SQLITE_ROW) {
        sqlite3_finalize(stmt);
        return NULL;
    }

    size_t buf_size = 2048;
    size_t buf_used = 0;
    char *buf = malloc(buf_size);
    if (buf == NULL) {
        sqlite3_finalize(stmt);
        return NULL;
    }

    buf[buf_used++] = '{';
    int col_count = sqlite3_column_count(stmt);

    for (int i = 0; i < col_count; i++) {
        if (i > 0) buf[buf_used++] = ',';

        const char *name = sqlite3_column_name(stmt, i);
        int type = sqlite3_column_type(stmt, i);

        size_t needed = strlen(name) + 256;
        if (buf_used + needed >= buf_size) {
            buf_size = buf_used + needed + 2048;
            char *new_buf = realloc(buf, buf_size);
            if (new_buf == NULL) {
                free(buf);
                sqlite3_finalize(stmt);
                return NULL;
            }
            buf = new_buf;
        }

        buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used,
                                     "\"%s\":", name);

        switch (type) {
            case SQLITE_INTEGER:
                buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used,
                                             "%lld", sqlite3_column_int64(stmt, i));
                break;
            case SQLITE_FLOAT:
                buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used,
                                             "%f", sqlite3_column_double(stmt, i));
                break;
            case SQLITE_TEXT: {
                const char *text = (const char *)sqlite3_column_text(stmt, i);
                size_t text_len = text ? strlen(text) : 0;
                if (json_escape_append(&buf, &buf_size, &buf_used,
                                        text ? text : "", text_len) != 0) {
                    free(buf);
                    sqlite3_finalize(stmt);
                    return NULL;
                }
                break;
            }
            case SQLITE_NULL:
                buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used, "null");
                break;
            default:
                buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used, "null");
                break;
        }
    }

    if (buf_used + 2 >= buf_size) {
        char *new_buf = realloc(buf, buf_used + 2);
        if (new_buf == NULL) {
            free(buf);
            sqlite3_finalize(stmt);
            return NULL;
        }
        buf = new_buf;
    }
    buf[buf_used++] = '}';
    buf[buf_used] = '\0';

    sqlite3_finalize(stmt);
    return buf;
}

static char *query_to_json_array(const char *sql) {
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return NULL;
    return stmt_to_json_array(stmt);
}

char *db_query_events_since(double since) {
    const char *sql = "SELECT * FROM events WHERE timestamp > ? ORDER BY timestamp ASC";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return NULL;
    sqlite3_bind_double(stmt, 1, since);
    return stmt_to_json_array(stmt);
}

char *db_query_incidents(void) {
    return query_to_json_array("SELECT * FROM incidents ORDER BY updated_at DESC");
}

char *db_query_units(void) {
    return query_to_json_array("SELECT * FROM units ORDER BY name ASC");
}

int db_upsert_incident(const char *id, const char *status, int severity,
                       double lat, double lng, const char *description,
                       double created_at, double updated_at) {
    const char *sql =
        "INSERT OR REPLACE INTO incidents "
        "(id, status, severity, lat, lng, description, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, status, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 3, severity);
    sqlite3_bind_double(stmt, 4, lat);
    sqlite3_bind_double(stmt, 5, lng);
    sqlite3_bind_text(stmt, 6, description, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 7, created_at);
    sqlite3_bind_double(stmt, 8, updated_at);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

int db_upsert_unit(const char *id, const char *name, const char *status,
                   const char *incident_id, double lat, double lng,
                   double updated_at) {
    const char *sql =
        "INSERT OR REPLACE INTO units "
        "(id, name, status, incident_id, lat, lng, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, status, -1, SQLITE_TRANSIENT);
    if (incident_id != NULL) {
        sqlite3_bind_text(stmt, 4, incident_id, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_double(stmt, 5, lat);
    sqlite3_bind_double(stmt, 6, lng);
    sqlite3_bind_double(stmt, 7, updated_at);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

int db_mark_events_synced(const char **event_ids, int count) {
    if (count <= 0) return 0;

    const char *sql = "UPDATE events SET synced = 1 WHERE id = ?";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    for (int i = 0; i < count; i++) {
        sqlite3_reset(stmt);
        sqlite3_bind_text(stmt, 1, event_ids[i], -1, SQLITE_TRANSIENT);
        rc = sqlite3_step(stmt);
        if (rc != SQLITE_DONE) {
            sqlite3_finalize(stmt);
            return -1;
        }
    }

    sqlite3_finalize(stmt);
    return 0;
}

int db_has_users(void) {
    const char *sql = "SELECT COUNT(*) FROM users WHERE active = 1";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return 0;

    rc = sqlite3_step(stmt);
    int count = 0;
    if (rc == SQLITE_ROW) {
        count = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    return count > 0 ? 1 : 0;
}

int db_create_user(const char *id, const char *username,
                   const char *password_hash, const char *display_name,
                   const char *role_id, double now) {
    const char *sql =
        "INSERT INTO users (id, username, password_hash, display_name, role_id, active, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?, 1, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, username, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, password_hash, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, display_name, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, role_id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 6, now);
    sqlite3_bind_double(stmt, 7, now);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

char *db_get_user_by_username(const char *username) {
    const char *sql =
        "SELECT u.id, u.username, u.password_hash, u.display_name, u.role_id, u.active,"
        " u.created_at, u.updated_at, r.name AS role_name, r.authority"
        " FROM users u JOIN roles r ON u.role_id = r.id"
        " WHERE u.username = ? AND u.active = 1";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return NULL;

    sqlite3_bind_text(stmt, 1, username, -1, SQLITE_TRANSIENT);
    return stmt_to_json_object(stmt);
}

char *db_get_user_by_id(const char *user_id) {
    const char *sql =
        "SELECT u.id, u.username, u.display_name, u.role_id, u.active,"
        " u.created_at, u.updated_at, r.name AS role_name, r.authority"
        " FROM users u JOIN roles r ON u.role_id = r.id"
        " WHERE u.id = ? AND u.active = 1";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return NULL;

    sqlite3_bind_text(stmt, 1, user_id, -1, SQLITE_TRANSIENT);
    return stmt_to_json_object(stmt);
}

char *db_query_users(void) {
    return query_to_json_array(
        "SELECT u.id, u.username, u.display_name, u.role_id, u.active,"
        " u.created_at, u.updated_at, r.name AS role_name, r.authority"
        " FROM users u JOIN roles r ON u.role_id = r.id"
        " ORDER BY u.username ASC");
}

int db_update_user(const char *id, const char *display_name,
                   const char *role_id, const char *password_hash,
                   int active, double now) {
    char sql[512];
    int n = snprintf(sql, sizeof(sql), "UPDATE users SET updated_at = %f", now);

    if (display_name != NULL)
        n += snprintf(sql + n, sizeof(sql) - (size_t)n, ", display_name = ?");
    if (role_id != NULL)
        n += snprintf(sql + n, sizeof(sql) - (size_t)n, ", role_id = ?");
    if (password_hash != NULL)
        n += snprintf(sql + n, sizeof(sql) - (size_t)n, ", password_hash = ?");

    snprintf(sql + n, sizeof(sql) - (size_t)n, ", active = %d WHERE id = ?", active);

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    int bind_idx = 1;
    if (display_name != NULL)
        sqlite3_bind_text(stmt, bind_idx++, display_name, -1, SQLITE_TRANSIENT);
    if (role_id != NULL)
        sqlite3_bind_text(stmt, bind_idx++, role_id, -1, SQLITE_TRANSIENT);
    if (password_hash != NULL)
        sqlite3_bind_text(stmt, bind_idx++, password_hash, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, bind_idx, id, -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

int db_create_role(const char *id, const char *name, int authority,
                   const char *description, int sort_order) {
    const char *sql =
        "INSERT INTO roles (id, name, authority, description, sort_order, active) "
        "VALUES (?, ?, ?, ?, ?, 1)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 3, authority);
    if (description != NULL) {
        sqlite3_bind_text(stmt, 4, description, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_int(stmt, 5, sort_order);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

char *db_query_roles(void) {
    return query_to_json_array(
        "SELECT * FROM roles WHERE active = 1 ORDER BY sort_order ASC");
}

int db_update_role(const char *id, const char *name, int authority,
                   const char *description, int sort_order, int active) {
    const char *sql =
        "UPDATE roles SET name = ?, authority = ?, description = ?,"
        " sort_order = ?, active = ? WHERE id = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 2, authority);
    if (description != NULL) {
        sqlite3_bind_text(stmt, 3, description, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    sqlite3_bind_int(stmt, 4, sort_order);
    sqlite3_bind_int(stmt, 5, active);
    sqlite3_bind_text(stmt, 6, id, -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

int db_set_role_permission(const char *id, const char *role_id,
                           const char *panel, int can_view, int can_edit) {
    const char *sql =
        "INSERT OR REPLACE INTO role_permissions (id, role_id, panel, can_view, can_edit) "
        "VALUES (?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, role_id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, panel, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 4, can_view);
    sqlite3_bind_int(stmt, 5, can_edit);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

char *db_get_role_permissions(const char *role_id) {
    const char *sql =
        "SELECT * FROM role_permissions WHERE role_id = ? ORDER BY panel ASC";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return NULL;

    sqlite3_bind_text(stmt, 1, role_id, -1, SQLITE_TRANSIENT);
    return stmt_to_json_array(stmt);
}

int db_set_role_view_panel(const char *id, const char *role_id,
                           const char *panel, const char *position,
                           int sort_order, const char *config_json) {
    const char *sql =
        "INSERT OR REPLACE INTO role_view_panels "
        "(id, role_id, panel, position, sort_order, config_json) "
        "VALUES (?, ?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, role_id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, panel, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, position, -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(stmt, 5, sort_order);
    if (config_json != NULL) {
        sqlite3_bind_text(stmt, 6, config_json, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 6);
    }

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

char *db_get_role_view_panels(const char *role_id) {
    const char *sql =
        "SELECT * FROM role_view_panels WHERE role_id = ? ORDER BY sort_order ASC";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return NULL;

    sqlite3_bind_text(stmt, 1, role_id, -1, SQLITE_TRANSIENT);
    return stmt_to_json_array(stmt);
}

int db_create_sop(const char *id, const char *title, const char *content,
                  const char *links_json, double now) {
    const char *sql =
        "INSERT INTO sops (id, title, content, links_json, active, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, 1, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 3, content, -1, SQLITE_TRANSIENT);
    if (links_json != NULL) {
        sqlite3_bind_text(stmt, 4, links_json, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_double(stmt, 5, now);
    sqlite3_bind_double(stmt, 6, now);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

char *db_query_sops(void) {
    return query_to_json_array(
        "SELECT * FROM sops WHERE active = 1 ORDER BY title ASC");
}

int db_update_sop(const char *id, const char *title, const char *content,
                  const char *links_json, int active, double now) {
    const char *sql =
        "UPDATE sops SET title = ?, content = ?, links_json = ?,"
        " active = ?, updated_at = ? WHERE id = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, content, -1, SQLITE_TRANSIENT);
    if (links_json != NULL) {
        sqlite3_bind_text(stmt, 3, links_json, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    sqlite3_bind_int(stmt, 4, active);
    sqlite3_bind_double(stmt, 5, now);
    sqlite3_bind_text(stmt, 6, id, -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

int db_delete_sop(const char *id) {
    const char *sql = "UPDATE sops SET active = 0 WHERE id = ?";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

int db_set_sop_mapping(const char *id, const char *sop_id,
                       const char *role_id, const char *event_type_id,
                       int sort_order) {
    const char *sql =
        "INSERT OR REPLACE INTO sop_mappings "
        "(id, sop_id, role_id, event_type_id, sort_order) "
        "VALUES (?, ?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, sop_id, -1, SQLITE_TRANSIENT);
    if (role_id != NULL) {
        sqlite3_bind_text(stmt, 3, role_id, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    if (event_type_id != NULL) {
        sqlite3_bind_text(stmt, 4, event_type_id, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_int(stmt, 5, sort_order);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

char *db_query_sop_mappings(void) {
    return query_to_json_array(
        "SELECT m.*, s.title AS sop_title"
        " FROM sop_mappings m JOIN sops s ON m.sop_id = s.id"
        " WHERE s.active = 1 ORDER BY m.sort_order ASC");
}

char *db_query_sops_for_role(const char *role_id, const char *event_type_id) {
    const char *sql =
        "SELECT DISTINCT s.* FROM sops s"
        " JOIN sop_mappings m ON s.id = m.sop_id"
        " WHERE s.active = 1"
        " AND (m.role_id IS NULL OR m.role_id = ?)"
        " AND (m.event_type_id IS NULL OR m.event_type_id = ?)"
        " ORDER BY m.sort_order ASC, s.title ASC";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return NULL;

    if (role_id != NULL) {
        sqlite3_bind_text(stmt, 1, role_id, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 1);
    }
    if (event_type_id != NULL) {
        sqlite3_bind_text(stmt, 2, event_type_id, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 2);
    }

    return stmt_to_json_array(stmt);
}

int db_create_event_type(const char *id, const char *name, const char *icon,
                         const char *color, int sort_order) {
    const char *sql =
        "INSERT INTO event_types (id, name, icon, color, sort_order, active) "
        "VALUES (?, ?, ?, ?, ?, 1)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT);
    if (icon != NULL) {
        sqlite3_bind_text(stmt, 3, icon, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    if (color != NULL) {
        sqlite3_bind_text(stmt, 4, color, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 4);
    }
    sqlite3_bind_int(stmt, 5, sort_order);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

char *db_query_event_types(void) {
    return query_to_json_array(
        "SELECT * FROM event_types WHERE active = 1 ORDER BY sort_order ASC");
}

int db_update_event_type(const char *id, const char *name, const char *icon,
                         const char *color, int sort_order, int active) {
    const char *sql =
        "UPDATE event_types SET name = ?, icon = ?, color = ?,"
        " sort_order = ?, active = ? WHERE id = ?";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT);
    if (icon != NULL) {
        sqlite3_bind_text(stmt, 2, icon, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 2);
    }
    if (color != NULL) {
        sqlite3_bind_text(stmt, 3, color, -1, SQLITE_TRANSIENT);
    } else {
        sqlite3_bind_null(stmt, 3);
    }
    sqlite3_bind_int(stmt, 4, sort_order);
    sqlite3_bind_int(stmt, 5, active);
    sqlite3_bind_text(stmt, 6, id, -1, SQLITE_TRANSIENT);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

int db_create_session(const char *token, const char *user_id,
                      double created_at, double expires_at) {
    const char *sql =
        "INSERT INTO sessions (token, user_id, created_at, expires_at) "
        "VALUES (?, ?, ?, ?)";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, token, -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, user_id, -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 3, created_at);
    sqlite3_bind_double(stmt, 4, expires_at);

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

char *db_get_session(const char *token) {
    const char *sql =
        "SELECT s.user_id, s.expires_at, u.username, u.display_name,"
        " u.role_id, r.name AS role_name, r.authority"
        " FROM sessions s"
        " JOIN users u ON s.user_id = u.id"
        " JOIN roles r ON u.role_id = r.id"
        " WHERE s.token = ? AND u.active = 1";

    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return NULL;

    sqlite3_bind_text(stmt, 1, token, -1, SQLITE_TRANSIENT);
    return stmt_to_json_object(stmt);
}

int db_delete_session(const char *token) {
    const char *sql = "DELETE FROM sessions WHERE token = ?";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return -1;

    sqlite3_bind_text(stmt, 1, token, -1, SQLITE_TRANSIENT);
    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? 0 : -1;
}

int db_cleanup_sessions(double now) {
    const char *sql = "DELETE FROM sessions WHERE expires_at < ?";
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) return 0;

    sqlite3_bind_double(stmt, 1, now);
    rc = sqlite3_step(stmt);
    int deleted = sqlite3_changes(s_db);
    sqlite3_finalize(stmt);
    return (rc == SQLITE_DONE) ? deleted : 0;
}
