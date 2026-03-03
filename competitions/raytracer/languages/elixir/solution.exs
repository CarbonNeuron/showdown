defmodule Vec do
  @moduledoc false

  def new(x, y, z), do: {x, y, z}
  def add({x1, y1, z1}, {x2, y2, z2}), do: {x1 + x2, y1 + y2, z1 + z2}
  def sub({x1, y1, z1}, {x2, y2, z2}), do: {x1 - x2, y1 - y2, z1 - z2}
  def mul({x, y, z}, s), do: {x * s, y * s, z * s}
  def vmul({x1, y1, z1}, {x2, y2, z2}), do: {x1 * x2, y1 * y2, z1 * z2}
  def dot({x1, y1, z1}, {x2, y2, z2}), do: x1 * x2 + y1 * y2 + z1 * z2
  def cross({x1, y1, z1}, {x2, y2, z2}),
    do: {y1 * z2 - z1 * y2, z1 * x2 - x1 * z2, x1 * y2 - y1 * x2}
  def length_sq(v), do: dot(v, v)
  def vec_length(v), do: :math.sqrt(length_sq(v))
  def norm(v) do
    l = vec_length(v)
    if l > 1.0e-12, do: mul(v, 1.0 / l), else: {0.0, 0.0, 0.0}
  end
  def reflect(i, n), do: sub(i, mul(n, 2.0 * dot(i, n)))
end

defmodule Ray do
  @moduledoc false
  defstruct [:origin, :dir]
end

defmodule Hit do
  @moduledoc false
  defstruct [:t, :point, :normal, :color, :refl, :spec]
end

