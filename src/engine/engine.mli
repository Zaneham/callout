(** Callout headless dispatch engine.

    Pure function: state + command -> state + events.
    Zero I/O, deterministic replay, structural sharing via Map. *)

module IdMap : Map.S with type key = string

(** Deterministic RNG state (xorshift64). Carried in engine state
    so replay always produces identical IDs. *)
type rng_state = { mutable seed : int64 }

type stats = {
  commands_processed : int;
  events_applied : int;
  incidents_created : int;
  units_created : int;
  dispatch_count : int;
  errors : int;
}

type state = {
  incidents : Shared.Types.incident IdMap.t;
  units : Shared.Types.unit_ IdMap.t;
  events : Shared.Types.event list;
  event_count : int;
  rng : rng_state;
  stats : stats;
}

type command =
  | Cmd_create_incident of {
      position : Shared.Types.position;
      severity : Shared.Types.severity;
      description : string;
    }
  | Cmd_change_incident_status of {
      incident_id : Shared.Types.incident_id;
      new_status : Shared.Types.incident_status;
    }
  | Cmd_dispatch_unit of {
      unit_id : Shared.Types.unit_id;
      incident_id : Shared.Types.incident_id;
    }
  | Cmd_release_unit of { unit_id : Shared.Types.unit_id }
  | Cmd_update_unit_position of {
      unit_id : Shared.Types.unit_id;
      position : Shared.Types.position;
    }
  | Cmd_change_unit_status of {
      unit_id : Shared.Types.unit_id;
      new_status : Shared.Types.unit_status;
    }
  | Cmd_add_note of {
      incident_id : Shared.Types.incident_id;
      text : string;
    }
  | Cmd_register_unit of {
      id : Shared.Types.unit_id;
      name : string;
    }

type command_envelope = {
  command : command;
  author : Shared.Types.user_id;
  authority : Shared.Types.authority;
  timestamp : float;
}

type apply_result = {
  state : state;
  new_events : Shared.Types.event list;
  error : string option;
}

val rng_next : rng_state -> int64
val rng_next_id : rng_state -> string

val init : seed:int64 -> state
val apply_command : state -> command_envelope -> apply_result
val apply_event : state -> Shared.Types.event -> state
val replay : seed:int64 -> Shared.Types.event list -> state

val get_incident : state -> Shared.Types.incident_id -> Shared.Types.incident option
val get_unit : state -> Shared.Types.unit_id -> Shared.Types.unit_ option
val get_all_incidents : state -> Shared.Types.incident list
val get_all_units : state -> Shared.Types.unit_ list
val get_events : state -> Shared.Types.event list
val get_stats : state -> stats
