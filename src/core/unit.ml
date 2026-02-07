open Shared.Types

type unit_error = string

let create ~id ~name ~now =
  {
    id;
    name;
    status = Available;
    position = None;
    updated_at = now;
  }

let update_position unit_ position =
  { unit_ with position = Some position; updated_at = position.timestamp }

let set_status unit_ new_status now =
  let valid =
    match unit_.status, new_status with
    (* From Available *)
    | Available, U_dispatched _ -> true
    | Available, Out_of_service -> true
    (* From U_dispatched *)
    | U_dispatched _, U_en_route _ -> true
    | U_dispatched _, Available -> true  (* dispatch cancelled *)
    (* From U_en_route *)
    | U_en_route _, U_on_scene _ -> true
    | U_en_route _, Returning -> true  (* recalled *)
    (* From U_on_scene *)
    | U_on_scene _, Returning -> true
    (* From Returning *)
    | Returning, Available -> true
    (* From Out_of_service *)
    | Out_of_service, Available -> true
    (* Everything else *)
    | _ -> false
  in
  if valid then
    Ok { unit_ with status = new_status; updated_at = now }
  else
    Error
      (Printf.sprintf "invalid unit transition: %s -> %s"
         (unit_status_to_string unit_.status)
         (unit_status_to_string new_status))

let mark_available unit_ now =
  match unit_.status with
  | Returning | Out_of_service ->
    Ok { unit_ with status = Available; updated_at = now }
  | Available ->
    Error "unit is already available"
  | U_dispatched _ | U_en_route _ | U_on_scene _ ->
    Error "unit must return before becoming available"

let mark_out_of_service unit_ now =
  match unit_.status with
  | Available ->
    Ok { unit_ with status = Out_of_service; updated_at = now }
  | Out_of_service ->
    Error "unit is already out of service"
  | U_dispatched _ | U_en_route _ | U_on_scene _ | Returning ->
    Error "unit must be available before going out of service"

let apply_event unit_ event =
  match event.payload with
  | Unit_dispatched { unit_id; incident_id } ->
    if unit_id = unit_.id then
      set_status unit_ (U_dispatched incident_id) event.timestamp
    else
      Ok unit_
  | Unit_status_changed { unit_id; new_status } ->
    if unit_id = unit_.id then
      set_status unit_ new_status event.timestamp
    else
      Ok unit_
  | Unit_position_updated { unit_id; position } ->
    if unit_id = unit_.id then
      Ok (update_position unit_ position)
    else
      Ok unit_
  | Incident_created _ | Incident_status_changed _ | Note_added _ ->
    Ok unit_
