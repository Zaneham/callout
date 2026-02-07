#ifndef CALLOUT_HTTP_H
#define CALLOUT_HTTP_H

/*
 * HTTP request handling.
 *
 * Serves static files and routes API calls to the OCaml core
 * via the FFI bridge. Mongoose does the heavy lifting on the
 * HTTP side. We just point it in the right direction.
 */

struct mg_connection;
struct mg_http_message;

/* Initialize HTTP handler with document root path */
void http_init(const char *doc_root);

/* Handle an incoming HTTP request. Called from the Mongoose event loop. */
void http_handle_request(struct mg_connection *c, struct mg_http_message *hm);

/* Serve a static file */
void http_serve_static(struct mg_connection *c, struct mg_http_message *hm);

/* Send a JSON response */
void http_send_json(struct mg_connection *c, int status_code, const char *json);

/* Send an error response */
void http_send_error(struct mg_connection *c, int status_code, const char *message);

#endif /* CALLOUT_HTTP_H */
