let epsilon = 1e-6
let inf = 1e20
let max_depth = 5
let ambient = 0.1
let ground_y = 0.0
let ground_reflect = 0.3
let ground_specular = 10.0
let check_size = 1.0
let pi = 4.0 *. atan 1.0

(* ── Vector ──────────────────────────────────────────────────────── *)

type vec3 = { x : float; y : float; z : float }

let v3 x y z = { x; y; z }
let vadd a b = { x = a.x +. b.x; y = a.y +. b.y; z = a.z +. b.z }
let vsub a b = { x = a.x -. b.x; y = a.y -. b.y; z = a.z -. b.z }
let vmul a t = { x = a.x *. t; y = a.y *. t; z = a.z *. t }
let vmulv a b = { x = a.x *. b.x; y = a.y *. b.y; z = a.z *. b.z }
let vdot a b = a.x *. b.x +. a.y *. b.y +. a.z *. b.z
let vcross a b =
  { x = a.y *. b.z -. a.z *. b.y;
    y = a.z *. b.x -. a.x *. b.z;
    z = a.x *. b.y -. a.y *. b.x }
let vlen v = sqrt (vdot v v)
let vnorm v = let l = vlen v in { x = v.x /. l; y = v.y /. l; z = v.z /. l }
let vreflect v n = vsub v (vmul n (2.0 *. vdot v n))

let clamp01 x = if x < 0.0 then 0.0 else if x > 1.0 then 1.0 else x

(* ── Scene ───────────────────────────────────────────────────────── *)

type sphere = {
  center : vec3;
  radius : float;
  color : vec3;
  reflectivity : float;
  specular : float;
}

type light = {
  position : vec3;
  intensity : float;
}

type ray = {
  origin : vec3;
  dir : vec3;
}

let spheres = [|
  { center = v3 (-2.0) 1.0 0.0; radius = 1.0;
    color = v3 0.9 0.2 0.2; reflectivity = 0.3; specular = 50.0 };
  { center = v3 0.0 0.75 0.0; radius = 0.75;
    color = v3 0.2 0.9 0.2; reflectivity = 0.2; specular = 30.0 };
  { center = v3 2.0 1.0 0.0; radius = 1.0;
    color = v3 0.2 0.2 0.9; reflectivity = 0.4; specular = 80.0 };
  { center = v3 (-0.75) 0.4 (-1.5); radius = 0.4;
    color = v3 0.9 0.9 0.2; reflectivity = 0.5; specular = 100.0 };
  { center = v3 1.5 0.5 (-1.0); radius = 0.5;
    color = v3 0.9 0.2 0.9; reflectivity = 0.6; specular = 60.0 };
|]

let num_spheres = Array.length spheres

let lights = [|
  { position = v3 (-3.0) 5.0 (-3.0); intensity = 0.7 };
  { position = v3 3.0 3.0 (-1.0); intensity = 0.4 };
|]

let num_lights = Array.length lights

(* ── Intersection ────────────────────────────────────────────────── *)

let intersect_sphere r s =
  let oc = vsub r.origin s.center in
  let b = vdot oc r.dir in
  let c = vdot oc oc -. s.radius *. s.radius in
  let disc = b *. b -. c in
  if disc < 0.0 then inf
  else
    let sq = sqrt disc in
    let t1 = -. b -. sq in
    if t1 > epsilon then t1
    else
      let t2 = -. b +. sq in
      if t2 > epsilon then t2
      else inf

let intersect_ground r =
  if abs_float r.dir.y < epsilon then inf
  else
    let t = (ground_y -. r.origin.y) /. r.dir.y in
    if t > epsilon then t else inf

(* ── Hit info ────────────────────────────────────────────────────── *)

type hit_info = {
  hit : bool;
  t : float;
  point : vec3;
  normal : vec3;
  color : vec3;
  refl : float;
  spec : float;
}

let no_hit = {
  hit = false; t = inf;
  point = v3 0.0 0.0 0.0;
  normal = v3 0.0 1.0 0.0;
  color = v3 0.0 0.0 0.0;
  refl = 0.0; spec = 0.0;
}

let scene_intersect r =
  let best = ref no_hit in
  let best_t = ref inf in
  (* spheres *)
  for i = 0 to num_spheres - 1 do
    let s = spheres.(i) in
    let t = intersect_sphere r s in
    if t < !best_t then begin
      best_t := t;
      let p = vadd r.origin (vmul r.dir t) in
      best := {
        hit = true; t;
        point = p;
        normal = vnorm (vsub p s.center);
        color = s.color;
        refl = s.reflectivity;
        spec = s.specular;
      }
    end
  done;
  (* ground plane *)
  let tg = intersect_ground r in
  if tg < !best_t then begin
    best_t := tg;
    let p = vadd r.origin (vmul r.dir tg) in
    let px = p.x /. check_size in
    let pz = p.z /. check_size in
    let fx = if px < 0.0 then floor (px -. 1.0) else floor px in
    let fz = if pz < 0.0 then floor (pz -. 1.0) else floor pz in
    let check = (int_of_float fx + int_of_float fz) land 1 in
    let col = if check = 1 then v3 0.3 0.3 0.3 else v3 0.8 0.8 0.8 in
    best := {
      hit = true; t = tg;
      point = p;
      normal = v3 0.0 1.0 0.0;
      color = col;
      refl = ground_reflect;
      spec = ground_specular;
    }
  end;
  !best

