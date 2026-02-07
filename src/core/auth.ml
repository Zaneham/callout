open Shared.Types

let can_create_incident _authority = true

let can_dispatch_unit authority =
  match authority with
  | Dispatcher | Incident_commander | Crew_leader -> true
  | Field_unit -> false

let can_change_incident_status authority =
  match authority with
  | Dispatcher | Incident_commander -> true
  | Crew_leader | Field_unit -> false

let can_override ~actor ~target =
  authority_outranks actor target

let resolve_conflict a b =
  let a_rank = authority_to_int a.authority in
  let b_rank = authority_to_int b.authority in
  if a_rank < b_rank then a        (* lower int = higher authority *)
  else if b_rank < a_rank then b
  else if a.timestamp >= b.timestamp then a  (* same authority: latest wins *)
  else b
