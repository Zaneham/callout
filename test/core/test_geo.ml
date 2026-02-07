(* Tests for geographic calculations. *)

open Shared.Types

let now = 1700000000.0

let make_pos lat lng =
  { lat; lng; accuracy = None; timestamp = now }

let test_haversine_zero_distance () =
  let pos = make_pos 34.0522 (-118.2437) in
  let d = Core.Geo.haversine_distance pos pos in
  Alcotest.(check bool) "zero distance" true (d < 0.01)

let test_haversine_known_distance () =
  (* Los Angeles to San Francisco: ~559 km *)
  let la = make_pos 34.0522 (-118.2437) in
  let sf = make_pos 37.7749 (-122.4194) in
  let d = Core.Geo.haversine_distance la sf in
  let km = d /. 1000.0 in
  Alcotest.(check bool) "LA to SF ~559km"
    true (km > 540.0 && km < 580.0)

let test_valid_position () =
  let valid = make_pos 34.0522 (-118.2437) in
  Alcotest.(check bool) "valid" true (Core.Geo.is_valid_position valid)

let test_invalid_latitude () =
  let invalid = make_pos 91.0 0.0 in
  Alcotest.(check bool) "invalid lat" false (Core.Geo.is_valid_position invalid)

let test_invalid_longitude () =
  let invalid = make_pos 0.0 181.0 in
  Alcotest.(check bool) "invalid lng" false (Core.Geo.is_valid_position invalid)

let test_invalid_timestamp () =
  let invalid = { lat = 0.0; lng = 0.0; accuracy = None; timestamp = -1.0 } in
  Alcotest.(check bool) "invalid timestamp" false (Core.Geo.is_valid_position invalid)

let () =
  Alcotest.run "Geographic Calculations"
    [ "haversine", [
        "zero distance", `Quick, test_haversine_zero_distance;
        "LA to SF", `Quick, test_haversine_known_distance;
      ]
    ; "validation", [
        "valid position", `Quick, test_valid_position;
        "invalid latitude", `Quick, test_invalid_latitude;
        "invalid longitude", `Quick, test_invalid_longitude;
        "invalid timestamp", `Quick, test_invalid_timestamp;
      ]
    ]
