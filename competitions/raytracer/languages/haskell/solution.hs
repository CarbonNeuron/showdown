{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE Strict #-}

module Main where

import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Lazy as BL
import Data.Word (Word8)
import System.Environment (getArgs)
import System.IO (stdout, hSetBinaryMode)

data Vec3 = Vec3 !Double !Double !Double

vadd :: Vec3 -> Vec3 -> Vec3
vadd (Vec3 x1 y1 z1) (Vec3 x2 y2 z2) = Vec3 (x1+x2) (y1+y2) (z1+z2)
{-# INLINE vadd #-}

vsub :: Vec3 -> Vec3 -> Vec3
vsub (Vec3 x1 y1 z1) (Vec3 x2 y2 z2) = Vec3 (x1-x2) (y1-y2) (z1-z2)
{-# INLINE vsub #-}

vmul :: Vec3 -> Double -> Vec3
vmul (Vec3 x y z) s = Vec3 (x*s) (y*s) (z*s)
{-# INLINE vmul #-}

vmulv :: Vec3 -> Vec3 -> Vec3
vmulv (Vec3 x1 y1 z1) (Vec3 x2 y2 z2) = Vec3 (x1*x2) (y1*y2) (z1*z2)
{-# INLINE vmulv #-}

vdot :: Vec3 -> Vec3 -> Double
vdot (Vec3 x1 y1 z1) (Vec3 x2 y2 z2) = x1*x2 + y1*y2 + z1*z2
{-# INLINE vdot #-}

vcross :: Vec3 -> Vec3 -> Vec3
vcross (Vec3 x1 y1 z1) (Vec3 x2 y2 z2) =
  Vec3 (y1*z2 - z1*y2) (z1*x2 - x1*z2) (x1*y2 - y1*x2)
{-# INLINE vcross #-}

vlength :: Vec3 -> Double
vlength v = sqrt (vdot v v)
{-# INLINE vlength #-}

vnorm :: Vec3 -> Vec3
vnorm v = let l = vlength v in if l > 0 then vmul v (1.0/l) else v
{-# INLINE vnorm #-}

vneg :: Vec3 -> Vec3
vneg (Vec3 x y z) = Vec3 (-x) (-y) (-z)
{-# INLINE vneg #-}

data Ray = Ray !Vec3 !Vec3  -- origin, direction

data Sphere = Sphere
  { sCenter :: !Vec3
  , sRadius :: !Double
  , sColor  :: !Vec3
  , sRefl   :: !Double
  , sSpec   :: !Double
  }

data Light = Light !Vec3 !Double  -- position, intensity

data HitRecord = HitRecord
  { hT      :: !Double
  , hPoint  :: !Vec3
  , hNormal :: !Vec3
  , hColor  :: !Vec3
  , hRefl   :: !Double
  , hSpecEx :: !Double
  }

spheres :: [Sphere]
spheres =
  [ Sphere (Vec3 (-2) 1 0)      1.0  (Vec3 0.9 0.2 0.2) 0.3 50
  , Sphere (Vec3 0 0.75 0)      0.75 (Vec3 0.2 0.9 0.2) 0.2 30
  , Sphere (Vec3 2 1 0)         1.0  (Vec3 0.2 0.2 0.9) 0.4 80
  , Sphere (Vec3 (-0.75) 0.4 (-1.5)) 0.4  (Vec3 0.9 0.9 0.2) 0.5 100
  , Sphere (Vec3 1.5 0.5 (-1))  0.5  (Vec3 0.9 0.2 0.9) 0.6 60
  ]

lights :: [Light]
lights =
  [ Light (Vec3 (-3) 5 (-3)) 0.7
  , Light (Vec3 3 3 (-1))    0.4
  ]

ambientIntensity :: Double
ambientIntensity = 0.1

intersectSphere :: Ray -> Sphere -> Maybe Double
intersectSphere (Ray ro rd) (Sphere sc sr _ _ _) =
  let !oc = vsub ro sc
      !a  = vdot rd rd
      !b  = 2.0 * vdot oc rd
      !c  = vdot oc oc - sr*sr
      !disc = b*b - 4*a*c
  in if disc < 0
     then Nothing
     else let !sqrtD = sqrt disc
              !t1 = (-b - sqrtD) / (2*a)
              !t2 = (-b + sqrtD) / (2*a)
          in if t1 > 1e-6 then Just t1
             else if t2 > 1e-6 then Just t2
             else Nothing
{-# INLINE intersectSphere #-}

intersectGround :: Ray -> Maybe Double
intersectGround (Ray (Vec3 _ oy _) (Vec3 _ dy _)) =
  if abs dy < 1e-9 then Nothing
  else let !t = -oy / dy
       in if t > 1e-6 then Just t else Nothing
{-# INLINE intersectGround #-}

checkerColor :: Vec3 -> Vec3
checkerColor (Vec3 x _ z) =
  let !fx = if x < 0 then floor (x - 1) else floor x :: Int
      !fz = if z < 0 then floor (z - 1) else floor z :: Int
      !check = (fx + fz) `mod` 2
  in if check == 0
     then Vec3 0.8 0.8 0.8
     else Vec3 0.3 0.3 0.3
{-# INLINE checkerColor #-}

groundRefl :: Double
groundRefl = 0.3

groundSpec :: Double
groundSpec = 10

findClosestHit :: Ray -> Maybe HitRecord
findClosestHit ray@(Ray ro rd) =
  let !groundHit = case intersectGround ray of
        Nothing -> Nothing
        Just t  ->
          let !p = vadd ro (vmul rd t)
              !n = Vec3 0 1 0
              !col = checkerColor p
          in Just (HitRecord t p n col groundRefl groundSpec)

      checkSphere best (Sphere sc sr scol srefl sspec) =
        case intersectSphere ray (Sphere sc sr scol srefl sspec) of
          Nothing -> best
          Just t  ->
            let dominated = case best of
                  Just (HitRecord bt _ _ _ _ _) -> t >= bt
                  Nothing -> False
            in if dominated then best
               else let !p = vadd ro (vmul rd t)
                        !n = vnorm (vsub p sc)
                    in Just (HitRecord t p n scol srefl sspec)

      !sphereHit = foldl checkSphere Nothing spheres

  in case (groundHit, sphereHit) of
       (Nothing, Nothing) -> Nothing
       (Just g, Nothing)  -> Just g
       (Nothing, Just s)  -> Just s
       (Just g, Just s)   -> if hT g < hT s then Just g else Just s

isInShadow :: Vec3 -> Vec3 -> Double -> Bool
isInShadow point lightDir lightDist =
  let !shadowRay = Ray (vadd point (vmul lightDir 1e-4)) lightDir
      -- Check spheres
      sphereBlocked = any (\sp ->
        case intersectSphere shadowRay sp of
          Nothing -> False
          Just t  -> t < lightDist
        ) spheres
      -- Check ground
      groundBlocked = case intersectGround shadowRay of
        Nothing -> False
        Just t  -> t < lightDist
  in sphereBlocked || groundBlocked
{-# INLINE isInShadow #-}

reflect :: Vec3 -> Vec3 -> Vec3
reflect d n = vsub d (vmul n (2.0 * vdot d n))
{-# INLINE reflect #-}

skyColor :: Vec3 -> Vec3
skyColor (Vec3 _ dy _) =
  let !t = 0.5 * (dy + 1.0)
  in vadd (vmul (Vec3 1 1 1) (1.0 - t)) (vmul (Vec3 0.5 0.7 1.0) t)
{-# INLINE skyColor #-}

traceRay :: Ray -> Int -> Vec3
traceRay _ 0 = Vec3 0 0 0
traceRay ray@(Ray _ rd) depth =
  case findClosestHit ray of
    Nothing -> skyColor (vnorm rd)
    Just (HitRecord _ p n col refl specExp) ->
      let -- Ambient
          !ambient = vmul col ambientIntensity

          -- Accumulate lighting from all lights
          addLight (Vec3 dr dg db) (Light lpos lint) =
            let !lv = vsub lpos p
                !ldist = vlength lv
                !ldir = vmul lv (1.0 / ldist)
                !ndotl = vdot n ldir
            in if ndotl <= 0 || isInShadow p ldir ldist
               then Vec3 dr dg db
               else let -- Diffuse
                        !diff = vmul (vmul col ndotl) lint
                        -- Specular (Phong)
                        !reflDir = reflect (vneg ldir) n
                        !viewDir = vneg rd
                        !rdotv = max 0 (vdot reflDir viewDir)
                        !specular = vmul (Vec3 1 1 1) (lint * (rdotv ** specExp))
                        !(Vec3 dx dy dz) = vadd diff specular
                    in Vec3 (dr+dx) (dg+dy) (db+dz)

          !lighting = foldl addLight (Vec3 0 0 0) lights
          !localColor = vadd ambient lighting

          -- Reflection
          !finalColor =
            if refl > 0 && depth > 1
            then let !reflDir = reflect rd n
                     !reflRay = Ray (vadd p (vmul n 1e-4)) (vnorm reflDir)
                     !reflColor = traceRay reflRay (depth - 1)
                 in vadd (vmul localColor (1.0 - refl)) (vmul reflColor refl)
            else localColor

      in finalColor

clamp :: Double -> Double
clamp x
  | x < 0     = 0
  | x > 1     = 1
  | otherwise  = x
{-# INLINE clamp #-}

gamma :: Double -> Double
gamma x = clamp x ** (1.0 / 2.2)
{-# INLINE gamma #-}

toByte :: Double -> Word8
toByte x = round (gamma x * 255.0)
{-# INLINE toByte #-}

main :: IO ()
main = do
  args <- getArgs
  let (width, height) = case args of
        [w, h] -> (read w :: Int, read h :: Int)
        _      -> (800, 600)

  let !camPos    = Vec3 0 1.5 (-5)
      !lookAt    = Vec3 0 0.5 0
      !up        = Vec3 0 1 0
      !forward   = vnorm (vsub lookAt camPos)
      !right     = vnorm (vcross forward up)
      !camUp     = vcross right forward
      !fovRad    = 60.0 * pi / 180.0
      !halfH     = tan (fovRad / 2.0)
      !aspect    = fromIntegral width / fromIntegral height
      !halfW     = aspect * halfH
      !w'        = fromIntegral width
      !h'        = fromIntegral height

  hSetBinaryMode stdout True

  let header = B.string7 "P6\n" <> B.intDec width <> B.char7 ' ' <> B.intDec height <> B.string7 "\n255\n"

  let pixel !j !i =
        let !u = (2.0 * ((fromIntegral i + 0.5) / w') - 1.0) * halfW
            !v = (1.0 - 2.0 * ((fromIntegral j + 0.5) / h')) * halfH
            !dir = vnorm (vadd forward (vadd (vmul right u) (vmul camUp v)))
            !ray = Ray camPos dir
            !(Vec3 r g b) = traceRay ray 5
        in B.word8 (toByte r) <> B.word8 (toByte g) <> B.word8 (toByte b)
      {-# INLINE pixel #-}

  let buildRow !j = mconcat [ pixel j i | i <- [0..width-1] ]

  let body = mconcat [ buildRow j | j <- [0..height-1] ]

  BL.hPut stdout (B.toLazyByteString (header <> body))
