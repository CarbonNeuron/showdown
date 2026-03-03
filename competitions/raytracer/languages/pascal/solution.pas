{$mode objfpc}
program solution;

uses
  Math, SysUtils;

type
  TVec3 = record
    x, y, z: Double;
  end;

  TSphere = record
    center: TVec3;
    radius: Double;
    color: TVec3;
    refl: Double;
    specExp: Double;
  end;

  TLight = record
    pos: TVec3;
    intensity: Double;
  end;

  TRay = record
    origin, dir: TVec3;
  end;

  THitRecord = record
    hit: Boolean;
    t: Double;
    point, normal, color: TVec3;
    refl, specExp: Double;
  end;

const
  NUM_SPHERES = 5;
  NUM_LIGHTS = 2;
  MAX_DEPTH = 5;
  EPSILON = 1e-6;
  INF = 1e30;

var
  spheres: array[0..NUM_SPHERES-1] of TSphere;
  lights: array[0..NUM_LIGHTS-1] of TLight;
  camPos, lookAt, camUp, camForward, camRight, camUpVec: TVec3;
  halfW, halfH: Double;
  imgWidth, imgHeight: Integer;
  pixels: array of Byte;

function Vec(ax, ay, az: Double): TVec3;
begin
  Vec.x := ax;
  Vec.y := ay;
  Vec.z := az;
end;

function VAdd(a, b: TVec3): TVec3;
begin
  VAdd.x := a.x + b.x;
  VAdd.y := a.y + b.y;
  VAdd.z := a.z + b.z;
end;

function VSub(a, b: TVec3): TVec3;
begin
  VSub.x := a.x - b.x;
  VSub.y := a.y - b.y;
  VSub.z := a.z - b.z;
end;

function VMul(a: TVec3; s: Double): TVec3;
begin
  VMul.x := a.x * s;
  VMul.y := a.y * s;
  VMul.z := a.z * s;
end;

function VMulV(a, b: TVec3): TVec3;
begin
  VMulV.x := a.x * b.x;
  VMulV.y := a.y * b.y;
  VMulV.z := a.z * b.z;
end;

function VDot(a, b: TVec3): Double;
begin
  VDot := a.x * b.x + a.y * b.y + a.z * b.z;
end;

function VCross(a, b: TVec3): TVec3;
begin
  VCross.x := a.y * b.z - a.z * b.y;
  VCross.y := a.z * b.x - a.x * b.z;
  VCross.z := a.x * b.y - a.y * b.x;
end;

function VLen(a: TVec3): Double;
begin
  VLen := Sqrt(VDot(a, a));
end;

function VNorm(a: TVec3): TVec3;
var
  l: Double;
begin
  l := VLen(a);
  if l > EPSILON then
    VNorm := VMul(a, 1.0 / l)
  else
    VNorm := Vec(0, 0, 0);
end;

function VNeg(a: TVec3): TVec3;
begin
  VNeg.x := -a.x;
  VNeg.y := -a.y;
  VNeg.z := -a.z;
end;

function VReflect(v, n: TVec3): TVec3;
begin
  VReflect := VSub(v, VMul(n, 2.0 * VDot(v, n)));
end;

function Clamp01(v: Double): Double;
begin
  if v < 0.0 then
    Clamp01 := 0.0
  else if v > 1.0 then
    Clamp01 := 1.0
  else
    Clamp01 := v;
end;

function VClamp(v: TVec3): TVec3;
begin
  VClamp := Vec(Clamp01(v.x), Clamp01(v.y), Clamp01(v.z));
end;

procedure InitScene;
begin
  { Spheres }
  spheres[0].center := Vec(-2, 1, 0);
  spheres[0].radius := 1.0;
  spheres[0].color := Vec(0.9, 0.2, 0.2);
  spheres[0].refl := 0.3;
  spheres[0].specExp := 50;

  spheres[1].center := Vec(0, 0.75, 0);
  spheres[1].radius := 0.75;
  spheres[1].color := Vec(0.2, 0.9, 0.2);
  spheres[1].refl := 0.2;
  spheres[1].specExp := 30;

  spheres[2].center := Vec(2, 1, 0);
  spheres[2].radius := 1.0;
  spheres[2].color := Vec(0.2, 0.2, 0.9);
  spheres[2].refl := 0.4;
  spheres[2].specExp := 80;

  spheres[3].center := Vec(-0.75, 0.4, -1.5);
  spheres[3].radius := 0.4;
  spheres[3].color := Vec(0.9, 0.9, 0.2);
  spheres[3].refl := 0.5;
  spheres[3].specExp := 100;

  spheres[4].center := Vec(1.5, 0.5, -1);
  spheres[4].radius := 0.5;
  spheres[4].color := Vec(0.9, 0.2, 0.9);
  spheres[4].refl := 0.6;
  spheres[4].specExp := 60;

  { Lights }
  lights[0].pos := Vec(-3, 5, -3);
  lights[0].intensity := 0.7;

  lights[1].pos := Vec(3, 3, -1);
  lights[1].intensity := 0.4;

  { Camera }
  camPos := Vec(0, 1.5, -5);
  lookAt := Vec(0, 0.5, 0);
  camUp := Vec(0, 1, 0);
