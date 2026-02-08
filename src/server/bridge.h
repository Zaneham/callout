#ifndef CALLOUT_BRIDGE_H
#define CALLOUT_BRIDGE_H

/*
 * The border crossing between C and OCaml.
 *
 * Everything from the network gets checked here before it's
 * allowed anywhere near the domain logic. The OCaml runtime
 * is started on bridge_init(), and all dispatch logic runs
 * through caml_callback into the engine.
 */

#include <stddef.h>

/* Initialize the OCaml runtime. Must be called once at startup. */
int bridge_init(void);

/* Shutdown the OCaml runtime. */
void bridge_shutdown(void);

/* Process an incoming WebSocket message (JSON).
 * Returns a JSON response string, or NULL on error.
 * Uses len for safe string creation — does not require null termination. */
const char *bridge_handle_ws_message(const char *json, size_t len);

/* Create a new incident from JSON. Returns JSON response or NULL.
 * Uses len for safe string creation — does not require null termination. */
const char *bridge_create_incident(const char *json, size_t len);

/* Get all incidents as JSON array. Returns NULL on error. */
const char *bridge_get_incidents(void);

/* Get all units as JSON array. Returns NULL on error. */
const char *bridge_get_units(void);

/* Get events as JSON array. Returns NULL on error. */
const char *bridge_get_events(void);

/* Load events from database JSON into the engine for replay.
 * Returns the number of events loaded, or -1 on error. */
int bridge_load_events(const char *json, size_t len);

#endif /* CALLOUT_BRIDGE_H */
