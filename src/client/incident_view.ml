(* Callout CAD — Incident Detail View
 *
 * Displays full incident details, event timeline,
 * assigned units, and status controls.
 *)

open Js_of_ocaml

let show_incident _incident_id =
  let doc = Dom_html.document in
  let panel = Dom_html.createDiv doc in
  panel##.className := Js.string "incident-detail";
  panel##.innerHTML := Js.string
    {|<div class="incident-header">
        <h2>Incident Detail</h2>
        <button class="close-btn">&times;</button>
      </div>
      <div class="incident-body">
        <div class="incident-status">
          <span class="status-badge">Loading...</span>
        </div>
        <div class="incident-timeline" id="incident-timeline">
        </div>
        <div class="incident-units" id="incident-units">
          <h3>Assigned Units</h3>
        </div>
        <div class="incident-notes" id="incident-notes">
          <h3>Notes</h3>
          <textarea id="note-input" placeholder="Add a note..."></textarea>
          <button id="add-note-btn" class="btn-primary">Add Note</button>
        </div>
      </div>|};
  Dom.appendChild doc##.body panel;

  (* Close button handler *)
  let close_btns = panel##querySelectorAll (Js.string ".close-btn") in
  let first_btn = close_btns##item 0 in
  Js.Opt.iter first_btn (fun btn ->
    (Js.Unsafe.coerce btn)##.onclick := Dom_html.handler (fun _e ->
      Dom.removeChild doc##.body panel;
      Js._true))
