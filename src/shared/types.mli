(** Core domain types for the Callout CAD system.

    All types are algebraic — no nulls, no invalid states.
    Exhaustive matching is enforced by the compiler. *)

type incident_id = string
type unit_id = string
type user_id = string

type severity = P1 | P2 | P3 | P4 | P5

type incident_status =
  | Reported
  | Dispatched
  | En_route
  | On_scene
  | Under_control
  | Resolved
  | Cancelled

type unit_status =
  | Available
  | U_dispatched of incident_id
  | U_en_route of incident_id
  | U_on_scene of incident_id
  | Returning
  | Out_of_service

type position = {
  lat : float;
  lng : float;
  accuracy : float option;
  timestamp : float;
}

type authority =
  | Dispatcher
  | Incident_commander
  | Crew_leader
  | Field_unit

type event_payload =
  | Incident_created of {
      position : position;
      severity : severity;
      description : string;
    }
  | Incident_status_changed of {
      incident_id : incident_id;
      new_status : incident_status;
    }
  | Unit_dispatched of {
      unit_id : unit_id;
      incident_id : incident_id;
    }
  | Unit_status_changed of {
      unit_id : unit_id;
      new_status : unit_status;
    }
  | Unit_position_updated of {
      unit_id : unit_id;
      position : position;
    }
  | Note_added of {
      incident_id : incident_id;
      text : string;
    }

type event = {
  id : string;
  timestamp : float;
  author : user_id;
  authority : authority;
  payload : event_payload;
}

type incident = {
  id : incident_id;
  status : incident_status;
  severity : severity;
  position : position;
  description : string;
  created_at : float;
  updated_at : float;
}

type unit_ = {
  id : unit_id;
  name : string;
  status : unit_status;
  position : position option;
  updated_at : float;
}

val severity_to_int : severity -> int
val int_to_severity : int -> severity option
val severity_to_string : severity -> string

val incident_status_to_string : incident_status -> string
val string_to_incident_status : string -> incident_status option

val unit_status_to_string : unit_status -> string

val authority_to_int : authority -> int
val int_to_authority : int -> authority option
val authority_to_string : authority -> string

val authority_outranks : authority -> authority -> bool
