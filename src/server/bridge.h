#ifndef CALLOUT_BRIDGE_H
#define CALLOUT_BRIDGE_H

/*
 * The border crossing between C and OCaml.
 *
 * Everything from the network gets checked here before it's
 * allowed anywhere near the domain logic. Think of it as the
 * bouncer. Currently running in stub mode while the FFI
 * integration is built out, so the bouncer is just waving
 * everyone through to the database directly.
 */

#include <stddef.h>

/* Initialize the OCaml runtime. Must be called once at startup. */
int bridge_init(void);

/* Shutdown the OCaml runtime. */
void bridge_shutdown(void);

/* Process an incoming WebSocket message (JSON).
 * Returns a JSON response string, or NULL on error. */
const char *bridge_handle_ws_message(const char *json, size_t len);

/* Create a new incident from JSON. Returns JSON response or NULL. */
const char *bridge_create_incident(const char *json, size_t len);

/* Get all incidents as JSON array. Returns NULL on error. */
const char *bridge_get_incidents(void);

/* Get all units as JSON array. Returns NULL on error. */
const char *bridge_get_units(void);

/* Get events since timestamp as JSON array. Returns NULL on error. */
const char *bridge_get_events(void);

#endif /* CALLOUT_BRIDGE_H */
