// The hall's lighting (see `scripts/bg_sanctum`). Two modes:
//
// - Lit (`u_lit` 1): the texture times the vertex colour is the surface's
//   albedo, and it is lit per pixel by the open sky and by the hall's lights.
//   The lights repeat down the hall with the bays, so the shader places them
//   itself from the world position (one bay's worth of numbers comes in as
//   uniforms); every surface sees the few that can reach it, whatever its
//   distance down the hall.
// - Emissive (`u_lit` 0): the texture times the vertex colour, as it is.
//   Lamps, glows and flames draw this way, additively.
//
// Both fog with distance; lit surfaces fog toward the air colour, brightened
// by the lamps near them, and emissive ones toward black.

varying vec2 v_vTexcoord;
varying vec4 v_vColour;
varying vec3 v_vPos;
varying vec3 v_vNormal;
varying float v_vFog;

uniform vec3 u_fogcol;
uniform float u_alpharef;
uniform float u_lit;
uniform float u_emit;      // the emissive mode's brightness
uniform float u_fogk;      // how much of the fog applies (lights carry further)

// The surface: specular strength, shininess, how metallic the highlight is
// (a metal tints it with its own colour), and whether the texture's alpha is
// a gloss map rather than coverage (opaque tiles).
uniform vec4 u_mat;

uniform vec3 u_cam;
uniform float u_time;
uniform float u_bay;
// Where each family of lights has woken up to, as a world z: torches, orbs,
// braziers. A light ahead of its front is out.
uniform vec3 u_front;

uniform vec3 u_amb;
// The open roof: its light, and the walls that frame it (half-width of the
// parapets' inner faces, their height). `u_skyspec` is what a polished floor
// reflects of it.
uniform vec3 u_skycol;
uniform vec3 u_skyspec;
uniform vec2 u_trench;
// The moon: the direction toward it, and its light where it clears the walls.
uniform vec3 u_moon;
uniform vec3 u_mooncol;

// Each family: position in its bay (x of the right-hand one, y, z from the
// bay's start), and radius; then colour.
uniform vec4 u_torch;
uniform vec3 u_torchcol;
uniform vec4 u_orb;
uniform vec3 u_orbcol;
uniform vec4 u_braz;
uniform vec3 u_brazcol;
// The moonbeam the opening starts in: where it falls (x and z; y unused),
// the radius of its pool, and its light (black once the hall is awake).
uniform vec4 u_beam;
uniform vec3 u_beamcol;
// Which bays have an alcove: every `x`th, at `y`.
uniform vec2 u_alcove;
// How much of the lamps' light the air holds.
uniform float u_scatter;

const float PI = 3.14159265;
const float HALF_PI = 1.57079633;

// A light's flicker. `s` tells one light from another. The same sum is in
// `hall_flicker`, which sizes the flames to match.
float flicker(float s) {
    float t = u_time;
    return 1.0 + 0.08 * sin(t * 0.13 + s * 12.9898)
               + 0.06 * sin(t * 0.41 + s * 78.233)
               + 0.03 * sin(t * 0.87 + s * 37.719);
}

// How far a light at `z` is on: nothing ahead of the front, then a flare as
// the front passes that settles to steady. The same curve is in
// `hall_ignite`.
float ignite(float front, float z) {
    float k = (front - z) / 240.0;
    if (k <= 0.0) return 0.0;
    return min(k, 1.0) + 1.6 * k * exp(-1.5 * k);
}

// One point light: its diffuse, its highlight and what it puts in the air.
void point_light(vec3 p, vec3 N, vec3 V, vec3 lp, float R, vec3 col,
                 inout vec3 dif, inout vec3 spc, inout vec3 air) {
    vec3 d3 = lp - p;
    float d = length(d3);
    float x = clamp(d / R, 0.0, 1.0);
    float win = 1.0 - x * x;
    win *= win;
    // A soft inverse square, windowed to zero at the radius so a light
    // leaving the candidate set never pops.
    float att = win / (1.0 + 9.0 * x * x);
    vec3 L = d3 / max(d, 1.0);
    float ndl = dot(N, L);
    // A little wrap, so the terminator is soft on stone.
    dif += col * att * clamp((ndl + 0.2) / 1.2, 0.0, 1.0);
    vec3 H = normalize(L + V);
    spc += col * att * pow(max(dot(N, H), 0.0), u_mat.y) * step(0.0, ndl);
    air += col * att;
}

// The angles, in the x-y plane, of the two wall tops as seen from `p`. The
// hall doesn't change along z, so a direction sees the sky exactly when its
// angle in that plane lies between these.
void sky_arc(vec3 p, out float a1, out float a2) {
    a1 = max(atan(u_trench.y - p.y, u_trench.x - p.x), 0.0);
    a2 = atan(u_trench.y - p.y, -u_trench.x - p.x);
    if (a2 < 0.0) a2 += 2.0 * PI;
    a2 = min(a2, PI);
}

// An angle in the x-y plane, folded to [-pi/2, 3pi/2] so a range of them
// round "up" doesn't wrap.
float section_angle(vec2 v) {
    float a = atan(v.y, v.x);
    if (a < -HALF_PI) a += 2.0 * PI;
    return a;
}

