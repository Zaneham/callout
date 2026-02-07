(** Authority levels and permission checks.

    Authority follows ICS (Incident Command System) hierarchy:
    Dispatcher > Incident Commander > Crew Leader > Field Unit

    Higher authority can override lower authority decisions.
    Same-level conflicts are resolved by timestamp. *)

val can_create_incident : Shared.Types.authority -> bool
val can_dispatch_unit : Shared.Types.authority -> bool
val can_change_incident_status : Shared.Types.authority -> bool
val can_override : actor:Shared.Types.authority -> target:Shared.Types.authority -> bool

val resolve_conflict :
  Shared.Types.event ->
  Shared.Types.event ->
  Shared.Types.event
