open Js_of_ocaml

let get_session_data () =
  let storage = Dom_html.window##.localStorage in
  let result = ref None in
  Js.Optdef.iter storage (fun s ->
    let v = s##getItem (Js.string "callout_session") in
    Js.Opt.iter v (fun t -> result := Some (Js.to_string t)));
  !result

let auth_get url on_success =
  let open XmlHttpRequest in
  let req = create () in
  req##_open (Js.string "GET") (Js.string url) Js._true;
  (match Login_view.get_token () with
   | Some t ->
     req##setRequestHeader (Js.string "Authorization")
       (Js.string ("Bearer " ^ t))
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
  req##send Js.null

let tab_panels : (string * Dom_html.divElement Js.t) list ref = ref []
let tab_buttons : (string * Dom_html.buttonElement Js.t) list ref = ref []
let map_initialized = ref false

let switch_tab name =
  List.iter (fun (n, panel) ->
    let cls = Js.to_string panel##.className in
    let base = List.filter (fun c -> c <> "active")
      (String.split_on_char ' ' cls) in
    let new_cls = if n = name then base @ ["active"] else base in
    panel##.className := Js.string (String.concat " " new_cls)
  ) !tab_panels;
  List.iter (fun (n, btn) ->
    if n = name then
      btn##.className := Js.string "tab-btn active"
    else
      btn##.className := Js.string "tab-btn"
  ) !tab_buttons;
  if name = "map" && not !map_initialized then begin
    map_initialized := true;
    ignore (Dom_html.window##setTimeout
      (Js.wrap_callback (fun () -> Map_view.init "map"))
      (Js.number_of_float 100.0))
  end

let popout_tab name =
  let loc = Dom_html.window##.location in
  let origin = Js.to_string loc##.origin in
  let url = origin ^ "/#tab=" ^ name in
  let features = "width=900,height=700,menubar=no,toolbar=no,location=no" in
  ignore (Dom_html.window##open_
    (Js.string url) (Js.string ("callout_" ^ name)) (Js.some (Js.string features)))

let build_app (me_json : string) =
  let doc = Dom_html.document in
  let me = Js.Unsafe.fun_call
    (Js.Unsafe.js_expr "JSON.parse")
    [| Js.Unsafe.inject (Js.string me_json) |] in

  let display_name =
    let v = Js.Unsafe.get me (Js.string "display_name") in
    if Js.to_string (Js.typeof v) = "string" then Js.to_string v
    else "Operator" in
  let authority : int = Js.Unsafe.get me (Js.string "authority") in
  let role_name =
    let v = Js.Unsafe.get me (Js.string "role_name") in
    if Js.to_string (Js.typeof v) = "string" then Js.to_string v
    else
      (match authority with
       | 0 -> "Dispatcher" | 1 -> "IC" | 2 -> "Crew Leader"
       | 3 -> "Field Unit" | _ -> "Unknown") in
  let role_id =
    let v = Js.Unsafe.get me (Js.string "role_id") in
    if Js.to_string (Js.typeof v) = "string" then Js.to_string v
    else "" in

  let panels = Js.Unsafe.get me (Js.string "panels") in
  let panel_count : int =
    if Js.to_string (Js.typeof panels) = "object" then
      Js.Unsafe.get panels (Js.string "length")
    else 0 in

  let has_panel name =
    if panel_count = 0 then true
    else begin
      let found = ref false in
      for i = 0 to panel_count - 1 do
        let p = Js.Unsafe.get panels i in
        let pname = Js.to_string (Js.Unsafe.get p (Js.string "panel")) in
        if pname = name then found := true
      done;
      !found
    end
  in

  let container = Dom_html.createDiv doc in
  container##.className := Js.string "app-container";

  let header = Dom_html.createDiv doc in
  header##.className := Js.string "app-header";

  let title_span = Dom_html.createH1 doc in
  title_span##.innerHTML := Js.string "Callout CAD";
  Dom.appendChild header title_span;

  let status_bar = Dom_html.createDiv doc in
  status_bar##.className := Js.string "status-bar";

  let conn_status = Dom_html.createSpan doc in
  conn_status##.id := Js.string "connection-status";
  conn_status##.className := Js.string "status-offline";
  conn_status##.innerHTML := Js.string "Offline";
  Dom.appendChild status_bar conn_status;

  let user_info = Dom_html.createSpan doc in
  user_info##.className := Js.string "user-info";
  user_info##.innerHTML := Js.string
    (Printf.sprintf "%s | %s" display_name role_name);
  Dom.appendChild status_bar user_info;

  if authority = 0 then begin
    let admin_btn = Dom_html.createButton doc in
    admin_btn##.className := Js.string "btn-secondary header-btn";
    admin_btn##.innerHTML := Js.string "Admin";
    admin_btn##.onclick := Dom_html.handler (fun _e ->
      let existing = doc##getElementById (Js.string "admin-overlay") in
      Js.Opt.iter existing (fun el -> Dom.removeChild doc##.body el);
      let overlay = Dom_html.createDiv doc in
      overlay##.id := Js.string "admin-overlay";
      overlay##.className := Js.string "admin-overlay";
      let close_bar = Dom_html.createDiv doc in
      close_bar##.className := Js.string "admin-close-bar";
      let close_btn = Dom_html.createButton doc in
      close_btn##.className := Js.string "close-btn";
      close_btn##.innerHTML := Js.string "X";
      close_btn##.onclick := Dom_html.handler (fun _e ->
        Dom.removeChild doc##.body overlay;
        Js._true);
      Dom.appendChild close_bar close_btn;
      Dom.appendChild overlay close_bar;
      let admin_panel = Admin_view.init () in
      Dom.appendChild overlay admin_panel;
      Dom.appendChild doc##.body overlay;
      Js._true);
    Dom.appendChild status_bar admin_btn
  end;

  let logout_btn = Dom_html.createButton doc in
  logout_btn##.className := Js.string "btn-secondary header-btn";
  logout_btn##.innerHTML := Js.string "Logout";
  logout_btn##.onclick := Dom_html.handler (fun _e ->
    let open XmlHttpRequest in
    let req = create () in
    req##_open (Js.string "POST") (Js.string "/api/logout") Js._true;
    (match Login_view.get_token () with
     | Some t ->
       req##setRequestHeader (Js.string "Authorization")
         (Js.string ("Bearer " ^ t))
     | None -> ());
    req##send Js.null;
    Login_view.clear_session ();
    Dom_html.window##.location##reload;
    Js._true);
  Dom.appendChild status_bar logout_btn;

  Dom.appendChild header status_bar;
  Dom.appendChild container header;

  let tab_bar = Dom_html.createDiv doc in
  tab_bar##.className := Js.string "tab-bar";

  let tab_content = Dom_html.createDiv doc in
  tab_content##.className := Js.string "tab-content";

  let add_tab name label =
    let btn = Dom_html.createButton doc in
    btn##.className := Js.string "tab-btn";
    btn##.innerHTML := Js.string label;
    btn##.onclick := Dom_html.handler (fun _e ->
      switch_tab name; Js._true);
    Dom.appendChild tab_bar btn;

    let popout = Dom_html.createButton doc in
    popout##.className := Js.string "tab-popout";
    popout##.innerHTML := Js.string "^";
    popout##setAttribute (Js.string "title") (Js.string "Open in new window");
    popout##.onclick := Dom_html.handler (fun _e ->
      popout_tab name; Js._true);
    Dom.appendChild tab_bar popout;

    let panel = Dom_html.createDiv doc in
    panel##.className := Js.string "tab-panel";
    Dom.appendChild tab_content panel;

    tab_panels := (name, panel) :: !tab_panels;
    tab_buttons := (name, btn) :: !tab_buttons;
    panel
  in

  if has_panel "incidents" || has_panel "dispatch" then begin
    let panel = add_tab "dispatch" "Dispatch" in
    panel##.className := Js.string "tab-panel dispatch-panel";

    let form_area = Dom_html.createDiv doc in
    form_area##.className := Js.string "dispatch-form-area";

    let form_h = Dom_html.createH2 doc in
    form_h##.innerHTML := Js.string "Event Entry";
    Dom.appendChild form_area form_h;

    let il_h = Dom_html.createH2 doc in
    il_h##.innerHTML := Js.string "Incidents";
    il_h##.style##.marginTop := Js.string "16px";
    Dom.appendChild form_area il_h;

    let il = Dom_html.createDiv doc in
    il##.id := Js.string "incident-list";
    il##.className := Js.string "sidebar-list";
    Dom.appendChild form_area il;

    if has_panel "units" then begin
      let ul_h = Dom_html.createH2 doc in
      ul_h##.innerHTML := Js.string "Units";
      ul_h##.style##.marginTop := Js.string "16px";
      Dom.appendChild form_area ul_h;

      let ul = Dom_html.createDiv doc in
      ul##.id := Js.string "unit-list";
      ul##.className := Js.string "sidebar-list";
      Dom.appendChild form_area ul
    end;

    Dom.appendChild panel form_area;

    let table_area = Dom_html.createDiv doc in
    table_area##.className := Js.string "event-table-area";
    table_area##.innerHTML := Js.string
      {|<table class="event-table">
          <thead><tr>
            <th>P</th><th>Status</th><th>Time</th>
            <th>ID</th><th>Type</th><th>Description</th><th>Location</th>
          </tr></thead>
          <tbody id="event-table-body"></tbody>
        </table>|};
    Dom.appendChild panel table_area
  end;

  if has_panel "map" then begin
    let panel = add_tab "map" "Map" in
    panel##.className := Js.string "tab-panel map-panel";

    let map_div = Dom_html.createDiv doc in
    map_div##.id := Js.string "map";
    map_div##.className := Js.string "map-container";
    Dom.appendChild panel map_div
  end;

  if has_panel "sops" && role_id <> "" then begin
    let panel = add_tab "sops" "SOPs" in
    let sop_panel = Sop_view.init role_id in
    Dom.appendChild panel sop_panel
  end;

  Dom.appendChild container tab_bar;
  Dom.appendChild container tab_content;

  let body = doc##.body in
  body##.innerHTML := Js.string "";
  Dom.appendChild body container;

  switch_tab "dispatch";

  Dispatch_view.init ();
  if has_panel "map" then
    Map_view.set_on_click_callback Dispatch_view.on_map_click;

  let ws_url =
    let loc = Dom_html.window##.location in
    let protocol = Js.to_string loc##.protocol in
    let host = Js.to_string loc##.host in
    let ws_proto = if protocol = "https:" then "wss:" else "ws:" in
    ws_proto ^ "//" ^ host ^ "/ws"
  in

  let ws = new%js WebSockets.webSocket (Js.string ws_url) in

  ws##.onopen := Dom.handler (fun _e ->
    let status = doc##getElementById (Js.string "connection-status") in
    Js.Opt.iter status (fun el ->
      el##.className := Js.string "status-online";
      el##.innerHTML := Js.string "Online");
    Js._true);

  ws##.onclose := Dom.handler (fun _e ->
    let status = doc##getElementById (Js.string "connection-status") in
    Js.Opt.iter status (fun el ->
      el##.className := Js.string "status-offline";
      el##.innerHTML := Js.string "Offline");
    Js._true);

  ws##.onmessage := Dom.handler (fun e ->
    let data = Js.to_string e##.data in
    Dispatch_view.handle_message data;
    Js._true);

  Dispatch_view.set_ws ws

let () =
  let open XmlHttpRequest in
  let req = create () in
  req##_open (Js.string "GET") (Js.string "/api/me") Js._true;
  (match Login_view.get_token () with
   | Some t ->
     req##setRequestHeader (Js.string "Authorization")
       (Js.string ("Bearer " ^ t))
   | None -> ());
  req##.onreadystatechange := Js.wrap_callback (fun () ->
    if req##.readyState = DONE then begin
      if req##.status = 200 then begin
        let data = Js.Opt.case req##.responseText (fun () -> "") Js.to_string in
        build_app data
      end else begin
        let doc = Dom_html.document in
        let login = Login_view.render (fun () ->
          match get_session_data () with
          | Some data -> build_app data
          | None -> auth_get "/api/me" build_app
        ) in
        Dom.appendChild doc##.body login
      end
    end);
  req##send Js.null
