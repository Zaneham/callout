#ifndef CALLOUT_DB_H
#define CALLOUT_DB_H

/*
 * SQLite interface.
 *
 * One file, no server process, works offline. WAL mode for
 * concurrent reads and writes. Schema gets applied automatically
 * the first time you open a fresh database, so there's no
 * "did you run the migrations" conversation.
 */

#include "sqlite3.h"

/* Open the database and apply schema if needed. Returns 0 on success. */
int db_open(const char *path);

/* Close the database cleanly */
void db_close(void);

/* Get the raw sqlite3 handle (for use by the OCaml bridge) */
sqlite3 *db_handle(void);

/* Insert an event into the events table. Returns 0 on success. */
int db_insert_event(const char *id, double timestamp, const char *author,
                    int authority, const char *payload_json, int synced);

/* Query events since a given timestamp. Returns JSON array string.
 * Caller must free the returned string. */
char *db_query_events_since(double since);

/* Query all incidents. Returns JSON array string.
 * Caller must free the returned string. */
char *db_query_incidents(void);

/* Query all units. Returns JSON array string.
 * Caller must free the returned string. */
char *db_query_units(void);

/* Insert or update an incident. Returns 0 on success. */
int db_upsert_incident(const char *id, const char *status, int severity,
                       double lat, double lng, const char *description,
                       double created_at, double updated_at);

/* Insert or update a unit. Returns 0 on success. */
int db_upsert_unit(const char *id, const char *name, const char *status,
                   const char *incident_id, double lat, double lng,
                   double updated_at);

/* Mark events as synced. Returns 0 on success. */
int db_mark_events_synced(const char **event_ids, int count);

#endif /* CALLOUT_DB_H */
