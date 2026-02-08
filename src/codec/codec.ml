open Shared.Types

let json_of_string s =
  try Some (Yojson.Basic.from_string s)
  with Yojson.Json_error _ -> None

let member_string j key =
  match Yojson.Basic.Util.member key j with
  | `String s -> Some s
  | _ -> None

let member_float j key =
  match Yojson.Basic.Util.member key j with
  | `Float f -> Some f
  | `Int i -> Some (Float.of_int i)
  | _ -> None

let decode_position j =
  match member_float j "lat", member_float j "lng" with
  | Some lat, Some lng ->
    let accuracy = member_float j "accuracy" in
    let timestamp = match member_float j "timestamp" with
      | Some t -> t | None -> 0.0
    in
    Some { lat; lng; accuracy; timestamp }
  | _ -> None

let decode_severity s =
  string_to_severity s

let decode_authority s =
  string_to_authority s

let decode_incident_status s =
  string_to_incident_status s

let decode_unit_status j =
  match j with
  | `String "available" -> Some Available
  | `String "returning" -> Some Returning
  | `String "out_of_service" -> Some Out_of_service
  | `Assoc _ ->
    let status = member_string j "status" in
    let iid = member_string j "incident_id" in
    (match status, iid with
     | Some "dispatched", Some id -> Some (U_dispatched id)
     | Some "en_route", Some id -> Some (U_en_route id)
     | Some "on_scene", Some id -> Some (U_on_scene id)
     | _ -> None)
  | _ -> None

let decode_command j =
  match member_string j "type" with
  | Some "create_incident" ->
    let pos_j = Yojson.Basic.Util.member "position" j in
    let sev_s = member_string j "severity" in
    let desc = member_string j "description" in
    (match decode_position pos_j, Option.bind sev_s decode_severity, desc with
     | Some position, Some severity, Some description ->
       Some (Engine.Cmd_create_incident { position; severity; description })
     | _ -> None)
  | Some "change_incident_status" ->
    (match member_string j "incident_id",
           Option.bind (member_string j "new_status") decode_incident_status with
     | Some incident_id, Some new_status ->
       Some (Engine.Cmd_change_incident_status { incident_id; new_status })
     | _ -> None)
  | Some "dispatch_unit" ->
    (match member_string j "unit_id", member_string j "incident_id" with
     | Some unit_id, Some incident_id ->
       Some (Engine.Cmd_dispatch_unit { unit_id; incident_id })
     | _ -> None)
  | Some "release_unit" ->
    (match member_string j "unit_id" with
     | Some unit_id -> Some (Engine.Cmd_release_unit { unit_id })
     | _ -> None)
  | Some "update_unit_position" ->
    let pos_j = Yojson.Basic.Util.member "position" j in
    (match member_string j "unit_id", decode_position pos_j with
     | Some unit_id, Some position ->
       Some (Engine.Cmd_update_unit_position { unit_id; position })
     | _ -> None)
  | Some "change_unit_status" ->
    let status_j = Yojson.Basic.Util.member "new_status" j in
    (match member_string j "unit_id", decode_unit_status status_j with
     | Some unit_id, Some new_status ->
       Some (Engine.Cmd_change_unit_status { unit_id; new_status })
     | _ -> None)
  | Some "add_note" ->
    (match member_string j "incident_id", member_string j "text" with
     | Some incident_id, Some text ->
       Some (Engine.Cmd_add_note { incident_id; text })
     | _ -> None)
  | Some "register_unit" ->
    (match member_string j "id", member_string j "name" with
     | Some id, Some name ->
       Some (Engine.Cmd_register_unit { id; name })
     | _ -> None)
  | _ -> None

let decode_command_envelope json_str =
  match json_of_string json_str with
  | None -> None
  | Some j ->
    let cmd_j = Yojson.Basic.Util.member "command" j in
    let cmd_opt = match cmd_j with
      | `Null -> decode_command j  (* flat format: command fields at top level *)
      | _ -> decode_command cmd_j  (* nested format: { command: { ... } } *)
    in
    match cmd_opt with
    | None -> None
    | Some command ->
      let author = match member_string j "author" with
        | Some a -> a | None -> "anonymous"
      in
      let authority = match Option.bind (member_string j "authority") decode_authority with
        | Some a -> a | None -> Dispatcher
      in
      let timestamp = match member_float j "timestamp" with
        | Some t -> t | None -> Unix.gettimeofday ()
      in
      Some { Engine.command; author; authority; timestamp }

