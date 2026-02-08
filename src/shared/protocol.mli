(** Wire protocol definitions for client-server communication.

    All messages are JSON-encoded. The protocol is symmetric:
    both client and server send the same message types over WebSocket. *)

type client_msg =
  | Push_events of Types.event list
  | Request_sync of { since : float }
  | Ping

type server_msg =
  | Events of Types.event list
  | Sync_complete of { server_time : float }
  | Error of { code : int; message : string }
  | Pong

(** Escape a string for safe inclusion in a JSON string literal.
    Handles quotes, backslashes, and control characters (U+0000..U+001F). *)
val json_escape : string -> string

val encode_event : Types.event -> string
val encode_events : Types.event list -> string

val encode_incident : Types.incident -> string
val encode_incidents : Types.incident list -> string
val encode_unit_ : Types.unit_ -> string
val encode_units : Types.unit_ list -> string

val encode_client_msg : client_msg -> string
val encode_server_msg : server_msg -> string
