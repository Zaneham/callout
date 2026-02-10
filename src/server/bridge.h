#ifndef CALLOUT_BRIDGE_H
#define CALLOUT_BRIDGE_H

#include <stddef.h>

int bridge_init(void);
void bridge_shutdown(void);
const char *bridge_handle_ws_message(const char *json, size_t len);
const char *bridge_create_incident(const char *json, size_t len);
const char *bridge_get_incidents(void);
const char *bridge_get_units(void);
const char *bridge_get_events(void);
int bridge_load_events(const char *json, size_t len);

#endif
