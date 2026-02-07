(* Callout CAD — Map View
 *
 * Leaflet map integration via js_of_ocaml FFI.
 * Map is the primary view — incidents and units are shown as markers.
 *)

open Js_of_ocaml

(* Leaflet FFI bindings — minimal surface area *)
let leaflet = Js.Unsafe.global##._L

let map_ref : Js.Unsafe.any option ref = ref None

(* Callback set by app.ml to break the map_view <-> dispatch_view cycle *)
let on_click_callback : (float -> float -> unit) ref = ref (fun _ _ -> ())

let set_on_click_callback f = on_click_callback := f

let init element_id =
  let map = Js.Unsafe.meth_call leaflet "map"
    [| Js.Unsafe.inject (Js.string element_id) |] in

  (* Default view: continental US center *)
  let _view = Js.Unsafe.meth_call map "setView"
    [| Js.Unsafe.inject (Js.array [| Js.Unsafe.inject 39.8283;
                                      Js.Unsafe.inject (-98.5795) |]);
       Js.Unsafe.inject 5 |] in

  (* OpenStreetMap tile layer — self-hostable *)
  let tile_url = Js.string "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" in
  let opts = Js.Unsafe.obj [|
    ("attribution", Js.Unsafe.inject (Js.string
      "&copy; <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a>"));
    ("maxZoom", Js.Unsafe.inject 19);
  |] in
  let tile_layer = Js.Unsafe.meth_call leaflet "tileLayer"
    [| Js.Unsafe.inject tile_url; Js.Unsafe.inject opts |] in
  let _added = Js.Unsafe.meth_call tile_layer "addTo"
    [| Js.Unsafe.inject map |] in

  (* Click handler: create incident at clicked location *)
  let on_click = Js.wrap_callback (fun e ->
    let latlng = Js.Unsafe.get e (Js.string "latlng") in
    let lat = Js.Unsafe.get latlng (Js.string "lat") in
    let lng = Js.Unsafe.get latlng (Js.string "lng") in
    !on_click_callback (Js.float_of_number lat) (Js.float_of_number lng)
  ) in
  let _handler = Js.Unsafe.meth_call map "on"
    [| Js.Unsafe.inject (Js.string "click"); Js.Unsafe.inject on_click |] in

  map_ref := Some map

let add_incident_marker ~lat ~lng ~popup_text =
  match !map_ref with
  | None -> ()
  | Some map ->
    let marker = Js.Unsafe.meth_call leaflet "marker"
      [| Js.Unsafe.inject (Js.array [| Js.Unsafe.inject lat;
                                        Js.Unsafe.inject lng |]) |] in
    let _added = Js.Unsafe.meth_call marker "addTo"
      [| Js.Unsafe.inject map |] in
    let _popup = Js.Unsafe.meth_call marker "bindPopup"
      [| Js.Unsafe.inject (Js.string popup_text) |] in
    ()

let add_unit_marker ~lat ~lng ~name =
  match !map_ref with
  | None -> ()
  | Some map ->
    let icon_opts = Js.Unsafe.obj [|
      ("className", Js.Unsafe.inject (Js.string "unit-marker"));
      ("html", Js.Unsafe.inject (Js.string name));
      ("iconSize", Js.Unsafe.inject (Js.array [| Js.Unsafe.inject 40;
                                                   Js.Unsafe.inject 40 |]));
    |] in
    let icon = Js.Unsafe.meth_call leaflet "divIcon"
      [| Js.Unsafe.inject icon_opts |] in
    let marker_opts = Js.Unsafe.obj [|
      ("icon", Js.Unsafe.inject icon);
    |] in
    let marker = Js.Unsafe.meth_call leaflet "marker"
      [| Js.Unsafe.inject (Js.array [| Js.Unsafe.inject lat;
                                        Js.Unsafe.inject lng |]);
         Js.Unsafe.inject marker_opts |] in
    let _added = Js.Unsafe.meth_call marker "addTo"
      [| Js.Unsafe.inject map |] in
    ()
