/*
 * Callout CAD Server
 *
 * The thin C layer that handles the boring-but-important bits:
 * HTTP, WebSocket, SQLite, and not falling over when someone
 * sends you a SIGTERM. All the actual dispatch logic lives in
 * OCaml, where the type system can keep an eye on it.
 *
 * No dynamic allocation after init. If malloc shows up in the
 * hot path, something has gone wrong.
 */

#include "mongoose.h"
#include "http.h"
#include "ws.h"
#include "db.h"
#include "bridge.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static volatile sig_atomic_t s_shutdown = 0;
static const char *s_listen_url = "http://0.0.0.0:8080";
static const char *s_db_path = "callout.db";
static const char *s_doc_root = "./static";

static void signal_handler(int sig) {
    (void)sig;
    s_shutdown = 1;
}

static void event_handler(struct mg_connection *c, int ev, void *ev_data) {
    switch (ev) {
        case MG_EV_HTTP_MSG: {
            struct mg_http_message *hm = (struct mg_http_message *)ev_data;

            /* Check for WebSocket upgrade */
            if (mg_match(hm->uri, mg_str("/ws"), NULL)) {
                mg_ws_upgrade(c, hm, NULL);
            } else {
                http_handle_request(c, hm);
            }
            break;
        }

        case MG_EV_WS_OPEN:
            ws_handle_open(c);
            break;

        case MG_EV_WS_MSG: {
            struct mg_ws_message *wm = (struct mg_ws_message *)ev_data;
            ws_handle_message(c, wm);
            break;
        }

        case MG_EV_CLOSE:
            if (c->is_websocket) {
                ws_handle_close(c);
            }
            break;

        default:
            break;
    }
}

static void print_usage(const char *prog) {
    fprintf(stderr,
        "Callout CAD Server\n"
        "Usage: %s [options]\n"
        "Options:\n"
        "  -p PORT      Listen port (default: 8080)\n"
        "  -d PATH      Database file path (default: callout.db)\n"
        "  -r PATH      Static file root (default: ./static)\n"
        "  -h           Show this help\n",
        prog);
}

int main(int argc, char *argv[]) {
    int port = 8080;

    /* Parse command line arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            port = atoi(argv[++i]);
            if (port <= 0 || port > 65535) {
                fprintf(stderr, "error: invalid port %d\n", port);
                return 1;
            }
        } else if (strcmp(argv[i], "-d") == 0 && i + 1 < argc) {
            s_db_path = argv[++i];
        } else if (strcmp(argv[i], "-r") == 0 && i + 1 < argc) {
            s_doc_root = argv[++i];
        } else if (strcmp(argv[i], "-h") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "error: unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }

    /* Build listen URL */
    char listen_url[128];
    snprintf(listen_url, sizeof(listen_url), "http://0.0.0.0:%d", port);
    s_listen_url = listen_url;

    /* Install signal handlers */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    /* Initialize subsystems */
    fprintf(stdout, "callout: starting server\n");

    if (db_open(s_db_path) != 0) {
        fprintf(stderr, "error: failed to open database\n");
        return 1;
    }

    if (bridge_init() != 0) {
        fprintf(stderr, "error: failed to initialize bridge\n");
        db_close();
        return 1;
    }

    http_init(s_doc_root);
    ws_init();

    /* Start Mongoose event loop */
    struct mg_mgr mgr;
    mg_mgr_init(&mgr);

    struct mg_connection *c = mg_http_listen(&mgr, s_listen_url, event_handler, NULL);
    if (c == NULL) {
        fprintf(stderr, "error: failed to bind to %s\n", s_listen_url);
        bridge_shutdown();
        db_close();
        return 1;
    }

    fprintf(stdout, "callout: listening on %s\n", s_listen_url);
    fprintf(stdout, "callout: serving files from %s\n", s_doc_root);
    fprintf(stdout, "callout: database at %s\n", s_db_path);

    /* Main event loop — polls until shutdown signal */
    while (!s_shutdown) {
        mg_mgr_poll(&mgr, 100);
    }

    /* Clean shutdown */
    fprintf(stdout, "\ncallout: shutting down\n");
    mg_mgr_free(&mgr);
    bridge_shutdown();
    db_close();
    fprintf(stdout, "callout: stopped\n");

    return 0;
}
