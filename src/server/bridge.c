#include "bridge.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include <caml/mlvalues.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/alloc.h>

/*
 * OCaml FFI bridge.
 *
 * Initialises the OCaml runtime, looks up the callbacks registered
 * by bridge_ffi.ml, and forwards every call across the border.
 * String results are copied into a static buffer because the OCaml
 * GC can relocate heap objects between calls.
 */

static int s_initialized = 0;

static const value *cb_init            = NULL;
static const value *cb_handle_ws_msg   = NULL;
static const value *cb_create_incident = NULL;
static const value *cb_get_incidents   = NULL;
static const value *cb_get_units       = NULL;
static const value *cb_get_events      = NULL;

/* Static buffer for string results — OCaml GC can move strings. */
static char s_result_buf[65536];

static const char *copy_ocaml_string(value v) {
    const char *s = String_val(v);
    size_t len = caml_string_length(v);
    if (len >= sizeof(s_result_buf)) len = sizeof(s_result_buf) - 1;
    memcpy(s_result_buf, s, len);
    s_result_buf[len] = '\0';
    return s_result_buf;
}

int bridge_init(void) {
    if (s_initialized) return 0;

    /* Start the OCaml runtime */
    char *argv[] = { "callout", NULL };
    caml_startup(argv);

    /* Look up callbacks registered by bridge_ffi.ml */
    cb_init            = caml_named_value("bridge_init");
    cb_handle_ws_msg   = caml_named_value("bridge_handle_ws_message");
    cb_create_incident = caml_named_value("bridge_create_incident");
    cb_get_incidents   = caml_named_value("bridge_get_incidents");
    cb_get_units       = caml_named_value("bridge_get_units");
    cb_get_events      = caml_named_value("bridge_get_events");

    if (!cb_init || !cb_handle_ws_msg || !cb_create_incident ||
        !cb_get_incidents || !cb_get_units || !cb_get_events) {
        fprintf(stderr, "bridge: failed to find OCaml callbacks\n");
        return -1;
    }

    /* Call the OCaml init to reset engine state */
    caml_callback(*cb_init, Val_unit);

    s_initialized = 1;
    fprintf(stdout, "bridge: initialized\n");
    return 0;
}

void bridge_shutdown(void) {
    s_initialized = 0;
}

const char *bridge_handle_ws_message(const char *json, size_t len) {
    (void)len;
    if (!cb_handle_ws_msg) return NULL;

    value v_json = caml_copy_string(json);
    value result = caml_callback(*cb_handle_ws_msg, v_json);
    return copy_ocaml_string(result);
}

const char *bridge_create_incident(const char *json, size_t len) {
    (void)len;
    if (!cb_create_incident) return NULL;

    value v_json = caml_copy_string(json);
    value result = caml_callback(*cb_create_incident, v_json);
    return copy_ocaml_string(result);
}

const char *bridge_get_incidents(void) {
    if (!cb_get_incidents) return NULL;

    value result = caml_callback(*cb_get_incidents, Val_unit);
    return copy_ocaml_string(result);
}

const char *bridge_get_units(void) {
    if (!cb_get_units) return NULL;

    value result = caml_callback(*cb_get_units, Val_unit);
    return copy_ocaml_string(result);
}

const char *bridge_get_events(void) {
    if (!cb_get_events) return NULL;

    value result = caml_callback(*cb_get_events, Val_unit);
    return copy_ocaml_string(result);
}