defmodule Raytracer do
  @moduledoc false

  @cam {0.0, 1.5, -5.0}
  @look_at {0.0, 0.5, 0.0}
  @up {0.0, 1.0, 0.0}
  @fov 60.0
  @max_depth 5
  @ambient 0.1

  @spheres [
    %{center: {-2.0, 1.0, 0.0}, radius: 1.0, color: {0.9, 0.2, 0.2}, refl: 0.3, spec: 50.0},
    %{center: {0.0, 0.75, 0.0}, radius: 0.75, color: {0.2, 0.9, 0.2}, refl: 0.2, spec: 30.0},
    %{center: {2.0, 1.0, 0.0}, radius: 1.0, color: {0.2, 0.2, 0.9}, refl: 0.4, spec: 80.0},
    %{center: {-0.75, 0.4, -1.5}, radius: 0.4, color: {0.9, 0.9, 0.2}, refl: 0.5, spec: 100.0},
    %{center: {1.5, 0.5, -1.0}, radius: 0.5, color: {0.9, 0.2, 0.9}, refl: 0.6, spec: 60.0}
  ]

  @lights [
    %{pos: {-3.0, 5.0, -3.0}, intensity: 0.7},
    %{pos: {3.0, 3.0, -1.0}, intensity: 0.4}
  ]

  def run do
    [w_str, h_str] = System.argv()
    width = String.to_integer(w_str)
    height = String.to_integer(h_str)

    forward = Vec.norm(Vec.sub(@look_at, @cam))
    right = Vec.norm(Vec.cross(forward, @up))
    cam_up = Vec.cross(right, forward)

    aspect = width / height
    half_h = :math.tan(@fov * :math.pi() / 360.0)
    half_w = half_h * aspect

    header = "P6\n#{width} #{height}\n255\n"

    pixels =
      for y <- 0..(height - 1), x <- 0..(width - 1) do
        u = (2.0 * (x + 0.5) / width - 1.0) * half_w
        v = (1.0 - 2.0 * (y + 0.5) / height) * half_h

        dir = Vec.norm(
          Vec.add(Vec.add(forward, Vec.mul(right, u)), Vec.mul(cam_up, v))
        )

        ray = %Ray{origin: @cam, dir: dir}
        {r, g, b} = trace(ray, @max_depth)
        rb = round(gamma(r) * 255) |> clamp_byte()
        gb = round(gamma(g) * 255) |> clamp_byte()
        bb = round(gamma(b) * 255) |> clamp_byte()
        <<rb, gb, bb>>
      end

    # Write raw bytes to fd 1 to avoid Erlang unicode encoding on :stdio
    {:ok, fd} = :file.open('/dev/stdout', [:write, :raw, :binary])
    :file.write(fd, [header | pixels])
    :file.close(fd)
  end

  defp gamma(v) do
    c = clamp(v, 0.0, 1.0)
    :math.pow(c, 1.0 / 2.2)
  end

  defp clamp(v, lo, hi), do: v |> max(lo) |> min(hi)
  defp clamp_byte(v) when v < 0, do: 0
  defp clamp_byte(v) when v > 255, do: 255
  defp clamp_byte(v), do: v

  defp trace(_ray, 0), do: {0.0, 0.0, 0.0}

  defp trace(ray, depth) do
    case intersect_scene(ray) do
      nil ->
        sky(ray.dir)

      hit ->
        local = shade(hit, ray)
        if hit.refl > 0.0 and depth > 0 do
          refl_dir = Vec.reflect(ray.dir, hit.normal)
          refl_origin = Vec.add(hit.point, Vec.mul(hit.normal, 1.0e-4))
          refl_ray = %Ray{origin: refl_origin, dir: Vec.norm(refl_dir)}
          refl_color = trace(refl_ray, depth - 1)
          {lr, lg, lb} = local
          {rr, rg, rb} = refl_color
          rf = hit.refl
          {lr * (1.0 - rf) + rr * rf, lg * (1.0 - rf) + rg * rf, lb * (1.0 - rf) + rb * rf}
        else
          local
        end
    end
  end

  defp sky(dir) do
    {_, dy, _} = dir
    t = 0.5 * (dy + 1.0)
    {1.0 * (1.0 - t) + 0.5 * t, 1.0 * (1.0 - t) + 0.7 * t, 1.0 * (1.0 - t) + 1.0 * t}
  end

  defp intersect_scene(ray) do
    sphere_hit =
      Enum.reduce(@spheres, nil, fn sphere, closest ->
        case intersect_sphere(ray, sphere) do
          nil -> closest
          t when closest == nil or t < closest.t ->
            point = Vec.add(ray.origin, Vec.mul(ray.dir, t))
            normal = Vec.norm(Vec.sub(point, sphere.center))
            %Hit{t: t, point: point, normal: normal, color: sphere.color,
                 refl: sphere.refl, spec: sphere.spec}
          _ -> closest
        end
      end)

    ground_hit = intersect_ground(ray)

    case {sphere_hit, ground_hit} do
      {nil, nil} -> nil
      {nil, g} -> g
      {s, nil} -> s
      {s, g} -> if s.t < g.t, do: s, else: g
    end
  end

  defp intersect_sphere(ray, sphere) do
    oc = Vec.sub(ray.origin, sphere.center)
    a = Vec.dot(ray.dir, ray.dir)
    b = 2.0 * Vec.dot(oc, ray.dir)
    c = Vec.dot(oc, oc) - sphere.radius * sphere.radius
    disc = b * b - 4.0 * a * c
    if disc < 0.0 do
      nil
    else
      sqrt_disc = :math.sqrt(disc)
      t1 = (-b - sqrt_disc) / (2.0 * a)
      t2 = (-b + sqrt_disc) / (2.0 * a)
      cond do
        t1 > 1.0e-4 -> t1
        t2 > 1.0e-4 -> t2
        true -> nil
      end
    end
  end

  defp intersect_ground(ray) do
    {_, oy, _} = ray.origin
    {_, dy, _} = ray.dir
    if abs(dy) < 1.0e-12 do
      nil
    else
      t = -oy / dy
      if t > 1.0e-4 do
        point = Vec.add(ray.origin, Vec.mul(ray.dir, t))
        {px, _, pz} = point
        fx = if px < 0.0, do: Float.floor(px) - 1.0, else: Float.floor(px)
        fz = if pz < 0.0, do: Float.floor(pz) - 1.0, else: Float.floor(pz)
        ix = trunc(fx)
        iz = trunc(fz)
        check = rem(ix + iz, 2)
        color = if check == 0, do: {0.8, 0.8, 0.8}, else: {0.3, 0.3, 0.3}
        %Hit{t: t, point: point, normal: {0.0, 1.0, 0.0}, color: color,
             refl: 0.3, spec: 10.0}
      else
        nil
      end
    end
  end

  defp shade(hit, ray) do
    {ar, ag, ab} = hit.color
    ambient = {ar * @ambient, ag * @ambient, ab * @ambient}

    Enum.reduce(@lights, ambient, fn light, {acc_r, acc_g, acc_b} ->
      light_dir = Vec.norm(Vec.sub(light.pos, hit.point))
      n_dot_l = Vec.dot(hit.normal, light_dir)

      if n_dot_l > 0.0 do
        shadow_origin = Vec.add(hit.point, Vec.mul(hit.normal, 1.0e-4))
        shadow_ray = %Ray{origin: shadow_origin, dir: light_dir}
        light_dist = Vec.vec_length(Vec.sub(light.pos, hit.point))

        if in_shadow?(shadow_ray, light_dist) do
          {acc_r, acc_g, acc_b}
        else
          {cr, cg, cb} = hit.color
          diff_r = cr * n_dot_l * light.intensity
          diff_g = cg * n_dot_l * light.intensity
          diff_b = cb * n_dot_l * light.intensity

          view_dir = Vec.norm(Vec.sub(ray.origin, hit.point))
          half_vec = Vec.norm(Vec.add(light_dir, view_dir))
          n_dot_h = max(Vec.dot(hit.normal, half_vec), 0.0)
          spec_val = :math.pow(n_dot_h, hit.spec) * light.intensity

          {acc_r + diff_r + spec_val, acc_g + diff_g + spec_val, acc_b + diff_b + spec_val}
        end
      else
        {acc_r, acc_g, acc_b}
      end
    end)
  end

  defp in_shadow?(shadow_ray, light_dist) do
    sphere_shadow =
      Enum.any?(@spheres, fn sphere ->
        case intersect_sphere(shadow_ray, sphere) do
          nil -> false
          t -> t < light_dist
        end
      end)

    if sphere_shadow do
      true
    else
      # Check ground shadow
      {_, oy, _} = shadow_ray.origin
      {_, dy, _} = shadow_ray.dir
      if abs(dy) > 1.0e-12 do
        t = -oy / dy
        t > 1.0e-4 and t < light_dist
      else
        false
      end
    end
  end
end

Raytracer.run()
