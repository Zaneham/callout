(* Callout CAD — OCaml FFI Bridge
 *
 * This module is the OCaml side of the C-OCaml boundary.
 * It holds the engine state as a process-global ref and
 * registers callbacks that the C server invokes via caml_callback.
 *)

let engine_state : Engine.state ref =
  ref (Engine.init ~seed:42L)

let () =
  Callback.register "bridge_init" (fun () ->
    engine_state := Engine.init ~seed:42L;
    "ok"
  )

let () =
  Callback.register "bridge_handle_ws_message" (fun json_str ->
    match Codec.decode_client_msg json_str with
    | None ->
      Shared.Protocol.encode_server_msg
        (Shared.Protocol.Error { code = 400; message = "invalid message" })
    | Some msg ->
      match msg with
      | Shared.Protocol.Ping ->
        Shared.Protocol.encode_server_msg Shared.Protocol.Pong
      | Shared.Protocol.Request_sync { since } ->
        let events = Engine.get_events !engine_state in
        let filtered = List.filter (fun (e : Shared.Types.event) ->
          e.timestamp >= since) events
        in
        Shared.Protocol.encode_server_msg (Shared.Protocol.Events filtered)
      | Shared.Protocol.Push_events events ->
        let state = List.fold_left Engine.apply_event !engine_state events in
        engine_state := state;
        Shared.Protocol.encode_server_msg
          (Shared.Protocol.Sync_complete { server_time = Unix.gettimeofday () })
  )

let () =
  Callback.register "bridge_create_incident" (fun json_str ->
    match Codec.decode_command_envelope json_str with
    | None -> Codec.encode_error "invalid command JSON"
    | Some env ->
      let result = Engine.apply_command !engine_state env in
      engine_state := result.Engine.state;
      Codec.encode_apply_result result
  )

let () =
  Callback.register "bridge_get_incidents" (fun () ->
    let incidents = Engine.get_all_incidents !engine_state in
    Shared.Protocol.encode_incidents incidents
  )

let () =
  Callback.register "bridge_get_units" (fun () ->
    let units = Engine.get_all_units !engine_state in
    Shared.Protocol.encode_units units
  )

let () =
  Callback.register "bridge_get_events" (fun () ->
    let events = Engine.get_events !engine_state in
    Shared.Protocol.encode_events events
  )
