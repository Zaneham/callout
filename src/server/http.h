#ifndef CALLOUT_HTTP_H
#define CALLOUT_HTTP_H

struct mg_connection;
struct mg_http_message;

void http_init(const char *doc_root);
void http_handle_request(struct mg_connection *c, struct mg_http_message *hm);
void http_serve_static(struct mg_connection *c, struct mg_http_message *hm);
void http_send_json(struct mg_connection *c, int status_code, const char *json);
void http_send_error(struct mg_connection *c, int status_code, const char *message);
void http_set_cors_origin(const char *origin);

#endif
