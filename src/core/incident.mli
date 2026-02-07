(** Incident lifecycle state machine.

    State transitions are explicit and total — the compiler enforces
    that every possible transition is handled. Invalid transitions
    return Error with a reason string. *)

type transition_error = string

val valid_transitions : Shared.Types.incident_status -> Shared.Types.incident_status list

val transition :
  Shared.Types.incident ->
  Shared.Types.incident_status ->
  float ->
  (Shared.Types.incident, transition_error) result

val create :
  id:Shared.Types.incident_id ->
  position:Shared.Types.position ->
  severity:Shared.Types.severity ->
  description:string ->
  now:float ->
  Shared.Types.incident

val apply_event :
  Shared.Types.incident ->
  Shared.Types.event ->
  (Shared.Types.incident, transition_error) result
