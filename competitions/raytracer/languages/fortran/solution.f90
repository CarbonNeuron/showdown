program raytracer
  implicit none

  integer, parameter :: dp = selected_real_kind(15, 307)
  real(dp), parameter :: PI = 3.14159265358979323846_dp
  real(dp), parameter :: INF_VAL = 1.0e20_dp
  real(dp), parameter :: EPS = 1.0e-6_dp
  real(dp), parameter :: AMBIENT = 0.1_dp
  real(dp), parameter :: GROUND_Y = 0.0_dp
  real(dp), parameter :: GROUND_REFLECT = 0.3_dp
  real(dp), parameter :: GROUND_SPEC = 10.0_dp
  real(dp), parameter :: CHECK_SIZE = 1.0_dp
  integer, parameter :: MAX_DEPTH = 5
  integer, parameter :: NUM_SPHERES = 5
  integer, parameter :: NUM_LIGHTS = 2

  ! Sphere data: cx,cy,cz, radius, cr,cg,cb, reflectivity, specular
  real(dp) :: sph(9, NUM_SPHERES)
  ! Light data: px,py,pz, intensity
  real(dp) :: lit(4, NUM_LIGHTS)

  ! Camera vectors
  real(dp) :: cam_pos(3), forward(3), right_v(3), cam_up(3)
  real(dp) :: half_h, half_w

  integer :: width, height, i, j, idx
  real(dp) :: aspect, inv_gamma, u_coord, v_coord
  real(dp) :: dir(3), color(3)
  character(len=32) :: arg1, arg2
  character(len=64) :: header
  integer :: header_len
  character(len=1), allocatable :: pixels(:)

  ! Setup scene
  ! Sphere 1: (-2,1,0) r=1 col(0.9,0.2,0.2) refl=0.3 spec=50
  sph(:,1) = (/ -2.0_dp, 1.0_dp, 0.0_dp, 1.0_dp, 0.9_dp, 0.2_dp, 0.2_dp, 0.3_dp, 50.0_dp /)
  ! Sphere 2: (0,0.75,0) r=0.75 col(0.2,0.9,0.2) refl=0.2 spec=30
  sph(:,2) = (/ 0.0_dp, 0.75_dp, 0.0_dp, 0.75_dp, 0.2_dp, 0.9_dp, 0.2_dp, 0.2_dp, 30.0_dp /)
  ! Sphere 3: (2,1,0) r=1 col(0.2,0.2,0.9) refl=0.4 spec=80
  sph(:,3) = (/ 2.0_dp, 1.0_dp, 0.0_dp, 1.0_dp, 0.2_dp, 0.2_dp, 0.9_dp, 0.4_dp, 80.0_dp /)
  ! Sphere 4: (-0.75,0.4,-1.5) r=0.4 col(0.9,0.9,0.2) refl=0.5 spec=100
  sph(:,4) = (/ -0.75_dp, 0.4_dp, -1.5_dp, 0.4_dp, 0.9_dp, 0.9_dp, 0.2_dp, 0.5_dp, 100.0_dp /)
  ! Sphere 5: (1.5,0.5,-1) r=0.5 col(0.9,0.2,0.9) refl=0.6 spec=60
  sph(:,5) = (/ 1.5_dp, 0.5_dp, -1.0_dp, 0.5_dp, 0.9_dp, 0.2_dp, 0.9_dp, 0.6_dp, 60.0_dp /)

  ! Light 1: (-3,5,-3) int=0.7
  lit(:,1) = (/ -3.0_dp, 5.0_dp, -3.0_dp, 0.7_dp /)
  ! Light 2: (3,3,-1) int=0.4
  lit(:,2) = (/ 3.0_dp, 3.0_dp, -1.0_dp, 0.4_dp /)

  ! Parse command line arguments
  call get_command_argument(1, arg1)
  call get_command_argument(2, arg2)
  read(arg1, *) width
  read(arg2, *) height

  if (width <= 0 .or. height <= 0) then
    write(0, '(A)') 'Invalid dimensions'
    stop 1
  end if

  aspect = real(width, dp) / real(height, dp)
  inv_gamma = 1.0_dp / 2.2_dp

  ! Setup camera
  cam_pos = (/ 0.0_dp, 1.5_dp, -5.0_dp /)
  call setup_camera(cam_pos, (/ 0.0_dp, 0.5_dp, 0.0_dp /), (/ 0.0_dp, 1.0_dp, 0.0_dp /), &
                    60.0_dp, aspect)

  ! Allocate pixel buffer
  allocate(pixels(width * height * 3))

  ! Render
  idx = 1
  do j = height - 1, 0, -1
    do i = 0, width - 1
      u_coord = (2.0_dp * ((real(i, dp) + 0.5_dp) / real(width, dp)) - 1.0_dp) * half_w
      v_coord = (2.0_dp * ((real(j, dp) + 0.5_dp) / real(height, dp)) - 1.0_dp) * half_h
      dir = normalize(forward + right_v * u_coord + cam_up * v_coord)
      call trace(cam_pos, dir, 0, color)

      ! Gamma correction and output
      color(1) = clamp01(color(1)) ** inv_gamma
      color(2) = clamp01(color(2)) ** inv_gamma
      color(3) = clamp01(color(3)) ** inv_gamma

      pixels(idx)   = achar(nint(color(1) * 255.0_dp))
      pixels(idx+1) = achar(nint(color(2) * 255.0_dp))
      pixels(idx+2) = achar(nint(color(3) * 255.0_dp))
      idx = idx + 3
    end do
  end do

  ! Write PPM P6 to stdout using stream access
  write(header, '(A,A,I0,A,I0,A,A)') 'P6', new_line('a'), width, ' ', height, new_line('a'), '255'
  header_len = len_trim(header)

  ! Write to file descriptor 1 (stdout) using stream I/O
  open(unit=10, file='/dev/stdout', access='stream', form='unformatted', status='unknown')
  ! Write header as bytes
  do i = 1, header_len
    write(10) header(i:i)
  end do
  write(10) new_line('a')
  ! Write pixel data
  do i = 1, width * height * 3
    write(10) pixels(i)
  end do
  close(10)

  deallocate(pixels)

