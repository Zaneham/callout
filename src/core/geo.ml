open Shared.Types

let pi = 4.0 *. atan 1.0
let earth_radius_m = 6_371_000.0

let to_radians deg = deg *. pi /. 180.0

let haversine_distance a b =
  let lat1 = to_radians a.lat in
  let lat2 = to_radians b.lat in
  let dlat = to_radians (b.lat -. a.lat) in
  let dlng = to_radians (b.lng -. a.lng) in
  let h =
    (sin (dlat /. 2.0) *. sin (dlat /. 2.0))
    +. (cos lat1 *. cos lat2 *. sin (dlng /. 2.0) *. sin (dlng /. 2.0))
  in
  2.0 *. earth_radius_m *. asin (sqrt h)

let bearing a b =
  let lat1 = to_radians a.lat in
  let lat2 = to_radians b.lat in
  let dlng = to_radians (b.lng -. a.lng) in
  let x = sin dlng *. cos lat2 in
  let y = (cos lat1 *. sin lat2) -. (sin lat1 *. cos lat2 *. cos dlng) in
  let theta = atan2 x y in
  let degrees = theta *. 180.0 /. pi in
  mod_float (degrees +. 360.0) 360.0

let is_valid_position pos =
  pos.lat >= -90.0 && pos.lat <= 90.0
  && pos.lng >= -180.0 && pos.lng <= 180.0
  && pos.timestamp > 0.0
