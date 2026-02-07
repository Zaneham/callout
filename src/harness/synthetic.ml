open Shared.Types

type scenario_config = {
  num_incidents : int;
  num_units : int;
  bbox_min_lat : float;
  bbox_max_lat : float;
  bbox_min_lng : float;
  bbox_max_lng : float;
}

let default_config num_dispatches =
  let num_units = max 10 (num_dispatches / 5) in
  let num_incidents = num_dispatches in
  {
    num_incidents;
    num_units;
    bbox_min_lat = 33.5;
    bbox_max_lat = 34.5;
    bbox_min_lng = -118.5;
    bbox_max_lng = -117.5;
  }

(* Use Engine's xorshift64 for deterministic generation *)

let rng_float rng lo hi =
  let v = Engine.rng_next rng in
  let frac = Int64.to_float (Int64.logand v 0x7FFFFFFFFFFFFFFFL) /.
             Int64.to_float 0x7FFFFFFFFFFFFFFFL in
  lo +. frac *. (hi -. lo)

let rng_int rng n =
  let v = Engine.rng_next rng in
  abs (Int64.to_int (Int64.rem v (Int64.of_int n)))

let rng_severity rng =
  match rng_int rng 5 with
  | 0 -> P1 | 1 -> P2 | 2 -> P3 | 3 -> P4 | _ -> P5

let rng_authority rng =
  match rng_int rng 10 with
  | 0 | 1 | 2 | 3 -> Dispatcher
  | 4 | 5 | 6 -> Incident_commander
  | 7 | 8 -> Crew_leader
  | _ -> Field_unit

let rng_position rng cfg ts =
  let lat = rng_float rng cfg.bbox_min_lat cfg.bbox_max_lat in
  let lng = rng_float rng cfg.bbox_min_lng cfg.bbox_max_lng in
  { lat; lng; accuracy = Some 10.0; timestamp = ts }

let generate_n_dispatches num_dispatches ~seed =
  let rng = Engine.({ seed }) in
  (* Warm up *)
  ignore (Engine.rng_next rng);
  ignore (Engine.rng_next rng);
  let cfg = default_config num_dispatches in
  let cmds = ref [] in
  let add cmd = cmds := cmd :: !cmds in
  let ts = ref 1000000.0 in
  let next_ts () = ts := !ts +. 0.001; !ts in

  (* Phase 1: Register units *)
  let unit_ids = Array.init cfg.num_units (fun i ->
    Printf.sprintf "unit-%06d" i
  ) in
  Array.iter (fun uid ->
    let t = next_ts () in
    add Engine.{
      command = Cmd_register_unit { id = uid; name = Printf.sprintf "Unit %s" uid };
      author = "harness";
      authority = Dispatcher;
      timestamp = t;
    }
  ) unit_ids;

  (* Phase 2: Create incidents.
     Cmd_create_incident doesn't specify an ID — the engine assigns ev.id
     as the incident ID via RNG. We run setup commands through the engine
     to discover the real IDs for subsequent dispatch commands. *)
  let create_cmds = Array.init cfg.num_incidents (fun _i ->
    let t = next_ts () in
    let pos = rng_position rng cfg t in
    let sev = rng_severity rng in
    let desc = Printf.sprintf "Synthetic incident at %.4f,%.4f" pos.lat pos.lng in
    Engine.{
      command = Cmd_create_incident { position = pos; severity = sev; description = desc };
      author = "harness";
      authority = Dispatcher;
      timestamp = t;
    }
  ) in
  Array.iter add create_cmds;

  (* To get incident IDs, we run just the register+create commands through engine *)
  let setup_cmds = List.rev !cmds in
  let engine_state = ref (Engine.init ~seed) in
  let real_incident_ids = ref [] in
  List.iter (fun cmd ->
    let result = Engine.apply_command !engine_state cmd in
    engine_state := result.Engine.state;
    List.iter (fun (ev : event) ->
      match ev.payload with
      | Incident_created _ -> real_incident_ids := ev.id :: !real_incident_ids
      | _ -> ()
    ) result.Engine.new_events
  ) setup_cmds;
  let real_incident_ids = Array.of_list (List.rev !real_incident_ids) in
  let n_incidents = Array.length real_incident_ids in

  (* Phase 3: Dispatch units to incidents (cycling) *)
  let dispatches_done = ref 0 in
  let unit_idx = ref 0 in
  let inc_idx = ref 0 in
  while !dispatches_done < num_dispatches && n_incidents > 0 do
    let t = next_ts () in
    let uid = unit_ids.(!unit_idx mod cfg.num_units) in
    let iid = real_incident_ids.(!inc_idx mod n_incidents) in
    let auth = rng_authority rng in
    add Engine.{
      command = Cmd_dispatch_unit { unit_id = uid; incident_id = iid };
      author = Printf.sprintf "dispatcher-%d" (rng_int rng 5);
      authority = auth;
      timestamp = t;
    };
    incr dispatches_done;
    incr unit_idx;
    incr inc_idx;

    (* After each batch of units, release some and progress incidents *)
    if !dispatches_done mod cfg.num_units = 0 then begin
      (* Release half the units *)
      for k = 0 to cfg.num_units / 2 - 1 do
        let t = next_ts () in
        add Engine.{
          command = Cmd_release_unit { unit_id = unit_ids.(k) };
          author = "harness";
          authority = Dispatcher;
          timestamp = t;
        }
      done;
      (* Mark released units available *)
      for k = 0 to cfg.num_units / 2 - 1 do
        let t = next_ts () in
        add Engine.{
          command = Cmd_change_unit_status {
            unit_id = unit_ids.(k);
            new_status = Available;
          };
          author = "harness";
          authority = Dispatcher;
          timestamp = t;
        }
      done
    end;

    (* Intersperse position updates *)
    if !dispatches_done mod 3 = 0 then begin
      let t = next_ts () in
      let uid = unit_ids.(rng_int rng cfg.num_units) in
      let pos = rng_position rng cfg t in
      add Engine.{
        command = Cmd_update_unit_position { unit_id = uid; position = pos };
        author = "harness";
        authority = Field_unit;
        timestamp = t;
      }
    end;

    (* Progress some incidents through lifecycle *)
    if !dispatches_done mod 7 = 0 && n_incidents > 0 then begin
      let target = real_incident_ids.(rng_int rng n_incidents) in
      let t = next_ts () in
      (* Try to advance — many will fail (wrong state), that's intentional *)
      let status = match rng_int rng 4 with
        | 0 -> En_route | 1 -> On_scene | 2 -> Under_control | _ -> Resolved
      in
      add Engine.{
        command = Cmd_change_incident_status {
          incident_id = target;
          new_status = status;
        };
        author = "harness";
        authority = Dispatcher;
        timestamp = t;
      }
    end;

    (* Intentional errors: field unit tries to dispatch *)
    if !dispatches_done mod 50 = 0 && n_incidents > 0 then begin
      let t = next_ts () in
      let uid = unit_ids.(rng_int rng cfg.num_units) in
      let iid = real_incident_ids.(rng_int rng n_incidents) in
      add Engine.{
        command = Cmd_dispatch_unit { unit_id = uid; incident_id = iid };
        author = "field-user";
        authority = Field_unit;
        timestamp = t;
      }
    end
  done;

  (* Add some notes *)
  for _ = 0 to min 100 (n_incidents - 1) do
    let t = next_ts () in
    let iid = real_incident_ids.(rng_int rng n_incidents) in
    add Engine.{
      command = Cmd_add_note { incident_id = iid; text = "Synthetic note" };
      author = "harness";
      authority = Dispatcher;
      timestamp = t;
    }
  done;

  List.rev !cmds
