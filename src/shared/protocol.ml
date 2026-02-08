type client_msg =
  | Push_events of Types.event list
  | Request_sync of { since : float }
  | Ping

type server_msg =
  | Events of Types.event list
  | Sync_complete of { server_time : float }
  | Error of { code : int; message : string }
  | Pong

(* JSON string escaping — handles quotes, backslashes, and control characters. *)
let json_escape s =
  let buf = Buffer.create (String.length s + 16) in
  String.iter (fun c ->
    match c with
    | '"' -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\r' -> Buffer.add_string buf "\\r"
    | '\t' -> Buffer.add_string buf "\\t"
    | c when Char.code c < 0x20 ->
      Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let encode_position (p : Types.position) =
  let acc_str = match p.accuracy with
    | Some a -> Printf.sprintf ",\"accuracy\":%f" a
    | None -> ""
  in
  Printf.sprintf "{\"lat\":%f,\"lng\":%f%s,\"timestamp\":%f}"
    p.lat p.lng acc_str p.timestamp

let encode_severity (s : Types.severity) =
  Printf.sprintf "\"%s\"" (json_escape (Types.severity_to_string s))

let encode_incident_status (s : Types.incident_status) =
  Printf.sprintf "\"%s\"" (json_escape (Types.incident_status_to_string s))

let encode_unit_status (s : Types.unit_status) =
  let base = Types.unit_status_to_string s in
  match s with
  | Types.U_dispatched id | Types.U_en_route id | Types.U_on_scene id ->
    Printf.sprintf "{\"status\":\"%s\",\"incident_id\":\"%s\"}"
      (json_escape base) (json_escape id)
  | _ -> Printf.sprintf "\"%s\"" (json_escape base)

let encode_authority (a : Types.authority) =
  Printf.sprintf "\"%s\"" (json_escape (Types.authority_to_string a))

let encode_event_payload = function
  | Types.Incident_created { position; severity; description } ->
    Printf.sprintf
      "{\"type\":\"incident_created\",\"position\":%s,\"severity\":%s,\"description\":\"%s\"}"
      (encode_position position) (encode_severity severity) (json_escape description)
  | Types.Incident_status_changed { incident_id; new_status } ->
    Printf.sprintf
      "{\"type\":\"incident_status_changed\",\"incident_id\":\"%s\",\"new_status\":%s}"
      (json_escape incident_id) (encode_incident_status new_status)
  | Types.Unit_dispatched { unit_id; incident_id } ->
    Printf.sprintf
      "{\"type\":\"unit_dispatched\",\"unit_id\":\"%s\",\"incident_id\":\"%s\"}"
      (json_escape unit_id) (json_escape incident_id)
  | Types.Unit_status_changed { unit_id; new_status } ->
    Printf.sprintf
      "{\"type\":\"unit_status_changed\",\"unit_id\":\"%s\",\"new_status\":%s}"
      (json_escape unit_id) (encode_unit_status new_status)
  | Types.Unit_position_updated { unit_id; position } ->
    Printf.sprintf
      "{\"type\":\"unit_position_updated\",\"unit_id\":\"%s\",\"position\":%s}"
      (json_escape unit_id) (encode_position position)
  | Types.Note_added { incident_id; text } ->
    Printf.sprintf
      "{\"type\":\"note_added\",\"incident_id\":\"%s\",\"text\":\"%s\"}"
      (json_escape incident_id) (json_escape text)

let encode_event (e : Types.event) =
  Printf.sprintf
    "{\"id\":\"%s\",\"timestamp\":%f,\"author\":\"%s\",\"authority\":%s,\"payload\":%s}"
    (json_escape e.id) e.timestamp (json_escape e.author)
    (encode_authority e.authority)
    (encode_event_payload e.payload)

let encode_events events =
  let encoded = List.map encode_event events in
  "[" ^ String.concat "," encoded ^ "]"

let encode_incident (inc : Types.incident) =
  Printf.sprintf
    "{\"id\":\"%s\",\"status\":%s,\"severity\":%s,\"position\":%s,\"description\":\"%s\",\"created_at\":%f,\"updated_at\":%f}"
    (json_escape inc.id)
    (encode_incident_status inc.status)
    (encode_severity inc.severity)
    (encode_position inc.position)
    (json_escape inc.description)
    inc.created_at
    inc.updated_at

let encode_incidents incidents =
  let encoded = List.map encode_incident incidents in
  "[" ^ String.concat "," encoded ^ "]"

let encode_unit_ (u : Types.unit_) =
  let pos_str = match u.position with
    | Some p -> encode_position p
    | None -> "null"
  in
  Printf.sprintf
    "{\"id\":\"%s\",\"name\":\"%s\",\"status\":%s,\"position\":%s,\"updated_at\":%f}"
    (json_escape u.id)
    (json_escape u.name)
    (encode_unit_status u.status)
    pos_str
    u.updated_at

let encode_units units =
  let encoded = List.map encode_unit_ units in
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
      code (json_escape message)
  | Pong -> "{\"type\":\"pong\"}"
