(* Callout CAD — Main Application Shell
 *
 * Compiled to JavaScript via js_of_ocaml.
 * Manages the top-level UI: map view + dispatch board.
 *)

open Js_of_ocaml

let () =
  let doc = Dom_html.document in

  (* Create main layout *)
  let container = Dom_html.createDiv doc in
  container##.id := Js.string "app";
  container##.className := Js.string "app-container";

  (* Header *)
  let header = Dom_html.createDiv doc in
  header##.className := Js.string "app-header";
  header##.innerHTML := Js.string
    {|<h1>Callout CAD</h1>
      <div class="status-bar">
        <span id="connection-status" class="status-offline">Offline</span>
        <span id="ws-count">0 units</span>
      </div>|};
  Dom.appendChild container header;

  (* Main content area: map + sidebar *)
  let main = Dom_html.createDiv doc in
  main##.className := Js.string "app-main";

  (* Map container *)
  let map_div = Dom_html.createDiv doc in
  map_div##.id := Js.string "map";
  map_div##.className := Js.string "map-container";
  Dom.appendChild main map_div;

  (* Sidebar: incident list *)
  let sidebar = Dom_html.createDiv doc in
  sidebar##.className := Js.string "sidebar";
  sidebar##.innerHTML := Js.string
    {|<h2>Incidents</h2>
      <div id="incident-list" class="incident-list"></div>
      <h2>Units</h2>
      <div id="unit-list" class="unit-list"></div>|};
  Dom.appendChild main sidebar;

  Dom.appendChild container main;

  (* Mount to body *)
  let body = doc##.body in
  Dom.appendChild body container;

  (* Initialize map *)
  Map_view.init "map";

  (* Initialize dispatch board *)
  Dispatch_view.init ();

  (* Wire map clicks to dispatch view (breaks circular dependency) *)
  Map_view.set_on_click_callback Dispatch_view.on_map_click;

  (* Connect WebSocket *)
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

  (* Store WebSocket reference for sending *)
  Dispatch_view.set_ws ws
