-- Raytracer for Showdown benchmark
local sqrt = math.sqrt
local floor = math.floor
local pow = math.pow
local max = math.max
local min = math.min
local huge = math.huge
local char = string.char

-- Set stdout to binary mode
if jit and jit.os == "Windows" then
    io.stdout:setvbuf("no")
end

local WIDTH = tonumber(arg[1]) or 800
local HEIGHT = tonumber(arg[2]) or 600

-- Vector operations (inline for performance)
local function vec(x, y, z) return {x, y, z} end

local function vadd(a, b) return {a[1]+b[1], a[2]+b[2], a[3]+b[3]} end
local function vsub(a, b) return {a[1]-b[1], a[2]-b[2], a[3]-b[3]} end
local function vmul(a, s) return {a[1]*s, a[2]*s, a[3]*s} end
local function vdot(a, b) return a[1]*b[1] + a[2]*b[2] + a[3]*b[3] end
local function vcross(a, b)
    return {a[2]*b[3]-a[3]*b[2], a[3]*b[1]-a[1]*b[3], a[1]*b[2]-a[2]*b[1]}
end
local function vlength(a) return sqrt(a[1]*a[1] + a[2]*a[2] + a[3]*a[3]) end
local function vnorm(a)
    local l = sqrt(a[1]*a[1] + a[2]*a[2] + a[3]*a[3])
    if l == 0 then return {0,0,0} end
    return {a[1]/l, a[2]/l, a[3]/l}
end
local function vmulv(a, b) return {a[1]*b[1], a[2]*b[2], a[3]*b[3]} end
local function vreflect(v, n)
    local d = 2 * vdot(v, n)
    return {v[1] - d*n[1], v[2] - d*n[2], v[3] - d*n[3]}
end

-- Scene definition
local spheres = {
    {center={-2, 1, 0},     radius=1,    color={0.9, 0.2, 0.2}, refl=0.3, spec=50},
    {center={0, 0.75, 0},   radius=0.75, color={0.2, 0.9, 0.2}, refl=0.2, spec=30},
    {center={2, 1, 0},      radius=1,    color={0.2, 0.2, 0.9}, refl=0.4, spec=80},
    {center={-0.75, 0.4, -1.5}, radius=0.4, color={0.9, 0.9, 0.2}, refl=0.5, spec=100},
    {center={1.5, 0.5, -1}, radius=0.5,  color={0.9, 0.2, 0.9}, refl=0.6, spec=60},
}

local lights = {
    {pos={-3, 5, -3}, intensity=0.7},
    {pos={3, 3, -1},  intensity=0.4},
}

local AMBIENT = 0.1
local MAX_DEPTH = 5

-- Ground plane at y=0
local GROUND_Y = 0
local GROUND_REFL = 0.3
local GROUND_SPEC = 10

local function ground_color(x, z)
    local fx = x < 0 and floor(x - 1) or floor(x)
    local fz = z < 0 and floor(z - 1) or floor(z)
    if (fx + fz) % 2 == 0 then
        return {0.8, 0.8, 0.8}
    else
        return {0.3, 0.3, 0.3}
    end
end

-- Ray-sphere intersection
local function intersect_sphere(ox, oy, oz, dx, dy, dz, s)
    local cx, cy, cz = s.center[1], s.center[2], s.center[3]
    local ex, ey, ez = ox - cx, oy - cy, oz - cz
    local a = dx*dx + dy*dy + dz*dz
    local b = 2 * (ex*dx + ey*dy + ez*dz)
    local c = ex*ex + ey*ey + ez*ez - s.radius * s.radius
    local disc = b*b - 4*a*c
    if disc < 0 then return nil end
    local sq = sqrt(disc)
    local t1 = (-b - sq) / (2*a)
    if t1 > 1e-4 then return t1 end
    local t2 = (-b + sq) / (2*a)
    if t2 > 1e-4 then return t2 end
    return nil
end

-- Ray-ground intersection (y=0 plane)
local function intersect_ground(oy, dy)
    if dy == 0 then return nil end
    local t = (GROUND_Y - oy) / dy
    if t > 1e-4 then return t end
    return nil
end

-- Sky color
local function sky_color(dy)
    local t = 0.5 * (dy + 1)
    return {(1-t) + t*0.5, (1-t) + t*0.7, (1-t) + t*1.0}
end

-- Shadow check: returns true if point is in shadow for a given light
local function in_shadow(px, py, pz, lx, ly, lz)
    local dx, dy, dz = lx - px, ly - py, lz - pz
    local dist = sqrt(dx*dx + dy*dy + dz*dz)
    dx, dy, dz = dx/dist, dy/dist, dz/dist

    -- Check spheres
    for i = 1, #spheres do
        local t = intersect_sphere(px, py, pz, dx, dy, dz, spheres[i])
        if t and t < dist then return true end
    end

    -- Check ground
    local tg = intersect_ground(py, dy)
    if tg and tg < dist then return true end

    return false
end