contains

  function normalize(v) result(res)
    real(dp), intent(in) :: v(3)
    real(dp) :: res(3), l
    l = sqrt(v(1)*v(1) + v(2)*v(2) + v(3)*v(3))
    res = v / l
  end function normalize

  function dot3(a, b) result(d)
    real(dp), intent(in) :: a(3), b(3)
    real(dp) :: d
    d = a(1)*b(1) + a(2)*b(2) + a(3)*b(3)
  end function dot3

  function cross3(a, b) result(c)
    real(dp), intent(in) :: a(3), b(3)
    real(dp) :: c(3)
    c(1) = a(2)*b(3) - a(3)*b(2)
    c(2) = a(3)*b(1) - a(1)*b(3)
    c(3) = a(1)*b(2) - a(2)*b(1)
  end function cross3

  function reflect_vec(v, n) result(r)
    real(dp), intent(in) :: v(3), n(3)
    real(dp) :: r(3)
    r = v - 2.0_dp * dot3(v, n) * n
  end function reflect_vec

  function clamp01(x) result(c)
    real(dp), intent(in) :: x
    real(dp) :: c
    c = min(max(x, 0.0_dp), 1.0_dp)
  end function clamp01

  subroutine setup_camera(pos, look_at, up, vfov, asp)
    real(dp), intent(in) :: pos(3), look_at(3), up(3), vfov, asp
    real(dp) :: theta

    theta = vfov * PI / 180.0_dp
    half_h = tan(theta / 2.0_dp)
    half_w = asp * half_h

    forward = normalize(look_at - pos)
    right_v = normalize(cross3(forward, up))
    cam_up = cross3(right_v, forward)
  end subroutine setup_camera

  function intersect_sphere(orig, dir, si) result(t)
    real(dp), intent(in) :: orig(3), dir(3)
    integer, intent(in) :: si
    real(dp) :: t, oc(3), b, c, disc, sq, t1, t2

    oc = orig - sph(1:3, si)
    b = dot3(oc, dir)
    c = dot3(oc, oc) - sph(4, si) * sph(4, si)
    disc = b * b - c
    if (disc < 0.0_dp) then
      t = INF_VAL
      return
    end if
    sq = sqrt(disc)
    t1 = -b - sq
    if (t1 > EPS) then
      t = t1
      return
    end if
    t2 = -b + sq
    if (t2 > EPS) then
      t = t2
      return
    end if
    t = INF_VAL
  end function intersect_sphere

  function intersect_ground(orig, dir) result(t)
    real(dp), intent(in) :: orig(3), dir(3)
    real(dp) :: t, tv
    if (abs(dir(2)) < EPS) then
      t = INF_VAL
      return
    end if
    tv = (GROUND_Y - orig(2)) / dir(2)
    if (tv > EPS) then
      t = tv
    else
      t = INF_VAL
    end if
  end function intersect_ground

  subroutine scene_intersect(orig, dir, hit, t_hit, point, normal, col, refl, spec)
    real(dp), intent(in) :: orig(3), dir(3)
    logical, intent(out) :: hit
    real(dp), intent(out) :: t_hit, point(3), normal(3), col(3), refl, spec
    integer :: si
    real(dp) :: t, tg, px, pz, fx, fz
    integer :: chk

    hit = .false.
    t_hit = INF_VAL

    ! Check spheres
    do si = 1, NUM_SPHERES
      t = intersect_sphere(orig, dir, si)
      if (t < t_hit) then
        hit = .true.
        t_hit = t
        point = orig + dir * t
        normal = normalize(point - sph(1:3, si))
        col = sph(5:7, si)
        refl = sph(8, si)
        spec = sph(9, si)
      end if
    end do

    ! Check ground plane
    tg = intersect_ground(orig, dir)
    if (tg < t_hit) then
      hit = .true.
      t_hit = tg
      point = orig + dir * tg
      normal = (/ 0.0_dp, 1.0_dp, 0.0_dp /)
      ! Checkerboard
      px = point(1) / CHECK_SIZE
      pz = point(3) / CHECK_SIZE
      if (px < 0.0_dp) then
        fx = floor(px - 1.0_dp)
      else
        fx = floor(px)
      end if
      if (pz < 0.0_dp) then
        fz = floor(pz - 1.0_dp)
      else
        fz = floor(pz)
      end if
      chk = iand(int(fx) + int(fz), 1)
      if (chk == 1) then
        col = (/ 0.3_dp, 0.3_dp, 0.3_dp /)
      else
        col = (/ 0.8_dp, 0.8_dp, 0.8_dp /)
      end if
      refl = GROUND_REFLECT
      spec = GROUND_SPEC
    end if
  end subroutine scene_intersect

  function in_shadow(point, light_dir, light_dist) result(shadowed)
    real(dp), intent(in) :: point(3), light_dir(3), light_dist
    logical :: shadowed
    integer :: si
    real(dp) :: t, tg

    shadowed = .false.
    do si = 1, NUM_SPHERES
      t = intersect_sphere(point, light_dir, si)
      if (t < light_dist) then
        shadowed = .true.
        return
      end if
    end do
    tg = intersect_ground(point, light_dir)
    if (tg < light_dist) then
      shadowed = .true.
    end if
  end function in_shadow

  recursive subroutine trace(orig, dir, depth, color)
    real(dp), intent(in) :: orig(3), dir(3)
    integer, intent(in) :: depth
    real(dp), intent(out) :: color(3)
    logical :: hit
    real(dp) :: t_hit, point(3), normal(3), col(3), refl, spec
    real(dp) :: sky_t
    real(dp) :: result(3), offset_point(3)
    real(dp) :: to_light(3), dist, light_dir(3), n_dot_l
    real(dp) :: refl_dir_l(3), view_dir(3), spec_dot, spec_val
    real(dp) :: refl_ray_dir(3), refl_color(3)
    real(dp) :: ndir(3)
    integer :: li

    call scene_intersect(orig, dir, hit, t_hit, point, normal, col, refl, spec)

    if (.not. hit) then
      ! Sky gradient
      ndir = normalize(dir)
      sky_t = 0.5_dp * (ndir(2) + 1.0_dp)
      color(1) = (1.0_dp - sky_t) * 1.0_dp + sky_t * 0.5_dp
      color(2) = (1.0_dp - sky_t) * 1.0_dp + sky_t * 0.7_dp
      color(3) = (1.0_dp - sky_t) * 1.0_dp + sky_t * 1.0_dp
      return
    end if

    ! Ambient
    result = col * AMBIENT

    offset_point = point + normal * EPS

    ! For each light
    do li = 1, NUM_LIGHTS
      to_light = lit(1:3, li) - point
      dist = sqrt(dot3(to_light, to_light))
      light_dir = to_light / dist

      if (in_shadow(offset_point, light_dir, dist)) cycle

      ! Diffuse
      n_dot_l = dot3(normal, light_dir)
      if (n_dot_l > 0.0_dp) then
        result = result + col * (n_dot_l * lit(4, li))

        ! Specular (Phong)
        refl_dir_l = reflect_vec(-light_dir, normal)
        view_dir = -dir
        spec_dot = dot3(view_dir, refl_dir_l)
        if (spec_dot > 0.0_dp) then
          spec_val = (spec_dot ** spec) * lit(4, li)
          result(1) = result(1) + spec_val
          result(2) = result(2) + spec_val
          result(3) = result(3) + spec_val
        end if
      end if
    end do

    ! Reflections
    if (depth < MAX_DEPTH .and. refl > 0.0_dp) then
      refl_ray_dir = reflect_vec(dir, normal)
      call trace(offset_point, refl_ray_dir, depth + 1, refl_color)
      result = result * (1.0_dp - refl) + refl_color * refl
    end if

    color = result
  end subroutine trace

end program raytracer
