(* Tests for authority and conflict resolution. *)

open Shared.Types

let now = 1700000000.0

let make_event ~authority ~timestamp =
  {
    id = Core.Event.generate_id ();
    timestamp;
    author = "user-1";
    authority;
    payload = Incident_status_changed {
      incident_id = "inc-001";
      new_status = Under_control;
    };
  }

let test_dispatcher_overrides_field () =
  let dispatcher_evt = make_event ~authority:Dispatcher ~timestamp:now in
  let field_evt = make_event ~authority:Field_unit ~timestamp:(now +. 10.0) in
  let winner = Core.Auth.resolve_conflict dispatcher_evt field_evt in
  Alcotest.(check string) "dispatcher wins" dispatcher_evt.id winner.id

let test_same_authority_latest_wins () =
  let early = make_event ~authority:Crew_leader ~timestamp:now in
  let late = make_event ~authority:Crew_leader ~timestamp:(now +. 5.0) in
  let winner = Core.Auth.resolve_conflict early late in
  Alcotest.(check string) "later wins" late.id winner.id

let test_authority_permissions () =
  Alcotest.(check bool) "dispatcher can dispatch" true
    (Core.Auth.can_dispatch_unit Dispatcher);
  Alcotest.(check bool) "IC can dispatch" true
    (Core.Auth.can_dispatch_unit Incident_commander);
  Alcotest.(check bool) "crew can dispatch" true
    (Core.Auth.can_dispatch_unit Crew_leader);
  Alcotest.(check bool) "field cannot dispatch" false
    (Core.Auth.can_dispatch_unit Field_unit)

let test_authority_ranking () =
  Alcotest.(check bool) "dispatcher outranks IC" true
    (authority_outranks Dispatcher Incident_commander);
  Alcotest.(check bool) "IC outranks crew" true
    (authority_outranks Incident_commander Crew_leader);
  Alcotest.(check bool) "crew outranks field" true
    (authority_outranks Crew_leader Field_unit);
  Alcotest.(check bool) "field does not outrank dispatcher" false
    (authority_outranks Field_unit Dispatcher)

let () =
  Alcotest.run "Authority & Conflict Resolution"
    [ "conflict resolution", [
        "dispatcher overrides field", `Quick, test_dispatcher_overrides_field;
        "same authority latest wins", `Quick, test_same_authority_latest_wins;
      ]
    ; "permissions", [
        "dispatch permissions", `Quick, test_authority_permissions;
      ]
    ; "ranking", [
        "authority hierarchy", `Quick, test_authority_ranking;
      ]
    ]
