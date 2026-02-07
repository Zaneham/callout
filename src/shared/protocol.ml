type client_msg =
  | Push_events of Types.event list
  | Request_sync of { since : float }
  | Ping

type server_msg =
  | Events of Types.event list
  | Sync_complete of { server_time : float }
  | Error of { code : int; message : string }
  | Pong

(* JSON encoding/decoding using a minimal approach.
   We build JSON strings directly to avoid external dependencies.
   In production, consider yojson or jsonm. *)

let encode_position (p : Types.position) =
  let acc_str = match p.accuracy with
    | Some a -> Printf.sprintf ",\"accuracy\":%f" a
    | None -> ""
  in
  Printf.sprintf "{\"lat\":%f,\"lng\":%f%s,\"timestamp\":%f}"
    p.lat p.lng acc_str p.timestamp

let encode_severity (s : Types.severity) =
  Printf.sprintf "\"%s\"" (Types.severity_to_string s)

let encode_incident_status (s : Types.incident_status) =
  Printf.sprintf "\"%s\"" (Types.incident_status_to_string s)

let encode_unit_status (s : Types.unit_status) =
  let base = Types.unit_status_to_string s in
  match s with
  | Types.U_dispatched id | Types.U_en_route id | Types.U_on_scene id ->
    Printf.sprintf "{\"status\":\"%s\",\"incident_id\":\"%s\"}" base id
  | _ -> Printf.sprintf "\"%s\"" base

let encode_authority (a : Types.authority) =
  Printf.sprintf "\"%s\"" (Types.authority_to_string a)

let encode_event_payload = function
  | Types.Incident_created { position; severity; description } ->
    Printf.sprintf
      "{\"type\":\"incident_created\",\"position\":%s,\"severity\":%s,\"description\":\"%s\"}"
      (encode_position position) (encode_severity severity) description
  | Types.Incident_status_changed { incident_id; new_status } ->
    Printf.sprintf
      "{\"type\":\"incident_status_changed\",\"incident_id\":\"%s\",\"new_status\":%s}"
      incident_id (encode_incident_status new_status)
  | Types.Unit_dispatched { unit_id; incident_id } ->
    Printf.sprintf
      "{\"type\":\"unit_dispatched\",\"unit_id\":\"%s\",\"incident_id\":\"%s\"}"
      unit_id incident_id
  | Types.Unit_status_changed { unit_id; new_status } ->
    Printf.sprintf
      "{\"type\":\"unit_status_changed\",\"unit_id\":\"%s\",\"new_status\":%s}"
      unit_id (encode_unit_status new_status)
  | Types.Unit_position_updated { unit_id; position } ->
    Printf.sprintf
      "{\"type\":\"unit_position_updated\",\"unit_id\":\"%s\",\"position\":%s}"
      unit_id (encode_position position)
  | Types.Note_added { incident_id; text } ->
    Printf.sprintf
      "{\"type\":\"note_added\",\"incident_id\":\"%s\",\"text\":\"%s\"}"
      incident_id text

let encode_event (e : Types.event) =
  Printf.sprintf
    "{\"id\":\"%s\",\"timestamp\":%f,\"author\":\"%s\",\"authority\":%s,\"payload\":%s}"
    e.id e.timestamp e.author
    (encode_authority e.authority)
    (encode_event_payload e.payload)

let encode_events events =
  let encoded = List.map encode_event events in
  "[" ^ String.concat "," encoded ^ "]"

let encode_client_msg = function
  | Push_events events ->
    Printf.sprintf "{\"type\":\"push_events\",\"events\":%s}"
      (encode_events events)
  | Request_sync { since } ->
    Printf.sprintf "{\"type\":\"request_sync\",\"since\":%f}" since
  | Ping -> "{\"type\":\"ping\"}"

let encode_server_msg = function
  | Events events ->
    Printf.sprintf "{\"type\":\"events\",\"events\":%s}"
      (encode_events events)
  | Sync_complete { server_time } ->
    Printf.sprintf "{\"type\":\"sync_complete\",\"server_time\":%f}" server_time
  | Error { code; message } ->
    Printf.sprintf "{\"type\":\"error\",\"code\":%d,\"message\":\"%s\"}"
      code message
  | Pong -> "{\"type\":\"pong\"}"

(* Decoding stubs — full JSON parsing requires yojson or similar.
   These will be implemented when the dependency is added. *)
let decode_event _json = None
let decode_client_msg _json = None
let decode_server_msg _json = None
