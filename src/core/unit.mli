(** Unit (truck/crew) state management.

    Units have strict lifecycle rules. A unit can only be in one
    state at a time, and state transitions follow ICS conventions. *)

type unit_error = string

val create :
  id:Shared.Types.unit_id ->
  name:string ->
  now:float ->
  Shared.Types.unit_

val update_position :
  Shared.Types.unit_ ->
  Shared.Types.position ->
  Shared.Types.unit_

val set_status :
  Shared.Types.unit_ ->
  Shared.Types.unit_status ->
  float ->
  (Shared.Types.unit_, unit_error) result

val mark_available :
  Shared.Types.unit_ ->
  float ->
  (Shared.Types.unit_, unit_error) result

val mark_out_of_service :
  Shared.Types.unit_ ->
  float ->
  (Shared.Types.unit_, unit_error) result

val apply_event :
  Shared.Types.unit_ ->
  Shared.Types.event ->
  (Shared.Types.unit_, unit_error) result
