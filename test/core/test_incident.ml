(* Tests for the incident state machine.
 *
 * Verifies:
 * - Valid transitions succeed
 * - Invalid transitions are rejected with clear errors
 * - State machine is total (no unhandled cases)
 *)

open Shared.Types

let now = 1700000000.0

let make_position () =
  { lat = 34.0522; lng = -118.2437; accuracy = Some 10.0; timestamp = now }

let make_incident ?(status = Reported) () =
  {
    id = "inc-001";
    status;
    severity = P2;
    position = make_position ();
    description = "Structure fire, 2-story residential";
    created_at = now;
    updated_at = now;
  }

(* --- Valid transitions --- *)

let test_reported_to_dispatched () =
  let inc = make_incident () in
  match Core.Incident.transition inc Dispatched (now +. 1.0) with
  | Ok updated ->
    Alcotest.(check string) "status" "dispatched"
      (incident_status_to_string updated.status)
  | Error e ->
    Alcotest.fail e

let test_dispatched_to_en_route () =
  let inc = make_incident ~status:Dispatched () in
  match Core.Incident.transition inc En_route (now +. 2.0) with
  | Ok updated ->
    Alcotest.(check string) "status" "en_route"
      (incident_status_to_string updated.status)
  | Error e ->
    Alcotest.fail e

let test_en_route_to_on_scene () =
  let inc = make_incident ~status:En_route () in
  match Core.Incident.transition inc On_scene (now +. 3.0) with
  | Ok updated ->
    Alcotest.(check string) "status" "on_scene"
      (incident_status_to_string updated.status)
  | Error e ->
    Alcotest.fail e

let test_on_scene_to_under_control () =
  let inc = make_incident ~status:On_scene () in
  match Core.Incident.transition inc Under_control (now +. 4.0) with
  | Ok updated ->
    Alcotest.(check string) "status" "under_control"
      (incident_status_to_string updated.status)
  | Error e ->
    Alcotest.fail e

let test_under_control_to_resolved () =
  let inc = make_incident ~status:Under_control () in
  match Core.Incident.transition inc Resolved (now +. 5.0) with
  | Ok updated ->
    Alcotest.(check string) "status" "resolved"
      (incident_status_to_string updated.status)
  | Error e ->
    Alcotest.fail e

let test_under_control_escalate_back () =
  let inc = make_incident ~status:Under_control () in
  match Core.Incident.transition inc On_scene (now +. 4.5) with
  | Ok updated ->
    Alcotest.(check string) "status" "on_scene"
      (incident_status_to_string updated.status)
  | Error e ->
    Alcotest.fail e

let test_any_to_cancelled () =
  let statuses = [ Reported; Dispatched; En_route; On_scene ] in
  List.iter (fun status ->
    let inc = make_incident ~status () in
    match Core.Incident.transition inc Cancelled (now +. 10.0) with
    | Ok updated ->
      Alcotest.(check string)
        (Printf.sprintf "%s -> cancelled" (incident_status_to_string status))
        "cancelled"
        (incident_status_to_string updated.status)
    | Error e ->
      Alcotest.fail e
  ) statuses

(* --- Invalid transitions --- *)

let test_reported_to_on_scene_rejected () =
  let inc = make_incident () in
  match Core.Incident.transition inc On_scene (now +. 1.0) with
  | Ok _ ->
    Alcotest.fail "should reject reported -> on_scene"
  | Error msg ->
    Alcotest.(check bool) "is error" true (String.length msg > 0)

let test_resolved_is_terminal () =
  let inc = make_incident ~status:Resolved () in
  let targets = [ Reported; Dispatched; En_route; On_scene; Under_control; Cancelled ] in
  List.iter (fun target ->
    match Core.Incident.transition inc target (now +. 10.0) with
    | Ok _ ->
      Alcotest.fail
        (Printf.sprintf "should reject resolved -> %s"
           (incident_status_to_string target))
    | Error _ -> ()
  ) targets

let test_cancelled_is_terminal () =
  let inc = make_incident ~status:Cancelled () in
  let targets = [ Reported; Dispatched; En_route; On_scene; Under_control; Resolved ] in
  List.iter (fun target ->
    match Core.Incident.transition inc target (now +. 10.0) with
    | Ok _ ->
      Alcotest.fail
        (Printf.sprintf "should reject cancelled -> %s"
           (incident_status_to_string target))
    | Error _ -> ()
  ) targets

let test_create_incident () =
  let pos = make_position () in
  let inc = Core.Incident.create
    ~id:"inc-new"
    ~position:pos
    ~severity:P1
    ~description:"Multi-alarm fire"
    ~now
  in
  Alcotest.(check string) "status" "reported"
    (incident_status_to_string inc.status);
  Alcotest.(check string) "id" "inc-new" inc.id;
  Alcotest.(check string) "severity" "P1"
    (severity_to_string inc.severity)

(* --- Test suite --- *)

let valid_transitions_suite =
  [ "reported -> dispatched", `Quick, test_reported_to_dispatched
  ; "dispatched -> en_route", `Quick, test_dispatched_to_en_route
  ; "en_route -> on_scene", `Quick, test_en_route_to_on_scene
  ; "on_scene -> under_control", `Quick, test_on_scene_to_under_control
  ; "under_control -> resolved", `Quick, test_under_control_to_resolved
  ; "under_control -> on_scene (escalate)", `Quick, test_under_control_escalate_back
  ; "any -> cancelled", `Quick, test_any_to_cancelled
  ]

let invalid_transitions_suite =
  [ "reported -> on_scene (skip)", `Quick, test_reported_to_on_scene_rejected
  ; "resolved is terminal", `Quick, test_resolved_is_terminal
  ; "cancelled is terminal", `Quick, test_cancelled_is_terminal
  ]

let creation_suite =
  [ "create incident", `Quick, test_create_incident
  ]

let () =
  Alcotest.run "Incident State Machine"
    [ "valid transitions", valid_transitions_suite
    ; "invalid transitions", invalid_transitions_suite
    ; "creation", creation_suite
    ]
