open Js_of_ocaml
open Shared.Escape

let get_auth_header () =
  match Login_view.get_token () with
  | Some t -> "Bearer " ^ t
  | None -> ""

let api_get url callback =
  let open XmlHttpRequest in
  let req = create () in
  req##_open (Js.string "GET") (Js.string url) Js._true;
  req##setRequestHeader (Js.string "Authorization")
    (Js.string (get_auth_header ()));
  req##.onreadystatechange := Js.wrap_callback (fun () ->
    if req##.readyState = XmlHttpRequest.DONE && req##.status = 200 then begin
      let data = Js.Opt.case req##.responseText (fun () -> "[]") Js.to_string in
      callback data
    end);
  req##send Js.null

let api_post url body callback =
  let open XmlHttpRequest in
  let req = create () in
  req##_open (Js.string "POST") (Js.string url) Js._true;
  req##setRequestHeader (Js.string "Content-Type")
    (Js.string "application/json");
  req##setRequestHeader (Js.string "Authorization")
    (Js.string (get_auth_header ()));
  req##.onreadystatechange := Js.wrap_callback (fun () ->
    if req##.readyState = XmlHttpRequest.DONE then
      callback req##.status);
  req##send (Js.some (Js.string body))

let api_put url body callback =
  let open XmlHttpRequest in
  let req = create () in
  req##_open (Js.string "PUT") (Js.string url) Js._true;
  req##setRequestHeader (Js.string "Content-Type")
    (Js.string "application/json");
  req##setRequestHeader (Js.string "Authorization")
    (Js.string (get_auth_header ()));
  req##.onreadystatechange := Js.wrap_callback (fun () ->
    if req##.readyState = XmlHttpRequest.DONE then
      callback req##.status);
  req##send (Js.some (Js.string body))

let all_panels = ["dispatch"; "incidents"; "units"; "map"; "sops"; "notes"; "admin"]

