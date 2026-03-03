import java.io.BufferedOutputStream

const val MAX_DEPTH = 5
const val AMBIENT = 0.1
const val EPSILON = 1e-6
const val NUM_SPHERES = 5
const val NUM_LIGHTS = 2
const val GROUND_Y = 0.0
const val GROUND_REFL = 0.3
const val GROUND_SPEC = 10.0

// Sphere data (center x,y,z, radius, color r,g,b, reflectivity, specular)
val sphereCX = doubleArrayOf(-2.0, 0.0, 2.0, -0.75, 1.5)
val sphereCY = doubleArrayOf(1.0, 0.75, 1.0, 0.4, 0.5)
val sphereCZ = doubleArrayOf(0.0, 0.0, 0.0, -1.5, -1.0)
val sphereR = doubleArrayOf(1.0, 0.75, 1.0, 0.4, 0.5)
val sphereColR = doubleArrayOf(0.9, 0.2, 0.2, 0.9, 0.9)
val sphereColG = doubleArrayOf(0.2, 0.9, 0.2, 0.9, 0.2)
val sphereColB = doubleArrayOf(0.2, 0.2, 0.9, 0.2, 0.9)
val sphereRefl = doubleArrayOf(0.3, 0.2, 0.4, 0.5, 0.6)
val sphereSpec = doubleArrayOf(50.0, 30.0, 80.0, 100.0, 60.0)

val lightPX = doubleArrayOf(-3.0, 3.0)
val lightPY = doubleArrayOf(5.0, 3.0)
val lightPZ = doubleArrayOf(-3.0, -1.0)
val lightInt = doubleArrayOf(0.7, 0.4)

// Inline vector ops to avoid allocation
inline fun dot(ax: Double, ay: Double, az: Double, bx: Double, by: Double, bz: Double): Double =
    ax * bx + ay * by + az * bz

inline fun lenSq(x: Double, y: Double, z: Double): Double = x * x + y * y + z * z

// Hit record stored as thread-local mutable state
var hitT = 0.0
var hitType = 0 // 0=none, 1=sphere, 2=ground
var hitIdx = 0
var hitPX = 0.0; var hitPY = 0.0; var hitPZ = 0.0
var hitNX = 0.0; var hitNY = 0.0; var hitNZ = 0.0
var hitCR = 0.0; var hitCG = 0.0; var hitCB = 0.0
var hitRefl = 0.0; var hitSpecExp = 0.0

fun intersectScene(
    rox: Double, roy: Double, roz: Double,
    rdx: Double, rdy: Double, rdz: Double
): Boolean {
    hitT = 1e20
    hitType = 0

    // Spheres
    for (i in 0 until NUM_SPHERES) {
        val ocx = rox - sphereCX[i]
        val ocy = roy - sphereCY[i]
        val ocz = roz - sphereCZ[i]
        val b = ocx * rdx + ocy * rdy + ocz * rdz
        val c = ocx * ocx + ocy * ocy + ocz * ocz - sphereR[i] * sphereR[i]
        val disc = b * b - c
        if (disc > 0) {
            val sqrtDisc = Math.sqrt(disc)
            var t = -b - sqrtDisc
            if (t < EPSILON) t = -b + sqrtDisc
            if (t > EPSILON && t < hitT) {
                hitT = t
                hitType = 1
                hitIdx = i
            }
        }
    }

    // Ground plane y=0
    if (Math.abs(rdy) > EPSILON) {
        val t = (GROUND_Y - roy) / rdy
        if (t > EPSILON && t < hitT) {
            hitT = t
            hitType = 2
        }
    }

    if (hitType == 0) return false

    hitPX = rox + rdx * hitT
    hitPY = roy + rdy * hitT
    hitPZ = roz + rdz * hitT

    if (hitType == 1) {
        val dx = hitPX - sphereCX[hitIdx]
        val dy = hitPY - sphereCY[hitIdx]
        val dz = hitPZ - sphereCZ[hitIdx]
        val invLen = 1.0 / Math.sqrt(dx * dx + dy * dy + dz * dz)
        hitNX = dx * invLen; hitNY = dy * invLen; hitNZ = dz * invLen
        hitCR = sphereColR[hitIdx]; hitCG = sphereColG[hitIdx]; hitCB = sphereColB[hitIdx]
        hitRefl = sphereRefl[hitIdx]
        hitSpecExp = sphereSpec[hitIdx]
    } else {
        hitNX = 0.0; hitNY = 1.0; hitNZ = 0.0
        val fx = if (hitPX < 0) Math.floor(hitPX) - 1 else Math.floor(hitPX)
        val fz = if (hitPZ < 0) Math.floor(hitPZ) - 1 else Math.floor(hitPZ)
        val check = (fx.toInt() + fz.toInt()) and 1
        if (check == 0) { hitCR = 0.8; hitCG = 0.8; hitCB = 0.8 }
        else { hitCR = 0.3; hitCG = 0.3; hitCB = 0.3 }
        hitRefl = GROUND_REFL
        hitSpecExp = GROUND_SPEC
    }
    return true
}

