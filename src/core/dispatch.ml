open Shared.Types

type dispatch_error = string

let can_dispatch (unit_ : unit_) =
  match unit_.status with
  | Available -> true
  | Returning -> true
  | U_dispatched _ | U_en_route _ | U_on_scene _ | Out_of_service -> false

let assign_unit ~unit_ ~(incident : incident) ~author_authority ~now =
  if authority_to_int author_authority > authority_to_int Crew_leader then
    Error "insufficient authority to dispatch units"
  else if not (can_dispatch unit_) then
    Error
      (Printf.sprintf "unit %s is %s, cannot dispatch"
         unit_.id (unit_status_to_string unit_.status))
  else
    match incident.status with
    | Resolved | Cancelled ->
      Error
        (Printf.sprintf "incident %s is %s, cannot dispatch to it"
           incident.id (incident_status_to_string incident.status))
    | Reported | Dispatched | En_route | On_scene | Under_control ->
      let new_unit = { unit_ with
        status = U_dispatched incident.id;
        updated_at = now;
      } in
      let payload = Unit_dispatched {
        unit_id = unit_.id;
        incident_id = incident.id;
      } in
      Ok (new_unit, payload)

let release_unit ~(unit_ : unit_) ~author_authority ~now =
  match unit_.status with
  | Available ->
    Error "unit is already available"
  | Out_of_service ->
    Error "cannot release out-of-service unit; change status first"
  | U_dispatched _ | U_en_route _ | U_on_scene _ | Returning ->
    if authority_to_int author_authority > authority_to_int Crew_leader then
      Error "insufficient authority to release units"
    else
      let new_unit = { unit_ with
        status = Returning;
        updated_at = now;
      } in
      let payload = Unit_status_changed {
        unit_id = unit_.id;
        new_status = Returning;
      } in
      Ok (new_unit, payload)
