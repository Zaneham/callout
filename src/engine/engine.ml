open Shared.Types

module IdMap = Map.Make(String)

type rng_state = { mutable seed : int64 }

type stats = {
  commands_processed : int;
  events_applied : int;
  incidents_created : int;
  units_created : int;
  dispatch_count : int;
  errors : int;
}

type state = {
  incidents : incident IdMap.t;
  units : unit_ IdMap.t;
  events : event list;
  event_count : int;
  rng : rng_state;
  stats : stats;
}

type command =
  | Cmd_create_incident of {
      position : position;
      severity : severity;
      description : string;
    }
  | Cmd_change_incident_status of {
      incident_id : incident_id;
      new_status : incident_status;
    }
  | Cmd_dispatch_unit of {
      unit_id : unit_id;
      incident_id : incident_id;
    }
  | Cmd_release_unit of { unit_id : unit_id }
  | Cmd_update_unit_position of {
      unit_id : unit_id;
      position : position;
    }
  | Cmd_change_unit_status of {
      unit_id : unit_id;
      new_status : unit_status;
    }
  | Cmd_add_note of {
      incident_id : incident_id;
      text : string;
    }
  | Cmd_register_unit of {
      id : unit_id;
      name : string;
    }

type command_envelope = {
  command : command;
  author : user_id;
  authority : authority;
  timestamp : float;
}

type apply_result = {
  state : state;
  new_events : event list;
  error : string option;
}

(* --- Xorshift64 RNG --- *)

let rng_next rng =
  let s = rng.seed in
  let s = Int64.logxor s (Int64.shift_left s 13) in
  let s = Int64.logxor s (Int64.shift_right_logical s 7) in
  let s = Int64.logxor s (Int64.shift_left s 17) in
  rng.seed <- s;
  s

let rng_next_id rng =
  let a = rng_next rng in
  let b = rng_next rng in
  Printf.sprintf "%016Lx%016Lx" a b

(* --- Init --- *)

let empty_stats = {
  commands_processed = 0;
  events_applied = 0;
  incidents_created = 0;
  units_created = 0;
  dispatch_count = 0;
  errors = 0;
}

let init ~seed =
  let rng = { seed } in
  (* Warm up the RNG with a few iterations *)
  ignore (rng_next rng);
  ignore (rng_next rng);
  {
    incidents = IdMap.empty;
    units = IdMap.empty;
    events = [];
    event_count = 0;
    rng;
    stats = empty_stats;
  }

(* --- apply_event: pure state reducer --- *)

let apply_event state (ev : event) =
  let incidents, units, stats =
    match ev.payload with
    | Incident_created { position; severity; description } ->
      let inc = Core.Incident.create
        ~id:ev.id ~position ~severity ~description ~now:ev.timestamp
      in
      let incidents = IdMap.add ev.id inc state.incidents in
      let stats = { state.stats with incidents_created = state.stats.incidents_created + 1 } in
      (incidents, state.units, stats)

    | Incident_status_changed { incident_id; _ } ->
      let incidents =
        match IdMap.find_opt incident_id state.incidents with
        | Some inc ->
          (match Core.Incident.apply_event inc ev with
           | Ok inc' -> IdMap.add incident_id inc' state.incidents
           | Error _ -> state.incidents)
        | None -> state.incidents
      in
      (incidents, state.units, state.stats)

    | Unit_dispatched { unit_id; incident_id } ->
      (* Update the unit *)
      let units =
        match IdMap.find_opt unit_id state.units with
        | Some u ->
          (match Core.Unit.apply_event u ev with
           | Ok u' -> IdMap.add unit_id u' state.units
           | Error _ -> state.units)
        | None -> state.units
      in
      (* Auto-transition incident Reported -> Dispatched *)
      let incidents =
        match IdMap.find_opt incident_id state.incidents with
        | Some inc ->
          (match Core.Incident.apply_event inc ev with
           | Ok inc' -> IdMap.add incident_id inc' state.incidents
           | Error _ -> state.incidents)
        | None -> state.incidents
      in
      let stats = { state.stats with dispatch_count = state.stats.dispatch_count + 1 } in
      (incidents, units, stats)

    | Unit_status_changed { unit_id; new_status } ->
      let units =
        match IdMap.find_opt unit_id state.units with
        | Some u ->
          (match Core.Unit.apply_event u ev with
           | Ok u' -> IdMap.add unit_id u' state.units
           | Error _ -> state.units)
        | None ->
          (* Unit not yet in state — auto-create on Available (registration via replay) *)
          (match new_status with
           | Available ->
             let u = Core.Unit.create ~id:unit_id ~name:unit_id ~now:ev.timestamp in
             IdMap.add unit_id u state.units
           | _ -> state.units)
      in
      let stats =
        if not (IdMap.mem unit_id state.units) && new_status = Available then
          { state.stats with units_created = state.stats.units_created + 1 }
        else
          state.stats
      in
      (state.incidents, units, stats)

    | Unit_position_updated { unit_id; _ } ->
      let units =
        match IdMap.find_opt unit_id state.units with
        | Some u ->
          (match Core.Unit.apply_event u ev with
           | Ok u' -> IdMap.add unit_id u' state.units
           | Error _ -> state.units)
        | None -> state.units
      in
      (state.incidents, units, state.stats)

    | Note_added _ ->
      (state.incidents, state.units, state.stats)
  in
  { state with
    incidents;
    units;
    events = ev :: state.events;
    event_count = state.event_count + 1;
    stats = { stats with events_applied = stats.events_applied + 1 };
  }

(* --- apply_command: validate + produce event + apply --- *)