let render_role_config content_el role_id role_name =
  let doc = Dom_html.document in
  content_el##.innerHTML := Js.string
    (Printf.sprintf {|<h3>%s — Configuration</h3>
      <button id="back-to-roles" class="btn-secondary">Back to Roles</button>
      <div style="margin-top:16px">
        <h4 style="color:#e94560;margin-bottom:8px">Panels</h4>
        <p style="color:#8888aa;font-size:11px;margin-bottom:8px">
          Which panels this role can see. Check to enable.</p>
        <div id="panel-config"></div>
      </div>
      <div style="margin-top:16px">
        <h4 style="color:#e94560;margin-bottom:8px">Permissions</h4>
        <p style="color:#8888aa;font-size:11px;margin-bottom:8px">
          View and edit permissions per panel.</p>
        <div id="perm-config"></div>
      </div>|} (html_escape role_name));

  let back_btn = doc##getElementById (Js.string "back-to-roles") in
  Js.Opt.iter back_btn (fun btn ->
    btn##.onclick := Dom_html.handler (fun _e ->
      ignore role_id;
      Dom_html.window##.location##reload;
      Js._true));

  let panel_el = doc##getElementById (Js.string "panel-config") in
  let perm_el = doc##getElementById (Js.string "perm-config") in

  api_get (Printf.sprintf "/api/roles/%s/panels" role_id) (fun panels_data ->
    Js.Opt.iter panel_el (fun el ->
      let existing_panels = ref [] in
      (try
        let arr = Js.Unsafe.fun_call
          (Js.Unsafe.js_expr "JSON.parse")
          [| Js.Unsafe.inject (Js.string panels_data) |] in
        let len : int = Js.Unsafe.get arr (Js.string "length") in
        for i = 0 to len - 1 do
          let obj = Js.Unsafe.get arr i in
          let pname = Js.to_string (Js.Unsafe.get obj (Js.string "panel")) in
          existing_panels := pname :: !existing_panels
        done
      with _ -> ());

      List.iter (fun pname ->
        let row = Dom_html.createDiv doc in
        row##.style##.cssText := Js.string
          "padding:4px 0;display:flex;align-items:center;gap:8px";

        let cb = Dom_html.createInput ~_type:(Js.string "checkbox") doc in
        if List.mem pname !existing_panels then
          cb##.checked := Js._true;
        cb##.onchange := Dom_html.handler (fun _e ->
          let checked = Js.to_bool cb##.checked in
          if checked then begin
            let body = Printf.sprintf
              {|{"panel":"%s","position":"tab","sort_order":0}|}
              (json_escape pname) in
            api_put (Printf.sprintf "/api/roles/%s/panels" role_id) body
              (fun _status -> ())
          end;
          Js._true);

        let lbl = Dom_html.createSpan doc in
        lbl##.innerHTML := Js.string (html_escape pname);
        lbl##.style##.cssText := Js.string "text-transform:capitalize";

        Dom.appendChild row cb;
        Dom.appendChild row lbl;
        Dom.appendChild el row
      ) all_panels));

  api_get (Printf.sprintf "/api/roles/%s/permissions" role_id) (fun perms_data ->
    Js.Opt.iter perm_el (fun el ->
      let perm_map = Hashtbl.create 16 in
      (try
        let arr = Js.Unsafe.fun_call
          (Js.Unsafe.js_expr "JSON.parse")
          [| Js.Unsafe.inject (Js.string perms_data) |] in
        let len : int = Js.Unsafe.get arr (Js.string "length") in
        for i = 0 to len - 1 do
          let obj = Js.Unsafe.get arr i in
          let pname = Js.to_string (Js.Unsafe.get obj (Js.string "panel")) in
          let cv : int = Js.Unsafe.get obj (Js.string "can_view") in
          let ce : int = Js.Unsafe.get obj (Js.string "can_edit") in
          Hashtbl.replace perm_map pname (cv, ce)
        done
      with _ -> ());

      let tbl = Dom_html.createTable doc in
      tbl##.className := Js.string "event-table";
      tbl##.style##.cssText := Js.string "max-width:500px";
      tbl##.innerHTML := Js.string
        {|<thead><tr><th>Panel</th><th>View</th><th>Edit</th></tr></thead>|};
      let tbody = Dom_html.createTbody doc in
      Dom.appendChild tbl tbody;

      List.iter (fun pname ->
        let (cv, ce) = try Hashtbl.find perm_map pname with Not_found -> (0, 0) in
        let tr = Dom_html.createTr doc in

        let td_name = Dom_html.createTd doc in
        td_name##.innerHTML := Js.string (html_escape pname);
        td_name##.style##.cssText := Js.string "text-transform:capitalize";
        Dom.appendChild tr td_name;

        let td_view = Dom_html.createTd doc in
        let cb_view = Dom_html.createInput ~_type:(Js.string "checkbox") doc in
        if cv = 1 then cb_view##.checked := Js._true;
        cb_view##.onchange := Dom_html.handler (fun _e ->
          let v = if Js.to_bool cb_view##.checked then 1 else 0 in
          let body = Printf.sprintf
            {|{"panel":"%s","can_view":%d,"can_edit":%d}|}
            (json_escape pname) v ce in
          api_put (Printf.sprintf "/api/roles/%s/permissions" role_id) body
            (fun _status -> ());
          Js._true);
        Dom.appendChild td_view cb_view;
        Dom.appendChild tr td_view;

        let td_edit = Dom_html.createTd doc in
        let cb_edit = Dom_html.createInput ~_type:(Js.string "checkbox") doc in
        if ce = 1 then cb_edit##.checked := Js._true;
        cb_edit##.onchange := Dom_html.handler (fun _e ->
          let e = if Js.to_bool cb_edit##.checked then 1 else 0 in
          let body = Printf.sprintf
            {|{"panel":"%s","can_view":%d,"can_edit":%d}|}
            (json_escape pname) cv e in
          api_put (Printf.sprintf "/api/roles/%s/permissions" role_id) body
            (fun _status -> ());
          Js._true);
        Dom.appendChild td_edit cb_edit;
        Dom.appendChild tr td_edit;

        Dom.appendChild tbody tr
      ) all_panels;

      Dom.appendChild el tbl))

