(** Geographic coordinate handling and distance calculations.

    Uses the Haversine formula for great-circle distance.
    All distances are in meters. *)

val haversine_distance : Shared.Types.position -> Shared.Types.position -> float

val bearing : Shared.Types.position -> Shared.Types.position -> float

val is_valid_position : Shared.Types.position -> bool
