open Js_of_ocaml
open Shared.Escape

let ws_ref : WebSockets.webSocket Js.t option ref = ref None

let set_ws ws = ws_ref := Some ws

let send_message msg =
  match !ws_ref with
  | Some ws when ws##.readyState = WebSockets.OPEN ->
    ws##send (Js.string msg)
  | _ -> ()

let json_parse (s : string) : 'a Js.t =
  Js.Unsafe.fun_call
    (Js.Unsafe.js_expr "JSON.parse")
    [| Js.Unsafe.inject (Js.string s) |]

let get_field obj field =
  Js.Unsafe.get obj (Js.string field)

let get_string obj field =
  Js.to_string (get_field obj field)

let get_opt_string obj field =
  let v = get_field obj field in
  if Js.Optdef.test (Js.Optdef.return v) &&
     Js.to_string (Js.typeof v) = "string" then
    Some (Js.to_string v)
  else
    None

let auth_request meth url body on_success =
  let open XmlHttpRequest in
  let req = create () in
  req##_open (Js.string meth) (Js.string url) Js._true;
  (match Login_view.get_token () with
   | Some t ->
     req##setRequestHeader (Js.string "Authorization")
       (Js.string ("Bearer " ^ t))
   | None -> ());
  (match body with
   | Some _ ->
     req##setRequestHeader (Js.string "Content-Type")
       (Js.string "application/json")
   | None -> ());
  req##.onreadystatechange := Js.wrap_callback (fun () ->
    if req##.readyState = XmlHttpRequest.DONE then begin
      if req##.status = 200 then begin
        let data = Js.Opt.case req##.responseText (fun () -> "") Js.to_string in
        on_success data
      end else if req##.status = 401 then begin
        Login_view.clear_session ();
        Dom_html.window##.location##reload
      end
    end);
  (match body with
   | Some b -> req##send (Js.some (Js.string b))
   | None -> req##send Js.null)

let auth_get url on_success = auth_request "GET" url None on_success

let render_incident_item doc container obj =
  let id = get_string obj "id" in
  let status = get_string obj "status" in
  let severity = get_string obj "severity" in
  let desc = match get_opt_string obj "description" with
    | Some d -> d | None -> ""
  in
  let item = Dom_html.createDiv doc in
  item##.className := Js.string "incident-item";
  item##.innerHTML := Js.string (Printf.sprintf
    {|<span class="severity %s">%s</span>
      <span class="incident-id">%s</span>
      <span class="incident-status">%s</span>
      <div class="incident-desc">%s</div>|}
    (html_escape severity) (html_escape severity)
    (html_escape (String.sub id 0 (min 8 (String.length id))))
    (html_escape status) (html_escape desc));
  Dom.appendChild container item

let render_unit_item doc container obj =
  let id = get_string obj "id" in
  let name = get_string obj "name" in
  let status_v = get_field obj "status" in
  let status_str =
    if Js.to_string (Js.typeof status_v) = "string" then
      Js.to_string status_v
    else
      match get_opt_string status_v "status" with
      | Some s -> s | None -> "unknown"
  in
  let item = Dom_html.createDiv doc in
  item##.className := Js.string "unit-item";
  item##.innerHTML := Js.string (Printf.sprintf
    {|<span class="unit-name">%s</span>
      <span class="unit-id">%s</span>
      <span class="unit-status %s">%s</span>|}
    (html_escape name)
    (html_escape (String.sub id 0 (min 8 (String.length id))))
    (html_escape status_str) (html_escape status_str));
  Dom.appendChild container item

let populate_list element_id json_str render_fn =
  let doc = Dom_html.document in
  let container = doc##getElementById (Js.string element_id) in
  Js.Opt.iter container (fun el ->
    el##.innerHTML := Js.string "";
    try
      let arr = json_parse json_str in
      let len : int = Js.Unsafe.get arr (Js.string "length") in
      for i = 0 to len - 1 do
        let obj = Js.Unsafe.get arr i in
        render_fn doc el obj
      done
    with _ -> ())

let fetch_incidents () =
  auth_get "/api/incidents" (fun data ->
    populate_list "incident-list" data render_incident_item)

let fetch_units () =
  auth_get "/api/units" (fun data ->
    populate_list "unit-list" data render_unit_item)

let init () =
  fetch_incidents ();
  fetch_units ()

let handle_message data =
  try
    let j = json_parse data in
    let msg_type = get_string j "type" in
    match msg_type with
    | "events" ->
      fetch_incidents ();
      fetch_units ()
    | "pong" -> ()
    | "error" ->
      let msg = match get_opt_string j "message" with
        | Some m -> m | None -> "unknown error"
      in
      Console.console##warn (Js.string (Printf.sprintf "server error: %s" msg))
    | "sync_complete" -> ()
    | _ -> ()
  with _ -> ()

let on_map_click lat lng =
  let doc = Dom_html.document in
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

  let cancel_btn = doc##getElementById (Js.string "cancel-btn") in
  Js.Opt.iter cancel_btn (fun btn ->
    btn##.onclick := Dom_html.handler (fun _e ->
      Dom.removeChild doc##.body dialog;
      Js._true));

  let create_btn = doc##getElementById (Js.string "create-btn") in
  Js.Opt.iter create_btn (fun btn ->
    btn##.onclick := Dom_html.handler (fun _e ->
      let severity_el = doc##getElementById (Js.string "severity-select") in
      let desc_el = doc##getElementById (Js.string "description-input") in
      let severity = Js.Opt.case severity_el
        (fun () -> "3")
        (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
      let description = Js.Opt.case desc_el
        (fun () -> "")
        (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in

      let msg = Printf.sprintf
        {|{"type":"push_events","events":[{"type":"incident_created","position":{"lat":%f,"lng":%f,"timestamp":%f},"severity":"P%s","description":"%s"}]}|}
        lat lng (Js.to_float (new%js Js.date_now)##getTime /. 1000.0)
        severity (json_escape description)
      in
      send_message msg;

      Map_view.add_incident_marker ~lat ~lng
        ~popup_text:(Printf.sprintf "P%s: %s" (html_escape severity) (html_escape description));

      Dom.removeChild doc##.body dialog;
      Js._true))
