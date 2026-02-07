#include "db.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static sqlite3 *s_db = NULL;

/*
 * Schema applied on first open. Matches db/schema.sql.
 * WAL mode so readers don't block writers and vice versa.
 */
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
    "CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);"
    "CREATE INDEX IF NOT EXISTS idx_events_synced ON events(synced);"
    "CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);"
    "CREATE INDEX IF NOT EXISTS idx_units_status ON units(status);";

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
    sqlite3_bind_double(stmt, 7, timestamp);  /* created_at = timestamp */

    rc = sqlite3_step(stmt);
    sqlite3_finalize(stmt);

    if (rc != SQLITE_DONE) {
        fprintf(stderr, "db: insert event error: %s\n", sqlite3_errmsg(s_db));
        return -1;
    }
    return 0;
}

/*
 * Helper: execute a query and return results as a JSON array string.
 * The callback builds the JSON incrementally.
 * Caller must free the returned string.
 */
static char *query_to_json_array(const char *sql) {
    sqlite3_stmt *stmt = NULL;
    int rc = sqlite3_prepare_v2(s_db, sql, -1, &stmt, NULL);
    if (rc != SQLITE_OK) {
        return NULL;
    }

    /* Pre-allocate a reasonable buffer */
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

    while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
        if (!first) {
            buf[buf_used++] = ',';
        }
        first = 0;

        buf[buf_used++] = '{';
        for (int i = 0; i < col_count; i++) {
            if (i > 0) buf[buf_used++] = ',';

            const char *name = sqlite3_column_name(stmt, i);
            int type = sqlite3_column_type(stmt, i);

            /* Ensure buffer has room (conservative estimate) */
            size_t needed = strlen(name) + 256;
            if (buf_used + needed >= buf_size) {
                buf_size *= 2;
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
                    if (buf_used + text_len + 4 >= buf_size) {
                        buf_size = buf_used + text_len + 4096;
                        char *new_buf = realloc(buf, buf_size);
                        if (new_buf == NULL) {
                            free(buf);
                            sqlite3_finalize(stmt);
                            return NULL;
                        }
                        buf = new_buf;
                    }
                    buf_used += (size_t)snprintf(buf + buf_used, buf_size - buf_used,
                                                 "\"%s\"", text ? text : "");
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
        buf[buf_used++] = '}';
    }

    buf[buf_used++] = ']';
    buf[buf_used] = '\0';

    sqlite3_finalize(stmt);
    return buf;
}

char *db_query_events_since(double since) {
    char sql[256];
    snprintf(sql, sizeof(sql),
             "SELECT * FROM events WHERE timestamp > %f ORDER BY timestamp ASC",
             since);
    return query_to_json_array(sql);
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
