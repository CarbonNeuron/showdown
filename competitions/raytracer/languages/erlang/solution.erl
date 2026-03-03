-module(solution).
-export([main/0]).

%% Vector operations using {X, Y, Z} tuples
vadd({Ax,Ay,Az}, {Bx,By,Bz}) -> {Ax+Bx, Ay+By, Az+Bz}.
vsub({Ax,Ay,Az}, {Bx,By,Bz}) -> {Ax-Bx, Ay-By, Az-Bz}.
vmul({X,Y,Z}, T) -> {X*T, Y*T, Z*T}.
vdot({Ax,Ay,Az}, {Bx,By,Bz}) -> Ax*Bx + Ay*By + Az*Bz.
vcross({Ax,Ay,Az}, {Bx,By,Bz}) ->
    {Ay*Bz - Az*By, Az*Bx - Ax*Bz, Ax*By - Ay*Bx}.
vlen(V) -> math:sqrt(vdot(V, V)).
vnorm(V) ->
    L = vlen(V),
    {element(1,V)/L, element(2,V)/L, element(3,V)/L}.
vreflect(V, N) ->
    vsub(V, vmul(N, 2.0 * vdot(V, N))).

clamp01(X) when X < 0.0 -> 0.0;
clamp01(X) when X > 1.0 -> 1.0;
clamp01(X) -> X.

%% Scene definition
-define(EPSILON, 1.0e-6).
-define(INF, 1.0e20).
-define(MAX_DEPTH, 5).
-define(AMBIENT, 0.1).
-define(GROUND_Y, 0.0).
-define(GROUND_REFLECT, 0.3).
-define(GROUND_SPECULAR, 10.0).
-define(CHECK_SIZE, 1.0).

spheres() ->
    [
        {sphere, {-2.0, 1.0, 0.0},   1.0,  {0.9, 0.2, 0.2}, 0.3, 50.0},
        {sphere, {0.0, 0.75, 0.0},    0.75, {0.2, 0.9, 0.2}, 0.2, 30.0},
        {sphere, {2.0, 1.0, 0.0},     1.0,  {0.2, 0.2, 0.9}, 0.4, 80.0},
        {sphere, {-0.75, 0.4, -1.5},  0.4,  {0.9, 0.9, 0.2}, 0.5, 100.0},
        {sphere, {1.5, 0.5, -1.0},    0.5,  {0.9, 0.2, 0.9}, 0.6, 60.0}
    ].

lights() ->
    [
        {light, {-3.0, 5.0, -3.0}, 0.7},
        {light, {3.0, 3.0, -1.0},  0.4}
    ].

%% Sphere intersection
intersect_sphere({Ox,Oy,Oz}, {Dx,Dy,Dz}, {sphere, {Cx,Cy,Cz}, Radius, _, _, _}) ->
    OCx = Ox - Cx, OCy = Oy - Cy, OCz = Oz - Cz,
    B = OCx*Dx + OCy*Dy + OCz*Dz,
    C = OCx*OCx + OCy*OCy + OCz*OCz - Radius*Radius,
    Disc = B*B - C,
    if
        Disc < 0.0 -> ?INF;
        true ->
            Sq = math:sqrt(Disc),
            T1 = -B - Sq,
            if
                T1 > ?EPSILON -> T1;
                true ->
                    T2 = -B + Sq,
                    if
                        T2 > ?EPSILON -> T2;
                        true -> ?INF
                    end
            end
    end.

%% Ground intersection
intersect_ground({_,Oy,_}, {_,Dy,_}) ->
    if
        abs(Dy) < ?EPSILON -> ?INF;
        true ->
            T = (?GROUND_Y - Oy) / Dy,
            if
                T > ?EPSILON -> T;
                true -> ?INF
            end
    end.

