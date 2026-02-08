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

let severity_to_int = function
  | P1 -> 1
  | P2 -> 2
  | P3 -> 3
  | P4 -> 4
  | P5 -> 5

let int_to_severity = function
  | 1 -> Some P1
  | 2 -> Some P2
  | 3 -> Some P3
  | 4 -> Some P4
  | 5 -> Some P5
  | _ -> None

let severity_to_string = function
  | P1 -> "P1"
  | P2 -> "P2"
  | P3 -> "P3"
  | P4 -> "P4"
  | P5 -> "P5"

let incident_status_to_string = function
  | Reported -> "reported"
  | Dispatched -> "dispatched"
  | En_route -> "en_route"
  | On_scene -> "on_scene"
  | Under_control -> "under_control"
  | Resolved -> "resolved"
  | Cancelled -> "cancelled"

let string_to_incident_status = function
  | "reported" -> Some Reported
  | "dispatched" -> Some Dispatched
  | "en_route" -> Some En_route
  | "on_scene" -> Some On_scene
  | "under_control" -> Some Under_control
  | "resolved" -> Some Resolved
  | "cancelled" -> Some Cancelled
  | _ -> None

let unit_status_to_string = function
  | Available -> "available"
  | U_dispatched _ -> "dispatched"
  | U_en_route _ -> "en_route"
  | U_on_scene _ -> "on_scene"
  | Returning -> "returning"
  | Out_of_service -> "out_of_service"

let authority_to_int = function
  | Dispatcher -> 0
  | Incident_commander -> 1
  | Crew_leader -> 2
  | Field_unit -> 3

let int_to_authority = function
  | 0 -> Some Dispatcher
  | 1 -> Some Incident_commander
  | 2 -> Some Crew_leader
  | 3 -> Some Field_unit
  | _ -> None

let authority_to_string = function
  | Dispatcher -> "dispatcher"
  | Incident_commander -> "incident_commander"
  | Crew_leader -> "crew_leader"
  | Field_unit -> "field_unit"

let string_to_authority = function
  | "dispatcher" -> Some Dispatcher
  | "incident_commander" -> Some Incident_commander
  | "crew_leader" -> Some Crew_leader
  | "field_unit" -> Some Field_unit
  | _ -> None

let string_to_severity = function
  | "P1" -> Some P1
  | "P2" -> Some P2
  | "P3" -> Some P3
  | "P4" -> Some P4
  | "P5" -> Some P5
  | _ -> None

let authority_outranks a b =
  authority_to_int a < authority_to_int b
