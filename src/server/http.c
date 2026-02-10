#include "http.h"
#include "mongoose.h"
#include "bridge.h"
#include "db.h"
#include "crypt_blowfish.h"

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>
#include <wincrypt.h>
#endif

static const char *s_doc_root = "./static";
static char s_cors_origin[256] = "*";

#define SESSION_TTL_SECONDS (8 * 3600)
#define TOKEN_HEX_LEN 64
#define ID_HEX_LEN    32

void http_init(const char *doc_root) {
    if (doc_root != NULL) {
        s_doc_root = doc_root;
    }
}

void http_set_cors_origin(const char *origin) {
    if (origin != NULL) {
        snprintf(s_cors_origin, sizeof(s_cors_origin), "%s", origin);
    }
}

void http_send_json(struct mg_connection *c, int status_code, const char *json) {
    char headers[512];
    snprintf(headers, sizeof(headers),
             "Content-Type: application/json\r\n"
             "Access-Control-Allow-Origin: %s\r\n"
             "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
             "Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS\r\n",
             s_cors_origin);
    mg_http_reply(c, status_code, headers, "%s", json);
}

void http_send_error(struct mg_connection *c, int status_code, const char *message) {
    char escaped[1024];
    size_t j = 0;
    for (size_t i = 0; message[i] && j < sizeof(escaped) - 2; i++) {
        if (message[i] == '"' || message[i] == '\\') {
            escaped[j++] = '\\';
        }
        escaped[j++] = message[i];
    }
    escaped[j] = '\0';
    char buf[1280];
    snprintf(buf, sizeof(buf), "{\"error\":\"%s\"}", escaped);
    http_send_json(c, status_code, buf);
}

static int gen_random_bytes(unsigned char *buf, size_t len) {
#ifdef _WIN32
    HCRYPTPROV prov;
    if (!CryptAcquireContextA(&prov, NULL, NULL, PROV_RSA_FULL,
                              CRYPT_VERIFYCONTEXT | CRYPT_SILENT)) {
        return -1;
    }
    BOOL ok = CryptGenRandom(prov, (DWORD)len, buf);
    CryptReleaseContext(prov, 0);
    return ok ? 0 : -1;
#else
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return -1;
    ssize_t n = read(fd, buf, len);
    close(fd);
    return (n == (ssize_t)len) ? 0 : -1;
#endif
}

static void bytes_to_hex(const unsigned char *bytes, size_t len,
                         char *hex_out, size_t hex_size) {
    static const char HEX[] = "0123456789abcdef";
    size_t i;
    for (i = 0; i < len && (i * 2 + 1) < hex_size; i++) {
        hex_out[i * 2]     = HEX[(bytes[i] >> 4) & 0x0f];
        hex_out[i * 2 + 1] = HEX[bytes[i] & 0x0f];
    }
    if (i * 2 < hex_size) hex_out[i * 2] = '\0';
}

static int gen_token(char *out, size_t out_size) {
    if (out_size < TOKEN_HEX_LEN + 1) return -1;
    unsigned char raw[32];
    if (gen_random_bytes(raw, sizeof(raw)) != 0) return -1;
    bytes_to_hex(raw, sizeof(raw), out, out_size);
    return 0;
}

static int gen_id(char *out, size_t out_size) {
    if (out_size < ID_HEX_LEN + 1) return -1;
    unsigned char raw[16];
    if (gen_random_bytes(raw, sizeof(raw)) != 0) return -1;
    bytes_to_hex(raw, sizeof(raw), out, out_size);
    return 0;
}

static int json_get_string(const char *json, size_t json_len,
                           const char *key,
                           char *out, size_t out_size) {
    char pattern[128];
    int plen = snprintf(pattern, sizeof(pattern), "\"%s\":\"", key);
    if (plen < 0 || (size_t)plen >= sizeof(pattern)) return -1;

    const char *pos = NULL;
    for (size_t i = 0; i + (size_t)plen <= json_len; i++) {
        if (memcmp(json + i, pattern, (size_t)plen) == 0) {
            pos = json + i + plen;
            break;
        }
    }
    if (pos == NULL) return -1;

    size_t j = 0;
    const char *end = json + json_len;
    while (pos < end && j < out_size - 1) {
        if (*pos == '\\' && pos + 1 < end) {
            pos++;
            out[j++] = *pos++;
        } else if (*pos == '"') {
            break;
        } else {
            out[j++] = *pos++;
        }
    }
    out[j] = '\0';
    return 0;
}

