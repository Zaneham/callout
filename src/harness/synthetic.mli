(** Deterministic synthetic command generation for stress testing.

    Uses the same xorshift64 RNG as the engine. Given the same seed
    and dispatch count, always produces the identical command list. *)

type scenario_config = {
  num_incidents : int;
  num_units : int;
  bbox_min_lat : float;
  bbox_max_lat : float;
  bbox_min_lng : float;
  bbox_max_lng : float;
}

val default_config : int -> scenario_config
val generate_n_dispatches : int -> seed:int64 -> Engine.command_envelope list