end;

procedure SetupCamera;
var
  fovRad, aspect: Double;
begin
  fovRad := 60.0 * Pi / 180.0;
  aspect := imgWidth / imgHeight;
  camForward := VNorm(VSub(lookAt, camPos));
  camRight := VNorm(VCross(camForward, camUp));
  camUpVec := VCross(camRight, camForward);
  halfH := Tan(fovRad / 2.0);
  halfW := aspect * halfH;
end;

function IntersectSphere(const ray: TRay; const sp: TSphere; out tHit: Double): Boolean;
var
  oc: TVec3;
  a, b, c, disc, sq, t0, t1: Double;
begin
  IntersectSphere := False;
  oc := VSub(ray.origin, sp.center);
  a := VDot(ray.dir, ray.dir);
  b := 2.0 * VDot(oc, ray.dir);
  c := VDot(oc, oc) - sp.radius * sp.radius;
  disc := b * b - 4.0 * a * c;
  if disc < 0 then Exit;
  sq := Sqrt(disc);
  t0 := (-b - sq) / (2.0 * a);
  t1 := (-b + sq) / (2.0 * a);
  if t0 > EPSILON then
  begin
    tHit := t0;
    IntersectSphere := True;
  end
  else if t1 > EPSILON then
  begin
    tHit := t1;
    IntersectSphere := True;
  end;
end;

function IntersectGround(const ray: TRay; out tHit: Double): Boolean;
begin
  IntersectGround := False;
  if Abs(ray.dir.y) < EPSILON then Exit;
  tHit := -ray.origin.y / ray.dir.y;
  if tHit > EPSILON then
    IntersectGround := True;
end;

function CheckerColor(p: TVec3): TVec3;
var
  fx, fz: Double;
  ix, iz, check: Integer;
begin
  if p.x < 0 then
    fx := Floor(p.x) - 1
  else
    fx := Floor(p.x);
  if p.z < 0 then
    fz := Floor(p.z) - 1
  else
    fz := Floor(p.z);
  ix := Trunc(fx);
  iz := Trunc(fz);
  check := (ix + iz) and 1;
  if check = 0 then
    CheckerColor := Vec(0.8, 0.8, 0.8)
  else
    CheckerColor := Vec(0.3, 0.3, 0.3);
end;

function TraceNearest(const ray: TRay): THitRecord;
var
  hr: THitRecord;
  bestT, tHit: Double;
  i: Integer;
  p, n: TVec3;
begin
  hr.hit := False;
  bestT := INF;

  { Check spheres }
  for i := 0 to NUM_SPHERES - 1 do
  begin
    if IntersectSphere(ray, spheres[i], tHit) then
    begin
      if tHit < bestT then
      begin
        bestT := tHit;
        p := VAdd(ray.origin, VMul(ray.dir, tHit));
        n := VNorm(VSub(p, spheres[i].center));
        hr.hit := True;
        hr.t := tHit;
        hr.point := p;
        hr.normal := n;
        hr.color := spheres[i].color;
        hr.refl := spheres[i].refl;
        hr.specExp := spheres[i].specExp;
      end;
    end;
  end;

  { Check ground }
  if IntersectGround(ray, tHit) then
  begin
    if tHit < bestT then
    begin
      bestT := tHit;
      p := VAdd(ray.origin, VMul(ray.dir, tHit));
      hr.hit := True;
      hr.t := tHit;
      hr.point := p;
      hr.normal := Vec(0, 1, 0);
      hr.color := CheckerColor(p);
      hr.refl := 0.3;
      hr.specExp := 10;
    end;
  end;

  TraceNearest := hr;
end;

function InShadow(const point, lightPos: TVec3): Boolean;
var
  shadowRay: TRay;
  toLight: TVec3;
  dist, tHit: Double;
  i: Integer;
begin
  InShadow := False;
  toLight := VSub(lightPos, point);
  dist := VLen(toLight);
  shadowRay.origin := VAdd(point, VMul(VNorm(toLight), EPSILON * 10));
  shadowRay.dir := VNorm(toLight);

  { Check spheres }
  for i := 0 to NUM_SPHERES - 1 do
  begin
    if IntersectSphere(shadowRay, spheres[i], tHit) then
    begin
      if tHit < dist then
      begin
        InShadow := True;
        Exit;
      end;
    end;
  end;

  { Check ground }
  if IntersectGround(shadowRay, tHit) then
  begin
    if (tHit > EPSILON) and (tHit < dist) then
    begin
      InShadow := True;
      Exit;
    end;
  end;