(* ── Shadow ──────────────────────────────────────────────────────── *)

let in_shadow point light_dir light_dist =
  let shadow_ray = { origin = point; dir = light_dir } in
  let blocked = ref false in
  for i = 0 to num_spheres - 1 do
    let t = intersect_sphere shadow_ray spheres.(i) in
    if t < light_dist then blocked := true
  done;
  if not !blocked then begin
    let tg = intersect_ground shadow_ray in
    if tg < light_dist then blocked := true
  end;
  !blocked

(* ── Trace ───────────────────────────────────────────────────────── *)

let rec trace r depth =
  let h = scene_intersect r in
  if not h.hit then
    (* sky gradient *)
    let d = vnorm r.dir in
    let t = 0.5 *. (d.y +. 1.0) in
    vadd (vmul (v3 1.0 1.0 1.0) (1.0 -. t)) (vmul (v3 0.5 0.7 1.0) t)
  else
    shade h r depth

and shade h r depth =
  let result = ref (vmul h.color ambient) in
  let offset_point = vadd h.point (vmul h.normal epsilon) in
  for i = 0 to num_lights - 1 do
    let lt = lights.(i) in
    let to_light = vsub lt.position h.point in
    let dist = vlen to_light in
    let light_dir = vmul to_light (1.0 /. dist) in
    if not (in_shadow offset_point light_dir dist) then begin
      let n_dot_l = vdot h.normal light_dir in
      if n_dot_l > 0.0 then begin
        (* diffuse *)
        result := vadd !result (vmul h.color (n_dot_l *. lt.intensity));
        (* specular *)
        let refl_dir = vreflect (vmul light_dir (-1.0)) h.normal in
        let view_dir = vmul r.dir (-1.0) in
        let spec_dot = vdot view_dir refl_dir in
        if spec_dot > 0.0 then begin
          let s = (spec_dot ** h.spec) *. lt.intensity in
          result := vadd !result (v3 s s s)
        end
      end
    end
  done;
  (* reflections *)
  if depth < max_depth && h.refl > 0.0 then begin
    let refl_ray = { origin = offset_point; dir = vreflect r.dir h.normal } in
    let refl_color = trace refl_ray (depth + 1) in
    result := vadd (vmul !result (1.0 -. h.refl)) (vmul refl_color h.refl)
  end;
  !result

(* ── Camera ──────────────────────────────────────────────────────── *)

type camera = {
  cam_origin : vec3;
  lower_left : vec3;
  horizontal : vec3;
  vertical : vec3;
}

let make_camera from_ at vup vfov aspect =
  let theta = vfov *. pi /. 180.0 in
  let half_h = tan (theta /. 2.0) in
  let half_w = aspect *. half_h in
  let w = vnorm (vsub from_ at) in
  let u = vnorm (vcross vup w) in
  let v = vcross w u in
  {
    cam_origin = from_;
    horizontal = vmul u (2.0 *. half_w);
    vertical = vmul v (2.0 *. half_h);
    lower_left = vsub (vsub (vsub from_ (vmul u half_w)) (vmul v half_h)) w;
  }

let cam_ray cam s t =
  let target = vadd (vadd cam.lower_left (vmul cam.horizontal s))
                     (vmul cam.vertical t) in
  { origin = cam.cam_origin; dir = vnorm (vsub target cam.cam_origin) }

(* ── Main ────────────────────────────────────────────────────────── *)

let () =
  if Array.length Sys.argv < 3 then begin
    Printf.eprintf "Usage: %s WIDTH HEIGHT\n" Sys.argv.(0);
    exit 1
  end;
  let width = int_of_string Sys.argv.(1) in
  let height = int_of_string Sys.argv.(2) in
  if width <= 0 || height <= 0 then begin
    Printf.eprintf "Invalid dimensions\n";
    exit 1
  end;
  let aspect = float_of_int width /. float_of_int height in
  let cam = make_camera (v3 0.0 1.5 (-5.0)) (v3 0.0 0.5 0.0)
                         (v3 0.0 1.0 0.0) 60.0 aspect in
  let inv_gamma = 1.0 /. 2.2 in
  let buf_size = width * height * 3 in
  let buf = Bytes.create buf_size in
  let pos = ref 0 in
  for j = height - 1 downto 0 do
    let v = (float_of_int j +. 0.5) /. float_of_int height in
    for i = 0 to width - 1 do
      let u = (float_of_int i +. 0.5) /. float_of_int width in
      let r = cam_ray cam u v in
      let col = trace r 0 in
      let cr = (clamp01 col.x) ** inv_gamma in
      let cg = (clamp01 col.y) ** inv_gamma in
      let cb = (clamp01 col.z) ** inv_gamma in
      Bytes.set buf !pos (Char.chr (int_of_float (cr *. 255.0 +. 0.5)));
      Bytes.set buf (!pos + 1) (Char.chr (int_of_float (cg *. 255.0 +. 0.5)));
      Bytes.set buf (!pos + 2) (Char.chr (int_of_float (cb *. 255.0 +. 0.5)));
      pos := !pos + 3
    done
  done;
  (* write PPM P6 *)
  let header = Printf.sprintf "P6\n%d %d\n255\n" width height in
  let oc = stdout in
  output_string oc header;
  output_bytes oc buf;
  flush oc
