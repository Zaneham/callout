(* Callout CAD — Offline Support
 *
 * Service worker registration and IndexedDB cache for offline operation.
 * Events are stored locally when offline and synced when reconnected.
 *)

open Js_of_ocaml

let register_service_worker () =
  let navigator = Dom_html.window##.navigator in
  let sw = Js.Unsafe.get navigator (Js.string "serviceWorker") in
  if Js.Optdef.test (Js.Optdef.return sw) then begin
    let _promise = Js.Unsafe.meth_call sw "register"
      [| Js.Unsafe.inject (Js.string "/sw.js") |] in
    ()
  end

(* IndexedDB wrapper for local event storage *)
module Local_store = struct
  let db_name = "callout-local"
  let store_name = "events"

  let open_db callback =
    let request = Js.Unsafe.meth_call
      (Js.Unsafe.global##.indexedDB) "open"
      [| Js.Unsafe.inject (Js.string db_name);
         Js.Unsafe.inject 1 |] in

    Js.Unsafe.set request (Js.string "onupgradeneeded")
      (Js.wrap_callback (fun e ->
        let db = Js.Unsafe.get (Js.Unsafe.get e (Js.string "target"))
          (Js.string "result") in
        let _store = Js.Unsafe.meth_call db "createObjectStore"
          [| Js.Unsafe.inject (Js.string store_name);
             Js.Unsafe.inject (Js.Unsafe.obj [|
               ("keyPath", Js.Unsafe.inject (Js.string "id"))
             |]) |] in
        ()));

    Js.Unsafe.set request (Js.string "onsuccess")
      (Js.wrap_callback (fun e ->
        let db = Js.Unsafe.get (Js.Unsafe.get e (Js.string "target"))
          (Js.string "result") in
        callback db))

  let store_event db event_json =
    let tx = Js.Unsafe.meth_call db "transaction"
      [| Js.Unsafe.inject (Js.string store_name);
         Js.Unsafe.inject (Js.string "readwrite") |] in
    let store = Js.Unsafe.meth_call tx "objectStore"
      [| Js.Unsafe.inject (Js.string store_name) |] in
    let _req = Js.Unsafe.meth_call store "put"
      [| Js.Unsafe.inject event_json |] in
    ()

  let get_unsynced_events db callback =
    let tx = Js.Unsafe.meth_call db "transaction"
      [| Js.Unsafe.inject (Js.string store_name);
         Js.Unsafe.inject (Js.string "readonly") |] in
    let store = Js.Unsafe.meth_call tx "objectStore"
      [| Js.Unsafe.inject (Js.string store_name) |] in
    let request = Js.Unsafe.meth_call store "getAll" [| |] in
    Js.Unsafe.set request (Js.string "onsuccess")
      (Js.wrap_callback (fun e ->
        let result = Js.Unsafe.get (Js.Unsafe.get e (Js.string "target"))
          (Js.string "result") in
        callback result))
end

let init () =
  register_service_worker ()
