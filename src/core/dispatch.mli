(** Dispatch logic — assigning units to incidents.

    Dispatch decisions are always made by a human (dispatcher or IC).
    This module validates the assignment, not decides it. *)

type dispatch_error = string

val assign_unit :
  unit_:Shared.Types.unit_ ->
  incident:Shared.Types.incident ->
  author_authority:Shared.Types.authority ->
  now:float ->
  (Shared.Types.unit_ * Shared.Types.event_payload, dispatch_error) result

val release_unit :
  unit_:Shared.Types.unit_ ->
  author_authority:Shared.Types.authority ->
  now:float ->
  (Shared.Types.unit_ * Shared.Types.event_payload, dispatch_error) result

val can_dispatch : Shared.Types.unit_ -> bool
