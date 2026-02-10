#include "ws.h"
#include "bridge.h"
#include "mongoose.h"

#include <string.h>
#include <stdio.h>

typedef struct {
    struct mg_connection *conn;
    char user_id[WS_USER_ID_MAX];
} ws_slot;

static ws_slot s_slots[WS_MAX_CONNECTIONS];
static int s_conn_count = 0;

void ws_init(void) {
    memset(s_slots, 0, sizeof(s_slots));
    s_conn_count = 0;
}

static int find_slot(void) {
    for (int i = 0; i < WS_MAX_CONNECTIONS; i++) {
        if (s_slots[i].conn == NULL) return i;
    }
    return -1;
}

static int find_slot_by_conn(struct mg_connection *c) {
    for (int i = 0; i < WS_MAX_CONNECTIONS; i++) {
        if (s_slots[i].conn == c) return i;
    }
    return -1;
}

void ws_handle_open(struct mg_connection *c) {
    int slot = find_slot();
    if (slot < 0) {
        fprintf(stderr, "ws: max connections reached (%d), rejecting\n",
                WS_MAX_CONNECTIONS);
        c->is_draining = 1;
        return;
    }
    s_slots[slot].conn = c;
    s_slots[slot].user_id[0] = '\0';
    s_conn_count++;
    fprintf(stdout, "ws: client connected (slot %d, total %d)\n",
            slot, s_conn_count);
}

void ws_handle_message(struct mg_connection *c, struct mg_ws_message *wm) {
    if (wm->data.len == 0 || wm->data.len > 65536) {
        mg_ws_send(c, "{\"type\":\"error\",\"message\":\"invalid message size\"}",
                   48, WEBSOCKET_OP_TEXT);
        return;
    }

    const char *response = bridge_handle_ws_message(wm->data.buf, wm->data.len);
    if (response != NULL) {
        mg_ws_send(c, response, strlen(response), WEBSOCKET_OP_TEXT);
    }
}

void ws_handle_close(struct mg_connection *c) {
    int slot = find_slot_by_conn(c);
    if (slot >= 0) {
        s_slots[slot].conn = NULL;
        s_slots[slot].user_id[0] = '\0';
        if (s_conn_count > 0) s_conn_count--;
    }
    fprintf(stdout, "ws: client disconnected (total %d)\n", s_conn_count);
}

void ws_set_user_id(struct mg_connection *c, const char *user_id) {
    int slot = find_slot_by_conn(c);
    if (slot >= 0 && user_id != NULL) {
        snprintf(s_slots[slot].user_id, WS_USER_ID_MAX, "%s", user_id);
    }
}

const char *ws_get_user_id(struct mg_connection *c) {
    int slot = find_slot_by_conn(c);
    if (slot >= 0 && s_slots[slot].user_id[0] != '\0') {
        return s_slots[slot].user_id;
    }
    return NULL;
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
