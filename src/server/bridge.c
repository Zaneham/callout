#include "bridge.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* Static linking via -output-obj; disable __declspec(dllimport) */
#ifdef _WIN32
#define CAMLDLLIMPORT
#endif

#include <caml/mlvalues.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/alloc.h>

static int s_initialized = 0;

static const value *cb_init            = NULL;
static const value *cb_handle_ws_msg   = NULL;
static const value *cb_create_incident = NULL;
static const value *cb_get_incidents   = NULL;
static const value *cb_get_units       = NULL;
static const value *cb_get_events      = NULL;
static const value *cb_load_events     = NULL;

static char *s_result_buf = NULL;
static size_t s_result_buf_size = 0;

static const char *copy_ocaml_string(value v) {
    const char *s = String_val(v);
    size_t len = caml_string_length(v);
    if (len + 1 > s_result_buf_size) {
        size_t new_size = len + 1;
        if (new_size < 65536) new_size = 65536;
        char *new_buf = realloc(s_result_buf, new_size);
        if (new_buf == NULL) return NULL;
        s_result_buf = new_buf;
        s_result_buf_size = new_size;
    }
    memcpy(s_result_buf, s, len);
    s_result_buf[len] = '\0';
    return s_result_buf;
}

int bridge_init(void) {
    if (s_initialized) return 0;

#ifdef _WIN32
    wchar_t *wargv[] = { L"callout", NULL };
    caml_startup(wargv);
#else
    char *argv[] = { "callout", NULL };
    caml_startup(argv);
#endif

    cb_init            = caml_named_value("bridge_init");
    cb_handle_ws_msg   = caml_named_value("bridge_handle_ws_message");
    cb_create_incident = caml_named_value("bridge_create_incident");
    cb_get_incidents   = caml_named_value("bridge_get_incidents");
    cb_get_units       = caml_named_value("bridge_get_units");
    cb_get_events      = caml_named_value("bridge_get_events");
    cb_load_events     = caml_named_value("bridge_load_events");

    if (!cb_init || !cb_handle_ws_msg || !cb_create_incident ||
        !cb_get_incidents || !cb_get_units || !cb_get_events) {
        fprintf(stderr, "bridge: failed to find OCaml callbacks\n");
        return -1;
    }

    caml_callback(*cb_init, Val_unit);

    s_initialized = 1;
    fprintf(stdout, "bridge: initialized\n");
    return 0;
}

void bridge_shutdown(void) {
    s_initialized = 0;
    free(s_result_buf);
    s_result_buf = NULL;
    s_result_buf_size = 0;
}

const char *bridge_handle_ws_message(const char *json, size_t len) {
    CAMLparam0();
    CAMLlocal2(v_json, result);
    if (!cb_handle_ws_msg) CAMLreturnT(const char *, NULL);

    v_json = caml_alloc_initialized_string(len, json);
    result = caml_callback(*cb_handle_ws_msg, v_json);
    const char *ret = copy_ocaml_string(result);
    CAMLreturnT(const char *, ret);
}

const char *bridge_create_incident(const char *json, size_t len) {
    CAMLparam0();
    CAMLlocal2(v_json, result);
    if (!cb_create_incident) CAMLreturnT(const char *, NULL);

    v_json = caml_alloc_initialized_string(len, json);
    result = caml_callback(*cb_create_incident, v_json);
    const char *ret = copy_ocaml_string(result);
    CAMLreturnT(const char *, ret);
}

const char *bridge_get_incidents(void) {
    CAMLparam0();
    CAMLlocal1(result);
    if (!cb_get_incidents) CAMLreturnT(const char *, NULL);

    result = caml_callback(*cb_get_incidents, Val_unit);
    const char *ret = copy_ocaml_string(result);
    CAMLreturnT(const char *, ret);
}

const char *bridge_get_units(void) {
    CAMLparam0();
    CAMLlocal1(result);
    if (!cb_get_units) CAMLreturnT(const char *, NULL);

    result = caml_callback(*cb_get_units, Val_unit);
    const char *ret = copy_ocaml_string(result);
    CAMLreturnT(const char *, ret);
}

const char *bridge_get_events(void) {
    CAMLparam0();
    CAMLlocal1(result);
    if (!cb_get_events) CAMLreturnT(const char *, NULL);

    result = caml_callback(*cb_get_events, Val_unit);
    const char *ret = copy_ocaml_string(result);
    CAMLreturnT(const char *, ret);
}

int bridge_load_events(const char *json, size_t len) {
    CAMLparam0();
    CAMLlocal2(v_json, result);
    if (!cb_load_events) CAMLreturnT(int, -1);

    v_json = caml_alloc_initialized_string(len, json);
    result = caml_callback(*cb_load_events, v_json);
    int count = Int_val(result);
    CAMLreturnT(int, count);
}
