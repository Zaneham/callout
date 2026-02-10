#ifndef CALLOUT_WS_H
#define CALLOUT_WS_H

#include <stddef.h>

#define WS_MAX_CONNECTIONS 64
#define WS_USER_ID_MAX     64

struct mg_connection;
struct mg_ws_message;
struct mg_mgr;

void ws_init(void);
void ws_handle_open(struct mg_connection *c);
void ws_handle_message(struct mg_connection *c, struct mg_ws_message *wm);
void ws_handle_close(struct mg_connection *c);
void ws_set_user_id(struct mg_connection *c, const char *user_id);
const char *ws_get_user_id(struct mg_connection *c);
void ws_broadcast(struct mg_mgr *mgr, const char *msg, size_t len);
int ws_connection_count(void);

#endif