let decode_event_payload j =
  match member_string j "type" with
  | Some "incident_created" ->
    let pos_j = Yojson.Basic.Util.member "position" j in
    (match decode_position pos_j,
           Option.bind (member_string j "severity") decode_severity,
           member_string j "description" with
     | Some position, Some severity, Some description ->
       Some (Incident_created { position; severity; description })
     | _ -> None)
  | Some "incident_status_changed" ->
    (match member_string j "incident_id",
           Option.bind (member_string j "new_status") decode_incident_status with
     | Some incident_id, Some new_status ->
       Some (Incident_status_changed { incident_id; new_status })
     | _ -> None)
  | Some "unit_dispatched" ->
    (match member_string j "unit_id", member_string j "incident_id" with
     | Some unit_id, Some incident_id ->
       Some (Unit_dispatched { unit_id; incident_id })
     | _ -> None)
  | Some "unit_status_changed" ->
    let status_j = Yojson.Basic.Util.member "new_status" j in
    (match member_string j "unit_id", decode_unit_status status_j with
     | Some unit_id, Some new_status ->
       Some (Unit_status_changed { unit_id; new_status })
     | _ -> None)
  | Some "unit_position_updated" ->
    let pos_j = Yojson.Basic.Util.member "position" j in
    (match member_string j "unit_id", decode_position pos_j with
     | Some unit_id, Some position ->
       Some (Unit_position_updated { unit_id; position })
     | _ -> None)
  | Some "note_added" ->
    (match member_string j "incident_id", member_string j "text" with
     | Some incident_id, Some text ->
       Some (Note_added { incident_id; text })
     | _ -> None)
  | _ -> None

let decode_event j =
  match member_string j "id",
        member_float j "timestamp",
        member_string j "author",
        Option.bind (member_string j "authority") decode_authority with
  | Some id, Some timestamp, Some author, Some authority ->
    let payload_j = Yojson.Basic.Util.member "payload" j in
    let payload_opt = match payload_j with
      | `Null -> decode_event_payload j  (* flat: payload fields inline *)
      | _ -> decode_event_payload payload_j
    in
    (match payload_opt with
     | Some payload -> Some { id; timestamp; author; authority; payload }
     | None -> None)
  | _ -> None

let decode_client_msg json_str =
  match json_of_string json_str with
  | None -> None
  | Some j ->
    match member_string j "type" with
    | Some "push_events" ->
      let events_j = Yojson.Basic.Util.member "events" j in
      (match events_j with
       | `List evs ->
         let events = List.filter_map decode_event evs in
         Some (Shared.Protocol.Push_events events)
       | _ -> None)
    | Some "request_sync" ->
      (match member_float j "since" with
       | Some since -> Some (Shared.Protocol.Request_sync { since })
       | None -> None)
    | Some "ping" -> Some Shared.Protocol.Ping
    | _ -> None

let encode_apply_result (r : Engine.apply_result) =
  match r.error with
  | Some msg ->
    Printf.sprintf "{\"ok\":false,\"error\":\"%s\"}" msg
  | None ->
    let events_json = Shared.Protocol.encode_events r.new_events in
    Printf.sprintf "{\"ok\":true,\"events\":%s}" events_json

let encode_error msg =
  Printf.sprintf "{\"ok\":false,\"error\":\"%s\"}" msg
