(* Callout CAD — Dispatch Board View
 *
 * Manages the incident list, unit list, and dispatch interactions.
 * Receives events from the WebSocket and updates the UI.
 *)

open Js_of_ocaml

let ws_ref : WebSockets.webSocket Js.t option ref = ref None

let set_ws ws = ws_ref := Some ws

let send_message msg =
  match !ws_ref with
  | Some ws when ws##.readyState = WebSockets.OPEN ->
    ws##send (Js.string msg)
  | _ -> ()

let init () =
  (* Fetch initial incident list *)
  let open XmlHttpRequest in
  let req = create () in
  req##_open (Js.string "GET") (Js.string "/api/incidents") Js._true;
  req##.onreadystatechange := Js.wrap_callback (fun () ->
    if req##.readyState = XmlHttpRequest.DONE && req##.status = 200 then begin
      let _data = Js.Opt.case req##.responseText (fun () -> "") Js.to_string in
      (* TODO: Parse JSON and populate incident list *)
      ()
    end);
  req##send Js.null;

  (* Fetch initial unit list *)
  let req2 = create () in
  req2##_open (Js.string "GET") (Js.string "/api/units") Js._true;
  req2##.onreadystatechange := Js.wrap_callback (fun () ->
    if req2##.readyState = XmlHttpRequest.DONE && req2##.status = 200 then begin
      let _data = Js.Opt.case req2##.responseText (fun () -> "") Js.to_string in
      (* TODO: Parse JSON and populate unit list *)
      ()
    end);
  req2##send Js.null

let handle_message data =
  (* TODO: Parse event JSON using Protocol.decode_server_msg,
     update local state, refresh UI *)
  let _ = data in
  ()

let on_map_click lat lng =
  let doc = Dom_html.document in

  (* Show a simple incident creation dialog *)
  let dialog = Dom_html.createDiv doc in
  dialog##.className := Js.string "incident-dialog";
  dialog##.innerHTML := Js.string (Printf.sprintf
    {|<div class="dialog-content">
        <h3>Create Incident</h3>
        <p>Location: %.6f, %.6f</p>
        <label>Severity:
          <select id="severity-select">
            <option value="1">P1 - Critical</option>
            <option value="2">P2 - Emergency</option>
            <option value="3" selected>P3 - Urgent</option>
            <option value="4">P4 - Non-urgent</option>
            <option value="5">P5 - Administrative</option>
          </select>
        </label>
        <label>Description:
          <textarea id="description-input" rows="3" placeholder="Describe the incident..."></textarea>
        </label>
        <div class="dialog-buttons">
          <button id="create-btn" class="btn-primary">Create</button>
          <button id="cancel-btn" class="btn-secondary">Cancel</button>
        </div>
      </div>|} lat lng);

  Dom.appendChild doc##.body dialog;

  (* Cancel button *)
  let cancel_btn = doc##getElementById (Js.string "cancel-btn") in
  Js.Opt.iter cancel_btn (fun btn ->
    btn##.onclick := Dom_html.handler (fun _e ->
      Dom.removeChild doc##.body dialog;
      Js._true));

  (* Create button *)
  let create_btn = doc##getElementById (Js.string "create-btn") in
  Js.Opt.iter create_btn (fun btn ->
    btn##.onclick := Dom_html.handler (fun _e ->
      (* Read form values *)
      let severity_el = doc##getElementById (Js.string "severity-select") in
      let desc_el = doc##getElementById (Js.string "description-input") in
      let severity = Js.Opt.case severity_el
        (fun () -> "3")
        (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
      let description = Js.Opt.case desc_el
        (fun () -> "")
        (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in

      (* Send to server via WebSocket *)
      let msg = Printf.sprintf
        {|{"type":"push_events","events":[{"type":"incident_created","position":{"lat":%f,"lng":%f,"timestamp":%f},"severity":"P%s","description":"%s"}]}|}
        lat lng (Js.to_float (new%js Js.date_now)##getTime /. 1000.0)
        severity description
      in
      send_message msg;

      (* Add marker to map *)
      Map_view.add_incident_marker ~lat ~lng
        ~popup_text:(Printf.sprintf "P%s: %s" severity description);

      (* Close dialog *)
      Dom.removeChild doc##.body dialog;
      Js._true))