fun shadowHit(
    rox: Double, roy: Double, roz: Double,
    rdx: Double, rdy: Double, rdz: Double,
    maxDist: Double
): Boolean {
    for (i in 0 until NUM_SPHERES) {
        val ocx = rox - sphereCX[i]
        val ocy = roy - sphereCY[i]
        val ocz = roz - sphereCZ[i]
        val b = ocx * rdx + ocy * rdy + ocz * rdz
        val c = ocx * ocx + ocy * ocy + ocz * ocz - sphereR[i] * sphereR[i]
        val disc = b * b - c
        if (disc > 0) {
            val sqrtDisc = Math.sqrt(disc)
            var t = -b - sqrtDisc
            if (t > EPSILON && t < maxDist) return true
            t = -b + sqrtDisc
            if (t > EPSILON && t < maxDist) return true
        }
    }
    // Ground
    if (Math.abs(rdy) > EPSILON) {
        val t = (GROUND_Y - roy) / rdy
        if (t > EPSILON && t < maxDist) return true
    }
    return false
}

fun sky(rdy: Double, rdx: Double, rdz: Double): Double = 0.0 // placeholder, computed inline

// Using DoubleArray(3) for return to avoid object allocation
val traceResult = DoubleArray(3)

fun trace(
    rox: Double, roy: Double, roz: Double,
    rdx: Double, rdy: Double, rdz: Double,
    depth: Int,
    outR: DoubleArray, outIdx: Int // write 3 values starting at outIdx
) {
    if (depth > MAX_DEPTH) {
        val t = 0.5 * (rdy + 1.0)
        outR[outIdx] = 1.0 - t + 0.5 * t
        outR[outIdx + 1] = 1.0 - t + 0.7 * t
        outR[outIdx + 2] = 1.0 - t + 1.0 * t
        return
    }

    if (!intersectScene(rox, roy, roz, rdx, rdy, rdz)) {
        val t = 0.5 * (rdy + 1.0)
        outR[outIdx] = 1.0 - t + 0.5 * t
        outR[outIdx + 1] = 1.0 - t + 0.7 * t
        outR[outIdx + 2] = 1.0 - t + 1.0 * t
        return
    }

    // Save hit data (recursive calls overwrite globals)
    val hpx = hitPX; val hpy = hitPY; val hpz = hitPZ
    val hnx = hitNX; val hny = hitNY; val hnz = hitNZ
    val hcr = hitCR; val hcg = hitCG; val hcb = hitCB
    val hr = hitRefl; val hse = hitSpecExp

    // Ambient
    var lr = hcr * AMBIENT
    var lg = hcg * AMBIENT
    var lb = hcb * AMBIENT

    // Lighting
    for (l in 0 until NUM_LIGHTS) {
        val tlx = lightPX[l] - hpx
        val tly = lightPY[l] - hpy
        val tlz = lightPZ[l] - hpz
        val dist = Math.sqrt(tlx * tlx + tly * tly + tlz * tlz)
        val invDist = 1.0 / dist
        val ldx = tlx * invDist
        val ldy = tly * invDist
        val ldz = tlz * invDist

        // Shadow check
        val sox = hpx + hnx * EPSILON
        val soy = hpy + hny * EPSILON
        val soz = hpz + hnz * EPSILON
        if (shadowHit(sox, soy, soz, ldx, ldy, ldz, dist)) continue

        val nDotL = hnx * ldx + hny * ldy + hnz * ldz
        if (nDotL > 0) {
            val diff = nDotL * lightInt[l]
            lr += hcr * diff
            lg += hcg * diff
            lb += hcb * diff

            // Specular: reflect(-lightDir, normal)
            val negLdx = -ldx; val negLdy = -ldy; val negLdz = -ldz
            val dotNL2 = 2.0 * (negLdx * hnx + negLdy * hny + negLdz * hnz)
            val reflLx = negLdx - hnx * dotNL2
            val reflLy = negLdy - hny * dotNL2
            val reflLz = negLdz - hnz * dotNL2

            val specAngle = Math.max(0.0, (-rdx) * reflLx + (-rdy) * reflLy + (-rdz) * reflLz)
            val spec = Math.pow(specAngle, hse) * lightInt[l]
            lr += spec; lg += spec; lb += spec
        }
    }

    // Reflection
    if (hr > 0 && depth < MAX_DEPTH) {
        val dotRN2 = 2.0 * (rdx * hnx + rdy * hny + rdz * hnz)
        val reflDx = rdx - hnx * dotRN2
        val reflDy = rdy - hny * dotRN2
        val reflDz = rdz - hnz * dotRN2
        val rox2 = hpx + hnx * EPSILON
        val roy2 = hpy + hny * EPSILON
        val roz2 = hpz + hnz * EPSILON

        trace(rox2, roy2, roz2, reflDx, reflDy, reflDz, depth + 1, outR, outIdx)
        val oneMinusR = 1.0 - hr
        lr = lr * oneMinusR + outR[outIdx] * hr
        lg = lg * oneMinusR + outR[outIdx + 1] * hr
        lb = lb * oneMinusR + outR[outIdx + 2] * hr
    }

    outR[outIdx] = lr
    outR[outIdx + 1] = lg
    outR[outIdx + 2] = lb
}