%% Find closest intersection
scene_intersect(Origin, Dir, Spheres) ->
    %% Check spheres
    Best0 = {false, ?INF, {0.0,0.0,0.0}, {0.0,0.0,0.0}, {0.0,0.0,0.0}, 0.0, 0.0},
    Best1 = lists:foldl(
        fun(S = {sphere, Center, _Radius, Color, Refl, Spec}, {_Hit, BestT, _P, _N, _C, _R, _Sp}) ->
            T = intersect_sphere(Origin, Dir, S),
            if
                T < BestT ->
                    Point = vadd(Origin, vmul(Dir, T)),
                    Normal = vnorm(vsub(Point, Center)),
                    {true, T, Point, Normal, Color, Refl, Spec};
                true ->
                    {_Hit, BestT, _P, _N, _C, _R, _Sp}
            end
        end, Best0, Spheres),
    %% Check ground
    {Hit1, BestT1, Point1, Normal1, Color1, Refl1, Spec1} = Best1,
    Tg = intersect_ground(Origin, Dir),
    if
        Tg < BestT1 ->
            GP = vadd(Origin, vmul(Dir, Tg)),
            {GPx, _, GPz} = GP,
            Px = GPx / ?CHECK_SIZE,
            Pz = GPz / ?CHECK_SIZE,
            Fx = if Px < 0.0 -> math:floor(Px - 1.0); true -> math:floor(Px) end,
            Fz = if Pz < 0.0 -> math:floor(Pz - 1.0); true -> math:floor(Pz) end,
            Check = (trunc(Fx) + trunc(Fz)) rem 2,
            GColor = if Check =:= 1 -> {0.3, 0.3, 0.3}; true -> {0.8, 0.8, 0.8} end,
            {true, Tg, GP, {0.0, 1.0, 0.0}, GColor, ?GROUND_REFLECT, ?GROUND_SPECULAR};
        true ->
            {Hit1, BestT1, Point1, Normal1, Color1, Refl1, Spec1}
    end.

%% Shadow check
in_shadow(Point, LightDir, LightDist, Spheres) ->
    %% Check spheres
    SphereBlock = lists:any(
        fun(S) ->
            T = intersect_sphere(Point, LightDir, S),
            T < LightDist
        end, Spheres),
    case SphereBlock of
        true -> true;
        false ->
            Tg = intersect_ground(Point, LightDir),
            Tg < LightDist
    end.

%% Sky color
sky_color(Dir) ->
    {_, Dy, _} = vnorm(Dir),
    T = 0.5 * (Dy + 1.0),
    vadd(vmul({1.0, 1.0, 1.0}, 1.0 - T), vmul({0.5, 0.7, 1.0}, T)).

%% Trace ray
trace(_Origin, _Dir, Depth, _Spheres, _Lights) when Depth >= ?MAX_DEPTH ->
    {0.0, 0.0, 0.0};
trace(Origin, Dir, Depth, Spheres, Lights) ->
    case scene_intersect(Origin, Dir, Spheres) of
        {false, _, _, _, _, _, _} ->
            sky_color(Dir);
        {true, _T, Point, Normal, Color, Refl, Spec} ->
            shade(Point, Normal, Color, Refl, Spec, Dir, Depth, Spheres, Lights)
    end.

shade(Point, Normal, Color, Refl, Spec, RayDir, Depth, Spheres, Lights) ->
    %% Ambient
    Result0 = vmul(Color, ?AMBIENT),
    %% Offset point for shadow/reflection rays
    OffsetPoint = vadd(Point, vmul(Normal, ?EPSILON)),
    %% Accumulate lighting from each light
    Result1 = lists:foldl(
        fun({light, LPos, LIntensity}, Acc) ->
            ToLight = vsub(LPos, Point),
            Dist = vlen(ToLight),
            LDir = vmul(ToLight, 1.0 / Dist),
            case in_shadow(OffsetPoint, LDir, Dist, Spheres) of
                true -> Acc;
                false ->
                    NDotL = vdot(Normal, LDir),
                    if
                        NDotL > 0.0 ->
                            %% Diffuse
                            Acc1 = vadd(Acc, vmul(Color, NDotL * LIntensity)),
                            %% Specular (Phong)
                            ReflDir = vreflect(vmul(LDir, -1.0), Normal),
                            ViewDir = vmul(RayDir, -1.0),
                            SpecDot = vdot(ViewDir, ReflDir),
                            if
                                SpecDot > 0.0 ->
                                    SpecVal = math:pow(SpecDot, Spec) * LIntensity,
                                    vadd(Acc1, {SpecVal, SpecVal, SpecVal});
                                true ->
                                    Acc1
                            end;
                        true ->
                            Acc
                    end
            end
        end, Result0, Lights),
    %% Reflections
    if
        Depth < ?MAX_DEPTH andalso Refl > 0.0 ->
            ReflRayDir = vreflect(RayDir, Normal),
            ReflColor = trace(OffsetPoint, ReflRayDir, Depth + 1, Spheres, Lights),
            vadd(vmul(Result1, 1.0 - Refl), vmul(ReflColor, Refl));
        true ->
            Result1
    end.