void main() {
    vec4 t = texture2D(gm_BaseTexture, v_vTexcoord);

    if (u_lit < 0.5) {
        // The alpha test (which a custom shader must do itself), against the
        // texture's alpha rather than the faded result, so distance fading
        // stays a smooth fade instead of turning into a hard cut.
        if (t.a < u_alpharef) discard;
        vec4 c = v_vColour * t;
        c.rgb *= u_emit;
        c.rgb = mix(c.rgb, u_fogcol, v_vFog * u_fogk);
        gl_FragColor = c;
        return;
    }

    float cover = mix(t.a, 1.0, u_mat.w);
    if (cover < u_alpharef) discard;
    float gloss = u_mat.x * mix(1.0, t.a, u_mat.w);

    vec3 alb = v_vColour.rgb * t.rgb;
    vec3 p = v_vPos;
    vec3 N = normalize(v_vNormal);
    vec3 V = normalize(u_cam - p);
    // Two-sided: every surface is lit on the side the camera sees.
    if (dot(N, V) < 0.0) N = -N;

    // --- the sky ----------------------------------------------------------
    float a1, a2;
    sky_arc(p, a1, a2);
    float nl = length(N.xy);
    float an = section_angle(N.xy);
    float lo = max(a1, an - HALF_PI);
    float hi = min(a2, an + HALF_PI);
    float irr = (hi > lo) ? (sin(hi - an) - sin(lo - an)) : 0.0;
    float sky = 0.5 * irr * nl + (1.0 - nl) * 0.5 * (a2 - a1) / PI;

    vec3 dif = u_amb + u_skycol * sky;
    vec3 spc = vec3(0.0);
    vec3 air = vec3(0.0);

    // --- the moon, off to one side: lit where its direction clears the wall
    // tops, so the wall nearer it throws a shadow across the floor ---------
    float am = section_angle(u_moon.xy);
    float moonlit = smoothstep(a1, a1 + 0.08, am)
                    * (1.0 - smoothstep(a2 - 0.08, a2, am));
    float mdl = dot(N, u_moon);
    dif += u_mooncol * moonlit * max(mdl, 0.0);
    spc += u_mooncol * moonlit * step(0.0, mdl)
           * pow(max(dot(N, normalize(u_moon + V)), 0.0), u_mat.y);

    // --- the torches, at the two bay joints either side of this point -------
    float k0 = floor(p.z / u_bay);
    for (int i = 0; i < 2; i++) {
        float k = k0 + float(i);
        float lz = k * u_bay + u_torch.z;
        float on = ignite(u_front.x, lz);
        if (on <= 0.0) continue;
        for (int j = 0; j < 2; j++) {
            float s = float(j) * 2.0 - 1.0;
            vec3 col = u_torchcol * on * flicker(k * 2.0 + float(j));
            point_light(p, N, V, vec3(s * u_torch.x, u_torch.y, lz),
                        u_torch.w, col, dif, spc, air);
        }
    }

    // --- the nearest alcove: its two orbs, and the braziers over it ---------
    float m = floor((p.z / u_bay - u_alcove.y - 0.5) / u_alcove.x + 0.5);
    float ka = m * u_alcove.x + u_alcove.y;
    float oz = ka * u_bay + u_orb.z;
    float bz = ka * u_bay + u_braz.z;
    float o_on = ignite(u_front.y, oz);
    float b_on = ignite(u_front.z, bz);
    for (int j = 0; j < 2; j++) {
        float s = float(j) * 2.0 - 1.0;
        if (o_on > 0.0) {
            // the orbs breathe rather than flicker
            float br = 1.0 + 0.12 * sin(u_time * 0.021 + ka * 1.7 + s);
            point_light(p, N, V, vec3(s * u_orb.x, u_orb.y, oz), u_orb.w,
                        u_orbcol * o_on * br, dif, spc, air);
        }
        if (b_on > 0.0) {
            point_light(p, N, V, vec3(s * u_braz.x, u_braz.y, bz), u_braz.w,
                        u_brazcol * b_on * flicker(ka * 5.0 + float(j) + 0.5),
                        dif, spc, air);
        }
    }

    // --- the opening's moonbeam ---------------------------------------------
    // A shaft falling straight down, a soft-edged disc `u_beam.w` across
    // round the point (`u_beam.x`, `u_beam.z`): a pool on the pavement.
    if (u_beamcol.r > 0.0) {
        float pool = 1.0 - smoothstep(u_beam.w * 0.30, u_beam.w,
                                      length(p.xz - u_beam.xz));
        pool *= pool;
        vec3 up = vec3(0.0, 1.0, 0.0);
        float nb = dot(N, up);
        dif += u_beamcol * pool * max(nb, 0.0);
        spc += u_beamcol * pool * step(0.0, nb)
               * pow(max(dot(N, normalize(up + V)), 0.0), u_mat.y);
        air += u_beamcol * pool * 0.25;
    }

    // --- the sky in a polished surface --------------------------------------
    // Seen if the reflected ray leaves between the wall tops, and faded when
    // it would have to run so far down the hall first that the far chamber
    // would be in the way.
    vec3 R = reflect(-V, N);
    float ar = section_angle(R.xy);
    float up = length(R.xy);
    float seen = smoothstep(a1, a1 + 0.06, ar)
                 * (1.0 - smoothstep(a2 - 0.06, a2, ar))
                 * smoothstep(0.02, 0.10, up);
    float run = (u_trench.y - p.y) / max(R.y, 0.001) * abs(R.z);
    seen *= 1.0 - smoothstep(3000.0, 9000.0, run);
    float fres = 0.04 + 0.96 * pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 5.0);

    // Stone reflects little looked at squarely and a lot at a glance (a
    // floor's highlights stretch into streaks toward the far end); metal
    // reflects the same at any angle, in its own colour.
    float fstone = mix(0.10, 1.0, pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 4.0));
    float fspec = mix(fstone, 1.0, u_mat.z);
    vec3 tint = mix(vec3(1.0), alb * 2.2, u_mat.z);
    vec3 c = alb * dif + (spc * fspec + u_skyspec * seen * fres) * gloss * tint;

    vec3 fogc = u_fogcol + air * u_scatter;
    c = mix(c, fogc, v_vFog);
    gl_FragColor = vec4(c, v_vColour.a * cover);
}