static int json_get_int(const char *json, size_t json_len,
                        const char *key, int *out) {
    char pattern[128];
    int plen = snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    if (plen < 0 || (size_t)plen >= sizeof(pattern)) return -1;

    const char *pos = NULL;
    for (size_t i = 0; i + (size_t)plen <= json_len; i++) {
        if (memcmp(json + i, pattern, (size_t)plen) == 0) {
            pos = json + i + plen;
            break;
        }
    }
    if (pos == NULL) return -1;

    while (pos < json + json_len && (*pos == ' ' || *pos == '\t')) pos++;

    *out = atoi(pos);
    return 0;
}

static int extract_bearer_token(struct mg_http_message *hm,
                                char *token_out, size_t token_size) {
    struct mg_str *auth = mg_http_get_header(hm, "Authorization");
    if (auth == NULL || auth->len < 8) return -1;
    if (auth->len < 7 || memcmp(auth->buf, "Bearer ", 7) != 0) return -1;

    size_t token_len = auth->len - 7;
    if (token_len >= token_size || token_len == 0) return -1;

    memcpy(token_out, auth->buf + 7, token_len);
    token_out[token_len] = '\0';
    return 0;
}

static int auth_check(struct mg_http_message *hm,
                      char *user_id_out, size_t user_id_size,
                      char *role_id_out, size_t role_id_size) {
    if (!db_has_users()) {
        if (user_id_out != NULL && user_id_size > 0) {
            snprintf(user_id_out, user_id_size, "open-mode");
        }
        if (role_id_out != NULL && role_id_size > 0) {
            snprintf(role_id_out, role_id_size, "role-dispatcher");
        }
        return 0;
    }

    char token[TOKEN_HEX_LEN + 1];
    if (extract_bearer_token(hm, token, sizeof(token)) != 0) return -1;

    char *session_json = db_get_session(token);
    if (session_json == NULL) return -1;

    double expires_at = 0.0;
    char expires_str[32];
    if (json_get_string(session_json, strlen(session_json), "expires_at",
                        expires_str, sizeof(expires_str)) == 0) {
        expires_at = strtod(expires_str, NULL);
    }
    if (expires_at > 0.0 && (double)time(NULL) > expires_at) {
        free(session_json);
        return -1;
    }

    int authority = -1;
    json_get_int(session_json, strlen(session_json), "authority", &authority);

    if (user_id_out != NULL) {
        json_get_string(session_json, strlen(session_json), "user_id",
                        user_id_out, user_id_size);
    }
    if (role_id_out != NULL) {
        json_get_string(session_json, strlen(session_json), "role_id",
                        role_id_out, role_id_size);
    }

    free(session_json);
    return authority;
}

static void handle_login(struct mg_connection *c, struct mg_http_message *hm) {
    if (mg_strcmp(hm->method, mg_str("POST")) != 0) {
        http_send_error(c, 405, "method not allowed");
        return;
    }

    if (hm->body.len == 0 || hm->body.len > 4096) {
        http_send_error(c, 400, "invalid request body");
        return;
    }

    char username[128];
    char password[128];
    if (json_get_string(hm->body.buf, hm->body.len, "username",
                        username, sizeof(username)) != 0 ||
        json_get_string(hm->body.buf, hm->body.len, "password",
                        password, sizeof(password)) != 0) {
        http_send_error(c, 400, "missing username or password");
        return;
    }

    char *user_json = db_get_user_by_username(username);
    if (user_json == NULL) {
        http_send_error(c, 401, "invalid credentials");
        return;
    }

    char stored_hash[BCRYPT_HASHSIZE + 1];
    if (json_get_string(user_json, strlen(user_json), "password_hash",
                        stored_hash, sizeof(stored_hash)) != 0) {
        free(user_json);
        http_send_error(c, 500, "internal error");
        return;
    }

    if (!crypt_checkpw(password, stored_hash)) {
        free(user_json);
        memset(password, 0, sizeof(password));
        http_send_error(c, 401, "invalid credentials");
        return;
    }

    memset(password, 0, sizeof(password));

    char user_id[64], role_id[64], display_name[128], role_name[64];
    int authority = 3;
    json_get_string(user_json, strlen(user_json), "id", user_id, sizeof(user_id));
    json_get_string(user_json, strlen(user_json), "role_id", role_id, sizeof(role_id));
    json_get_string(user_json, strlen(user_json), "display_name", display_name, sizeof(display_name));
    json_get_string(user_json, strlen(user_json), "role_name", role_name, sizeof(role_name));
    json_get_int(user_json, strlen(user_json), "authority", &authority);
    free(user_json);

    char token[TOKEN_HEX_LEN + 1];
    if (gen_token(token, sizeof(token)) != 0) {
        http_send_error(c, 500, "failed to generate session");
        return;
    }

    double now = (double)time(NULL);
    double expires = now + SESSION_TTL_SECONDS;

    if (db_create_session(token, user_id, now, expires) != 0) {
        http_send_error(c, 500, "failed to create session");
        return;
    }

    char response[1024];
    snprintf(response, sizeof(response),
             "{\"token\":\"%s\",\"user_id\":\"%s\",\"username\":\"%s\","
             "\"display_name\":\"%s\",\"role_id\":\"%s\","
             "\"role_name\":\"%s\",\"authority\":%d,"
             "\"expires_at\":%.0f}",
             token, user_id, username, display_name,
             role_id, role_name, authority, expires);

    http_send_json(c, 200, response);
}