let render_roles_tab content_el =
  api_get "/api/roles" (fun data ->
    let doc = Dom_html.document in
    content_el##.innerHTML := Js.string
      {|<h3>Roles</h3>
        <p style="color:#8888aa;font-size:11px;margin-bottom:12px">
          Click a role to configure its panels and permissions.</p>
        <div id="admin-roles-list"></div>|};
    let list_el = doc##getElementById (Js.string "admin-roles-list") in
    Js.Opt.iter list_el (fun el ->
      try
        let arr = Js.Unsafe.fun_call
          (Js.Unsafe.js_expr "JSON.parse")
          [| Js.Unsafe.inject (Js.string data) |] in
        let len : int = Js.Unsafe.get arr (Js.string "length") in
        for i = 0 to len - 1 do
          let obj = Js.Unsafe.get arr i in
          let rid = Js.to_string (Js.Unsafe.get obj (Js.string "id")) in
          let name = Js.to_string (Js.Unsafe.get obj (Js.string "name")) in
          let authority : int = Js.Unsafe.get obj (Js.string "authority") in
          let desc_v = Js.Unsafe.get obj (Js.string "description") in
          let desc = if Js.to_string (Js.typeof desc_v) = "string"
            then Js.to_string desc_v else "" in
          let item = Dom_html.createDiv doc in
          item##.className := Js.string "admin-item";
          item##.style##.cssText := Js.string "cursor:pointer";
          item##.innerHTML := Js.string (Printf.sprintf
            {|<span class="admin-item-name">%s</span>
              <span class="admin-item-meta">Authority: %d</span>
              <span class="admin-item-desc">%s</span>|}
            (html_escape name) authority (html_escape desc));
          item##.onclick := Dom_html.handler (fun _e ->
            render_role_config (Js.Unsafe.coerce content_el) rid name;
            Js._true);
          Dom.appendChild el item
        done
      with _ -> ()))

