(** Event log — append-only, immutable record of all system changes.

    Nothing is ever deleted from the event log. Events are the
    source of truth; materialized views (incidents, units tables)
    are derived from the log. *)

val create_event :
  author:Shared.Types.user_id ->
  authority:Shared.Types.authority ->
  payload:Shared.Types.event_payload ->
  now:float ->
  Shared.Types.event

val generate_id : unit -> string

val events_since :
  Shared.Types.event list ->
  float ->
  Shared.Types.event list

val events_for_incident :
  Shared.Types.event list ->
  Shared.Types.incident_id ->
  Shared.Types.event list
