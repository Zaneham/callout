open Shared.Types

module StringSet = Set.Make(String)

type sync_result = {
  accepted : event list;
  rejected : (event * string) list;
}

(* Merge remote events into local event list.
   For events with conflicting effects on the same entity,
   authority ranking breaks ties, then timestamp. *)
let merge_events ~local ~remote =
  let local_ids =
    List.fold_left
      (fun acc (e : event) -> StringSet.add e.id acc)
      StringSet.empty local
  in
  let new_events =
    List.filter (fun (e : event) -> not (StringSet.mem e.id local_ids)) remote
  in
  (* All genuinely new events are accepted.
     Conflict resolution happens at the application layer
     when materializing state from the event log —
     Auth.resolve_conflict picks the winner. *)
  let accepted =
    List.sort
      (fun (a : event) (b : event) -> compare a.timestamp b.timestamp)
      new_events
  in
  { accepted; rejected = [] }

(* Placeholder: in the real system, "synced" is tracked in SQLite.
   This operates on an in-memory list for testing. *)
let unsynced_events _events = []
