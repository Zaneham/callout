let time_ms f =
  let t0 = Unix.gettimeofday () in
  let result = f () in
  let t1 = Unix.gettimeofday () in
  (result, (t1 -. t0) *. 1000.0)

let print_banner () =
  Printf.printf "\n========================================\n";
  Printf.printf "  CALLOUT ENGINE HARNESS\n";
  Printf.printf "========================================\n"

let run_batch ~num_dispatches ~seed ~verbose =
  Printf.printf "\nHEADLESS ENGINE TEST\n";
  Printf.printf "Dispatches: %d, Seed: %Ld\n\n" num_dispatches seed;

  (* Generate commands *)
  let cmds, gen_ms = time_ms (fun () ->
    Synthetic.generate_n_dispatches num_dispatches ~seed
  ) in
  let num_cmds = List.length cmds in
  Printf.printf "Generated %d commands in %.2f ms\n" num_cmds gen_ms;

  (* Run through engine *)
  let state = ref (Engine.init ~seed) in
  let _, run_ms = time_ms (fun () ->
    let total = num_cmds in
    let checkpoint = max 1 (total / 10) in
    let i = ref 0 in
    List.iter (fun cmd ->
      let result = Engine.apply_command !state cmd in
      state := result.Engine.state;
      incr i;
      if verbose && !i mod checkpoint = 0 then
        Printf.printf "  ... %d / %d commands (%.0f%%)\n%!" !i total
          (100.0 *. float_of_int !i /. float_of_int total)
    ) cmds
  ) in
  let final_state = !state in
  let stats = Engine.get_stats final_state in

  (* Replay from events *)
  let events = List.rev (Engine.get_events final_state) in
  let replayed, replay_ms = time_ms (fun () ->
    Engine.replay ~seed events
  ) in
  let replay_stats = Engine.get_stats replayed in
  let replay_ok =
    stats.events_applied = replay_stats.events_applied &&
    stats.incidents_created = replay_stats.incidents_created &&
    stats.units_created = replay_stats.units_created &&
    stats.dispatch_count = replay_stats.dispatch_count
  in

  (* Print results *)
  Printf.printf "\n========================================\n";
  Printf.printf "RESULTS\n";
  Printf.printf "========================================\n";
  Printf.printf "Commands:     %d\n" stats.commands_processed;
  Printf.printf "Events:       %d\n" stats.events_applied;
  Printf.printf "Errors:       %d\n" stats.errors;
  Printf.printf "Incidents:    %d\n" stats.incidents_created;
  Printf.printf "Units:        %d\n" stats.units_created;
  Printf.printf "Dispatches:   %d\n" stats.dispatch_count;
  Printf.printf "Time:         %.2f ms\n" run_ms;
  if num_cmds > 0 then begin
    let throughput = float_of_int num_cmds /. (run_ms /. 1000.0) in
    let per_cmd = run_ms *. 1000.0 /. float_of_int num_cmds in
    Printf.printf "Throughput:   %.0f cmd/sec\n" throughput;
    Printf.printf "Per command:  %.3f us\n" per_cmd
  end;
  Printf.printf "Replay:       %.2f ms\n" replay_ms;
  Printf.printf "========================================\n";
  if replay_ok then
    Printf.printf "REPLAY: PASSED (deterministic)\n"
  else begin
    Printf.printf "REPLAY: FAILED\n";
    Printf.printf "  expected events=%d got=%d\n"
      stats.events_applied replay_stats.events_applied;
    Printf.printf "  expected incidents=%d got=%d\n"
      stats.incidents_created replay_stats.incidents_created
  end;
  Printf.printf "========================================\n\n";
  replay_ok

let () =
  let num_dispatches = ref 0 in
  let stress = ref false in
  let seed = ref 42L in
  let verbose = ref false in
  let specs = [
    ("--test", Arg.Set_int num_dispatches, "N  Run N synthetic dispatches");
    ("--stress", Arg.Set stress, "  Escalating stress test (100 to 1M)");
    ("--seed", Arg.Int (fun n -> seed := Int64.of_int n), "N  RNG seed (default: 42)");
    ("--verbose", Arg.Set verbose, "  Per-batch progress output");
  ] in
  Arg.parse specs (fun _ -> ()) "callout-harness [--test N | --stress] [--seed N] [--verbose]";

  print_banner ();

  if !stress then begin
    let levels = [100; 1_000; 10_000; 100_000; 1_000_000] in
    let all_ok = ref true in
    List.iter (fun n ->
      Printf.printf "\n--- STRESS LEVEL: %d dispatches ---\n" n;
      let ok = run_batch ~num_dispatches:n ~seed:!seed ~verbose:!verbose in
      if not ok then all_ok := false
    ) levels;
    if !all_ok then
      Printf.printf "\nALL STRESS LEVELS PASSED\n\n"
    else begin
      Printf.printf "\nSOME STRESS LEVELS FAILED\n\n";
      exit 1
    end
  end else if !num_dispatches > 0 then begin
    let ok = run_batch ~num_dispatches:!num_dispatches ~seed:!seed ~verbose:!verbose in
    if not ok then exit 1
  end else begin
    Printf.printf "\nUsage: callout-harness --test N | --stress [--seed N] [--verbose]\n\n";
    exit 1
  end