%% Camera setup
make_camera(From, At, Vup, Vfov, Aspect) ->
    Theta = Vfov * math:pi() / 180.0,
    HalfH = math:tan(Theta / 2.0),
    HalfW = Aspect * HalfH,
    W = vnorm(vsub(From, At)),
    U = vnorm(vcross(Vup, W)),
    V = vcross(W, U),
    Horizontal = vmul(U, 2.0 * HalfW),
    Vertical = vmul(V, 2.0 * HalfH),
    LowerLeft = vsub(vsub(vsub(From, vmul(U, HalfW)), vmul(V, HalfH)), W),
    {From, LowerLeft, Horizontal, Vertical}.

cam_ray({CamOrigin, LowerLeft, Horizontal, Vertical}, S, T) ->
    Target = vadd(vadd(LowerLeft, vmul(Horizontal, S)), vmul(Vertical, T)),
    Dir = vnorm(vsub(Target, CamOrigin)),
    {CamOrigin, Dir}.

%% Render one row (top-to-bottom: j goes from Height-1 down to 0)
render_row(J, Width, Height, Camera, Spheres, Lights, InvGamma) ->
    V = (float(J) + 0.5) / float(Height),
    render_pixels(0, Width, V, Width, Height, Camera, Spheres, Lights, InvGamma, []).

render_pixels(I, Width, _V, _W, _H, _Camera, _Spheres, _Lights, _InvGamma, Acc) when I >= Width ->
    list_to_binary(lists:reverse(Acc));
render_pixels(I, Width, V, W, H, Camera, Spheres, Lights, InvGamma, Acc) ->
    U = (float(I) + 0.5) / float(W),
    {Origin, Dir} = cam_ray(Camera, U, V),
    {Cr, Cg, Cb} = trace(Origin, Dir, 0, Spheres, Lights),
    R = round(math:pow(clamp01(Cr), InvGamma) * 255.0),
    G = round(math:pow(clamp01(Cg), InvGamma) * 255.0),
    B = round(math:pow(clamp01(Cb), InvGamma) * 255.0),
    render_pixels(I + 1, Width, V, W, H, Camera, Spheres, Lights, InvGamma, [<<R:8, G:8, B:8>> | Acc]).

%% Main entry point
main() ->
    Args = init:get_plain_arguments(),
    [WidthStr, HeightStr | _] = Args,
    Width = list_to_integer(WidthStr),
    Height = list_to_integer(HeightStr),

    Aspect = float(Width) / float(Height),
    Camera = make_camera({0.0, 1.5, -5.0}, {0.0, 0.5, 0.0}, {0.0, 1.0, 0.0}, 60.0, Aspect),
    Spheres = spheres(),
    Lights = lights(),
    InvGamma = 1.0 / 2.2,

    %% PPM header
    Header = io_lib:format("P6\n~B ~B\n255\n", [Width, Height]),

    %% Render all rows top-to-bottom (j from Height-1 down to 0)
    Rows = [render_row(J, Width, Height, Camera, Spheres, Lights, InvGamma)
            || J <- lists:seq(Height - 1, 0, -1)],

    %% Output binary PPM via port
    StdoutPort = open_port({fd, 0, 1}, [out, binary]),
    port_command(StdoutPort, Header),
    lists:foreach(fun(Row) -> port_command(StdoutPort, Row) end, Rows),
    port_close(StdoutPort),
    halt(0).