let rec render_users_tab content_el =
  api_get "/api/users" (fun data ->
    let doc = Dom_html.document in
    content_el##.innerHTML := Js.string
      {|<h3>Users</h3>
        <button id="admin-add-user" class="btn-primary">Add User</button>
        <div id="admin-users-list"></div>
        <div id="admin-user-form" style="display:none">
          <label>Username <input type="text" id="new-username" /></label>
          <label>Display Name <input type="text" id="new-display-name" /></label>
          <label>Password <input type="password" id="new-password" /></label>
          <label>Role
            <select id="new-role-id"></select>
          </label>
          <div class="dialog-buttons">
            <button id="save-user-btn" class="btn-primary">Save</button>
            <button id="cancel-user-btn" class="btn-secondary">Cancel</button>
          </div>
        </div>|};

    let list_el = doc##getElementById (Js.string "admin-users-list") in
    Js.Opt.iter list_el (fun el ->
      try
        let arr = Js.Unsafe.fun_call
          (Js.Unsafe.js_expr "JSON.parse")
          [| Js.Unsafe.inject (Js.string data) |] in
        let len : int = Js.Unsafe.get arr (Js.string "length") in
        for i = 0 to len - 1 do
          let obj = Js.Unsafe.get arr i in
          let username = Js.to_string (Js.Unsafe.get obj (Js.string "username")) in
          let display_name = Js.to_string (Js.Unsafe.get obj (Js.string "display_name")) in
          let role_name = Js.to_string (Js.Unsafe.get obj (Js.string "role_name")) in
          let active : int = Js.Unsafe.get obj (Js.string "active") in
          let item = Dom_html.createDiv doc in
          item##.className := Js.string "admin-item";
          item##.innerHTML := Js.string (Printf.sprintf
            {|<span class="admin-item-name">%s</span>
              <span class="admin-item-meta">%s | %s</span>
              <span class="admin-item-status %s">%s</span>|}
            (html_escape display_name)
            (html_escape username) (html_escape role_name)
            (if active = 1 then "active" else "inactive")
            (if active = 1 then "Active" else "Inactive"));
          Dom.appendChild el item
        done
      with _ -> ());

    let add_btn = doc##getElementById (Js.string "admin-add-user") in
    let form = doc##getElementById (Js.string "admin-user-form") in
    Js.Opt.iter add_btn (fun btn ->
      btn##.onclick := Dom_html.handler (fun _e ->
        Js.Opt.iter form (fun f ->
          (Js.Unsafe.coerce f)##.style##.display := Js.string "block");
        api_get "/api/roles" (fun roles_data ->
          let role_select = doc##getElementById (Js.string "new-role-id") in
          Js.Opt.iter role_select (fun sel ->
            sel##.innerHTML := Js.string "";
            try
              let arr = Js.Unsafe.fun_call
                (Js.Unsafe.js_expr "JSON.parse")
                [| Js.Unsafe.inject (Js.string roles_data) |] in
              let len : int = Js.Unsafe.get arr (Js.string "length") in
              for i = 0 to len - 1 do
                let obj = Js.Unsafe.get arr i in
                let rid = Js.to_string (Js.Unsafe.get obj (Js.string "id")) in
                let rname = Js.to_string (Js.Unsafe.get obj (Js.string "name")) in
                let opt = Dom_html.createOption doc in
                opt##.value := Js.string rid;
                opt##.innerHTML := Js.string (html_escape rname);
                Dom.appendChild sel opt
              done
            with _ -> ()));
        Js._true));

    let cancel_btn = doc##getElementById (Js.string "cancel-user-btn") in
    Js.Opt.iter cancel_btn (fun btn ->
      btn##.onclick := Dom_html.handler (fun _e ->
        Js.Opt.iter form (fun f ->
          (Js.Unsafe.coerce f)##.style##.display := Js.string "none");
        Js._true));

    let save_btn = doc##getElementById (Js.string "save-user-btn") in
    Js.Opt.iter save_btn (fun btn ->
      btn##.onclick := Dom_html.handler (fun _e ->
        let username = Js.Opt.case (doc##getElementById (Js.string "new-username"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let display_name = Js.Opt.case (doc##getElementById (Js.string "new-display-name"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let password = Js.Opt.case (doc##getElementById (Js.string "new-password"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let role_id = Js.Opt.case (doc##getElementById (Js.string "new-role-id"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let body = Printf.sprintf
          {|{"username":"%s","display_name":"%s","password":"%s","role_id":"%s"}|}
          (json_escape username) (json_escape display_name)
          (json_escape password) (json_escape role_id) in
        api_post "/api/users" body (fun status ->
          if status = 201 then
            render_users_tab content_el);
        Js._true)))

