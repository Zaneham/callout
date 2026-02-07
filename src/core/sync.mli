(** Offline sync and conflict resolution.

    Event log + last-write-wins + authority ranking.
    Dispatcher outranks field. Full audit trail preserved. *)

type sync_result = {
  accepted : Shared.Types.event list;
  rejected : (Shared.Types.event * string) list;
}

val merge_events :
  local:Shared.Types.event list ->
  remote:Shared.Types.event list ->
  sync_result

val unsynced_events : Shared.Types.event list -> Shared.Types.event list
