#ifndef CALLOUT_DB_H
#define CALLOUT_DB_H

#include "sqlite3.h"

int db_open(const char *path);
void db_close(void);
sqlite3 *db_handle(void);

int db_insert_event(const char *id, double timestamp, const char *author,
                    int authority, const char *payload_json, int synced);
char *db_query_events_since(double since);
char *db_query_incidents(void);
char *db_query_units(void);
int db_upsert_incident(const char *id, const char *status, int severity,
                       double lat, double lng, const char *description,
                       double created_at, double updated_at);
int db_upsert_unit(const char *id, const char *name, const char *status,
                   const char *incident_id, double lat, double lng,
                   double updated_at);
int db_mark_events_synced(const char **event_ids, int count);

int db_has_users(void);
int db_create_user(const char *id, const char *username,
                   const char *password_hash, const char *display_name,
                   const char *role_id, double now);
char *db_get_user_by_username(const char *username);
char *db_get_user_by_id(const char *user_id);
char *db_query_users(void);
int db_update_user(const char *id, const char *display_name,
                   const char *role_id, const char *password_hash,
                   int active, double now);

int db_create_role(const char *id, const char *name, int authority,
                   const char *description, int sort_order);
char *db_query_roles(void);
int db_update_role(const char *id, const char *name, int authority,
                   const char *description, int sort_order, int active);

int db_set_role_permission(const char *id, const char *role_id,
                           const char *panel, int can_view, int can_edit);
char *db_get_role_permissions(const char *role_id);

int db_set_role_view_panel(const char *id, const char *role_id,
                           const char *panel, const char *position,
                           int sort_order, const char *config_json);
char *db_get_role_view_panels(const char *role_id);

int db_create_sop(const char *id, const char *title, const char *content,
                  const char *links_json, double now);
char *db_query_sops(void);
int db_update_sop(const char *id, const char *title, const char *content,
                  const char *links_json, int active, double now);
int db_delete_sop(const char *id);

int db_set_sop_mapping(const char *id, const char *sop_id,
                       const char *role_id, const char *event_type_id,
                       int sort_order);
char *db_query_sop_mappings(void);
char *db_query_sops_for_role(const char *role_id, const char *event_type_id);

int db_create_event_type(const char *id, const char *name, const char *icon,
                         const char *color, int sort_order);
char *db_query_event_types(void);
int db_update_event_type(const char *id, const char *name, const char *icon,
                         const char *color, int sort_order, int active);

int db_create_session(const char *token, const char *user_id,
                      double created_at, double expires_at);
char *db_get_session(const char *token);
int db_delete_session(const char *token);
int db_cleanup_sessions(double now);

#endif