let make_event state ~author ~authority ~payload ~timestamp =
  let id = rng_next_id state.rng in
  { id; timestamp; author; authority; payload }

let ok_result state evs =
  { state; new_events = evs; error = None }

let err_result state msg =
  let stats = { state.stats with
    errors = state.stats.errors + 1;
    commands_processed = state.stats.commands_processed + 1;
  } in
  { state = { state with stats }; new_events = []; error = Some msg }

let apply_command state (env : command_envelope) =
  let bump_processed st =
    { st with stats = { st.stats with commands_processed = st.stats.commands_processed + 1 } }
  in
  match env.command with
  | Cmd_create_incident { position; severity; description } ->
    if not (Core.Auth.can_create_incident env.authority) then
      err_result state "insufficient authority to create incident"
    else
      let payload = Incident_created { position; severity; description } in
      let ev = make_event state ~author:env.author ~authority:env.authority
                 ~payload ~timestamp:env.timestamp in
      let state = apply_event state ev in
      let state = bump_processed state in
      ok_result state [ev]

  | Cmd_change_incident_status { incident_id; new_status } ->
    if not (Core.Auth.can_change_incident_status env.authority) then
      err_result state "insufficient authority to change incident status"
    else
      (match IdMap.find_opt incident_id state.incidents with
       | None -> err_result state (Printf.sprintf "incident %s not found" incident_id)
       | Some inc ->
         (match Core.Incident.transition inc new_status env.timestamp with
          | Error msg -> err_result state msg
          | Ok _ ->
            let payload = Incident_status_changed { incident_id; new_status } in
            let ev = make_event state ~author:env.author ~authority:env.authority
                       ~payload ~timestamp:env.timestamp in
            let state = apply_event state ev in
            let state = bump_processed state in
            ok_result state [ev]))

  | Cmd_dispatch_unit { unit_id; incident_id } ->
    (match IdMap.find_opt unit_id state.units, IdMap.find_opt incident_id state.incidents with
     | None, _ -> err_result state (Printf.sprintf "unit %s not found" unit_id)
     | _, None -> err_result state (Printf.sprintf "incident %s not found" incident_id)
     | Some u, Some inc ->
       (match Core.Dispatch.assign_unit ~unit_:u ~incident:inc
                ~author_authority:env.authority ~now:env.timestamp with
        | Error msg -> err_result state msg
        | Ok (_, payload) ->
          let ev = make_event state ~author:env.author ~authority:env.authority
                     ~payload ~timestamp:env.timestamp in
          let state = apply_event state ev in
          let state = bump_processed state in
          ok_result state [ev]))

  | Cmd_release_unit { unit_id } ->
    (match IdMap.find_opt unit_id state.units with
     | None -> err_result state (Printf.sprintf "unit %s not found" unit_id)
     | Some u ->
       (match Core.Dispatch.release_unit ~unit_:u
                ~author_authority:env.authority ~now:env.timestamp with
        | Error msg -> err_result state msg
        | Ok (_, payload) ->
          let ev = make_event state ~author:env.author ~authority:env.authority
                     ~payload ~timestamp:env.timestamp in
          let state = apply_event state ev in
          let state = bump_processed state in
          ok_result state [ev]))

  | Cmd_update_unit_position { unit_id; position } ->
    (match IdMap.find_opt unit_id state.units with
     | None -> err_result state (Printf.sprintf "unit %s not found" unit_id)
     | Some _ ->
       let payload = Unit_position_updated { unit_id; position } in
       let ev = make_event state ~author:env.author ~authority:env.authority
                  ~payload ~timestamp:env.timestamp in
       let state = apply_event state ev in
       let state = bump_processed state in
       ok_result state [ev])

  | Cmd_change_unit_status { unit_id; new_status } ->
    (match IdMap.find_opt unit_id state.units with
     | None -> err_result state (Printf.sprintf "unit %s not found" unit_id)
     | Some u ->
       (match Core.Unit.set_status u new_status env.timestamp with
        | Error msg -> err_result state msg
        | Ok _ ->
          let payload = Unit_status_changed { unit_id; new_status } in
          let ev = make_event state ~author:env.author ~authority:env.authority
                     ~payload ~timestamp:env.timestamp in
          let state = apply_event state ev in
          let state = bump_processed state in
          ok_result state [ev]))

  | Cmd_add_note { incident_id; text } ->
    (match IdMap.find_opt incident_id state.incidents with
     | None -> err_result state (Printf.sprintf "incident %s not found" incident_id)
     | Some _ ->
       let payload = Note_added { incident_id; text } in
       let ev = make_event state ~author:env.author ~authority:env.authority
                  ~payload ~timestamp:env.timestamp in
       let state = apply_event state ev in
       let state = bump_processed state in
       ok_result state [ev])

  | Cmd_register_unit { id; name = _ } ->
    if IdMap.mem id state.units then
      err_result state (Printf.sprintf "unit %s already registered" id)
    else
      let payload = Unit_status_changed { unit_id = id; new_status = Available } in
      let ev = make_event state ~author:env.author ~authority:env.authority
                 ~payload ~timestamp:env.timestamp in
      let state = apply_event state ev in
      let state = bump_processed state in
      ok_result state [ev]

(* --- Replay --- *)

let replay ~seed events =
  let state = init ~seed in
  List.fold_left apply_event state events

(* --- Queries --- *)

let get_incident state id = IdMap.find_opt id state.incidents
let get_unit state id = IdMap.find_opt id state.units
let get_all_incidents state = IdMap.fold (fun _ v acc -> v :: acc) state.incidents []
let get_all_units state = IdMap.fold (fun _ v acc -> v :: acc) state.units []
let get_events state = List.rev state.events
let get_stats state = state.stats
