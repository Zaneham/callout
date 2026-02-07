#ifndef CALLOUT_WS_H
#define CALLOUT_WS_H

#include <stddef.h>

/*
 * WebSocket connection management.
 *
 * Keeps track of who's listening and makes sure they all hear
 * about it when something happens. Connection slots are
 * pre-allocated at startup because the middle of an incident
 * is a poor time to discover you've run out of memory.
 */

#define WS_MAX_CONNECTIONS 64

struct mg_connection;
struct mg_ws_message;
struct mg_mgr;

/* Initialize WebSocket subsystem */
void ws_init(void);

/* Handle WebSocket upgrade request */
void ws_handle_open(struct mg_connection *c);

/* Handle incoming WebSocket message */
void ws_handle_message(struct mg_connection *c, struct mg_ws_message *wm);

/* Handle WebSocket connection close */
void ws_handle_close(struct mg_connection *c);

/* Broadcast a message to all connected WebSocket clients */
void ws_broadcast(struct mg_mgr *mgr, const char *msg, size_t len);

/* Get number of active WebSocket connections */
int ws_connection_count(void);

#endif /* CALLOUT_WS_H */
