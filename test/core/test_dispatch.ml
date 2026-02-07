(* Tests for dispatch logic — unit assignment and release. *)

open Shared.Types

let now = 1700000000.0

let make_position () =
  { lat = 34.0522; lng = -118.2437; accuracy = None; timestamp = now }

let make_unit ?(status = Available) () =
  {
    id = "eng-1";
    name = "Engine 1";
    status;
    position = Some (make_position ());
    updated_at = now;
  }

let make_incident ?(status = Reported) () =
  {
    id = "inc-001";
    status;
    severity = P2;
    position = make_position ();
    description = "Structure fire";
    created_at = now;
    updated_at = now;
  }

(* --- Dispatch tests --- *)

let test_dispatch_available_unit () =
  let unit_ = make_unit () in
  let incident = make_incident () in
  match Core.Dispatch.assign_unit ~unit_ ~incident ~author_authority:Dispatcher ~now with
  | Ok (updated_unit, _payload) ->
    Alcotest.(check string) "status" "dispatched"
      (unit_status_to_string updated_unit.status)
  | Error e ->
    Alcotest.fail e

let test_dispatch_returning_unit () =
  let unit_ = make_unit ~status:Returning () in
  let incident = make_incident () in
  match Core.Dispatch.assign_unit ~unit_ ~incident ~author_authority:Dispatcher ~now with
  | Ok (updated_unit, _payload) ->
    Alcotest.(check string) "status" "dispatched"
      (unit_status_to_string updated_unit.status)
  | Error e ->
    Alcotest.fail e

let test_reject_dispatch_busy_unit () =
  let unit_ = make_unit ~status:(U_dispatched "inc-other") () in
  let incident = make_incident () in
  match Core.Dispatch.assign_unit ~unit_ ~incident ~author_authority:Dispatcher ~now with
  | Ok _ ->
    Alcotest.fail "should reject dispatch of busy unit"
  | Error _ -> ()

let test_reject_dispatch_to_resolved () =
  let unit_ = make_unit () in
  let incident = make_incident ~status:Resolved () in
  match Core.Dispatch.assign_unit ~unit_ ~incident ~author_authority:Dispatcher ~now with
  | Ok _ ->
    Alcotest.fail "should reject dispatch to resolved incident"
  | Error _ -> ()

let test_reject_field_unit_dispatch () =
  let unit_ = make_unit () in
  let incident = make_incident () in
  match Core.Dispatch.assign_unit ~unit_ ~incident ~author_authority:Field_unit ~now with
  | Ok _ ->
    Alcotest.fail "field units cannot dispatch"
  | Error _ -> ()

let test_release_unit () =
  let unit_ = make_unit ~status:(U_on_scene "inc-001") () in
  match Core.Dispatch.release_unit ~unit_ ~author_authority:Dispatcher ~now with
  | Ok (updated_unit, _payload) ->
    Alcotest.(check string) "status" "returning"
      (unit_status_to_string updated_unit.status)
  | Error e ->
    Alcotest.fail e

let test_can_dispatch () =
  Alcotest.(check bool) "available" true
    (Core.Dispatch.can_dispatch (make_unit ~status:Available ()));
  Alcotest.(check bool) "returning" true
    (Core.Dispatch.can_dispatch (make_unit ~status:Returning ()));
  Alcotest.(check bool) "dispatched" false
    (Core.Dispatch.can_dispatch (make_unit ~status:(U_dispatched "x") ()));
  Alcotest.(check bool) "out of service" false
    (Core.Dispatch.can_dispatch (make_unit ~status:Out_of_service ()))

let () =
  Alcotest.run "Dispatch Logic"
    [ "dispatch", [
        "dispatch available unit", `Quick, test_dispatch_available_unit;
        "dispatch returning unit", `Quick, test_dispatch_returning_unit;
        "reject busy unit", `Quick, test_reject_dispatch_busy_unit;
        "reject resolved incident", `Quick, test_reject_dispatch_to_resolved;
        "reject field unit dispatch", `Quick, test_reject_field_unit_dispatch;
      ]
    ; "release", [
        "release unit", `Quick, test_release_unit;
      ]
    ; "can_dispatch", [
        "check dispatchability", `Quick, test_can_dispatch;
      ]
    ]
