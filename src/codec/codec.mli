(** Server-side JSON codec using yojson.

    Cannot live in [shared] because js_of_ocaml can't compile yojson. *)

val decode_command_envelope : string -> Engine.command_envelope option
val decode_client_msg : string -> Shared.Protocol.client_msg option
val encode_apply_result : Engine.apply_result -> string
val encode_error : string -> string
