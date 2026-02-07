#include "bridge.h"
#include "db.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/*
 * OCaml FFI bridge, currently in stub mode.
 *
 * Eventually this will initialise the OCaml runtime and call
 * into the real dispatch engine. For now it talks straight to
 * SQLite, which is honest if nothing else. The important thing
 * is that the interface is right, so when the FFI lands,
 * nothing else in the server needs to change.
 */

static int s_initialized = 0;

int bridge_init(void) {
    if (s_initialized) return 0;

    /* TODO: Initialize OCaml runtime
     * char *argv[] = { "callout", NULL };
     * caml_startup(argv);
     */

    s_initialized = 1;
    fprintf(stdout, "bridge: initialized (stub mode)\n");
    return 0;
}

void bridge_shutdown(void) {
    s_initialized = 0;
}

const char *bridge_handle_ws_message(const char *json, size_t len) {
    (void)json;
    (void)len;

    /* TODO: Deserialize JSON, call OCaml dispatch logic,
     * serialize response. For now, echo back a stub. */
    return "{\"type\":\"pong\"}";
}

const char *bridge_create_incident(const char *json, size_t len) {
    (void)json;
    (void)len;

    /* TODO: Parse JSON, call OCaml Incident.create,
     * write to DB, return created incident as JSON. */
    return "{\"status\":\"stub\",\"message\":\"incident creation not yet implemented\"}";
}

const char *bridge_get_incidents(void) {
    return db_query_incidents();
}

const char *bridge_get_units(void) {
    return db_query_units();
}

const char *bridge_get_events(void) {
    return db_query_events_since(0.0);
}
