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

val encode_event : Types.event -> string
val decode_event : string -> Types.event option

val encode_client_msg : client_msg -> string
val decode_client_msg : string -> client_msg option

val encode_server_msg : server_msg -> string
val decode_server_msg : string -> server_msg option