static void handle_logout(struct mg_connection *c, struct mg_http_message *hm) {
    if (mg_strcmp(hm->method, mg_str("POST")) != 0) {
        http_send_error(c, 405, "method not allowed");
        return;
    }

    char token[TOKEN_HEX_LEN + 1];
    if (extract_bearer_token(hm, token, sizeof(token)) != 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }

    db_delete_session(token);
    http_send_json(c, 200, "{\"ok\":true}");
}

static void handle_me(struct mg_connection *c, struct mg_http_message *hm) {
    if (mg_strcmp(hm->method, mg_str("GET")) != 0) {
        http_send_error(c, 405, "method not allowed");
        return;
    }

    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }

    char *permissions_json = db_get_role_permissions(role_id);
    char *panels_json = db_get_role_view_panels(role_id);

    char *user_json = NULL;
    if (strcmp(user_id, "open-mode") != 0) {
        user_json = db_get_user_by_id(user_id);
    }

    char response[8192];
    snprintf(response, sizeof(response),
             "{\"user_id\":\"%s\",\"role_id\":\"%s\",\"authority\":%d,"
             "\"open_mode\":%s,"
             "\"permissions\":%s,"
             "\"panels\":%s,"
             "\"user\":%s}",
             user_id, role_id, authority,
             db_has_users() ? "false" : "true",
             permissions_json ? permissions_json : "[]",
             panels_json ? panels_json : "[]",
             user_json ? user_json : "null");

    http_send_json(c, 200, response);

    free(permissions_json);
    free(panels_json);
    free(user_json);
}

