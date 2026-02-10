open Js_of_ocaml
open Shared.Escape

let render on_success =
  let doc = Dom_html.document in
  let container = Dom_html.createDiv doc in
  container##.id := Js.string "login-view";
  container##.className := Js.string "login-view";
  container##.innerHTML := Js.string
    {|<div class="login-box">
        <h1>Callout CAD</h1>
        <p class="login-subtitle">Sign in to continue</p>
        <div id="login-error" class="login-error" style="display:none"></div>
        <label>Username
          <input type="text" id="login-username" autocomplete="username" />
        </label>
        <label>Password
          <input type="password" id="login-password" autocomplete="current-password" />
        </label>
        <button id="login-btn" class="btn-primary login-btn">Sign In</button>
      </div>|};

  let do_login () =
    let username_el = doc##getElementById (Js.string "login-username") in
    let password_el = doc##getElementById (Js.string "login-password") in
    let username = Js.Opt.case username_el
      (fun () -> "")
      (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in
    let password = Js.Opt.case password_el
      (fun () -> "")
      (fun el -> Js.to_string (Js.Unsafe.get el (Js.string "value"))) in

    if username = "" || password = "" then begin
      let err_el = doc##getElementById (Js.string "login-error") in
      Js.Opt.iter err_el (fun el ->
        el##.innerHTML := Js.string (html_escape "Please enter username and password");
        (Js.Unsafe.coerce el)##.style##.display := Js.string "block")
    end else begin
      let body = Printf.sprintf
        {|{"username":"%s","password":"%s"}|}
        (json_escape username) (json_escape password) in

      let open XmlHttpRequest in
      let req = create () in
      req##_open (Js.string "POST") (Js.string "/api/login") Js._true;
      req##setRequestHeader (Js.string "Content-Type")
        (Js.string "application/json");
      req##.onreadystatechange := Js.wrap_callback (fun () ->
        if req##.readyState = XmlHttpRequest.DONE then begin
          if req##.status = 200 then begin
            let data = Js.Opt.case req##.responseText (fun () -> "") Js.to_string in
            let j = Js.Unsafe.fun_call
              (Js.Unsafe.js_expr "JSON.parse")
              [| Js.Unsafe.inject (Js.string data) |] in
            let token = Js.to_string (Js.Unsafe.get j (Js.string "token")) in
            let storage = Dom_html.window##.localStorage in
            Js.Optdef.iter storage (fun s ->
              s##setItem (Js.string "callout_token") (Js.string token));
            Js.Optdef.iter storage (fun s ->
              s##setItem (Js.string "callout_session") (Js.string data));
            on_success ()
          end else begin
            let err_el = doc##getElementById (Js.string "login-error") in
            Js.Opt.iter err_el (fun el ->
              el##.innerHTML := Js.string (html_escape "Invalid username or password");
              (Js.Unsafe.coerce el)##.style##.display := Js.string "block")
          end
        end);
      req##send (Js.some (Js.string body))
    end
  in

  let btn = container##querySelector (Js.string "#login-btn") in
  Js.Opt.iter btn (fun b ->
    (Js.Unsafe.coerce b)##.onclick := Dom_html.handler (fun _e ->
      do_login ();
      Js._true));

  container

let get_token () =
  let storage = Dom_html.window##.localStorage in
  let token = ref "" in
  Js.Optdef.iter storage (fun s ->
    let v = s##getItem (Js.string "callout_token") in
    Js.Opt.iter v (fun t -> token := Js.to_string t));
  if !token = "" then None else Some !token

let clear_session () =
  let storage = Dom_html.window##.localStorage in
  Js.Optdef.iter storage (fun s ->
    s##removeItem (Js.string "callout_token");
    s##removeItem (Js.string "callout_session"))