-- Main trace function
local function trace(ox, oy, oz, dx, dy, dz, depth)
    if depth > MAX_DEPTH then
        return sky_color(dy)
    end

    local closest_t = huge
    local hit_sphere = nil
    local hit_ground = false

    -- Test spheres
    for i = 1, #spheres do
        local t = intersect_sphere(ox, oy, oz, dx, dy, dz, spheres[i])
        if t and t < closest_t then
            closest_t = t
            hit_sphere = spheres[i]
            hit_ground = false
        end
    end

    -- Test ground
    local tg = intersect_ground(oy, dy)
    if tg and tg < closest_t then
        closest_t = tg
        hit_sphere = nil
        hit_ground = true
    end

    if not hit_ground and not hit_sphere then
        return sky_color(dy)
    end

    -- Hit point
    local hx = ox + dx * closest_t
    local hy = oy + dy * closest_t
    local hz = oz + dz * closest_t

    local nx, ny, nz
    local obj_color
    local refl, spec_exp

    if hit_ground then
        nx, ny, nz = 0, 1, 0
        obj_color = ground_color(hx, hz)
        refl = GROUND_REFL
        spec_exp = GROUND_SPEC
    else
        local s = hit_sphere
        local cx, cy, cz = s.center[1], s.center[2], s.center[3]
        local inv_r = 1 / s.radius
        nx = (hx - cx) * inv_r
        ny = (hy - cy) * inv_r
        nz = (hz - cz) * inv_r
        obj_color = s.color
        refl = s.refl
        spec_exp = s.spec
    end

    -- Ambient
    local cr = obj_color[1] * AMBIENT
    local cg = obj_color[2] * AMBIENT
    local cb = obj_color[3] * AMBIENT

    -- Lighting (Phong)
    for i = 1, #lights do
        local light = lights[i]
        local lx = light.pos[1] - hx
        local ly = light.pos[2] - hy
        local lz = light.pos[3] - hz
        local ld = sqrt(lx*lx + ly*ly + lz*lz)
        lx, ly, lz = lx/ld, ly/ld, lz/ld

        local nDotL = nx*lx + ny*ly + nz*lz
        if nDotL > 0 then
            if not in_shadow(hx, hy, hz, light.pos[1], light.pos[2], light.pos[3]) then
                local intensity = light.intensity

                -- Diffuse
                local diff = nDotL * intensity
                cr = cr + obj_color[1] * diff
                cg = cg + obj_color[2] * diff
                cb = cb + obj_color[3] * diff

                -- Specular (reflect -lightDir over normal)
                -- reflect(-L, N) = -L - 2*dot(-L,N)*N = 2*dot(L,N)*N - L
                local rlx = 2*nDotL*nx - lx
                local rly = 2*nDotL*ny - ly
                local rlz = 2*nDotL*nz - lz
                -- dot(-rayDir, reflectedLight)
                local specDot = (-dx)*rlx + (-dy)*rly + (-dz)*rlz
                if specDot > 0 then
                    local sp = pow(specDot, spec_exp) * intensity
                    cr = cr + sp
                    cg = cg + sp
                    cb = cb + sp
                end
            end
        end
    end

    -- Reflection
    if refl > 0 and depth < MAX_DEPTH then
        -- reflect ray direction over normal
        local rdotn = dx*nx + dy*ny + dz*nz
        local rrx = dx - 2*rdotn*nx
        local rry = dy - 2*rdotn*ny
        local rrz = dz - 2*rdotn*nz
        local ref = trace(hx, hy, hz, rrx, rry, rrz, depth + 1)
        local one_minus_refl = 1 - refl
        cr = cr * one_minus_refl + ref[1] * refl
        cg = cg * one_minus_refl + ref[2] * refl
        cb = cb * one_minus_refl + ref[3] * refl
    end

    return {cr, cg, cb}
end

-- Camera setup
local cam_pos = {0, 1.5, -5}
local look_at = {0, 0.5, 0}
local up = {0, 1, 0}
local fov = 60

local forward = vnorm(vsub(look_at, cam_pos))
local right = vnorm(vcross(forward, up))
local cam_up = vcross(right, forward)

local aspect = WIDTH / HEIGHT
local fov_rad = fov * math.pi / 180
local half_h = math.tan(fov_rad / 2)
local half_w = half_h * aspect

-- Render
local header = "P6\n" .. WIDTH .. " " .. HEIGHT .. "\n255\n"
io.write(header)

local inv_gamma = 1 / 2.2
local chunks = {}
local chunk_size = 0
local FLUSH_SIZE = 65536

for y = 0, HEIGHT - 1 do
    for x = 0, WIDTH - 1 do
        -- Map pixel to [-1, 1]
        local px = (2 * (x + 0.5) / WIDTH - 1) * half_w
        local py = (1 - 2 * (y + 0.5) / HEIGHT) * half_h

        local dx = forward[1] + px * right[1] + py * cam_up[1]
        local dy = forward[2] + px * right[2] + py * cam_up[2]
        local dz = forward[3] + px * right[3] + py * cam_up[3]
        local dl = sqrt(dx*dx + dy*dy + dz*dz)
        dx, dy, dz = dx/dl, dy/dl, dz/dl

        local col = trace(cam_pos[1], cam_pos[2], cam_pos[3], dx, dy, dz, 0)

        -- Gamma correction and clamp
        local r = col[1]
        local g = col[2]
        local b = col[3]
        if r > 1 then r = 1 elseif r < 0 then r = 0 end
        if g > 1 then g = 1 elseif g < 0 then g = 0 end
        if b > 1 then b = 1 elseif b < 0 then b = 0 end

        r = pow(r, inv_gamma)
        g = pow(g, inv_gamma)
        b = pow(b, inv_gamma)

        local ri = floor(r * 255 + 0.5)
        local gi = floor(g * 255 + 0.5)
        local bi = floor(b * 255 + 0.5)

        chunks[#chunks + 1] = char(ri, gi, bi)
        chunk_size = chunk_size + 3

        if chunk_size >= FLUSH_SIZE then
            io.write(table.concat(chunks))
            chunks = {}
            chunk_size = 0
        end
    end
end

if chunk_size > 0 then
    io.write(table.concat(chunks))
end