static void handle_roles(struct mg_connection *c, struct mg_http_message *hm) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
        char *result = db_query_roles();
        if (result != NULL) {
            http_send_json(c, 200, result);
            free(result);
        } else {
            http_send_error(c, 500, "failed to query roles");
        }
    } else if (mg_strcmp(hm->method, mg_str("POST")) == 0) {
        if (authority != 0) {
            http_send_error(c, 403, "admin only");
            return;
        }
        if (hm->body.len == 0 || hm->body.len > 4096) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char id[64], name[128], description[256];
        int auth_level = 3, sort_order = 0;
        gen_id(id, sizeof(id));
        if (json_get_string(hm->body.buf, hm->body.len, "name",
                            name, sizeof(name)) != 0) {
            http_send_error(c, 400, "missing name");
            return;
        }
        json_get_int(hm->body.buf, hm->body.len, "authority", &auth_level);
        json_get_string(hm->body.buf, hm->body.len, "description",
                        description, sizeof(description));
        json_get_int(hm->body.buf, hm->body.len, "sort_order", &sort_order);

        if (auth_level < 0 || auth_level > 3) {
            http_send_error(c, 400, "authority must be 0-3");
            return;
        }

        if (db_create_role(id, name, auth_level, description, sort_order) != 0) {
            http_send_error(c, 500, "failed to create role");
            return;
        }

        char response[256];
        snprintf(response, sizeof(response), "{\"id\":\"%s\"}", id);
        http_send_json(c, 201, response);
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_role_by_id(struct mg_connection *c, struct mg_http_message *hm,
                               const char *rid) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }
    if (authority != 0) {
        http_send_error(c, 403, "admin only");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("PUT")) == 0) {
        if (hm->body.len == 0 || hm->body.len > 4096) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char name[128], description[256];
        int auth_level = 3, sort_order = 0, active = 1;
        json_get_string(hm->body.buf, hm->body.len, "name", name, sizeof(name));
        json_get_int(hm->body.buf, hm->body.len, "authority", &auth_level);
        json_get_string(hm->body.buf, hm->body.len, "description",
                        description, sizeof(description));
        json_get_int(hm->body.buf, hm->body.len, "sort_order", &sort_order);
        json_get_int(hm->body.buf, hm->body.len, "active", &active);

        if (db_update_role(rid, name, auth_level, description,
                           sort_order, active) != 0) {
            http_send_error(c, 500, "failed to update role");
            return;
        }
        http_send_json(c, 200, "{\"ok\":true}");
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_role_permissions(struct mg_connection *c,
                                     struct mg_http_message *hm,
                                     const char *rid) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
        char *result = db_get_role_permissions(rid);
        if (result != NULL) {
            http_send_json(c, 200, result);
            free(result);
        } else {
            http_send_error(c, 500, "failed to query permissions");
        }
    } else if (mg_strcmp(hm->method, mg_str("PUT")) == 0) {
        if (authority != 0) {
            http_send_error(c, 403, "admin only");
            return;
        }
        if (hm->body.len == 0 || hm->body.len > 16384) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char panel[64], perm_id[64];
        int can_view = 1, can_edit = 0;
        json_get_string(hm->body.buf, hm->body.len, "panel", panel, sizeof(panel));
        json_get_int(hm->body.buf, hm->body.len, "can_view", &can_view);
        json_get_int(hm->body.buf, hm->body.len, "can_edit", &can_edit);
        gen_id(perm_id, sizeof(perm_id));

        if (db_set_role_permission(perm_id, rid, panel, can_view, can_edit) != 0) {
            http_send_error(c, 500, "failed to set permission");
            return;
        }
        http_send_json(c, 200, "{\"ok\":true}");
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_role_panels(struct mg_connection *c,
                                struct mg_http_message *hm,
                                const char *rid) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
        char *result = db_get_role_view_panels(rid);
        if (result != NULL) {
            http_send_json(c, 200, result);
            free(result);
        } else {
            http_send_error(c, 500, "failed to query panels");
        }
    } else if (mg_strcmp(hm->method, mg_str("PUT")) == 0) {
        if (authority != 0) {
            http_send_error(c, 403, "admin only");
            return;
        }
        if (hm->body.len == 0 || hm->body.len > 16384) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char panel[64], position[32], config_json[2048], panel_id[64];
        int sort_order = 0;
        json_get_string(hm->body.buf, hm->body.len, "panel", panel, sizeof(panel));
        json_get_string(hm->body.buf, hm->body.len, "position",
                        position, sizeof(position));
        json_get_int(hm->body.buf, hm->body.len, "sort_order", &sort_order);

        const char *cfg = NULL;
        if (json_get_string(hm->body.buf, hm->body.len, "config_json",
                            config_json, sizeof(config_json)) == 0) {
            cfg = config_json;
        }
        gen_id(panel_id, sizeof(panel_id));

        if (db_set_role_view_panel(panel_id, rid, panel, position,
                                    sort_order, cfg) != 0) {
            http_send_error(c, 500, "failed to set panel");
            return;
        }
        http_send_json(c, 200, "{\"ok\":true}");
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_role_sops(struct mg_connection *c,
                              struct mg_http_message *hm,
                              const char *rid) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
        char event_type[64] = {0};
        struct mg_str qs = hm->query;
        struct mg_str val = mg_http_var(qs, mg_str("event_type_id"));
        if (val.len > 0 && val.len < sizeof(event_type)) {
            memcpy(event_type, val.buf, val.len);
            event_type[val.len] = '\0';
        }

        char *result = db_query_sops_for_role(
            rid, event_type[0] ? event_type : NULL);
        if (result != NULL) {
            http_send_json(c, 200, result);
            free(result);
        } else {
            http_send_error(c, 500, "failed to query SOPs");
        }
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_users(struct mg_connection *c, struct mg_http_message *hm) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }
    if (authority != 0) {
        http_send_error(c, 403, "admin only");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
        char *result = db_query_users();
        if (result != NULL) {
            http_send_json(c, 200, result);
            free(result);
        } else {
            http_send_error(c, 500, "failed to query users");
        }
    } else if (mg_strcmp(hm->method, mg_str("POST")) == 0) {
        if (hm->body.len == 0 || hm->body.len > 4096) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char username[128], password[128], display_name[128], new_role_id[64], new_id[64];
        if (json_get_string(hm->body.buf, hm->body.len, "username",
                            username, sizeof(username)) != 0 ||
            json_get_string(hm->body.buf, hm->body.len, "password",
                            password, sizeof(password)) != 0 ||
            json_get_string(hm->body.buf, hm->body.len, "display_name",
                            display_name, sizeof(display_name)) != 0 ||
            json_get_string(hm->body.buf, hm->body.len, "role_id",
                            new_role_id, sizeof(new_role_id)) != 0) {
            http_send_error(c, 400, "missing required fields");
            return;
        }

        char hash[BCRYPT_HASHSIZE];
        if (crypt_hashpw(password, hash, sizeof(hash)) != 0) {
            memset(password, 0, sizeof(password));
            http_send_error(c, 500, "failed to hash password");
            return;
        }
        memset(password, 0, sizeof(password));

        gen_id(new_id, sizeof(new_id));
        double now = (double)time(NULL);

        if (db_create_user(new_id, username, hash, display_name,
                           new_role_id, now) != 0) {
            http_send_error(c, 500, "failed to create user");
            return;
        }

        char response[256];
        snprintf(response, sizeof(response), "{\"id\":\"%s\"}", new_id);
        http_send_json(c, 201, response);
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_user_by_id(struct mg_connection *c, struct mg_http_message *hm,
                               const char *uid) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }
    if (authority != 0) {
        http_send_error(c, 403, "admin only");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("PUT")) == 0) {
        if (hm->body.len == 0 || hm->body.len > 4096) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char display_name[128], new_role_id[64], password[128];
        int active = 1;

        const char *dn_ptr = NULL, *rid_ptr = NULL, *pw_hash_ptr = NULL;

        if (json_get_string(hm->body.buf, hm->body.len, "display_name",
                            display_name, sizeof(display_name)) == 0) {
            dn_ptr = display_name;
        }
        if (json_get_string(hm->body.buf, hm->body.len, "role_id",
                            new_role_id, sizeof(new_role_id)) == 0) {
            rid_ptr = new_role_id;
        }
        json_get_int(hm->body.buf, hm->body.len, "active", &active);

        char hash[BCRYPT_HASHSIZE];
        if (json_get_string(hm->body.buf, hm->body.len, "password",
                            password, sizeof(password)) == 0 && password[0] != '\0') {
            if (crypt_hashpw(password, hash, sizeof(hash)) != 0) {
                memset(password, 0, sizeof(password));
                http_send_error(c, 500, "failed to hash password");
                return;
            }
            pw_hash_ptr = hash;
        }
        memset(password, 0, sizeof(password));

        double now = (double)time(NULL);
        if (db_update_user(uid, dn_ptr, rid_ptr, pw_hash_ptr, active, now) != 0) {
            http_send_error(c, 500, "failed to update user");
            return;
        }
        http_send_json(c, 200, "{\"ok\":true}");
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_sops(struct mg_connection *c, struct mg_http_message *hm) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
        char *result = db_query_sops();
        if (result != NULL) {
            http_send_json(c, 200, result);
            free(result);
        } else {
            http_send_error(c, 500, "failed to query SOPs");
        }
    } else if (mg_strcmp(hm->method, mg_str("POST")) == 0) {
        if (authority != 0) {
            http_send_error(c, 403, "admin only");
            return;
        }
        if (hm->body.len == 0 || hm->body.len > 65536) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char id[64], title[256], content[32768], links_json[4096];
        gen_id(id, sizeof(id));
        if (json_get_string(hm->body.buf, hm->body.len, "title",
                            title, sizeof(title)) != 0 ||
            json_get_string(hm->body.buf, hm->body.len, "content",
                            content, sizeof(content)) != 0) {
            http_send_error(c, 400, "missing title or content");
            return;
        }

        const char *links = NULL;
        if (json_get_string(hm->body.buf, hm->body.len, "links_json",
                            links_json, sizeof(links_json)) == 0) {
            links = links_json;
        }

        double now = (double)time(NULL);
        if (db_create_sop(id, title, content, links, now) != 0) {
            http_send_error(c, 500, "failed to create SOP");
            return;
        }

        char response[256];
        snprintf(response, sizeof(response), "{\"id\":\"%s\"}", id);
        http_send_json(c, 201, response);
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_sop_by_id(struct mg_connection *c, struct mg_http_message *hm,
                              const char *sid) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }
    if (authority != 0) {
        http_send_error(c, 403, "admin only");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("PUT")) == 0) {
        if (hm->body.len == 0 || hm->body.len > 65536) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char title[256], content[32768], links_json[4096];
        int active = 1;
        json_get_string(hm->body.buf, hm->body.len, "title", title, sizeof(title));
        json_get_string(hm->body.buf, hm->body.len, "content", content, sizeof(content));
        json_get_int(hm->body.buf, hm->body.len, "active", &active);

        const char *links = NULL;
        if (json_get_string(hm->body.buf, hm->body.len, "links_json",
                            links_json, sizeof(links_json)) == 0) {
            links = links_json;
        }

        double now = (double)time(NULL);
        if (db_update_sop(sid, title, content, links, active, now) != 0) {
            http_send_error(c, 500, "failed to update SOP");
            return;
        }
        http_send_json(c, 200, "{\"ok\":true}");
    } else if (mg_strcmp(hm->method, mg_str("DELETE")) == 0) {
        if (db_delete_sop(sid) != 0) {
            http_send_error(c, 500, "failed to delete SOP");
            return;
        }
        http_send_json(c, 200, "{\"ok\":true}");
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_sop_mappings(struct mg_connection *c, struct mg_http_message *hm) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
        char *result = db_query_sop_mappings();
        if (result != NULL) {
            http_send_json(c, 200, result);
            free(result);
        } else {
            http_send_error(c, 500, "failed to query SOP mappings");
        }
    } else if (mg_strcmp(hm->method, mg_str("POST")) == 0) {
        if (authority != 0) {
            http_send_error(c, 403, "admin only");
            return;
        }
        if (hm->body.len == 0 || hm->body.len > 4096) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char id[64], sop_id[64], map_role_id[64], event_type_id[64];
        int sort_order = 0;
        gen_id(id, sizeof(id));
        if (json_get_string(hm->body.buf, hm->body.len, "sop_id",
                            sop_id, sizeof(sop_id)) != 0) {
            http_send_error(c, 400, "missing sop_id");
            return;
        }

        const char *r_id = NULL, *et_id = NULL;
        if (json_get_string(hm->body.buf, hm->body.len, "role_id",
                            map_role_id, sizeof(map_role_id)) == 0) {
            r_id = map_role_id;
        }
        if (json_get_string(hm->body.buf, hm->body.len, "event_type_id",
                            event_type_id, sizeof(event_type_id)) == 0) {
            et_id = event_type_id;
        }
        json_get_int(hm->body.buf, hm->body.len, "sort_order", &sort_order);

        if (db_set_sop_mapping(id, sop_id, r_id, et_id, sort_order) != 0) {
            http_send_error(c, 500, "failed to create SOP mapping");
            return;
        }

        char response[256];
        snprintf(response, sizeof(response), "{\"id\":\"%s\"}", id);
        http_send_json(c, 201, response);
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_event_types(struct mg_connection *c, struct mg_http_message *hm) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
        char *result = db_query_event_types();
        if (result != NULL) {
            http_send_json(c, 200, result);
            free(result);
        } else {
            http_send_error(c, 500, "failed to query event types");
        }
    } else if (mg_strcmp(hm->method, mg_str("POST")) == 0) {
        if (authority != 0) {
            http_send_error(c, 403, "admin only");
            return;
        }
        if (hm->body.len == 0 || hm->body.len > 4096) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char id[64], name[128], icon[64], color[16];
        int sort_order = 0;
        gen_id(id, sizeof(id));
        if (json_get_string(hm->body.buf, hm->body.len, "name",
                            name, sizeof(name)) != 0) {
            http_send_error(c, 400, "missing name");
            return;
        }

        const char *icon_ptr = NULL, *color_ptr = NULL;
        if (json_get_string(hm->body.buf, hm->body.len, "icon",
                            icon, sizeof(icon)) == 0) {
            icon_ptr = icon;
        }
        if (json_get_string(hm->body.buf, hm->body.len, "color",
                            color, sizeof(color)) == 0) {
            color_ptr = color;
        }
        json_get_int(hm->body.buf, hm->body.len, "sort_order", &sort_order);

        if (db_create_event_type(id, name, icon_ptr, color_ptr, sort_order) != 0) {
            http_send_error(c, 500, "failed to create event type");
            return;
        }

        char response[256];
        snprintf(response, sizeof(response), "{\"id\":\"%s\"}", id);
        http_send_json(c, 201, response);
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_event_type_by_id(struct mg_connection *c,
                                     struct mg_http_message *hm,
                                     const char *etid) {
    char user_id[64], role_id[64];
    int authority = auth_check(hm, user_id, sizeof(user_id),
                               role_id, sizeof(role_id));
    if (authority < 0) {
        http_send_error(c, 401, "not authenticated");
        return;
    }
    if (authority != 0) {
        http_send_error(c, 403, "admin only");
        return;
    }

    if (mg_strcmp(hm->method, mg_str("PUT")) == 0) {
        if (hm->body.len == 0 || hm->body.len > 4096) {
            http_send_error(c, 400, "invalid request body");
            return;
        }

        char name[128], icon[64], color[16];
        int sort_order = 0, active = 1;
        json_get_string(hm->body.buf, hm->body.len, "name", name, sizeof(name));
        json_get_int(hm->body.buf, hm->body.len, "sort_order", &sort_order);
        json_get_int(hm->body.buf, hm->body.len, "active", &active);

        const char *icon_ptr = NULL, *color_ptr = NULL;
        if (json_get_string(hm->body.buf, hm->body.len, "icon",
                            icon, sizeof(icon)) == 0) {
            icon_ptr = icon;
        }
        if (json_get_string(hm->body.buf, hm->body.len, "color",
                            color, sizeof(color)) == 0) {
            color_ptr = color;
        }

        if (db_update_event_type(etid, name, icon_ptr, color_ptr,
                                  sort_order, active) != 0) {
            http_send_error(c, 500, "failed to update event type");
            return;
        }
        http_send_json(c, 200, "{\"ok\":true}");
    } else {
        http_send_error(c, 405, "method not allowed");
    }
}

static void handle_api(struct mg_connection *c, struct mg_http_message *hm) {
    if (mg_strcmp(hm->method, mg_str("OPTIONS")) == 0) {
        http_send_json(c, 204, "");
        return;
    }

    if (mg_match(hm->uri, mg_str("/api/login"), NULL)) {
        handle_login(c, hm);
        return;
    }
    if (mg_match(hm->uri, mg_str("/api/logout"), NULL)) {
        handle_logout(c, hm);
        return;
    }

    if (mg_match(hm->uri, mg_str("/api/me"), NULL)) {
        handle_me(c, hm);
        return;
    }

    if (mg_match(hm->uri, mg_str("/api/incidents"), NULL)) {
        char user_id[64], role_id[64];
        int authority = auth_check(hm, user_id, sizeof(user_id),
                                   role_id, sizeof(role_id));
        if (authority < 0) {
            http_send_error(c, 401, "not authenticated");
            return;
        }

        if (mg_strcmp(hm->method, mg_str("GET")) == 0) {
            const char *result = bridge_get_incidents();
            if (result != NULL) {
                http_send_json(c, 200, result);
            } else {
                http_send_error(c, 500, "failed to query incidents");
            }
        } else if (mg_strcmp(hm->method, mg_str("POST")) == 0) {
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
        return;
    }

    if (mg_match(hm->uri, mg_str("/api/units"), NULL)) {
        char user_id[64], role_id[64];
        int authority = auth_check(hm, user_id, sizeof(user_id),
                                   role_id, sizeof(role_id));
        if (authority < 0) {
            http_send_error(c, 401, "not authenticated");
            return;
        }

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
        return;
    }

    if (mg_match(hm->uri, mg_str("/api/events"), NULL)) {
        char user_id[64], role_id[64];
        int authority = auth_check(hm, user_id, sizeof(user_id),
                                   role_id, sizeof(role_id));
        if (authority < 0) {
            http_send_error(c, 401, "not authenticated");
            return;
        }

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
        return;
    }

    if (mg_match(hm->uri, mg_str("/api/roles"), NULL)) {
        handle_roles(c, hm);
        return;
    }

    {
        struct mg_str caps[2];
        if (mg_match(hm->uri, mg_str("/api/roles/*/permissions"), caps)) {
            char rid[64];
            if (caps[0].len > 0 && caps[0].len < sizeof(rid)) {
                memcpy(rid, caps[0].buf, caps[0].len);
                rid[caps[0].len] = '\0';
                handle_role_permissions(c, hm, rid);
                return;
            }
        }
    }

    {
        struct mg_str caps[2];
        if (mg_match(hm->uri, mg_str("/api/roles/*/panels"), caps)) {
            char rid[64];
            if (caps[0].len > 0 && caps[0].len < sizeof(rid)) {
                memcpy(rid, caps[0].buf, caps[0].len);
                rid[caps[0].len] = '\0';
                handle_role_panels(c, hm, rid);
                return;
            }
        }
    }

    {
        struct mg_str caps[2];
        if (mg_match(hm->uri, mg_str("/api/roles/*/sops"), caps)) {
            char rid[64];
            if (caps[0].len > 0 && caps[0].len < sizeof(rid)) {
                memcpy(rid, caps[0].buf, caps[0].len);
                rid[caps[0].len] = '\0';
                handle_role_sops(c, hm, rid);
                return;
            }
        }
    }

    {
        struct mg_str caps[2];
        if (mg_match(hm->uri, mg_str("/api/roles/*"), caps)) {
            char rid[64];
            if (caps[0].len > 0 && caps[0].len < sizeof(rid)) {
                memcpy(rid, caps[0].buf, caps[0].len);
                rid[caps[0].len] = '\0';
                handle_role_by_id(c, hm, rid);
                return;
            }
        }
    }

    if (mg_match(hm->uri, mg_str("/api/users"), NULL)) {
        handle_users(c, hm);
        return;
    }

    {
        struct mg_str caps[2];
        if (mg_match(hm->uri, mg_str("/api/users/*"), caps)) {
            char uid[64];
            if (caps[0].len > 0 && caps[0].len < sizeof(uid)) {
                memcpy(uid, caps[0].buf, caps[0].len);
                uid[caps[0].len] = '\0';
                handle_user_by_id(c, hm, uid);
                return;
            }
        }
    }

    if (mg_match(hm->uri, mg_str("/api/sops"), NULL)) {
        handle_sops(c, hm);
        return;
    }

    {
        struct mg_str caps[2];
        if (mg_match(hm->uri, mg_str("/api/sops/*"), caps)) {
            char sid[64];
            if (caps[0].len > 0 && caps[0].len < sizeof(sid)) {
                memcpy(sid, caps[0].buf, caps[0].len);
                sid[caps[0].len] = '\0';
                handle_sop_by_id(c, hm, sid);
                return;
            }
        }
    }

    if (mg_match(hm->uri, mg_str("/api/sop-mappings"), NULL)) {
        handle_sop_mappings(c, hm);
        return;
    }

    if (mg_match(hm->uri, mg_str("/api/event-types"), NULL)) {
        handle_event_types(c, hm);
        return;
    }

    {
        struct mg_str caps[2];
        if (mg_match(hm->uri, mg_str("/api/event-types/*"), caps)) {
            char etid[64];
            if (caps[0].len > 0 && caps[0].len < sizeof(etid)) {
                memcpy(etid, caps[0].buf, caps[0].len);
                etid[caps[0].len] = '\0';
                handle_event_type_by_id(c, hm, etid);
                return;
            }
        }
    }

    http_send_error(c, 404, "not found");
}

void http_serve_static(struct mg_connection *c, struct mg_http_message *hm) {
    struct mg_http_serve_opts opts = {
        .root_dir = s_doc_root,
        .ssi_pattern = NULL,
    };
    mg_http_serve_dir(c, hm, &opts);
}

void http_handle_request(struct mg_connection *c, struct mg_http_message *hm) {
    if (mg_match(hm->uri, mg_str("/api/*"), NULL) ||
        mg_match(hm->uri, mg_str("/api/login"), NULL)) {
        handle_api(c, hm);
    } else {
        http_serve_static(c, hm);
    }
}
