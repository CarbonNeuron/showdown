with Ada.Command_Line;
with Ada.Numerics.Elementary_Functions;
with Ada.Streams.Stream_IO;

procedure Solution is

   use Ada.Numerics.Elementary_Functions;

   type Vec3 is record
      X, Y, Z : Float := 0.0;
   end record;

   function "+" (A, B : Vec3) return Vec3 is
   begin
      return (A.X + B.X, A.Y + B.Y, A.Z + B.Z);
   end "+";

   function "-" (A, B : Vec3) return Vec3 is
   begin
      return (A.X - B.X, A.Y - B.Y, A.Z - B.Z);
   end "-";

   function "*" (A : Vec3; S : Float) return Vec3 is
   begin
      return (A.X * S, A.Y * S, A.Z * S);
   end "*";

   function "*" (S : Float; A : Vec3) return Vec3 is
   begin
      return (A.X * S, A.Y * S, A.Z * S);
   end "*";

   function Dot (A, B : Vec3) return Float is
   begin
      return A.X * B.X + A.Y * B.Y + A.Z * B.Z;
   end Dot;

   function Cross (A, B : Vec3) return Vec3 is
   begin
      return (A.Y * B.Z - A.Z * B.Y,
              A.Z * B.X - A.X * B.Z,
              A.X * B.Y - A.Y * B.X);
   end Cross;

   function Length (A : Vec3) return Float is
   begin
      return Sqrt (Dot (A, A));
   end Length;

   function Normalize (A : Vec3) return Vec3 is
      L : constant Float := Length (A);
   begin
      if L > 1.0e-12 then
         return A * (1.0 / L);
      else
         return (0.0, 0.0, 0.0);
      end if;
   end Normalize;

   function Mul_Vec (A, B : Vec3) return Vec3 is
   begin
      return (A.X * B.X, A.Y * B.Y, A.Z * B.Z);
   end Mul_Vec;

   type Sphere_Rec is record
      Center : Vec3;
      Radius : Float;
      Color  : Vec3;
      Refl   : Float;
      Spec   : Float;
   end record;

   type Light_Rec is record
      Pos       : Vec3;
      Intensity : Float;
   end record;

   Num_Spheres : constant := 5;
   Num_Lights  : constant := 2;

   Spheres : array (1 .. Num_Spheres) of Sphere_Rec :=
     (1 => (Center => (-2.0, 1.0, 0.0), Radius => 1.0,
            Color => (0.9, 0.2, 0.2), Refl => 0.3, Spec => 50.0),
      2 => (Center => (0.0, 0.75, 0.0), Radius => 0.75,
            Color => (0.2, 0.9, 0.2), Refl => 0.2, Spec => 30.0),
      3 => (Center => (2.0, 1.0, 0.0), Radius => 1.0,
            Color => (0.2, 0.2, 0.9), Refl => 0.4, Spec => 80.0),
      4 => (Center => (-0.75, 0.4, -1.5), Radius => 0.4,
            Color => (0.9, 0.9, 0.2), Refl => 0.5, Spec => 100.0),
      5 => (Center => (1.5, 0.5, -1.0), Radius => 0.5,
            Color => (0.9, 0.2, 0.9), Refl => 0.6, Spec => 60.0));

   Lights : array (1 .. Num_Lights) of Light_Rec :=
     (1 => (Pos => (-3.0, 5.0, -3.0), Intensity => 0.7),
      2 => (Pos => (3.0, 3.0, -1.0), Intensity => 0.4));

   Ambient : constant Float := 0.1;

   -- Camera
   Cam_Pos : constant Vec3 := (0.0, 1.5, -5.0);
   Look_At : constant Vec3 := (0.0, 0.5, 0.0);
   Up_Vec  : constant Vec3 := (0.0, 1.0, 0.0);
   FOV     : constant Float := 60.0;

   Forward_Dir : constant Vec3 := Normalize (Look_At - Cam_Pos);
   Right_Dir   : constant Vec3 := Normalize (Cross (Forward_Dir, Up_Vec));
   Cam_Up      : constant Vec3 := Cross (Right_Dir, Forward_Dir);

   Half_FOV : constant Float := Tan ((FOV * Ada.Numerics.Pi / 180.0) / 2.0);

   Max_Depth : constant := 5;
   Epsilon   : constant Float := 1.0e-4;

   -- Ground at y=0 checkerboard
   Ground_Y     : constant Float := 0.0;
   Ground_Refl  : constant Float := 0.3;
   Ground_Spec  : constant Float := 10.0;
   Sq_Size      : constant Float := 1.0;

   function Floor_F (V : Float) return Integer is
      I : Integer := Integer (V);
   begin
      if Float (I) > V then
         I := I - 1;
      end if;
      return I;
   end Floor_F;

   function Ground_Color (P : Vec3) return Vec3 is
      FX, FZ : Integer;
      Chk    : Integer;
   begin
      if P.X < 0.0 then
         FX := Floor_F (P.X - 1.0);
      else
         FX := Floor_F (P.X);
      end if;
      if P.Z < 0.0 then
         FZ := Floor_F (P.Z - 1.0);
      else
         FZ := Floor_F (P.Z);
      end if;
      Chk := (FX + FZ) mod 2;
      if Chk < 0 then
         Chk := Chk + 2;
      end if;
      if Chk = 0 then
         return (0.8, 0.8, 0.8);
      else
         return (0.3, 0.3, 0.3);
      end if;
   end Ground_Color;

   function Sky_Color (Dir : Vec3) return Vec3 is
      T : Float;
   begin
      T := 0.5 * (Dir.Y + 1.0);
      if T < 0.0 then T := 0.0; end if;
      if T > 1.0 then T := 1.0; end if;
      return (1.0, 1.0, 1.0) * (1.0 - T) + (0.5, 0.7, 1.0) * T;
   end Sky_Color;

   type Hit_Kind is (Hit_None, Hit_Sphere, Hit_Ground);

   type Hit_Info is record
      Kind     : Hit_Kind := Hit_None;
      T        : Float := 1.0e30;
      Point    : Vec3;
      Normal   : Vec3;
      Color    : Vec3;
      Refl     : Float := 0.0;
      Spec_Exp : Float := 0.0;
      Sphere_Idx : Integer := 0;
   end record;

   function Intersect_Sphere (Origin, Dir : Vec3; S : Sphere_Rec;
                               T_Out : out Float) return Boolean is
      OC   : constant Vec3 := Origin - S.Center;
      A    : constant Float := Dot (Dir, Dir);
      B    : constant Float := 2.0 * Dot (OC, Dir);
      C    : constant Float := Dot (OC, OC) - S.Radius * S.Radius;
      Disc : constant Float := B * B - 4.0 * A * C;
      Sq   : Float;
      T1, T2 : Float;
   begin
      if Disc < 0.0 then
         T_Out := 1.0e30;
         return False;
      end if;
      Sq := Sqrt (Disc);
      T1 := (-B - Sq) / (2.0 * A);
      T2 := (-B + Sq) / (2.0 * A);
      if T1 > Epsilon then
         T_Out := T1;
         return True;
      elsif T2 > Epsilon then
         T_Out := T2;
         return True;
      else
         T_Out := 1.0e30;
         return False;
      end if;
   end Intersect_Sphere;

   function Find_Hit (Origin, Dir : Vec3) return Hit_Info is
      H     : Hit_Info;
      T_Val : Float;
   begin
      H.Kind := Hit_None;
      H.T := 1.0e30;

      -- Check spheres
      for I in Spheres'Range loop
         if Intersect_Sphere (Origin, Dir, Spheres (I), T_Val) then
            if T_Val < H.T then
               H.Kind := Hit_Sphere;
               H.T := T_Val;
               H.Point := Origin + Dir * T_Val;
               H.Normal := Normalize (H.Point - Spheres (I).Center);
               H.Color := Spheres (I).Color;
               H.Refl := Spheres (I).Refl;
               H.Spec_Exp := Spheres (I).Spec;
               H.Sphere_Idx := I;
            end if;
         end if;
      end loop;

      -- Check ground plane y=0
      if abs (Dir.Y) > 1.0e-12 then
         T_Val := (Ground_Y - Origin.Y) / Dir.Y;
         if T_Val > Epsilon and then T_Val < H.T then
            H.Kind := Hit_Ground;
            H.T := T_Val;
            H.Point := Origin + Dir * T_Val;
            H.Normal := (0.0, 1.0, 0.0);
            H.Color := Ground_Color (H.Point);
            H.Refl := Ground_Refl;
            H.Spec_Exp := Ground_Spec;
            H.Sphere_Idx := 0;
         end if;
      end if;

      return H;
   end Find_Hit;

   function Is_Shadowed (Point, Light_Pos : Vec3) return Boolean is
      Dir  : constant Vec3 := Light_Pos - Point;
      Dist : constant Float := Length (Dir);
      Ndir : constant Vec3 := Normalize (Dir);
      T_Val : Float;
   begin
      -- Check spheres
      for I in Spheres'Range loop
         if Intersect_Sphere (Point, Ndir, Spheres (I), T_Val) then
            if T_Val < Dist then
               return True;
            end if;
         end if;
      end loop;

      -- Check ground
      if abs (Ndir.Y) > 1.0e-12 then
         T_Val := (Ground_Y - Point.Y) / Ndir.Y;
         if T_Val > Epsilon and then T_Val < Dist then
            return True;
         end if;
      end if;

      return False;
   end Is_Shadowed;

   function Trace (Origin, Dir : Vec3; Depth : Integer) return Vec3 is
      H       : Hit_Info;
      Local   : Vec3 := (0.0, 0.0, 0.0);
      L_Dir   : Vec3;
      NDotL   : Float;
      V       : Vec3;
      R_Spec  : Vec3;
      Spec_F  : Float;
      Refl_Dir : Vec3;
      Refl_Col : Vec3;
      Final   : Vec3;
      Shad_Orig : Vec3;
   begin
      if Depth > Max_Depth then
         return Sky_Color (Dir);
      end if;

      H := Find_Hit (Origin, Dir);

      if H.Kind = Hit_None then
         return Sky_Color (Dir);
      end if;

      -- Ambient
      Local := H.Color * Ambient;

      -- Offset point for shadow rays
      Shad_Orig := H.Point + H.Normal * Epsilon;

      -- For each light
      for I in Lights'Range loop
         if not Is_Shadowed (Shad_Orig, Lights (I).Pos) then
            L_Dir := Normalize (Lights (I).Pos - H.Point);
            NDotL := Dot (H.Normal, L_Dir);
            if NDotL > 0.0 then
               -- Diffuse
               Local := Local + H.Color * (NDotL * Lights (I).Intensity);

               -- Specular (white)
               V := Normalize (Origin - H.Point);
               R_Spec := H.Normal * (2.0 * NDotL) - L_Dir;
               Spec_F := Dot (V, Normalize (R_Spec));
               if Spec_F > 0.0 then
                  Spec_F := Spec_F ** H.Spec_Exp * Lights (I).Intensity;
                  Local := Local + (1.0, 1.0, 1.0) * Spec_F;
               end if;
            end if;
         end if;
      end loop;

      -- Reflection
      if H.Refl > 0.0 and then Depth < Max_Depth then
         Refl_Dir := Dir - H.Normal * (2.0 * Dot (Dir, H.Normal));
         Refl_Col := Trace (Shad_Orig, Normalize (Refl_Dir), Depth + 1);
         Final := Local * (1.0 - H.Refl) + Refl_Col * H.Refl;
      else
         Final := Local;
      end if;

      return Final;
   end Trace;

   function Clamp (V : Float) return Float is
   begin
      if V < 0.0 then return 0.0; end if;
      if V > 1.0 then return 1.0; end if;
      return V;
   end Clamp;

   function Gamma (V : Float) return Float is
   begin
      return Clamp (V) ** (1.0 / 2.2);
   end Gamma;

   function To_Byte (V : Float) return Integer is
      I : Integer;
   begin
      I := Integer (Gamma (V) * 255.0);
      if I < 0 then I := 0; end if;
      if I > 255 then I := 255; end if;
      return I;
   end To_Byte;

   Width  : Integer;
   Height : Integer;

   use Ada.Streams;
   use Ada.Streams.Stream_IO;

   F      : Ada.Streams.Stream_IO.File_Type;
   S      : Stream_Access;

   procedure Write_String (Str : String) is
      Buf : Stream_Element_Array (1 .. Stream_Element_Offset (Str'Length));
   begin
      for I in Str'Range loop
         Buf (Stream_Element_Offset (I - Str'First + 1)) :=
           Stream_Element (Character'Pos (Str (I)));
      end loop;
      Write (S.all, Buf);
   end Write_String;

   procedure Write_Byte (B : Integer) is
      Buf : Stream_Element_Array (1 .. 1);
   begin
      Buf (1) := Stream_Element (B);
      Write (S.all, Buf);
   end Write_Byte;

   Col   : Vec3;
   U, V_Coord : Float;
   PX, PY : Float;
   Ray_Dir : Vec3;
   Aspect : Float;
   Width_Str  : constant String := Ada.Command_Line.Argument (1);
   Height_Str : constant String := Ada.Command_Line.Argument (2);

begin
   Width  := Integer'Value (Width_Str);
   Height := Integer'Value (Height_Str);
   Aspect := Float (Width) / Float (Height);

   -- Write to stdout (fd 1) via stream IO
   Open (F, Out_File, "/dev/stdout");
   S := Stream (F);

   -- PPM header
   declare
      W_Img : constant String := Integer'Image (Width);
      H_Img : constant String := Integer'Image (Height);
      Header : constant String :=
        "P6" & ASCII.LF &
        W_Img (W_Img'First + 1 .. W_Img'Last) & " " &
        H_Img (H_Img'First + 1 .. H_Img'Last) & ASCII.LF &
        "255" & ASCII.LF;
   begin
      Write_String (Header);
   end;

   for J in 0 .. Height - 1 loop
      for I in 0 .. Width - 1 loop
         U := (2.0 * (Float (I) + 0.5) / Float (Width) - 1.0) * Aspect * Half_FOV;
         V_Coord := (1.0 - 2.0 * (Float (J) + 0.5) / Float (Height)) * Half_FOV;

         Ray_Dir := Normalize (Forward_Dir + Right_Dir * U + Cam_Up * V_Coord);
         Col := Trace (Cam_Pos, Ray_Dir, 0);

         Write_Byte (To_Byte (Col.X));
         Write_Byte (To_Byte (Col.Y));
         Write_Byte (To_Byte (Col.Z));
      end loop;
   end loop;

   Close (F);
end Solution;