let rec render_sops_tab content_el =
  api_get "/api/sops" (fun data ->
    let doc = Dom_html.document in
    content_el##.innerHTML := Js.string
      {|<h3>SOPs</h3>
        <button id="admin-add-sop" class="btn-primary">Add SOP</button>
        <div id="admin-sops-list"></div>
        <div id="admin-sop-form" style="display:none">
          <label>Title <input type="text" id="new-sop-title" /></label>
          <label>Content <textarea id="new-sop-content" rows="6"></textarea></label>
          <label>Links JSON <textarea id="new-sop-links" rows="2"
            placeholder='[{"label":"Link","url":"https://..."}]'></textarea></label>
          <div class="dialog-buttons">
            <button id="save-sop-btn" class="btn-primary">Save</button>
            <button id="cancel-sop-btn" class="btn-secondary">Cancel</button>
          </div>
        </div>|};

    let list_el = doc##getElementById (Js.string "admin-sops-list") in
    Js.Opt.iter list_el (fun el ->
      try
        let arr = Js.Unsafe.fun_call
          (Js.Unsafe.js_expr "JSON.parse")
          [| Js.Unsafe.inject (Js.string data) |] in
        let len : int = Js.Unsafe.get arr (Js.string "length") in
        for i = 0 to len - 1 do
          let obj = Js.Unsafe.get arr i in
          let title = Js.to_string (Js.Unsafe.get obj (Js.string "title")) in
          let item = Dom_html.createDiv doc in
          item##.className := Js.string "admin-item";
          item##.innerHTML := Js.string (Printf.sprintf
            {|<span class="admin-item-name">%s</span>|}
            (html_escape title));
          Dom.appendChild el item
        done
      with _ -> ());

    let form = doc##getElementById (Js.string "admin-sop-form") in
    let add_btn = doc##getElementById (Js.string "admin-add-sop") in
    Js.Opt.iter add_btn (fun btn ->
      btn##.onclick := Dom_html.handler (fun _e ->
        Js.Opt.iter form (fun f ->
          (Js.Unsafe.coerce f)##.style##.display := Js.string "block");
        Js._true));

    let cancel_btn = doc##getElementById (Js.string "cancel-sop-btn") in
    Js.Opt.iter cancel_btn (fun btn ->
      btn##.onclick := Dom_html.handler (fun _e ->
        Js.Opt.iter form (fun f ->
          (Js.Unsafe.coerce f)##.style##.display := Js.string "none");
        Js._true));

    let save_btn = doc##getElementById (Js.string "save-sop-btn") in
    Js.Opt.iter save_btn (fun btn ->
      btn##.onclick := Dom_html.handler (fun _e ->
        let title = Js.Opt.case (doc##getElementById (Js.string "new-sop-title"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let content = Js.Opt.case (doc##getElementById (Js.string "new-sop-content"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let links = Js.Opt.case (doc##getElementById (Js.string "new-sop-links"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let body = Printf.sprintf
          {|{"title":"%s","content":"%s","links_json":"%s"}|}
          (json_escape title) (json_escape content) (json_escape links) in
        api_post "/api/sops" body (fun status ->
          if status = 201 then
            render_sops_tab content_el);
        Js._true)))

