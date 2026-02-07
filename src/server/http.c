#include "http.h"
#include "mongoose.h"
#include "bridge.h"

#include <string.h>
#include <stdio.h>

static const char *s_doc_root = "./static";

void http_init(const char *doc_root) {
    if (doc_root != NULL) {
        s_doc_root = doc_root;
    }
}

void http_send_json(struct mg_connection *c, int status_code, const char *json) {
    mg_http_reply(c, status_code,
                  "Content-Type: application/json\r\n"
                  "Access-Control-Allow-Origin: *\r\n",
                  "%s", json);
}

void http_send_error(struct mg_connection *c, int status_code, const char *message) {
    char buf[512];
    snprintf(buf, sizeof(buf), "{\"error\":\"%s\"}", message);
    http_send_json(c, status_code, buf);
}

/*
 * Route API requests to the appropriate handler.
 * All API routes are handled here; everything else is static.
 */
static void handle_api(struct mg_connection *c, struct mg_http_message *hm) {
    if (mg_match(hm->uri, mg_str("/api/incidents"), NULL)) {
        if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
            const char *result = bridge_get_incidents();
            if (result != NULL) {
                http_send_json(c, 200, result);
            } else {
                http_send_error(c, 500, "failed to query incidents");
            }
        } else if (mg_strcmp(hm->method, mg_str("POST")) == 0) {
            /* Validate content length before processing */
            if (hm->body.len == 0 || hm->body.len > 65536) {
                http_send_error(c, 400, "invalid request body");
                return;
            }
            const char *result = bridge_create_incident(hm->body.buf, hm->body.len);
            if (result != NULL) {
                http_send_json(c, 201, result);
            } else {
                http_send_error(c, 400, "invalid incident data");
            }
        } else {
            http_send_error(c, 405, "method not allowed");
        }
    } else if (mg_match(hm->uri, mg_str("/api/units"), NULL)) {
        if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
            const char *result = bridge_get_units();
            if (result != NULL) {
                http_send_json(c, 200, result);
            } else {
                http_send_error(c, 500, "failed to query units");
            }
        } else {
            http_send_error(c, 405, "method not allowed");
        }
    } else if (mg_match(hm->uri, mg_str("/api/events"), NULL)) {
        if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
            const char *result = bridge_get_events();
            if (result != NULL) {
                http_send_json(c, 200, result);
            } else {
                http_send_error(c, 500, "failed to query events");
            }
        } else {
            http_send_error(c, 405, "method not allowed");
        }
    } else {
        http_send_error(c, 404, "not found");
    }
}

void http_serve_static(struct mg_connection *c, struct mg_http_message *hm) {
    struct mg_http_serve_opts opts = {
        .root_dir = s_doc_root,
        .ssi_pattern = NULL,
    };
    mg_http_serve_dir(c, hm, &opts);
}

void http_handle_request(struct mg_connection *c, struct mg_http_message *hm) {
    if (mg_match(hm->uri, mg_str("/api/*"), NULL)) {
        handle_api(c, hm);
    } else {
        http_serve_static(c, hm);
    }
}