end;

function Sky(const dir: TVec3): TVec3;
var
  t: Double;
begin
  t := 0.5 * (dir.y + 1.0);
  Sky := VAdd(VMul(Vec(1, 1, 1), 1.0 - t), VMul(Vec(0.5, 0.7, 1.0), t));
end;

function Trace(const ray: TRay; depth: Integer): TVec3;
var
  hr: THitRecord;
  localColor, ambient, diffuse, specular, reflColor, reflDir, lightDir, reflLightDir: TVec3;
  reflRay: TRay;
  nDotL, specAngle, specVal: Double;
  i: Integer;
begin
  if depth > MAX_DEPTH then
  begin
    Trace := Sky(ray.dir);
    Exit;
  end;

  hr := TraceNearest(ray);
  if not hr.hit then
  begin
    Trace := Sky(ray.dir);
    Exit;
  end;

  { Ambient }
  ambient := VMul(hr.color, 0.1);
  localColor := ambient;

  { For each light }
  for i := 0 to NUM_LIGHTS - 1 do
  begin
    if not InShadow(hr.point, lights[i].pos) then
    begin
      lightDir := VNorm(VSub(lights[i].pos, hr.point));
      nDotL := VDot(hr.normal, lightDir);
      if nDotL > 0 then
      begin
        { Diffuse }
        diffuse := VMul(hr.color, nDotL * lights[i].intensity);
        localColor := VAdd(localColor, diffuse);

        { Specular }
        reflLightDir := VReflect(VNeg(lightDir), hr.normal);
        specAngle := VDot(VNeg(ray.dir), reflLightDir);
        if specAngle > 0 then
        begin
          specVal := Power(specAngle, hr.specExp) * lights[i].intensity;
          specular := Vec(specVal, specVal, specVal);
          localColor := VAdd(localColor, specular);
        end;
      end;
    end;
  end;

  { Reflection }
  if (hr.refl > 0) and (depth < MAX_DEPTH) then
  begin
    reflDir := VReflect(ray.dir, hr.normal);
    reflRay.origin := VAdd(hr.point, VMul(reflDir, EPSILON * 10));
    reflRay.dir := reflDir;
    reflColor := Trace(reflRay, depth + 1);
    localColor := VAdd(VMul(localColor, 1.0 - hr.refl), VMul(reflColor, hr.refl));
  end;

  Trace := localColor;
end;

procedure Render;
var
  i, j, idx: Integer;
  u, v: Double;
  ray: TRay;
  dir, color: TVec3;
  r, g, b: Byte;
begin
  SetLength(pixels, imgWidth * imgHeight * 3);
  for j := 0 to imgHeight - 1 do
  begin
    for i := 0 to imgWidth - 1 do
    begin
      u := (2.0 * ((i + 0.5) / imgWidth) - 1.0) * halfW;
      v := (1.0 - 2.0 * ((j + 0.5) / imgHeight)) * halfH;
      dir := VNorm(VAdd(VAdd(camForward, VMul(camRight, u)), VMul(camUpVec, v)));
      ray.origin := camPos;
      ray.dir := dir;
      color := Trace(ray, 0);
      color := VClamp(color);
      { Gamma correction }
      r := Round(Power(color.x, 1.0 / 2.2) * 255.0);
      g := Round(Power(color.y, 1.0 / 2.2) * 255.0);
      b := Round(Power(color.z, 1.0 / 2.2) * 255.0);
      idx := (j * imgWidth + i) * 3;
      pixels[idx] := r;
      pixels[idx + 1] := g;
      pixels[idx + 2] := b;
    end;
  end;
end;

procedure WritePPM;
var
  header: AnsiString;
  headerBytes: array of Byte;
  i: Integer;
begin
  header := 'P6' + #10 + IntToStr(imgWidth) + ' ' + IntToStr(imgHeight) + #10 + '255' + #10;
  SetLength(headerBytes, Length(header));
  for i := 1 to Length(header) do
    headerBytes[i - 1] := Ord(header[i]);

  { Write header }
  FileWrite(StdOutputHandle, headerBytes[0], Length(headerBytes));
  { Write pixel data }
  FileWrite(StdOutputHandle, pixels[0], Length(pixels));
end;

begin
  if ParamCount < 2 then
  begin
    WriteLn(StdErr, 'Usage: solution <width> <height>');
    Halt(1);
  end;
  imgWidth := StrToInt(ParamStr(1));
  imgHeight := StrToInt(ParamStr(2));

  InitScene;
  SetupCamera;
  Render;
  WritePPM;
end.