let rec render_event_types_tab content_el =
  api_get "/api/event-types" (fun data ->
    let doc = Dom_html.document in
    content_el##.innerHTML := Js.string
      {|<h3>Event Types</h3>
        <button id="admin-add-et" class="btn-primary">Add Event Type</button>
        <div id="admin-et-list"></div>
        <div id="admin-et-form" style="display:none">
          <label>Name <input type="text" id="new-et-name" /></label>
          <label>Icon <input type="text" id="new-et-icon" placeholder="optional" /></label>
          <label>Color <input type="text" id="new-et-color" placeholder="#ff0000" /></label>
          <div class="dialog-buttons">
            <button id="save-et-btn" class="btn-primary">Save</button>
            <button id="cancel-et-btn" class="btn-secondary">Cancel</button>
          </div>
        </div>|};

    let list_el = doc##getElementById (Js.string "admin-et-list") in
    Js.Opt.iter list_el (fun el ->
      try
        let arr = Js.Unsafe.fun_call
          (Js.Unsafe.js_expr "JSON.parse")
          [| Js.Unsafe.inject (Js.string data) |] in
        let len : int = Js.Unsafe.get arr (Js.string "length") in
        for i = 0 to len - 1 do
          let obj = Js.Unsafe.get arr i in
          let name = Js.to_string (Js.Unsafe.get obj (Js.string "name")) in
          let item = Dom_html.createDiv doc in
          item##.className := Js.string "admin-item";
          item##.innerHTML := Js.string (Printf.sprintf
            {|<span class="admin-item-name">%s</span>|}
            (html_escape name));
          Dom.appendChild el item
        done
      with _ -> ());

    let form = doc##getElementById (Js.string "admin-et-form") in
    let add_btn = doc##getElementById (Js.string "admin-add-et") in
    Js.Opt.iter add_btn (fun btn ->
      btn##.onclick := Dom_html.handler (fun _e ->
        Js.Opt.iter form (fun f ->
          (Js.Unsafe.coerce f)##.style##.display := Js.string "block");
        Js._true));

    let cancel_btn = doc##getElementById (Js.string "cancel-et-btn") in
    Js.Opt.iter cancel_btn (fun btn ->
      btn##.onclick := Dom_html.handler (fun _e ->
        Js.Opt.iter form (fun f ->
          (Js.Unsafe.coerce f)##.style##.display := Js.string "none");
        Js._true));

    let save_btn = doc##getElementById (Js.string "save-et-btn") in
    Js.Opt.iter save_btn (fun btn ->
      btn##.onclick := Dom_html.handler (fun _e ->
        let name = Js.Opt.case (doc##getElementById (Js.string "new-et-name"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let icon = Js.Opt.case (doc##getElementById (Js.string "new-et-icon"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let color = Js.Opt.case (doc##getElementById (Js.string "new-et-color"))
          (fun () -> "") (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
        let body = Printf.sprintf
          {|{"name":"%s","icon":"%s","color":"%s"}|}
          (json_escape name) (json_escape icon) (json_escape color) in
        api_post "/api/event-types" body (fun status ->
          if status = 201 then
            render_event_types_tab content_el);
        Js._true)))

let render () =
  let doc = Dom_html.document in
  let panel = Dom_html.createDiv doc in
  panel##.className := Js.string "admin-panel";
  panel##.innerHTML := Js.string
    {|<div class="admin-header">
        <h2>Administration</h2>
      </div>
      <div class="admin-tabs">
        <button class="admin-tab active" data-tab="roles">Roles & Panels</button>
        <button class="admin-tab" data-tab="users">Users</button>
        <button class="admin-tab" data-tab="sops">SOPs</button>
        <button class="admin-tab" data-tab="event-types">Event Types</button>
      </div>
      <div class="admin-content" id="admin-content"></div>|};

  let content_el_opt = panel##querySelector (Js.string "#admin-content") in
  Js.Opt.iter content_el_opt (fun content_el ->
    let tabs = panel##querySelectorAll (Js.string ".admin-tab") in
    let tab_count = tabs##.length in
    for i = 0 to tab_count - 1 do
      let tab_opt = tabs##item i in
      Js.Opt.iter tab_opt (fun tab ->
        (Js.Unsafe.coerce tab)##.onclick := Dom_html.handler (fun _e ->
          for j = 0 to tab_count - 1 do
            let t = tabs##item j in
            Js.Opt.iter t (fun t ->
              ignore ((Js.Unsafe.coerce t)##.classList##remove (Js.string "active")))
          done;
          ignore ((Js.Unsafe.coerce tab)##.classList##add (Js.string "active"));
          let tab_name = Js.to_string
            ((Js.Unsafe.coerce tab)##getAttribute (Js.string "data-tab")) in
          (match tab_name with
           | "roles" -> render_roles_tab (Js.Unsafe.coerce content_el)
           | "users" -> render_users_tab (Js.Unsafe.coerce content_el)
           | "sops" -> render_sops_tab (Js.Unsafe.coerce content_el)
           | "event-types" -> render_event_types_tab (Js.Unsafe.coerce content_el)
           | _ -> ());
          Js._true))
    done;

    render_roles_tab (Js.Unsafe.coerce content_el));

  panel

let init () = render ()
