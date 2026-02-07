#include "ws.h"
#include "bridge.h"
#include "mongoose.h"

#include <string.h>
#include <stdio.h>

/*
 * Fixed-size connection array. Allocated once, reused forever.
 * If you need more than 64 simultaneous WebSocket clients,
 * bump WS_MAX_CONNECTIONS and have a word with yourself
 * about what kind of dispatch centre you're running.
 */
static struct mg_connection *s_connections[WS_MAX_CONNECTIONS];
static int s_conn_count = 0;

void ws_init(void) {
    memset(s_connections, 0, sizeof(s_connections));
    s_conn_count = 0;
}

static int find_slot(void) {
    for (int i = 0; i < WS_MAX_CONNECTIONS; i++) {
        if (s_connections[i] == NULL) return i;
    }
    return -1;
}

static void remove_connection(struct mg_connection *c) {
    for (int i = 0; i < WS_MAX_CONNECTIONS; i++) {
        if (s_connections[i] == c) {
            s_connections[i] = NULL;
            s_conn_count--;
            return;
        }
    }
}

void ws_handle_open(struct mg_connection *c) {
    int slot = find_slot();
    if (slot < 0) {
        /* No room — reject the connection */
        fprintf(stderr, "ws: max connections reached (%d), rejecting\n",
                WS_MAX_CONNECTIONS);
        c->is_draining = 1;
        return;
    }
    s_connections[slot] = c;
    s_conn_count++;
    fprintf(stdout, "ws: client connected (slot %d, total %d)\n",
            slot, s_conn_count);
}

void ws_handle_message(struct mg_connection *c, struct mg_ws_message *wm) {
    /* Validate message size before processing */
    if (wm->data.len == 0 || wm->data.len > 65536) {
        mg_ws_send(c, "{\"type\":\"error\",\"message\":\"invalid message size\"}",
                   48, WEBSOCKET_OP_TEXT);
        return;
    }

    /* Pass to OCaml bridge for processing.
     * The bridge returns a JSON response string (or NULL on error). */
    const char *response = bridge_handle_ws_message(wm->data.buf, wm->data.len);
    if (response != NULL) {
        mg_ws_send(c, response, strlen(response), WEBSOCKET_OP_TEXT);
    }
}

void ws_handle_close(struct mg_connection *c) {
    remove_connection(c);
    fprintf(stdout, "ws: client disconnected (total %d)\n", s_conn_count);
}

void ws_broadcast(struct mg_mgr *mgr, const char *msg, size_t len) {
    for (struct mg_connection *c = mgr->conns; c != NULL; c = c->next) {
        if (c->is_websocket) {
            mg_ws_send(c, msg, len, WEBSOCKET_OP_TEXT);
        }
    }
}

int ws_connection_count(void) {
    return s_conn_count;
}
