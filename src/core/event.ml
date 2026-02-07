open Shared.Types

(* Simple UUID v4 generator using Random.
   In production, use a proper UUID library or OS entropy source. *)
let generate_id () =
  let hex () = Printf.sprintf "%04x" (Random.int 0xFFFF) in
  Printf.sprintf "%s%s-%s-%s-%s-%s%s%s"
    (hex ()) (hex ()) (hex ()) (hex ()) (hex ()) (hex ()) (hex ()) (hex ())

let create_event ~author ~authority ~payload ~now =
  {
    id = generate_id ();
    timestamp = now;
    author;
    authority;
    payload;
  }

let events_since events since =
  List.filter (fun (e : event) -> e.timestamp > since) events
  |> List.sort (fun (a : event) (b : event) -> compare a.timestamp b.timestamp)

let incident_id_of_payload = function
  | Incident_created _ -> None
  | Incident_status_changed { incident_id; _ } -> Some incident_id
  | Unit_dispatched { incident_id; _ } -> Some incident_id
  | Unit_status_changed _ -> None
  | Unit_position_updated _ -> None
  | Note_added { incident_id; _ } -> Some incident_id

let events_for_incident events incident_id =
  List.filter
    (fun (e : event) ->
       match incident_id_of_payload e.payload with
       | Some id -> id = incident_id
       | None -> false)
    events
  |> List.sort (fun (a : event) (b : event) -> compare a.timestamp b.timestamp)
