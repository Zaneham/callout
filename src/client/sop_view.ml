open Js_of_ocaml
open Shared.Escape

let container_ref : Dom_html.divElement Js.t option ref = ref None

let fetch_and_render role_id event_type_id =
  match !container_ref with
  | None -> ()
  | Some container ->
    let url = Printf.sprintf "/api/roles/%s/sops%s"
      role_id
      (match event_type_id with
       | Some et -> "?event_type_id=" ^ et
       | None -> "")
    in

    let token = Login_view.get_token () in
    let open XmlHttpRequest in
    let req = create () in
    req##_open (Js.string "GET") (Js.string url) Js._true;
    (match token with
     | Some t ->
       req##setRequestHeader (Js.string "Authorization")
         (Js.string ("Bearer " ^ t))
     | None -> ());
    req##.onreadystatechange := Js.wrap_callback (fun () ->
      if req##.readyState = XmlHttpRequest.DONE && req##.status = 200 then begin
        let data = Js.Opt.case req##.responseText (fun () -> "[]") Js.to_string in
        let doc = Dom_html.document in
        let list_el = container##querySelector (Js.string ".sop-list") in
        Js.Opt.iter list_el (fun el ->
          el##.innerHTML := Js.string "";
          try
            let arr = Js.Unsafe.fun_call
              (Js.Unsafe.js_expr "JSON.parse")
              [| Js.Unsafe.inject (Js.string data) |] in
            let len : int = Js.Unsafe.get arr (Js.string "length") in
            if len = 0 then
              el##.innerHTML := Js.string
                {|<div class="sop-empty">No SOPs configured for this role</div>|}
            else
              for i = 0 to len - 1 do
                let obj = Js.Unsafe.get arr i in
                let title = Js.to_string (Js.Unsafe.get obj (Js.string "title")) in
                let content = Js.to_string (Js.Unsafe.get obj (Js.string "content")) in
                let links_raw = Js.Unsafe.get obj (Js.string "links_json") in

                let item = Dom_html.createDiv doc in
                item##.className := Js.string "sop-item";

                let header = Dom_html.createDiv doc in
                header##.className := Js.string "sop-header";
                header##.innerHTML := Js.string
                  (Printf.sprintf {|<span class="sop-title">%s</span>|}
                     (html_escape title));
                Dom.appendChild item header;

                let body = Dom_html.createDiv doc in
                body##.className := Js.string "sop-body";
                body##.style##.display := Js.string "none";
                body##.innerHTML := Js.string
                  (Printf.sprintf {|<div class="sop-content">%s</div>|}
                     (html_escape content));

                (if Js.to_string (Js.typeof links_raw) = "string" then begin
                  let links_str = Js.to_string links_raw in
                  if links_str <> "" then begin
                    try
                      let links_arr = Js.Unsafe.fun_call
                        (Js.Unsafe.js_expr "JSON.parse")
                        [| Js.Unsafe.inject (Js.string links_str) |] in
                      let links_len : int =
                        Js.Unsafe.get links_arr (Js.string "length") in
                      if links_len > 0 then begin
                        let links_div = Dom_html.createDiv doc in
                        links_div##.className := Js.string "sop-links";
                        for j = 0 to links_len - 1 do
                          let link_obj = Js.Unsafe.get links_arr j in
                          let label = Js.to_string
                            (Js.Unsafe.get link_obj (Js.string "label")) in
                          let url = Js.to_string
                            (Js.Unsafe.get link_obj (Js.string "url")) in
                          let btn = Dom_html.createA doc in
                          btn##.className := Js.string "sop-link-btn";
                          btn##.innerHTML := Js.string (html_escape label);
                          btn##setAttribute (Js.string "href") (Js.string url);
                          btn##setAttribute (Js.string "target") (Js.string "_blank");
                          btn##setAttribute (Js.string "rel")
                            (Js.string "noopener noreferrer");
                          Dom.appendChild links_div btn
                        done;
                        Dom.appendChild body links_div
                      end
                    with _ -> ()
                  end
                end);

                Dom.appendChild item body;

                header##.onclick := Dom_html.handler (fun _e ->
                  let current = Js.to_string body##.style##.display in
                  body##.style##.display := Js.string
                    (if current = "none" then "block" else "none");
                  Js._true);

                Dom.appendChild el item
              done
          with _ -> ())
      end);
    req##send Js.null

let init role_id =
  let doc = Dom_html.document in
  let container = Dom_html.createDiv doc in
  container##.className := Js.string "sop-panel";
  container##.innerHTML := Js.string
    {|<h2>SOPs</h2>
      <div class="sop-list"></div>|};
  container_ref := Some container;
  fetch_and_render role_id None;
  container

let refresh role_id event_type_id =
  fetch_and_render role_id event_type_id