fun toByte(v: Double): Byte {
    val clamped = if (v < 0.0) 0.0 else if (v > 1.0) 1.0 else v
    val gamma = Math.pow(clamped, 1.0 / 2.2)
    return (gamma * 255.0 + 0.5).toInt().toByte()
}

fun main(args: Array<String>) {
    val width = args[0].toInt()
    val height = args[1].toInt()

    // Camera setup
    val camPX = 0.0; val camPY = 1.5; val camPZ = -5.0
    val lookX = 0.0; val lookY = 0.5; val lookZ = 0.0

    val fwdX = lookX - camPX; val fwdY = lookY - camPY; val fwdZ = lookZ - camPZ
    val fwdLen = Math.sqrt(fwdX * fwdX + fwdY * fwdY + fwdZ * fwdZ)
    val fx = fwdX / fwdLen; val fy = fwdY / fwdLen; val fz = fwdZ / fwdLen

    // up = (0,1,0)
    // right = cross(forward, up)
    val rx = fy * 0.0 - fz * 1.0
    val ry = fz * 0.0 - fx * 0.0
    val rz = fx * 1.0 - fy * 0.0
    val rLen = Math.sqrt(rx * rx + ry * ry + rz * rz)
    val rightX = rx / rLen; val rightY = ry / rLen; val rightZ = rz / rLen

    // camUp = cross(right, forward)
    val cux = rightY * fz - rightZ * fy
    val cuy = rightZ * fx - rightX * fz
    val cuz = rightX * fy - rightY * fx

    val fovRad = 60.0 * Math.PI / 180.0
    val halfH = Math.tan(fovRad / 2.0)
    val aspect = width.toDouble() / height.toDouble()
    val halfW = aspect * halfH

    val out = BufferedOutputStream(System.out, 1 shl 20)
    val header = "P6\n${width} ${height}\n255\n".toByteArray()
    out.write(header)

    val row = ByteArray(width * 3)
    val color = DoubleArray(3)

    for (j in 0 until height) {
        for (i in 0 until width) {
            val u = (2.0 * ((i + 0.5) / width) - 1.0) * halfW
            val v = (1.0 - 2.0 * ((j + 0.5) / height)) * halfH

            // dir = normalize(forward + right*u + camUp*v)
            val dx = fx + rightX * u + cux * v
            val dy = fy + rightY * u + cuy * v
            val dz = fz + rightZ * u + cuz * v
            val dLen = Math.sqrt(dx * dx + dy * dy + dz * dz)
            val dirX = dx / dLen; val dirY = dy / dLen; val dirZ = dz / dLen

            trace(camPX, camPY, camPZ, dirX, dirY, dirZ, 0, color, 0)

            val idx = i * 3
            row[idx] = toByte(color[0])
            row[idx + 1] = toByte(color[1])
            row[idx + 2] = toByte(color[2])
        }
        out.write(row)
    }
    out.flush()
}
