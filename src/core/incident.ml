open Shared.Types

type transition_error = string

(* Explicit enumeration of every valid state transition.
   No wildcards — if a new status is added, the compiler forces
   us to decide what transitions are valid from it. *)
let valid_transitions = function
  | Reported -> [ Dispatched; Cancelled ]
  | Dispatched -> [ En_route; Cancelled ]
  | En_route -> [ On_scene; Cancelled ]
  | On_scene -> [ Under_control; Cancelled ]
  | Under_control -> [ Resolved; On_scene ]  (* can escalate back *)
  | Resolved -> []  (* terminal *)
  | Cancelled -> [] (* terminal *)

let transition (incident : incident) new_status now =
  let allowed = valid_transitions incident.status in
  if List.mem new_status allowed then
    Ok { incident with status = new_status; updated_at = now }
  else
    Error
      (Printf.sprintf "invalid transition: %s -> %s"
         (incident_status_to_string incident.status)
         (incident_status_to_string new_status))

let create ~id ~position ~severity ~description ~now =
  {
    id;
    status = Reported;
    severity;
    position;
    description;
    created_at = now;
    updated_at = now;
  }

let apply_event (incident : incident) event =
  match event.payload with
  | Incident_status_changed { incident_id; new_status } ->
    if incident_id = incident.id then
      transition incident new_status event.timestamp
    else
      Error "event incident_id does not match"
  | Incident_created _ ->
    Error "cannot apply Incident_created to existing incident"
  | Unit_dispatched { incident_id; _ } ->
    if incident_id = incident.id then
      match incident.status with
      | Reported -> transition incident Dispatched event.timestamp
      | _ -> Ok incident  (* unit dispatch to already-dispatched incident is fine *)
    else
      Error "event incident_id does not match"
  | Unit_status_changed _ | Unit_position_updated _ | Note_added _ ->
    Ok incident
